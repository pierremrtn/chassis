---
name: chassis-create-view-model
description: Implement a Flutter ViewModel for a Chassis screen as a `ViewModel<State, Event>` subclass that holds an immutable State, emits sealed Event types for one-time UI side effects, and dispatches message objects directly through the base class's `run(Command)`, `read(ReadQuery)`, and `watch(WatchQuery)` methods — no mediator field, no generated methods; `Chassis.initialize` installs the app mediator and the constructor's `mediator:` parameter is the testing seam. Use when adding a screen, dialog, or feature that needs reactive state, async data, or one-shot UI events.
---
# Creating a Chassis ViewModel

## Contents
- [Core Concepts](#core-concepts)
- [Designing the State Class](#designing-the-state-class)
- [Designing the Event Sealed Class](#designing-the-event-sealed-class)
- [Dispatch Methods: `run`, `read`, `watch`](#dispatch-methods-run-read-watch)
- [Concurrency: Keys and `RunPolicy`](#concurrency-keys-and-runpolicy)
- [Optimistic Updates](#optimistic-updates)
- [The Testing Seam](#the-testing-seam)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

A **ViewModel** is the bridge between business logic and the widget tree. In Chassis, every ViewModel subclasses `ViewModel<TState, TEvent>` and manages three concerns:

1. **State** — the persistent, observable data that determines what the UI renders.
2. **Events** — one-time occurrences (snackbar, navigation, dialog, vibration) that should fire once per emission, never on rebuild.
3. **Dispatch** — translating user actions into Command/Query messages routed through the Mediator.

> ViewModels serve as the bridge between business logic and the widget tree. Their primary responsibility is state transformation — converting raw domain data into a format the UI can render directly without additional processing.
> — `docs/04_ui_integration.md`

ViewModels never call repositories directly and never contain business logic — every operation is a message routed to a Handler that owns the logic. **ViewModels are message-direct**: they never reference the generated mediator class and hold no mediator field. They dispatch the message object itself — `run(CreateOrderCommand(...))` — and the mediator installed once at startup by `Chassis.initialize(AppMediator(...))` (see `chassis-bootstrap-app`) routes it to its handler, through the middlewares. The constructor's optional `mediator:` parameter overrides the global — that is the testing seam:

```dart
class UserProfileViewModel extends ViewModel<UserProfileState, UserProfileEvent> {
  UserProfileViewModel({required this.userId, super.mediator})
      : super(UserProfileState.initial());

  final String userId;
}
```

In production `mediator:` stays null and the global is resolved lazily at the first dispatch; dispatching with neither installed throws an actionable `StateError`. A ViewModel file imports only the message types (Application layer) and `chassis_flutter` — never `main.dart`, never repositories.

**ViewModel methods are synchronous and usually expression-bodied.** All asynchrony lives in the dispatch machinery, reported through callbacks:

```dart
void addTodo(String title) => run(
      AddTodoCommand(title),
      onState: (todo) => setState(state.copyWith(lastAdded: todo)),
      onError: (error, stack) => sendEvent(AddTodoFailedEvent(error)),
    );
```

Platform/UI async — image picker, permissions, biometrics, share sheet — lives in the *widget*, which awaits it, guards `context.mounted`, and passes plain data to a synchronous ViewModel method. ViewModels are await-free.

## Designing the State Class

The State is an immutable class — its fields declared as `final` named parameters in the primary-constructor header — with a `copyWith` method and an `initial()` factory. It contains *only* persistent UI data — anything that should be re-rendered the same way after a rebuild or rotation.

Async data must be wrapped in `Async<T>` (the sealed `AsyncLoading` / `AsyncData` / `AsyncError` union). This forces the UI to handle loading and error states exhaustively, eliminating the class of bugs where a screen forgets to render a spinner or an error.

```dart
class const UserProfileState({
  required final Async<User> user,
  required final bool isEditing,
}) {
  UserProfileState copyWith({Async<User>? user, bool? isEditing}) {
    return UserProfileState(
      user: user ?? this.user,
      isEditing: isEditing ?? this.isEditing,
    );
  }

  static UserProfileState initial() {
    return const UserProfileState(user: Async.loading(), isEditing: false);
  }
}
```

Local UI flags like `isEditing` belong here. Domain data like `user` flows in through `Async<User>` from a dispatched query.

## Designing the Event Sealed Class

The Event hierarchy is a sealed class with one variant per kind of one-time occurrence. Sealed classes give exhaustive pattern matching at the listener (the compiler refuses incomplete `switch`es), and the per-variant type carries any payload the listener needs.

```dart
sealed class UserProfileEvent {}

class const UserUpdatedEvent() implements UserProfileEvent;

class const UserUpdateFailedEvent(
  final Object error, // the error OBJECT — never error.toString()
) implements UserProfileEvent;
```

**Failure events carry the error object** (the domain error, or a dedicated type) — never `error.toString()`. A string-ified error destroys pattern matching: the listener can no longer branch on the error type to translate it or decide the UI reaction.

Events are emitted with `sendEvent(...)` from inside the ViewModel and consumed by `ViewModelProvider.withEventListener`, the `EventListener` widget, or `EventListenerMixin` — see `chassis-handle-view-model-events`. Events sent before anyone subscribes (during construction, for example) are buffered — bounded — and delivered to the first subscriber; after that, broadcast semantics apply and events emitted with no listener are dropped.

> A common mistake is modeling events as nullable state properties, such as `String? snackbarMessage` in the state class. (...) Rebuilds replay events — if the widget rebuilds for unrelated reasons, the snackbar shows again. (...) Events solve these problems by firing once per occurrence, regardless of rebuilds.
> — `docs/04_ui_integration.md`

## Dispatch Methods: `run`, `read`, `watch`

The ViewModel base class dispatches messages and reports their lifecycle as `Async<T>` values through callbacks: `run` takes a `Command`, `read` takes a `ReadQuery`, `watch` takes a `WatchQuery` — the message object itself, not a closure or a stream. Subscriptions are tracked automatically and cleaned up when the ViewModel disposes.

```dart
@protected Future<Async<R>> run<R>(Command<R> command, {
  Object? key,                            // default: command.runtimeType
  RunPolicy policy = const RunPolicy.concurrent(),
  Async<R>? current,
  AsyncData<R>? optimistic,
  bool emitLoading = true,
  void Function(Async<R> state)? onState,
  void Function(R value)? onSuccess,
  void Function(Object error, StackTrace stack)? onError,
});

// Identical to run in every parameter and guarantee:
@protected Future<Async<R>> read<R>(ReadQuery<R> query, {
  Object? key,                            // default: query.runtimeType
  RunPolicy policy = const RunPolicy.concurrent(),
  Async<R>? current,
  AsyncData<R>? optimistic,
  bool emitLoading = true,
  void Function(Async<R> state)? onState,
  void Function(R value)? onSuccess,
  void Function(Object error, StackTrace stack)? onError,
});

@protected WatchHandle watch<R>(WatchQuery<R> query, {
  Object? key,                            // default: query.runtimeType
  Async<R>? current,
  bool emitLoading = true,
  void Function(Async<R> state)? onState,
  void Function(R data)? onData,
  void Function(Object error, StackTrace stack)? onError,
  void Function()? onDone,
});
```

**The callback contract** (documented on the `ViewModel` class — the same for all three):

- **`onState`** (if provided) fires for **every** transition: loading, data, and error. It receives the `Async<R>`.
- **`onSuccess` (`run`/`read`) / `onData` (`watch`) and `onError` are additive** conveniences, fired *after* `onState` for their respective transition. Providing them never suppresses `onState`. The naming asymmetry is deliberate — a `run` result is a *success*, a `watch` emission is *data* — do not try to harmonize it.
- **`onError` receives `(Object error, StackTrace stack)`** everywhere.
- **The error path must always be covered**: every `run`/`read` call provides `onState` (which receives the error transition) or `onError`. `onSuccess` alone is the invisible-failure anti-pattern — the operation fails and neither state nor events record it.
- **Callbacks run outside the internal try/catch.** An exception thrown by your callback is a bug in the callback and propagates as such — it is never converted into an `AsyncError`.
- **At least one callback is required** (asserted in debug builds). Callbacks are not invoked after the ViewModel disposes.

**Failures are soft.** Any dispatch failure — the handler throwing (even synchronously), a wiring error, a missing handler (`HandlerNotRegisteredError`) — becomes an `AsyncError` through the callbacks, never a crash at the call site. The one exception: dispatching with no `Chassis.initialize` and no constructor override throws an actionable `StateError`.

**Anti-flicker with `current:`** — pass the state's existing `Async<R>` and the loading emission (and any error) carries the existing data as `previous`, so a refetch does not blank the UI (see `chassis-render-async-state`). Pass `emitLoading: false` to skip the initial loading emission entirely (for example, a silent background refresh).

**`run`/`read` specifics** —

- Return `Future<Async<R>>` resolving to the final `AsyncData` or `AsyncError`, useful when the caller needs the outcome inline. A dropped or debounce-coalesced call resolves with the winning run's result.
- `read` is identical to `run` in every parameter and guarantee. A refetching read typically wants `policy: const RunPolicy.restartable()` so a newer read supersedes the in-flight one.
- `optimistic:` — see [Optimistic Updates](#optimistic-updates).

**`watch` specifics** —

- A new `watch` on the same key cancels and replaces the previous subscription — and the key defaults to the query's runtime type, so **re-watching the same query class with new params swaps the subscription with no explicit key**. Pass distinct explicit keys to watch several instances of the same query class concurrently (additive watches).
- Returns a **`WatchHandle`** (`cancel()`, `isCancelled`) for stopping a subscription before dispose; disposal cancels all of them.
- A stream error emits a *soft error*: an `AsyncError` carrying the last known data, so the UI can keep the previous snapshot visible. A handler that throws synchronously (a non-`async*` handler failing) reports the same soft `AsyncError` and returns an already-cancelled handle — no crash at the call site.
- **`onDone`** fires when the watched stream itself completes — never on cancellation (keyed replacement, `cancel()`, or disposal). The handle is released before `onDone` runs, so re-watching under the same key from inside it is safe. Without `onDone`, a finite stream ending is invisible: the state stays frozen on the last emission.

## Concurrency: Keys and `RunPolicy`

Operations are keyed, and **the key defaults to the message's runtime type**: two dispatches of the same command class interact under the same `RunPolicy`, and a re-`watch` of the same query class replaces the previous subscription. Pass an explicit `key:` to depart from that — distinct keys separate operations of one message class (watch two instances concurrently, guard double-taps per entity); a shared key makes *different* message types interact under one policy. All runs sharing a key must have the same result type `R` (asserted in debug builds).

A `RunPolicy` answers one question — when several runs collide on a key, who wins?

| Policy | Who wins | Canonical use |
|---|---|---|
| `RunPolicy.concurrent()` (default) | Everyone: all runs execute and report; the last completion writes last, which may be the oldest dispatch | Independent operations that don't collide |
| `RunPolicy.restartable({debounce})` | The latest: a new run invalidates the callbacks of in-flight runs on the key; a non-zero `debounce` additionally coalesces bursts before dispatching | Refetches, search-as-you-type |
| `RunPolicy.droppable()` | The first: while a run is in flight, new calls do not dispatch and resolve with the in-flight result | Submit buttons, double-tap guards |
| `RunPolicy.sequential()` | Everyone, in order: runs queue per key | Ordered mutations |

**`restartable` does not cancel the underlying execution** — only the callbacks are cut. The superseded network call completes and its side effects land; only its lifecycle reporting is suppressed. Do not use it to "abort" a mutation.

## Optimistic Updates

For mutations whose outcome is known upfront (toggle a favorite, mark a notification read), `optimistic:` on `run`/`read` emits the given `AsyncData` through `onState` at dispatch *instead of* a loading state — the field takes the expected value immediately.

- `onSuccess`/`onError` (and the result transition of `onState`) fire only for the **real** result.
- On failure, the reported `AsyncError.previous` is the last **confirmed** data — the latest `AsyncData` completed by a run on the same `key`, or the data carried by `current:` — never the optimistic value. Rendering `previous` rolls the UI back.
- Typed `AsyncData<R>?` rather than a bare value, so that `optimistic: AsyncData(null)` stays distinct from "not optimistic" when `R` is nullable.
- Requires `onState` (asserted in debug builds): the optimistic value is emitted through `onState` only.
- `watch` has no optimistic parameter — patch the stream in the repository instead.

**Doctrine: a UI that must mark the value "unconfirmed" is not optimistic.** Optimistic UI renders the expected value *as if confirmed*. If the design needs a pending marker (a greyed-out message, a syncing badge), that is a real domain status — model it on the entity and let the repository emit it, or use the normal loading pipeline.

## The Testing Seam

The constructor's `mediator:` parameter always wins over the global installed by `Chassis.initialize`. Tests construct the ViewModel with a real `Mediator` carrying fake handlers — never touching the global:

```dart
final vm = TodoViewModel(
  mediator: Mediator()..registerCommandHandler(FakeAddTodoHandler()),
);
```

Never call `Chassis.initialize` in tests: it is process-global state that leaks between test cases. Register a fake for every message the ViewModel dispatches — a missing handler does not crash, it surfaces as a soft `AsyncError` (`HandlerNotRegisteredError`) through the callbacks. In widget tests, provide the ViewModel with `ViewModelProvider<T>.value(value: vm)` — see `chassis-consume-view-model`.

## Rules

- **DO** subclass `ViewModel<TState, TEvent>` with the constructor shape `MyViewModel({super.mediator}) : super(TState.initial());` — the `super(...)` initializer call means ViewModel subclasses keep a classic constructor, never a primary one. *`super.mediator` forwards the optional override that wins over the global — the testing seam. In production it stays null and the mediator installed by `Chassis.initialize` is resolved lazily at the first dispatch.*
- **DO** dispatch message objects directly: `run(SomeCommand(...))`, `read(SomeReadQuery(...))`, `watch(SomeWatchQuery(...))`. *ViewModels never reference the generated mediator class and hold no mediator field; the message type is the compile-checked contract, and every dispatch crosses the mediator's middlewares.*
- **DO** write ViewModel methods as synchronous, usually expression-bodied: `void save() => run(SaveCommand(...), ...);`. *All asynchrony lives in the dispatch machinery; an `async` ViewModel method is a design smell.*
- **DO** define an immutable `TState` class — fields declared as `final` named parameters in the primary-constructor header (`class const TState({required final Async<X> x})`) — with a `copyWith` method and a static `initial()` factory. *Immutability makes transitions explicit, debuggable, and safe under concurrent dispatch.*
- **DO** wrap every asynchronous datum in state with `Async<T>`. *The sealed union forces loading and error handling at the render site — see `chassis-render-async-state`.*
- **DO** define a sealed `TEvent` class with one variant per one-time occurrence, failure variants carrying the error object (`class const FooFailedEvent(final Object error) implements TEvent;`). *Sealed unions give exhaustive `switch` at the listener; `error.toString()` destroys pattern matching.*
- **DO** cover the error path of every `run`/`read`: provide `onState` or `onError`. *`onSuccess` alone is the invisible-failure anti-pattern — the command fails and neither state nor events record it (this will become a lint).*
- **DO** use `setState(state.copyWith(...))` to update state. *`setState` is the framework's notify hook; direct field mutation does not exist on an immutable state.*
- **DO** use `sendEvent(<EventVariant>)` for one-time UI side effects.
- **DO** start long-lived subscriptions with `watch(...)` in the constructor, or in a method that can be re-called with new arguments. *The framework disposes the subscription with the ViewModel, and a re-watch of the same query class replaces the previous subscription — new params swap the stream instead of leaking a second one.*
- **DO** pass an explicit `key:` to depart from the default per-message-type keying. *Distinct keys make watches of one query class additive and scope run policies per entity; a shared key makes different message types interact under one policy.*
- **DO** pass `current:` when re-running or re-watching data the screen already shows. *Loading and error emissions then carry the existing data, and the UI does not flash a spinner.*
- **DO** route query errors through state via `onState` and command errors through events via `onError: (error, stack) => sendEvent(<FailedEvent>(error))`. *Queries produce the data the screen renders — the error belongs in the `Async` field; commands fire on screens that already have valid content — a failed command should not replace the view.* See `chassis-handle-errors`.
- **DO** await platform/UI async in the widget — image picker, permissions, biometrics, share sheet — then call a synchronous ViewModel method with plain data. *The widget guards `context.mounted` (the `use_build_context_synchronously` lint enforces it) and disables the button while awaiting (two concurrent `pickImage` calls throw `PlatformException(already_active)`); the ViewModel stays await-free.*
- **DO** rely on `autoDispose` / `autoDisposeStreamSubscription` for any `Disposable` resource the ViewModel owns outside `watch(...)`. *Manual cleanup is error-prone; the framework cleans up in reverse order on dispose.*
- **DON'T** call repositories from a ViewModel. *ViewModels depend only on message types; business logic lives in Handlers.*
- **DON'T** put business logic in the ViewModel. *Validation, orchestration, and rules belong in Handlers, where they are testable in isolation.*
- **DON'T** `await` inside a ViewModel method. *If a method wants to await, either the logic belongs in a handler (compose repositories there) or the await is platform UI work that belongs in the widget.*
- **DON'T** model one-time occurrences as nullable state fields (`String? snackbarMessage`). *Rebuilds replay them; manual cleanup is required; state becomes polluted.* Use the Event channel.
- **DON'T** mutate state in place. *State is immutable; create a new instance via `copyWith`.*
- **DON'T** let work that can throw run inside `onState`/`onSuccess`/`onData`/`onError` callbacks unguarded. *Callbacks execute outside the framework's try/catch — a throwing callback propagates as a crash, it does not become an `AsyncError`.*
- **DON'T** hand-roll `Timer` debounces, double-tap guards, or stale-response checks — `RunPolicy` already encodes these concurrency semantics: `restartable(debounce: ...)` for search-as-you-type (quiet-window dispatch + latest-wins invalidation of in-flight runs), `droppable()` for double-taps, a shared `key:` for anything that must not race. *The manual version is ~15 lines per screen and usually misses a race the policy handles — debouncing alone does not fix result races, which is exactly why chassis makes them one parameter.*
- **DON'T** use `optimistic:` for a value the UI must mark as "unconfirmed". *That is not optimistic UI — it is a real domain status; model it on the entity (the repository emits it as pending) or use the normal loading pipeline.*
- **DON'T** call `Chassis.initialize` in tests. *Pass the fake through the constructor — `MyViewModel(mediator: fakeMediator)` — which always wins over the global and leaks nothing between test cases.*

## Workflow

- [ ] **Step 1 — Identify the screen's data needs.** What domain data does it render (queries)? What user actions does it accept (commands)? What one-time UI effects does it produce (events)?
- [ ] **Step 2 — Define the State class** with the persistent UI data as `final` named parameters in the primary-constructor header. Wrap async fields in `Async<T>`. Add `copyWith` and `initial()`.
- [ ] **Step 3 — Define the Event sealed class** with one variant per one-time occurrence. Each variant is a primary-constructor declaration that `implements <Feature>Event` (`class const <Variant>(...) implements <Feature>Event;`); failure variants carry the error object.
- [ ] **Step 4 — Subclass `ViewModel<State, Event>`** with `MyViewModel({required this.routeParam, super.mediator}) : super(State.initial());` — no mediator field.
- [ ] **Step 5 — For watch-based data**, call `watch(Watch<X>Query(...), current: state.<field>, onState: ...)` in the constructor, or in a `load(...)` method that can be re-called with new arguments — the re-watch replaces the previous subscription because both dispatches share the query-type key.
- [ ] **Step 6 — For one-time fetches**, expose a synchronous method: `void load() => read(Get<X>Query(...), policy: const RunPolicy.restartable(), current: state.<field>, onState: ...);` — restartable so a refetch supersedes the in-flight one instead of racing it.
- [ ] **Step 7 — For commands**, expose a synchronous method: `void submit() => run(<X>Command(...), policy: const RunPolicy.droppable(), onSuccess: ..., onError: ...);` — droppable so a double-tap cannot dispatch twice. Cover the error path (`onState` or `onError`); emit success and failure events via `sendEvent(...)`. Add `onState:` too when the screen renders the command's progress.
- [ ] **Step 8 — For local UI flags** (`isEditing`, selected tab, form-step index), expose simple methods that call `setState(state.copyWith(...))` directly — no message involved.
- [ ] **Step 9 — Provide the ViewModel** to the widget subtree using `ViewModelProvider` or `ViewModelProvider.withEventListener`. See `chassis-consume-view-model` and `chassis-handle-view-model-events`.
- [ ] **Step 10 — Render state** — inline `switch` expression for simple cases, `AsyncBuilder` for anti-flicker. See `chassis-render-async-state`.
- [ ] **Step 11 — Test** by passing a `Mediator` with fake handlers to the constructor (`MyViewModel(mediator: fakeMediator)`) — never `Chassis.initialize` in tests.

## Examples

### Watch query + command + local flag

```dart
// presentation/user_profile/user_profile_state.dart
import 'package:chassis/chassis.dart';
import 'package:app/domain/users/user.dart';

class const UserProfileState({
  required final Async<User> user,
  required final bool isEditing,
}) {
  UserProfileState copyWith({Async<User>? user, bool? isEditing}) {
    return UserProfileState(
      user: user ?? this.user,
      isEditing: isEditing ?? this.isEditing,
    );
  }

  static UserProfileState initial() =>
      const UserProfileState(user: Async.loading(), isEditing: false);
}

sealed class UserProfileEvent {}

class const UserUpdatedEvent() implements UserProfileEvent;

class const UserUpdateFailedEvent(final Object error)
    implements UserProfileEvent;
```

```dart
// presentation/user_profile/user_profile_view_model.dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:app/application/users/users.dart'; // WatchUserQuery, UpdateUserEmailCommand
import 'user_profile_state.dart';

class UserProfileViewModel
    extends ViewModel<UserProfileState, UserProfileEvent> {
  UserProfileViewModel({required this.userId, super.mediator})
      : super(UserProfileState.initial()) {
    watch(
      WatchUserQuery(userId: userId),
      onState: (user) => setState(state.copyWith(user: user)),
    );
  }

  final String userId;

  void toggleEditMode() =>
      setState(state.copyWith(isEditing: !state.isEditing));

  void updateEmail(String newEmail) => run(
        UpdateUserEmailCommand(userId: userId, newEmail: newEmail),
        policy: const RunPolicy.droppable(),
        onSuccess: (_) {
          setState(state.copyWith(isEditing: false));
          sendEvent(const UserUpdatedEvent());
        },
        onError: (error, stack) => sendEvent(UserUpdateFailedEvent(error)),
      );
}
```

The ViewModel references only message classes — no mediator field, no generated methods. `Chassis.initialize(AppMediator(...))` in `main()` decided where those messages go.

### One-time read with full lifecycle in state and a success event

```dart
class ExportProfileViewModel
    extends ViewModel<ExportProfileState, ExportProfileEvent> {
  ExportProfileViewModel({super.mediator}) : super(ExportProfileState.initial());

  void export(String userId, ExportFormat format) => read(
        ExportUserDataQuery(userId: userId, format: format),
        current: state.file, // a re-export keeps the previous file visible
        onState: (file) => setState(state.copyWith(file: file)),
        onSuccess: (file) => sendEvent(ExportReadyEvent(file.path)),
      );
}
```

`onState` fires on the loading emission, then again on data or error — so the error path is covered through state. `onSuccess` fires additively after `onState` on success; providing it never suppresses `onState`.

### Search-as-you-type with a debounced restartable read

```dart
class SearchViewModel extends ViewModel<SearchState, SearchEvent> {
  SearchViewModel({super.mediator}) : super(SearchState.initial());

  void search(String terms) => read(
        SearchProductsQuery(terms: terms),
        policy: const RunPolicy.restartable(
          debounce: Duration(milliseconds: 300),
        ),
        current: state.results, // keep showing old results while loading
        onState: (results) => setState(state.copyWith(results: results)),
      );
}
```

Every call shares the default key (`SearchProductsQuery`): a burst of keystrokes coalesces into the latest call, and a superseded dispatch stops reporting — no stale results racing into state. Remember: `restartable` cuts callbacks, not the underlying execution.

### Optimistic toggle with rollback

```dart
void toggleFavorite(String recipeId) {
  final favorites = state.favorites;
  if (favorites is! AsyncData<Set<String>>) return; // nothing confirmed yet
  final toggled = favorites.value.contains(recipeId)
      ? ({...favorites.value}..remove(recipeId))
      : {...favorites.value, recipeId};
  run(
    ToggleFavoriteCommand(recipeId: recipeId), // Command<Set<String>>
    key: recipeId, // per-recipe flights; double-tap on one recipe is dropped
    policy: const RunPolicy.droppable(),
    current: favorites,
    optimistic: AsyncData(toggled),
    onState: (favorites) => setState(state.copyWith(favorites: favorites)),
    onError: (error, stack) => sendEvent(FavoriteToggleFailedEvent(error)),
  );
}
```

The star flips instantly (`onState` receives the optimistic set at dispatch). On failure, `onState` receives an `AsyncError` whose `previous` is the last *confirmed* set — rendering it rolls the UI back — and `onError` notifies the user. If the design instead required a "syncing…" badge on the item, this would not be optimistic UI: model that status in the domain.

### Platform async stays in the widget

```dart
// ❌ In the ViewModel: Future<void> changeAvatar() async { await picker... }
// ✅ The widget awaits, guards, and hands plain data to a sync method:
class _AvatarButtonState extends State<AvatarButton> {
  bool _picking = false;

  Future<void> _pickAvatar() async {
    setState(() => _picking = true);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (!mounted || file == null) return;
      context.read<ProfileViewModel>().changeAvatar(file);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
        // Disabled while awaiting: two concurrent pickImage calls throw
        // PlatformException(already_active).
        onPressed: _picking ? null : _pickAvatar,
        icon: const Icon(Icons.photo_camera),
      );
}
```

```dart
// The ViewModel method is synchronous — it receives plain data:
void changeAvatar(XFile file) => run(
      UpdateAvatarCommand(path: file.path),
      current: state.avatar,
      onState: (avatar) => setState(state.copyWith(avatar: avatar)),
    );
```

### Pattern matching on `Async<T>` when state transitions branch

```dart
void loadUser(String userId) => read(
      GetUserQuery(userId: userId),
      policy: const RunPolicy.restartable(),
      onState: (user) {
        switch (user) {
          case AsyncLoading():
            setState(state.copyWith(user: user));
          case AsyncData():
            setState(state.copyWith(user: user, isEditing: false));
          case AsyncError(:final error):
            setState(state.copyWith(user: user));
            sendEvent(UserLoadFailedEvent(error));
        }
      },
    );
```

The sealed `Async<T>` union forces every case to be handled at compile time. Use this expanded form when state transitions differ across the lifecycle; the compact form (`onState: (user) => setState(...)`) is preferable when every transition flows into the same field unchanged.

### Testing through the constructor seam

```dart
class FailingUpdateEmailHandler
    implements CommandHandler<UpdateUserEmailCommand, User> {
  @override
  Future<User> run(UpdateUserEmailCommand command) async =>
      throw EmailAlreadyInUseException();
}
```

```dart
test('a failed update emits UserUpdateFailedEvent carrying the error', () async {
  final vm = UserProfileViewModel(
    userId: '42',
    mediator: Mediator()
      ..registerQueryHandler(FakeWatchUserHandler()) // the constructor watches
      ..registerCommandHandler(FailingUpdateEmailHandler()),
  );
  final events = <UserProfileEvent>[];
  vm.events.listen(events.add);

  vm.updateEmail('taken@example.com');
  await pumpEventQueue();

  expect(
    events.single,
    isA<UserUpdateFailedEvent>()
        .having((e) => e.error, 'error', isA<EmailAlreadyInUseException>()),
  );
});
```

No `Chassis.initialize`, no global state: the override passed to the constructor wins. Register a fake for every message the ViewModel dispatches.

### Anti-pattern: invisible failure

```dart
// ❌ onSuccess alone: on failure, nothing happens — no state transition,
// no event. The user taps "Save" and the app silently does nothing.
void save() => run(
      SaveDraftCommand(state.draft),
      onSuccess: (_) => sendEvent(const DraftSavedEvent()),
    );
```

```dart
// ✅ The error path is covered.
void save() => run(
      SaveDraftCommand(state.draft),
      onSuccess: (_) => sendEvent(const DraftSavedEvent()),
      onError: (error, stack) => sendEvent(DraftSaveFailedEvent(error)),
    );
```

### Anti-pattern: events in state

```dart
// ❌ Don't do this — rebuilds replay the snackbar, navigation loops, manual cleanup required.
class BadState({
  final String? snackbarMessage,
  final String? navigationRoute,
});
```

```dart
// ✅ Fires once per occurrence, no manual cleanup, state stays focused on what to render.
sealed class GoodEvent {}

class const ShowSnackbarEvent(final String message) implements GoodEvent;

// In the ViewModel:
void notifySaved() => sendEvent(const ShowSnackbarEvent('Saved'));
```

See `chassis-handle-view-model-events` for how listeners consume the event channel.
