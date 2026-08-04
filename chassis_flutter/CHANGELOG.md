# Changelog

## 1.0.0

First stable release.

### Breaking changes

- `ViewModel` no longer takes or stores a `Mediator`: the constructor is now
  `ViewModel(T initial)` (a single positional parameter, like Bloc's
  `Bloc(initialState)`). The base class never used the mediator — `run` and
  `watch` receive closures/streams. Migration: keep a typed field on the
  subclass and pass only the initial state to super:
  `MyViewModel(this._mediator) : super(MyState.initial());` with
  `final AppMediator _mediator;`.
- `ViewModel.run` now takes a closure (`Future<R> Function()`) instead of a
  `Future<R>`, so a `RunPolicy` can defer or skip dispatch. Migration:
  `run(mediator.foo(...))` → `run(() => mediator.foo(...))`.
- Removed the rxdart-based `BaseUtils` helpers (`listenToStreams`,
  `combineStreams`, `combineStreams2`, `combineStreams3`) and the rxdart
  dependency. Depend on rxdart directly and pass the combined stream to
  `watch()` if you need them.
- `ConsumerMixin` is renamed `EventListenerMixin`, and registers event
  listeners per ViewModel *instance* (was: per type), so a recreated
  ViewModel can be listened to again.
- `ViewModel.run`/`watch` callback contract redesigned: `onState` (if
  provided) is now invoked for **every** transition (loading, data, error);
  `onSuccess` (`run`) / `onData` (`watch`) and `onError` are additive
  conveniences invoked after `onState`. Previously, providing
  `onData`/`onError` suppressed `onState`, which could leave state stuck on
  loading. `run`'s success callback is named `onSuccess` (a one-shot result
  is a success); `watch` keeps `onData` (a stream emission is data).
- Callbacks are invoked outside the internal try/catch: an exception thrown
  by a callback propagates as the bug it is, instead of silently converting a
  successful operation into an `AsyncError`.
- `watch` now returns a `WatchHandle` (cancellable) and accepts a `key`: a
  new `watch` with the same key cancels and replaces the previous
  subscription. Previously re-watching stacked subscriptions that all kept
  writing into the state until dispose.
- Aligned with the new `Async<T>` API from `chassis` 1.0.0 (`previous` is an
  `AsyncData<T>?`).

### New

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
- `ViewModel.run` accepts `key` and `policy` (`RunPolicy`) to control how
  overlapping runs on the same key interact: `concurrent` (default),
  `restartable({debounce})` (latest wins, optional coalescing window),
  `droppable` (first wins), `sequential` (queued per key). Fixes the stale
  result race where the oldest dispatch could overwrite the newest state.
- `AsyncBuilder` without an `errorBuilder` now renders a standard
  `ErrorWidget` in debug builds instead of silently collapsing to an empty
  box (release builds still render nothing).
- `run`/`watch` accept `current` (the current `Async` state): loading and
  error transitions carry its data, so a refetch no longer blanks the UI.
- `run`/`watch` accept `emitLoading` (default `true`).
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
