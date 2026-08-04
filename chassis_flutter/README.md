# chassis_flutter

Flutter UI integration for the [Chassis](https://pub.dev/packages/chassis) framework. This package provides ViewModel base classes, reactive widgets, and presentation layer utilities following the MVVM pattern.

## Overview

The `chassis_flutter` package connects business logic from the `chassis` core package to the Flutter widget tree. It provides:

* **ViewModel** - State management and command/query dispatch
* **AsyncBuilder** - Renders `Async<T>` states with anti-flickering
* **ViewModelProvider** - Dependency injection using `provider`
* **EventListener** - Turns one-time ViewModel events into UI side effects, with automatic cleanup (also available as `ViewModelProvider.withEventListener` at the provision site and `EventListenerMixin` for StatefulWidgets)
* **SafeChangeNotifier** - A `ChangeNotifier` where `notifyListeners()` after disposal is a no-op instead of an error

## Core Components

### ViewModel

Bridges UI and business logic by holding state and dispatching operations through the Mediator:

```dart
class UserProfileState {
  const UserProfileState({required this.user});
  final Async<User> user;

  UserProfileState copyWith({Async<User>? user}) {
    return UserProfileState(user: user ?? this.user);
  }

  static UserProfileState initial() {
    return UserProfileState(user: Async.loading());
  }
}

sealed class UserProfileEvent {}
class UserUpdatedEvent implements UserProfileEvent {}

class UserProfileViewModel extends ViewModel<UserProfileState, UserProfileEvent> {
  UserProfileViewModel(this._mediator) : super(UserProfileState.initial());

  final Mediator _mediator;

  void loadUser(String userId) {
    watch(
      _mediator.watch(WatchUserQuery(userId: userId)),
      current: state.user,
      onState: (asyncUser) {
        setState(state.copyWith(user: asyncUser));
      },
    );
  }

  void updateEmail(String userId, String newEmail) {
    run(
      () => _mediator.run(UpdateUserEmailCommand(userId: userId, newEmail: newEmail)),
      onSuccess: (_) => sendEvent(UserUpdatedEvent()),
    );
  }
}
```

### The run() / watch() callback contract

Both methods share the same callback contract:

* `onState` (if provided) is invoked for **every** transition: loading, data, and error.
* `onSuccess` (`run`) / `onData` (`watch`) and `onError` are **additive** conveniences, invoked *after* `onState` for their respective transition. Providing them never suppresses `onState`. They carry the same value — a `run` result is a *success*, a `watch` emission is *data*.
* Callbacks run *outside* the internal try/catch: an exception thrown by your callback is a bug in the callback and propagates as such — it is never converted into an `AsyncError`.
* At least one callback is required (enforced by an assert).
* Callbacks are never invoked after the ViewModel is disposed.

```dart
void createUser(String name, String email) {
  run(
    () => mediator.run(CreateUserCommand(name: name, email: email)),
    onState: (user) => setState(state.copyWith(user: user)),   // every transition
    onSuccess: (user) => sendEvent(UserCreatedEvent()),        // additionally, on success
    onError: (error) => sendEvent(CreateFailedEvent()),        // additionally, on failure
  );
}
```

### run() - Execute async operations

```dart
Future<Async<R>> run<R>(
  Future<R> Function() operation, {
  Object? key,
  RunPolicy policy = const RunPolicy.concurrent(),
  Async<R>? current,
  bool emitLoading = true,
  void Function(Async<R> state)? onState,
  void Function(R value)? onSuccess,
  void Function(Object error)? onError,
})
```

`run` takes a *closure*, not a `Future`: a `Future` is already executing when you hold it, and the policies below need to defer, coalesce, or skip the execution entirely.

| Parameter | Description |
|-----------|-------------|
| `key` | Groups runs for `policy`. Required by every policy except `concurrent`; all runs sharing a key must have the same result type `R`. |
| `policy` | How runs sharing the same `key` interact — see [Run policies](#run-policies) below. |
| `current` | The current `Async` state, if any. The initial loading emission and an error result carry its data (`AsyncData`), so a refetch does not blank the UI (anti-flicker). |
| `emitLoading` | Whether to emit a loading state when the operation dispatches (for a debounced run, that is when the debounce window fires). Set to `false` for background refreshes that should not surface a loading state. |

Returns the final `Async<R>` state (`AsyncData` or `AsyncError`). A dropped or debounce-coalesced call resolves with the winning run's result. If the ViewModel is disposed while a debounced run is still pending, the returned future resolves with an `AsyncError` describing the cancellation — the operation itself never ran.

```dart
void refreshUser(String userId) {
  run(
    () => mediator.read(GetUserQuery(userId: userId)),
    current: state.user, // keep showing the previous user while refetching
    onState: (asyncUser) => setState(state.copyWith(user: asyncUser)),
  );
}
```

### Run policies

`RunPolicy` declares how concurrent invocations of the same logical operation interact. Runs are grouped by `key`; every policy except `concurrent` requires one (enforced by an assert).

| Policy | Behavior | Typical use |
|--------|----------|-------------|
| `RunPolicy.concurrent()` *(default)* | Every call executes independently. | Unrelated operations. |
| `RunPolicy.restartable({Duration debounce})` | A new call supersedes the in-flight one: the superseded run still completes but stops reporting state. With `debounce`, calls inside the window coalesce into one. | Search-as-you-type, refetch with latest arguments. |
| `RunPolicy.droppable()` | While a run is in flight, new calls are dropped and resolve with the in-flight run's result. | Submit buttons, pull-to-refresh. |
| `RunPolicy.sequential()` | Calls queue and execute one at a time, in order. | Ordered mutations (reorder, incremental sync). |

```dart
void search(String terms) {
  run(
    () => mediator.read(SearchQuery(terms: terms)),
    key: #search,
    policy: const RunPolicy.restartable(debounce: Duration(milliseconds: 300)),
    current: state.results,
    onState: (results) => setState(state.copyWith(results: results)),
  );
}

void submit() {
  run(
    () => mediator.run(SubmitOrderCommand()),
    key: #submit,
    policy: const RunPolicy.droppable(), // double-taps resolve with the first run
    onSuccess: (_) => sendEvent(OrderSubmittedEvent()),
  );
}
```

There is deliberately no debounce-only policy: debouncing without latest-wins invalidation would still let an older run's result overwrite a newer one. Debounce is therefore an option of `restartable`, where superseded runs stop reporting.

### watch() - Subscribe to streams

```dart
WatchHandle watch<R>(
  Stream<R> stream, {
  Object? key,
  Async<R>? current,
  bool emitLoading = true,
  void Function(Async<R> state)? onState,
  void Function(R data)? onData,
  void Function(Object error)? onError,
  void Function()? onDone,
})
```

| Parameter | Description |
|-----------|-------------|
| `key` | Optional. If provided, a previous `watch` with the same key is cancelled and replaced — see [UI Integration](https://github.com/pierremrtn/chassis/blob/main/docs/04_ui_integration.md) for the re-watch pattern. Without a key, subscriptions are additive and live until disposal. |
| `current` | Same anti-flicker behavior as in `run`. |
| `emitLoading` | Whether to emit a loading state immediately. |
| `onDone` | Invoked when the stream itself completes — never on cancellation (keyed replacement, `WatchHandle.cancel`, or disposal). Without it, a finite stream ending is invisible: the state stays frozen on the last emission. The handle is released before `onDone` runs, so re-watching under the same key from inside it is safe. |

Returns a `WatchHandle` to cancel the subscription before disposal:

```dart
final handle = watch(
  mediator.watch(WatchOrdersQuery()),
  onState: (orders) => setState(state.copyWith(orders: orders)),
);

// Later, if needed (safe to call twice):
await handle.cancel();
handle.isCancelled; // true — also set by keyed replacement or disposal
```

Stream errors do not terminate the state flow abruptly: the error emission carries the last known data (soft error), so the UI can keep rendering stale data alongside the error.

All subscriptions are automatically cancelled when the ViewModel is disposed.

### Events

`sendEvent` emits one-time notifications on the `events` stream. Events emitted *before the first subscription* are buffered (bounded) and delivered to the first subscriber, so events sent during construction are not lost. After the first subscription, regular broadcast semantics apply: events emitted while nobody listens are dropped.

`ViewModelProvider.withEventListener` creates the ViewModel eagerly and subscribes immediately, so it receives construction-time events.

### AsyncBuilder

Renders `Async<T>` states with custom loading, error, and data builders:

```dart
AsyncBuilder<User>(
  state: context.select((UserProfileViewModel vm) => vm.state.user),
  builder: (context, user) {
    return Column(
      children: [
        CircleAvatar(backgroundImage: NetworkImage(user.avatarUrl)),
        Text(user.name),
        Text(user.email),
      ],
    );
  },
  loadingBuilder: (context) => CircularProgressIndicator(),
  errorBuilder: (context, error) => Text('Error: $error'),
  maintainState: true, // Show previous data during refetch (anti-flickering)
)
```

**Parameters:**

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `state` | `Async<T>` | The async state to render | Required |
| `builder` | `Widget Function(BuildContext, T)` | Renders when data is available | Required |
| `loadingBuilder` | `WidgetBuilder?` | Renders during loading without data | `CircularProgressIndicator` |
| `errorBuilder` | `Widget Function(BuildContext, Object)?` | Renders on error without data | Diagnostic `ErrorWidget` in debug builds (so missed errors are visible), `SizedBox.shrink()` in release |
| `maintainState` | `bool` | Keep rendering carried data while loading or in error | `true` |

With `maintainState: true` (the default), `builder` is called whenever the state has a value — including `AsyncLoading` / `AsyncError` states carrying `previous` data — which prevents flickering during refetches.

Nullable types are fully supported: for `AsyncBuilder<int?>`, a state of `AsyncData(null)` renders the data branch with `null` as the value, not the loading branch. The distinction between "no value yet" and "the value is null" is preserved by `Async<T>` itself.

### ViewModelProvider

Provides ViewModels to the widget tree using the `provider` package:

```dart
ViewModelProvider(
  create: (context) => UserProfileViewModel(mediator),
  child: UserProfileScreen(),
)
```

Access the ViewModel in widgets:

```dart
// Rebuild only when the selected field changes — preferred for rendering
final asyncUser = context.select(
  (UserProfileViewModel vm) => vm.state.user,
);

// Rebuild on every state change — for widgets that render most of the state
final viewModel = context.watch<UserProfileViewModel>();

// Access without rebuilding — for callbacks
final viewModel = context.read<UserProfileViewModel>();

// Or without the provider extensions
final viewModel = ViewModelProvider.of<UserProfileViewModel>(context);
```

`ViewModelProvider.value(value: ...)` provides an existing instance to a new subtree without taking ownership of its disposal.

When a subtree needs several ViewModels, `MultiViewModelProvider` flattens the nesting:

```dart
MultiViewModelProvider(
  providers: [
    ViewModelProvider(create: (context) => UserViewModel(mediator)),
    ViewModelProvider(create: (context) => CartViewModel(mediator)),
  ],
  child: const HomeScreen(),
)
```

### Listening to events

Handle one-time events from a ViewModel via `ViewModelProvider.withEventListener`, which wires up the subscription at the point of provision and cleans it up automatically:

```dart
ViewModelProvider.withEventListener<UserProfileViewModel, UserProfileEvent>(
  create: (_) => UserProfileViewModel(mediator),
  onEvent: (context, viewModel, event) {
    switch (event) {
      case UserUpdatedEvent():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile updated')),
        );
    }
  },
  child: UserProfileScreen(),
);
```

The `context` passed to `onEvent` sits *above* the provided ViewModel in the tree, so `ScaffoldMessenger.of(context)` and `Navigator.of(context)` work as expected. Use the `viewModel` argument instead of `context.read` when you need the VM itself. Unlike the default (lazy) constructor, `withEventListener` creates the ViewModel eagerly so that events emitted during construction are not missed.

When a descendant subtree needs to listen to a ViewModel provided by an ancestor, wrap it in an `EventListener` — the event-side counterpart of `AsyncBuilder`:

```dart
EventListener<UserProfileViewModel, UserProfileEvent>(
  onEvent: (context, event) {
    // React to events from the ancestor-provided VM. This context sits
    // below the provider, so context.read<UserProfileViewModel>() works.
  },
  child: const UserProfileDetails(),
);
```

The listener resubscribes automatically if the provider swaps its ViewModel instance, and passes its `child` through untouched — state changes never rebuild the subtree through it.

Finally, `EventListenerMixin` serves widgets that are already `StatefulWidget`s and would rather not wrap their tree, or whose handler needs local `State` fields (controllers, focus nodes):

```dart
class _UserProfileDetailsState extends State<UserProfileDetails> with EventListenerMixin {
  @override
  void initState() {
    super.initState();
    onEvent<UserProfileViewModel, UserProfileEvent>((event) {
      // React to events from an ancestor-provided VM.
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

### SafeChangeNotifier

`ViewModel` extends `SafeChangeNotifier`, a drop-in replacement for Flutter's `ChangeNotifier` that makes `notifyListeners()` a no-op, rather than an error, after disposal. Both `SafeChangeNotifier` and the `SafeNotifierMixin` are exported for your own notifiers:

```dart
class MyNotifier extends SafeChangeNotifier {
  void update() {
    notifyListeners(); // Safe to call even after disposal
  }
}
```

## Complete Example

This is the package's [runnable example](https://github.com/pierremrtn/chassis/blob/main/chassis_flutter/example/example.dart): a counter streaming from the logic layer, with a reset command and a one-time event.

```dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

// --- Logic layer: query + handler ---

final class WatchCounterQuery extends WatchQuery<int> {}

class WatchCounterHandler implements WatchHandler<WatchCounterQuery, int> {
  @override
  Stream<int> watch(WatchCounterQuery query) =>
      Stream.periodic(const Duration(seconds: 1), (i) => i);
}

final class ResetCounterCommand extends Command<void> {}

class ResetCounterHandler implements CommandHandler<ResetCounterCommand, void> {
  @override
  Future<void> run(ResetCounterCommand command) async {}
}

// --- Presentation layer: state, events, view model ---

class CounterState {
  const CounterState({this.count = const Async.loading()});

  final Async<int> count;

  CounterState copyWith({Async<int>? count}) =>
      CounterState(count: count ?? this.count);
}

sealed class CounterEvent {}

final class CounterResetEvent implements CounterEvent {}

class CounterViewModel extends ViewModel<CounterState, CounterEvent> {
  CounterViewModel(this._mediator) : super(const CounterState()) {
    watchCounter();
  }

  final Mediator _mediator;

  void watchCounter() {
    watch(
      _mediator.watch(WatchCounterQuery()),
      current: state.count,
      onState: (count) => setState(state.copyWith(count: count)),
    );
  }

  void reset() {
    run(
      () => _mediator.run(ResetCounterCommand()),
      onSuccess: (_) => sendEvent(CounterResetEvent()),
    );
  }
}

// --- App wiring ---

void main() {
  final mediator = Mediator()
    ..registerQueryHandler(WatchCounterHandler())
    ..registerCommandHandler(ResetCounterHandler())
    ..addMiddleware(LoggingMiddleware());

  runApp(MyApp(mediator: mediator));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.mediator});

  final Mediator mediator;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ViewModelProvider.withEventListener<CounterViewModel, CounterEvent>(
        create: (context) => CounterViewModel(mediator),
        onEvent: (context, viewModel, event) {
          switch (event) {
            case CounterResetEvent():
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Counter reset')),
              );
          }
        },
        child: const CounterScreen(),
      ),
    );
  }
}

