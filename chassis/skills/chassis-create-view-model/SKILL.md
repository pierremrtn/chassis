---
name: chassis-create-view-model
description: Implement a Flutter ViewModel for a Chassis screen as a `ViewModel<State, Event>` subclass that holds an immutable State, emits sealed Event types for one-time UI side effects, and dispatches operations through the generated mediator wrapped by the base class's `run()` and `watch()` methods. Use when adding a screen, dialog, or feature that needs reactive state, async data, or one-shot UI events.
---
# Creating a Chassis ViewModel

## Contents
- [Core Concepts](#core-concepts)
- [Designing the State Class](#designing-the-state-class)
- [Designing the Event Sealed Class](#designing-the-event-sealed-class)
- [Lifecycle Methods: `run()` and `watch()`](#lifecycle-methods-run-and-watch)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

A **ViewModel** is the bridge between business logic and the widget tree. In Chassis, every ViewModel subclasses `ViewModel<TState, TEvent>` and manages three concerns:

1. **State** — the persistent, observable data that determines what the UI renders.
2. **Events** — one-time occurrences (snackbar, navigation, dialog, vibration) that should fire once per emission, never on rebuild.
3. **Dispatch** — translating user actions into Commands or Queries through the Mediator.

> ViewModels serve as the bridge between business logic and the widget tree. Their primary responsibility is state transformation — converting raw domain data into a format the UI can render directly without additional processing.
> — `docs/04_ui_integration.md`

ViewModels never call repositories directly and never contain business logic. The architectural rule is strict: every operation goes through a mediator method, which routes to a Handler that owns the logic. Keep an `AppMediator`-typed field (the base class holds no mediator) so the generated typed methods — `_mediator.createOrder(...)` — are available; they are compile-checked and always dispatch through middlewares.

## Designing the State Class

The State is an immutable class with `final` fields, a `copyWith` method, and an `initial()` factory. It contains *only* persistent UI data — anything that should be re-rendered the same way after a rebuild or rotation.

Async data must be wrapped in `Async<T>` (the sealed `AsyncLoading` / `AsyncData` / `AsyncError` union). This forces the UI to handle loading and error states exhaustively, eliminating the class of bugs where a screen forgets to render a spinner or an error.

```dart
class UserProfileState {
  const UserProfileState({required this.user, required this.isEditing});

  final Async<User> user;
  final bool isEditing;

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

Local UI flags like `isEditing` belong here. Domain data like `user` flows in through `Async<User>` from a Mediator query.

## Designing the Event Sealed Class

The Event hierarchy is a sealed class with one variant per kind of one-time occurrence. Sealed classes give exhaustive pattern matching at the listener (the compiler refuses incomplete `switch`es), and the per-variant type carries any payload the listener needs.

```dart
sealed class UserProfileEvent {}

class UserUpdatedEvent implements UserProfileEvent {
  const UserUpdatedEvent();
}

class UserUpdateFailedEvent implements UserProfileEvent {
  const UserUpdateFailedEvent(this.error);
  final Object error;
}
```

Events are emitted with `sendEvent(...)` from inside the ViewModel and consumed by `ViewModelProvider.withEventListener`, the `EventListener` widget, or `EventListenerMixin` — see `chassis-handle-view-model-events`. Events sent before anyone subscribes (during construction, for example) are buffered — bounded — and delivered to the first subscriber; after that, broadcast semantics apply and events emitted with no listener are dropped.

> A common mistake is modeling events as nullable state properties, such as `String? snackbarMessage` in the state class. (...) Rebuilds replay events — if the widget rebuilds for unrelated reasons, the snackbar shows again. (...) Events solve these problems by firing once per occurrence, regardless of rebuilds.
> — `docs/04_ui_integration.md`

## Lifecycle Methods: `run()` and `watch()`

The ViewModel base class provides two methods for handling asynchronous operations. They wrap a `Future<T>` or `Stream<T>` (typically obtained from a generated mediator method) and report the lifecycle as `Async<T>` values through callbacks. Subscriptions are tracked automatically and cleaned up when the ViewModel disposes.

```dart
Future<Async<R>> run<R>(Future<R> Function() operation,
    {Object? key, RunPolicy policy = const RunPolicy.concurrent(),
     Async<R>? current, bool emitLoading = true, onState, onSuccess, onError});

WatchHandle watch<R>(Stream<R> stream,
    {Object? key, Async<R>? current, bool emitLoading = true,
     onState, onData, onError});
```

**The callback contract** (documented on the `ViewModel` class — the same for both methods):

- **`onState`** (if provided) fires for **every** transition: loading, data, and error. It receives the `Async<R>`.
- **`onSuccess` (`run`) / `onData` (`watch`) and `onError` are additive** conveniences, fired *after* `onState` for their respective transition. Providing them never suppresses `onState`. They carry the same value — a `run` result is a *success*, a `watch` emission is *data*.
- **Callbacks run outside the internal try/catch.** An exception thrown by your callback is a bug in the callback and propagates as such — it is never converted into an `AsyncError` of the operation.
- **At least one callback is required** (asserted in debug builds).
- Callbacks are not invoked after the ViewModel disposes.

**Anti-flicker with `current:`** — pass the state's existing `Async<R>` and the loading emission (and any error) carries the existing data as `previous`, so a refetch does not blank the UI. `AsyncBuilder`'s default `maintainState: true` then keeps rendering the carried value. Pass `emitLoading: false` to skip the initial loading emission entirely (for example, a silent background refresh).

**`run` specifics** — returns `Future<Async<R>>` resolving to the final `AsyncData` or `AsyncError`, useful when the caller needs the outcome inline.

**`watch` specifics** —

- **`key:`** — a new `watch` with the same key cancels and replaces the previous subscription. The canonical use is re-watching with new arguments: `watch(_mediator.watchUser(userId: id), key: #user, ...)`. Without a key, subscriptions are additive and live until dispose.
- Returns a **`WatchHandle`** with `cancel()` for stopping a subscription before dispose.
- A stream error emits a *soft error*: an `AsyncError` carrying the last known data, so the UI can keep the previous snapshot visible.

## Rules

- **DO** subclass `ViewModel<TState, TEvent>` and pass only the initial state to the super constructor (`super(TState.initial())`). *The base class wires `ChangeNotifier` lifecycle, the event stream, and resource cleanup — it holds no mediator.*
- **DO** keep a typed mediator field (`final AppMediator _mediator;` — or a module interface like `AuthMediator` in shared packages) and dispatch through the generated typed methods. *The base class holds no mediator; the subclass's typed field is the only dispatch path, and its generated methods are compile-checked.*
- **DO** define an immutable `TState` class with `final` fields, a `copyWith` method, and a static `initial()` factory. *Immutability makes transitions explicit, debuggable, and safe under concurrent dispatch.*
- **DO** wrap every asynchronous datum in state with `Async<T>`. *`AsyncBuilder` and pattern matching require it; loading and error states cannot be forgotten.*
- **DO** define a sealed `TEvent` class with one variant per one-time occurrence. *Sealed unions give exhaustive `switch` at the listener.*
- **DO** use `setState(state.copyWith(...))` to update state. *`setState` is the framework's notify hook; direct field mutation does not exist on an immutable state.*
- **DO** use `sendEvent(<EventVariant>)` for one-time UI side effects.
- **DO** subscribe to long-lived streams in the ViewModel constructor (or in a method called once) using `watch(...)`. *The framework disposes the subscription with the ViewModel.*
- **DO** pass `key:` to `watch(...)` whenever the subscription can be restarted with new arguments. *A keyed re-watch cancels and replaces the previous subscription; without the key both subscriptions keep emitting into the same state.*
- **DO** pass `current:` when re-running or re-watching data the screen already shows. *Loading and error emissions then carry the existing data, and the UI does not flash a spinner.*
- **DO** route query errors through state via `onState` so `AsyncBuilder.errorBuilder` renders them. *Queries produce the data the screen needs; without it there is no useful view.*
- **DO** route command errors through events via `onError` (`sendEvent(<FailedEvent>(error))`). *Commands are triggered on screens that already have valid content; a failed command should not replace the view. `onError` is additive — pair it with `onState` when state should track the command lifecycle too.*
- **DO** rely on `autoDispose` / `autoDisposeStreamSubscription` for any `Disposable` resource the ViewModel owns outside `watch(...)`. *Manual cleanup is error-prone; the framework cleans up in reverse order on dispose.*
- **DON'T** call repositories from a ViewModel. *ViewModels depend only on the Mediator; business logic lives in Handlers.*
- **DON'T** put business logic in the ViewModel. *Validation, orchestration, and rules belong in Handlers, where they are testable in isolation.*
- **DON'T** model one-time occurrences as nullable state fields (`String? snackbarMessage`). *Rebuilds replay them; manual cleanup is required; state becomes polluted.* Use the Event channel.
- **DON'T** mutate state in place. *State is immutable; create a new instance via `copyWith`.*
- **DON'T** let work that can throw run inside `onState`/`onSuccess`/`onData`/`onError` callbacks unguarded. *Callbacks execute outside the framework's try/catch — a throwing callback propagates as a crash, it does not become an `AsyncError`.*
- **DON'T** manually manage stream subscriptions inside a ViewModel. *Use `watch(...)` so the framework owns subscription lifecycle.*
- **DON'T** hand-roll `Timer` debounces, double-tap guards, or stale-response checks — `RunPolicy` already encodes these concurrency semantics: `restartable(debounce: ...)` for search-as-you-type (quiet-window dispatch + latest-wins invalidation of in-flight runs), `droppable()` for double-taps, a shared `key:` for anything that must not race. *The manual version is ~15 lines per screen and usually misses a race the policy handles — debouncing alone does not fix result races, which is exactly why chassis makes them one parameter.*

## Workflow

- [ ] **Step 1 — Identify the screen's data needs.** What domain data does it render (queries)? What user actions does it accept (commands)? What one-time UI effects does it produce (events)?
- [ ] **Step 2 — Define the State class** with the persistent UI data. Wrap async fields in `Async<T>`. Add `copyWith` and `initial()`.
- [ ] **Step 3 — Define the Event sealed class** with one variant per one-time occurrence. Each variant `implements <Feature>Event` and carries only what the listener needs.
- [ ] **Step 4 — Subclass `ViewModel<State, Event>`.** Keep a typed field: `MyViewModel(this._mediator) : super(State.initial());` with `final AppMediator _mediator;`.
- [ ] **Step 5 — For watch-based data**, call `watch(_mediator.<watchQuery>(...), key: #<name>, current: state.<field>, onState: ...)` in the constructor (or in a `load(...)` method that can be re-called with new arguments). Update state with `setState(state.copyWith(...))`.
- [ ] **Step 6 — For one-time fetches**, expose a method that calls `run(() => _mediator.<readQuery>(...), key: #<field>, policy: const RunPolicy.restartable(), current: state.<field>, onState: ...)` — restartable so a refetch supersedes the in-flight one instead of racing it.
- [ ] **Step 7 — For commands**, expose a method that calls `run(() => _mediator.<command>(...), key: #<action>, policy: const RunPolicy.droppable(), onSuccess: ..., onError: ...)` — droppable so a double-tap cannot dispatch twice. Emit success and failure events via `sendEvent(...)`. Add `onState:` too when the screen renders the command's progress.
- [ ] **Step 8 — For local UI flags** (`isEditing`, selected tab, form-step index), expose simple methods that call `setState(state.copyWith(...))` directly — no Mediator involved.
- [ ] **Step 9 — Provide the ViewModel** to the widget subtree using `ViewModelProvider` or `ViewModelProvider.withEventListener`. See `chassis-consume-view-model` and `chassis-handle-view-model-events`.
- [ ] **Step 10 — Render state** with `AsyncBuilder` for the `Async<T>` fields. See `chassis-render-async-state`.

## Examples

### Watch query + command + local flag

```dart
// presentation/user_profile/user_profile_state.dart
import 'package:chassis/chassis.dart';
import '../../domain/users/user.dart';

class UserProfileState {
  const UserProfileState({required this.user, required this.isEditing});

  final Async<User> user;
  final bool isEditing;

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

class UserUpdatedEvent implements UserProfileEvent {
  const UserUpdatedEvent();
}

class UserUpdateFailedEvent implements UserProfileEvent {
  const UserUpdateFailedEvent(this.error);
  final Object error;
}
```

```dart
// presentation/user_profile/user_profile_view_model.dart
import 'package:chassis/chassis.dart';
import 'package:chassis_flutter/chassis_flutter.dart';
import '../../app/app.chassis.dart'; // generated AppMediator
import 'user_profile_state.dart';

class UserProfileViewModel extends ViewModel<UserProfileState, UserProfileEvent> {
  UserProfileViewModel(this._mediator, {required this.userId})
      : super(UserProfileState.initial()) {
    watch(
      _mediator.watchUser(userId: userId),
      key: #user,
      onState: (asyncUser) => setState(state.copyWith(user: asyncUser)),
    );
  }

  final AppMediator _mediator;
  final String userId;

  void toggleEditMode() {
    setState(state.copyWith(isEditing: !state.isEditing));
  }

  void updateEmail(String newEmail) {
    run(
      () => _mediator.updateUserEmail(userId: userId, newEmail: newEmail),
      onSuccess: (_) {
        setState(state.copyWith(isEditing: false));
        sendEvent(const UserUpdatedEvent());
      },
      onError: (error) => sendEvent(UserUpdateFailedEvent(error)),
    );
  }
}
```

### One-time read with full lifecycle in state and a success event

```dart
class ExportProfileViewModel extends ViewModel<ExportProfileState, ExportProfileEvent> {
  ExportProfileViewModel(this._mediator) : super(ExportProfileState.initial());

  final AppMediator _mediator;

  void export(String userId, ExportFormat format) {
    run(
      () => _mediator.exportUserData(userId: userId, format: format),
      current: state.file, // a re-export keeps the previous file visible
      onState: (asyncFile) => setState(state.copyWith(file: asyncFile)),
      onSuccess: (file) => sendEvent(ExportReadyEvent(file.path)),
    );
  }
}
```

`onState` fires on the loading emission, then again on data or error; `onSuccess` fires additively after `onState` on success. The two callbacks coexist on the same `run()` call — providing `onSuccess` never suppresses `onState`.

### Re-watching with a key

```dart
class SearchViewModel extends ViewModel<SearchState, SearchEvent> {
  SearchViewModel(this._mediator) : super(SearchState.initial());

  final AppMediator _mediator;

  void search(String terms) {
    // Each call replaces the previous subscription — no stale results
    // racing into state after the user types a new query.
    watch(
      _mediator.watchSearchResults(terms: terms),
      key: #results,
      current: state.results, // keep showing old results while loading
      onState: (results) => setState(state.copyWith(results: results)),
    );
  }
}
```

### Pattern matching on `Async<T>` when state shape needs branching

```dart
void loadUser(String userId) {
  run(
    () => _mediator.getUser(userId: userId),
    onState: (asyncUser) {
      switch (asyncUser) {
        case AsyncLoading():
          setState(state.copyWith(user: asyncUser));
        case AsyncData(:final value):
          setState(state.copyWith(user: asyncUser, isEditing: false));
          sendEvent(UserLoadedEvent(value));
        case AsyncError(:final error):
          setState(state.copyWith(user: asyncUser));
          sendEvent(UserLoadFailedEvent(error));
      }
    },
  );
}
```

The sealed `Async<T>` union forces every case to be handled at compile time. Use this expanded form when state transitions differ across the lifecycle; the compact form (`onState: (asyncUser) => setState(...)`) is preferable when every state flows into the same field unchanged.

### Anti-pattern: events in state

```dart
// ❌ Don't do this — rebuilds replay the snackbar, navigation loops, manual cleanup required.
class BadState {
  final String? snackbarMessage;
  final String? navigationRoute;
  BadState({this.snackbarMessage, this.navigationRoute});
}

// After consuming, must imperatively clear:
viewModel.setState(state.copyWith(snackbarMessage: null));
```

Use the Event channel instead:

```dart
// ✅ Fires once per occurrence, no manual cleanup, state stays focused on what to render.
sealed class GoodEvent {}

class ShowSnackbarEvent implements GoodEvent {
  const ShowSnackbarEvent(this.message);
  final String message;
}

viewModel.sendEvent(const ShowSnackbarEvent('Saved'));
```

See `chassis-handle-view-model-events` for how listeners consume the event channel.
