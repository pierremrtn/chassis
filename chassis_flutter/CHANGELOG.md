# Changelog

## 1.0.0

First stable release.

Requires Dart 3.13+: the library and every documented example use primary
constructors, stable since Dart 3.13.

### Breaking changes

- **Message-direct dispatch.** `ViewModel.run`/`watch` no longer take a
  closure/stream: they take the message itself — `run(Command<R>)`,
  `watch(WatchQuery<R>)` — plus the new `read(ReadQuery<R>)`. The dispatch
  happens inside the framework's machinery, through the mediator installed by
  `Chassis.initialize` (or the constructor override). ViewModels never
  reference a generated mediator class: a ViewModel method is synchronous and
  expression-bodied — `void addTodo(String title) => run(AddTodoCommand(title),
  ...)`. Platform interactions (image picker, permissions, biometrics) belong
  in the widget, which awaits them and passes plain data to the ViewModel.
- `Chassis.initialize(Mediator)`: installs the application mediator once, in
  `main()` before `runApp`. `ViewModel`'s constructor is
  `ViewModel(T initial, {Mediator? mediator})` — the named parameter
  overrides the global (the testing seam; no shared static between tests).
  Resolution is lazy, at the first dispatch, and fails with an actionable
  `StateError` when nothing is installed.
- Operations are keyed by default: `key` defaults to the message's runtime
  type, so two dispatches of the same message class share their `RunPolicy` —
  and a re-`watch` of the same query class *replaces* the previous
  subscription (pass distinct explicit keys for additive watches). The
  "policy requires a key" assert is gone.
- `onError` callbacks now receive the stack trace:
  `void Function(Object error, StackTrace stack)` on `run`, `read`, and
  `watch`.
- A `WatchHandler` that throws synchronously (not `async*`) now reports a
  soft `AsyncError` through the callbacks — the same outcome the identical
  failure has when the handler is `async*` — instead of crashing at the call
  site. The returned `WatchHandle` is already cancelled.
- Removed the rxdart-based `BaseUtils` helpers (`listenToStreams`,
  `combineStreams`, `combineStreams2`, `combineStreams3`) and the rxdart
  dependency. Depend on rxdart directly and expose the combined stream
  through a `WatchQuery` handler if you need them.
- `ConsumerMixin` is renamed `EventListenerMixin`, and registers event
  listeners per ViewModel *instance* (was: per type), so a recreated
  ViewModel can be listened to again.
- `ViewModel.run`/`read`/`watch` callback contract redesigned: `onState` (if
  provided) is now invoked for **every** transition (loading, data, error);
  `onSuccess` (`run`/`read`) / `onData` (`watch`) and `onError` are additive
  conveniences invoked after `onState`. Previously, providing
  `onData`/`onError` suppressed `onState`, which could leave state stuck on
  loading. `run`'s success callback is named `onSuccess` (a one-shot result
  is a success); `watch` keeps `onData` (a stream emission is data).
- Callbacks are invoked outside the internal try/catch: an exception thrown
  by a callback propagates as the bug it is, instead of silently converting a
  successful operation into an `AsyncError`.
- `watch` returns a `WatchHandle` (cancellable): a new `watch` with the same
  key cancels and replaces the previous subscription. Previously re-watching
  stacked subscriptions that all kept writing into the state until dispose.
- `SafeChangeNotifier`'s dispose chain now reaches `ChangeNotifier.dispose()`
  (it previously stopped at a pure-Dart mixin): Flutter's use-after-dispose
  debug asserts and leak tracking are armed again. `addListener` on a
  disposed notifier now throws in debug builds — only *notifying* is a safe
  no-op after disposal.
- Aligned with the new `Async<T>` API from `chassis` 1.0.0 (`previous` is an
  `AsyncData<T>?`).

### New

- `ViewModel.run`/`read` accept an `optimistic:` parameter (`AsyncData<R>?`):
  emitted through `onState` at dispatch instead of a loading state, so the
  field takes the expected value immediately. `onSuccess`/`onError` fire only
  for the real result. On failure, the reported `AsyncError.previous` is the
  last *confirmed* data (the latest completed run on the same `key`, or the
  data carried by `current:`) — never the optimistic value — so the UI rolls
  back. Typed `AsyncData` rather than a bare value so that, for a nullable
  `R`, `optimistic: AsyncData(null)` stays distinct from "not optimistic".
- Sharing a `key` across runs with different result types triggers a debug
  assert naming the key and both types, instead of a cryptic `CastError`
  inside the policy machinery.

- `EventListener`: a widget that invokes a callback for each event of the
  ViewModel provided above it — the event-side counterpart of `AsyncBuilder`
  (state maps to widgets, events map to one-shot side effects). Its callback
  context sits below the provider, so `context.read<T>()` resolves the
  emitting view model, and it resubscribes automatically if the provider
  swaps its instance.
- `ViewModelProvider.withEventListener`: provides a ViewModel and listens to
  its events in one widget — the fusion of `ViewModelProvider` and
  `EventListener` for the common case where the provision site handles the
  events. Created eagerly so construction-time events are not missed.
- `ViewModel.run`/`read` accept `key` and `policy` (`RunPolicy`) to control
  how overlapping runs on the same key interact: `concurrent` (default),
  `restartable({debounce})` (latest wins, optional coalescing window),
  `droppable` (first wins), `sequential` (queued per key). Fixes the stale
  result race where the oldest dispatch could overwrite the newest state.
- `AsyncBuilder` without an `errorBuilder` now renders a standard
  `ErrorWidget` in debug builds instead of silently collapsing to an empty
  box (release builds still render nothing).
- `run`/`read`/`watch` accept `current` (the current `Async` state): loading
  and error transitions carry its data, so a refetch no longer blanks the UI.
- `run`/`read`/`watch` accept `emitLoading` (default `true`).
- `watch` accepts `onDone`, invoked when the watched stream itself completes
  (never on cancellation — keyed replacement, `WatchHandle.cancel`, or
  disposal). Without it, a finite stream ending was invisible: the state
  stayed frozen on the last emission. The handle is released before `onDone`
  runs, so re-watching under the same key from inside it is safe.
- Events emitted before the first subscription to `events` are buffered
  (bounded) and delivered to the first subscriber — `ViewModelProvider
  .withEventListener` now really receives events emitted during construction, as its
  documentation always promised.
- `SafeChangeNotifier`/`SafeNotifierMixin` are now exported.
- `MultiViewModelProvider`: merges multiple `ViewModelProvider`s without
  nesting (same shape as provider's `MultiProvider`).
- `AsyncBuilder` renders the data branch for `AsyncData(null)` with nullable
  `T`, and renders data when `maintainState` is false (previously it fell
  through to an empty box).

### Fixed

- `ViewModel.dispose` now closes the events stream, cancels keyed watches,
  and reports cleanup exceptions through `FlutterError.reportError` instead
  of swallowing them.
- Callbacks are not invoked after the ViewModel is disposed.

## 0.0.1+2

- doc: added pubspec topics.
- doc: README improvements.

## 0.0.1+1

- doc: README improvements.

## 0.0.1

- Initial version.