class CounterScreen extends StatelessWidget {
  const CounterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chassis counter')),
      body: Center(
        child: AsyncBuilder<int>(
          state: context.select(
            (CounterViewModel vm) => vm.state.count,
          ),
          builder: (context, count) => Text('Count: $count'),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.read<CounterViewModel>().reset(),
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
```

In a real application the mediator would be the generated `AppMediator` from [chassis_builder](https://pub.dev/packages/chassis_builder) rather than a hand-wired `Mediator`.

## State vs Events

**State** - Persistent data that determines UI rendering:

```dart
class UserListState {
  const UserListState({required this.users});
  final Async<List<User>> users;
}
```

**Events** - One-time notifications for side effects:

```dart
sealed class UserListEvent {}
class UserDeletedEvent implements UserListEvent {}
class UserDeleteFailedEvent implements UserListEvent {
  const UserDeleteFailedEvent(this.message);
  final String message;
}
```

Events handle navigation, dialogs, snackbars—actions that happen once and should not persist in state.

## Testing

### ViewModel Testing

```dart
class MockMediator extends Mock implements Mediator {}

void main() {
  setUpAll(() {
    registerFallbackValue(WatchUserQuery(userId: ''));
  });

  test('loadUser dispatches WatchUserQuery', () {
    final mockMediator = MockMediator();
    when(() => mockMediator.watch<User>(any()))
        .thenAnswer((_) => Stream.value(User(id: '1', name: 'John')));

    final viewModel = UserProfileViewModel(mockMediator);
    viewModel.loadUser('1');

    verify(() => mockMediator.watch<User>(any())).called(1);
  });
}
```

### Widget Testing

```dart
class MockUserViewModel extends Mock implements UserProfileViewModel {}

testWidgets('UserScreen displays user from ViewModel', (tester) async {
  final mockViewModel = MockUserViewModel();

  when(() => mockViewModel.state).thenReturn(
    UserProfileState(user: Async.data(User(id: '1', name: 'Alice'))),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: ViewModelProvider.value(
        value: mockViewModel,
        child: UserScreen(),
      ),
    ),
  );

  expect(find.text('Alice'), findsOneWidget);
});
```

## Installation

Add to `pubspec.yaml`:

```yaml
dependencies:
  chassis: ^1.0.0
  chassis_flutter: ^1.0.0
```

`chassis_flutter` re-exports `chassis` and `provider`, so a single import covers the full API:

```dart
import 'package:chassis_flutter/chassis_flutter.dart';
```

## Next Steps

* **[Quick Start](https://github.com/pierremrtn/chassis/blob/main/docs/00_quick_start.md)** - Build a complete application
* **[UI Integration](https://github.com/pierremrtn/chassis/blob/main/docs/04_ui_integration.md)** - Deep dive into ViewModel and AsyncBuilder
* **[Core Architecture](https://github.com/pierremrtn/chassis/blob/main/docs/01_core_architecture.md)** - Understand the architectural principles
* **[chassis](https://pub.dev/packages/chassis)** - Core package documentation

## License

MIT License - See [LICENSE](https://github.com/pierremrtn/chassis/blob/main/LICENSE) for details.
