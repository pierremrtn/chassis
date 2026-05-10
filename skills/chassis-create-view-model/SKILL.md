---
name: chassis-create-view-model
description: Implement a Flutter ViewModel for a Chassis screen as a `ViewModel<State, Event>` subclass that holds an immutable State, emits sealed Event types for one-time UI side effects, and dispatches operations through the Mediator's `run()` and `watch()` lifecycle methods. Use when adding a screen, dialog, or feature that needs reactive state, async data, or one-shot UI events.
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

ViewModels never call repositories directly and never contain business logic. The architectural rule is strict: every operation goes through `mediator.<extension>(...)`, which routes to a Handler that owns the logic. This keeps ViewModels thin transformation layers and concentrates business rules in tested, framework-independent handlers.

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
    return UserProfileState(user: Async.loading(), isEditing: false);
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

Events are emitted with `sendEvent(...)` from inside the ViewModel and consumed by `ViewModelProvider.withEvents` or `ConsumerMixin` — see `chassis-handle-view-model-events`.

> A common mistake is modeling events as nullable state properties, such as `String? snackbarMessage` in the state class. (...) Rebuilds replay events — if the widget rebuilds for unrelated reasons, the snackbar shows again. (...) Events solve these problems by firing once per occurrence, regardless of rebuilds.
> — `docs/04_ui_integration.md`

## Lifecycle Methods: `run()` and `watch()`

The ViewModel base class provides two methods for handling asynchronous operations. They wrap a `Future<T>` or `Stream<T>` (typically obtained from a Mediator extension method) and route the result through callbacks. Subscriptions and disposable resources are tracked automatically and cleaned up when the ViewModel disposes.

- `run(Future<T> future, {onState, onData, onError})` — for one-time futures: commands and read queries.
- `watch(Stream<T> stream, {onState, onData, onError})` — for streams: watch queries.

Three callback shapes are available, and you pick whichever matches the call site:

- **`onState`** — receives `Async<T>` covering loading, data, and error. Use when state mirrors the operation's full lifecycle (typical for queries that drive an `AsyncBuilder`).
- **`onData`** — fires only on success with the unwrapped value. Use for command success when the state does not need to track loading.
- **`onError`** — fires only on failure with the raw error. Use to dispatch a failure event without polluting state.

Mix `onData` and `onError` when success and failure should branch into different events but loading is irrelevant in state.

## Rules

- **DO** subclass `ViewModel<TState, TEvent>` and pass the initial state to the super constructor (`super(mediator, initial: TState.initial())`). *The base class wires `ChangeNotifier` lifecycle, event stream, and resource cleanup.*
- **DO** define an immutable `TState` class with `final` fields, a `copyWith` method, and a static `initial()` factory. *Immutability makes transitions explicit, debuggable, and safe under concurrent dispatch.*
- **DO** wrap every asynchronous datum in state with `Async<T>`. *`AsyncBuilder` and pattern matching require it; loading and error states cannot be forgotten.*
- **DO** define a sealed `TEvent` class with one variant per one-time occurrence. *Sealed unions give exhaustive `switch` at the listener.*
- **DO** dispatch every operation through `mediator.<extension>(...)` — the type-safe extension generated from a `@chassisHandler`-annotated handler.
- **DO** use `setState(state.copyWith(...))` to update state. *`setState` is the framework's notify hook; direct field mutation does not exist on an immutable state.*
- **DO** use `sendEvent(<EventVariant>)` for one-time UI side effects.
- **DO** subscribe to long-lived streams in the ViewModel constructor (or in a method called once) using `watch(...)`. *The framework disposes the subscription with the ViewModel.*
- **DO** route query errors through state via `onState` so `AsyncBuilder.errorBuilder` renders them. *Queries produce the data the screen needs; without it there is no useful view.*
- **DO** route command errors through events via `onError` (`sendEvent(<FailedEvent>(error))`). *Commands are triggered on screens that already have valid content; a failed command should not replace the view.*
- **DO** rely on `autoDispose` / `autoDisposeStreamSubscription` for any `Disposable` resource the ViewModel owns. *Manual cleanup is error-prone; the framework cleans up in reverse order on dispose.*
- **DON'T** call repositories from a ViewModel. *ViewModels depend only on the Mediator; business logic lives in Handlers.*
- **DON'T** put business logic in the ViewModel. *Validation, orchestration, and rules belong in Handlers, where they are testable in isolation.*
- **DON'T** model one-time occurrences as nullable state fields (`String? snackbarMessage`). *Rebuilds replay them; manual cleanup is required; state becomes polluted.* Use the Event channel.
- **DON'T** mutate state in place. *State is immutable; create a new instance via `copyWith`.*
- **DON'T** manually manage stream subscriptions inside a ViewModel. *Use `watch(...)` so the framework owns subscription lifecycle.*

## Workflow

- [ ] **Step 1 — Identify the screen's data needs.** What domain data does it render (queries)? What user actions does it accept (commands)? What one-time UI effects does it produce (events)?
- [ ] **Step 2 — Define the State class** with the persistent UI data. Wrap async fields in `Async<T>`. Add `copyWith` and `initial()`.
- [ ] **Step 3 — Define the Event sealed class** with one variant per one-time occurrence. Each variant `implements <Feature>Event` and carries only what the listener needs.
- [ ] **Step 4 — Subclass `ViewModel<State, Event>`.** Pass `super(mediator, initial: State.initial())`.
- [ ] **Step 5 — For watch-based data**, call `watch(mediator.<watchQuery>(...), onState: ...)` in the constructor (or in a `load(...)` method called once). Update state with `setState(state.copyWith(...))`.
- [ ] **Step 6 — For one-time fetches**, expose a method that calls `run(mediator.<readQuery>(...), onState: ...)`.
- [ ] **Step 7 — For commands**, expose a method that calls `run(mediator.<command>(...), onData: ..., onError: ...)`. Emit success and failure events via `sendEvent(...)`.
- [ ] **Step 8 — For local UI flags** (`isEditing`, selected tab, form-step index), expose simple methods that call `setState(state.copyWith(...))` directly — no Mediator involved.
- [ ] **Step 9 — Provide the ViewModel** to the widget subtree using `ViewModelProvider` or `ViewModelProvider.withEvents`. See `chassis-consume-view-model` and `chassis-handle-view-model-events`.
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
      UserProfileState(user: Async.loading(), isEditing: false);
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
import '../../app/app_mediator.dart';
import 'user_profile_state.dart';

class UserProfileViewModel extends ViewModel<UserProfileState, UserProfileEvent> {
  UserProfileViewModel(super.mediator, {required this.userId})
      : super(initial: UserProfileState.initial()) {
    watch(
      mediator.watchUser(userId: userId),
      onState: (asyncUser) => setState(state.copyWith(user: asyncUser)),
    );
  }

  final String userId;

  void toggleEditMode() {
    setState(state.copyWith(isEditing: !state.isEditing));
  }

  void updateEmail(String newEmail) {
    run(
      mediator.updateUserEmail(userId: userId, newEmail: newEmail),
      onData: (_) {
        setState(state.copyWith(isEditing: false));
        sendEvent(const UserUpdatedEvent());
      },
      onError: (error) => sendEvent(UserUpdateFailedEvent(error)),
    );
  }
}
```

### One-time read with full lifecycle in state

```dart
class ExportProfileViewModel extends ViewModel<ExportProfileState, ExportProfileEvent> {
  ExportProfileViewModel(super.mediator)
      : super(initial: ExportProfileState.initial());

  void export(String userId, ExportFormat format) {
    run(
      mediator.exportUserData(userId: userId, format: format),
      onState: (asyncFile) => setState(state.copyWith(file: asyncFile)),
      onData: (file) => sendEvent(ExportReadyEvent(file.path)),
    );
  }
}
```

The `onState` callback maintains the loading / data / error lifecycle in state for an `AsyncBuilder` to render, while `onData` separately fires a one-time event when the export is ready. Both callbacks coexist on the same `run()` call.

### Pattern matching on `Async<T>` when state shape needs branching

```dart
void loadUser(String userId) {
  run(
    mediator.getUser(userId: userId),
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
