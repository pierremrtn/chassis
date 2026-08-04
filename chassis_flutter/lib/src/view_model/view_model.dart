import 'dart:async';

import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/foundation.dart';

/// A handle on a subscription started with [ViewModel.watch].
///
/// Allows cancelling the subscription before the ViewModel is disposed.
class WatchHandle {
  WatchHandle._(this._cancel);

  final Future<void> Function() _cancel;
  bool _cancelled = false;

  /// Whether [cancel] has been called (directly, by a keyed replacement, by
  /// the watched stream completing, or by the ViewModel's disposal).
  bool get isCancelled => _cancelled;

  /// Cancels the underlying stream subscription. Safe to call twice.
  Future<void> cancel() {
    if (_cancelled) return Future<void>.value();
    _cancelled = true;
    return _cancel();
  }
}

/// {@template view_model}
/// A base class for view models that provides state management and event handling.
///
/// This class extends [SafeChangeNotifier] to provide safe disposal behavior.
/// It manages both state (of type [T]) and events (of type [E]) in a reactive way.
///
/// The ViewModel provides:
/// - State management with automatic UI updates
/// - Event emission for one-time notifications
/// - Async operation lifecycle via [run], reported as [Async] states
/// - Automatic cleanup of resources and subscriptions
/// - Stream watching with state management
///
/// ViewModels typically keep a field typed as the generated mediator
/// (`AppMediator`, or a module interface like `AuthMediator`) and dispatch
/// operations through it inside [run] and [watch] closures.
///
/// ## Callback contract of [run] and [watch]
///
/// - `onState` (if provided) is invoked for **every** transition: loading,
///   data, and error.
/// - `onSuccess` ([run]) / `onData` ([watch]) and `onError` are **additive**
///   conveniences, invoked *after* `onState` for their respective transition.
///   Providing them never suppresses `onState`. They carry the same value: a
///   [run] result is a *success*, a [watch] emission is *data*.
/// - `onDone` ([watch] only) is invoked when the watched stream completes —
///   never on cancellation (keyed replacement, handle cancel, or disposal).
/// - Callbacks are invoked *outside* the internal try/catch: an exception
///   thrown by your callback is a bug in the callback and propagates as such —
///   it is never converted into an [AsyncError].
///
/// ## Concurrency
///
/// Overlapping [run] calls writing to the same state field race: the last
/// completion wins, which may be the oldest dispatch. Give such runs a `key`
/// and a [RunPolicy] to control who wins (see [RunPolicy]). [watch] gets the
/// same protection from its `key` parameter: a new keyed watch replaces the
/// previous subscription.
///
/// Example usage:
/// ```dart
/// class UserViewModel extends ViewModel<UserState, UserEvent> {
///   UserViewModel(this._mediator) : super(UserState.initial());
///
///   final AppMediator _mediator;
///
///   void loadUser(String userId) {
///     run(
///       () => _mediator.getUser(userId),
///       key: #user,
///       policy: const RunPolicy.restartable(),
///       current: state.user,
///       onState: (user) => setState(state.copyWith(user: user)),
///     );
///   }
///
///   void watchUser(String userId) {
///     // Re-calling watchUser with a new id replaces the previous
///     // subscription thanks to the key.
///     watch(
///       _mediator.watchUser(userId),
///       key: #user,
///       current: state.user,
///       onState: (user) => setState(state.copyWith(user: user)),
///     );
///   }
///
///   void createUser(String name, String email) {
///     run(
///       () => _mediator.createUser(name: name, email: email),
///       key: #createUser,
///       policy: const RunPolicy.droppable(),
///       onState: (user) => setState(state.copyWith(user: user)),
///       onSuccess: (user) => sendEvent(UserCreatedEvent(user)),
///       onError: (error) => sendEvent(UserCreationFailedEvent(error.toString())),
///     );
///   }
/// }
/// ```
/// {@endtemplate}
class ViewModel<T, E> extends SafeChangeNotifier {
  /// {@macro view_model}
  ViewModel(T initial) : _state = initial;

  /// Maximum number of events buffered before the first listener subscribes.
  static const int _maxPendingEvents = 128;

  /// List of cleanup functions to be called when the view model is disposed.
  final List<void Function()> _cleanups = [];

  /// Subscriptions started with [watch] using a key, replaceable per key.
  final Map<Object, WatchHandle> _keyedWatches = {};

  /// Per-key generation counters for [RunPolicy.restartable]: a run whose
  /// epoch is no longer current has been superseded and skips its callbacks.
  final Map<Object, int> _runEpochs = {};

  /// In-flight run per key, for [RunPolicy.droppable].
  final Map<Object, Future<Async<Object?>>> _inFlightRuns = {};

  /// Tail of the run queue per key, for [RunPolicy.sequential].
  final Map<Object, Future<Async<Object?>>> _runQueues = {};

  /// Pending debounce timer per key, for [RunPolicy.restartable] with a
  /// non-zero debounce window.
  final Map<Object, Timer> _debounceTimers = {};

  /// Callers coalesced by a debounce window, per key. All of them resolve
  /// with the winning run's result once it dispatches.
  final Map<Object, List<_PendingRun>> _pendingRuns = {};

  /// Events emitted before anyone subscribed to [events] (see [sendEvent]).
  final List<E> _pendingEvents = [];
  bool _hadFirstListener = false;

  /// Stream controller for broadcasting events.
  late final StreamController<E> _events =
      StreamController<E>.broadcast(onListen: _flushPendingEvents);

  /// The current state of the view model.
  T _state;

  /// The current state of the view model.
  T get state => _state;

  /// Stream of events emitted by this view model.
  ///
  /// Events emitted *before the first subscription* are buffered (bounded)
  /// and delivered to the first subscriber, so events sent during
  /// construction are not lost. After the first subscription, regular
  /// broadcast semantics apply: events emitted while nobody listens are
  /// dropped.
  Stream<E> get events => _events.stream;

  void _flushPendingEvents() {
    if (_hadFirstListener) return;
    _hadFirstListener = true;
    for (final event in _pendingEvents) {
      _events.add(event);
    }
    _pendingEvents.clear();
  }

  /// Updates the current state and notifies listeners.
  ///
  /// This method updates the internal state and triggers a rebuild of all
  /// listening widgets. It does not perform any equality checks, so it will
  /// notify listeners every time it's called.
  ///
  /// If the view model is disposed, the state will be updated but listeners
  /// won't be notified due to the safe disposal behavior.
  @protected
  void setState(T state) {
    _state = state;
    notifyListeners();
  }

  /// Sends an event to all listeners of the events stream.
  ///
  /// Events are used for one-time notifications that don't require state changes,
  /// such as navigation events, snackbar messages, or other side effects.
  ///
  /// Events sent before the first subscriber are buffered and replayed to it
  /// (bounded to the most recent [_maxPendingEvents]).
  @protected
  void sendEvent(E event) {
    if (disposed) return;
    if (!_hadFirstListener) {
      assert(
        _pendingEvents.length < _maxPendingEvents,
        'ViewModel<$T, $E> buffered $_maxPendingEvents events without any '
        'listener on `events`. Are you emitting events in a loop before the '
        'UI subscribes?',
      );
      _pendingEvents.add(event);
      if (_pendingEvents.length > _maxPendingEvents) {
        _pendingEvents.removeAt(0);
      }
      return;
    }
    _events.add(event);
  }

  @override
  void dispose() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    for (final pending in _pendingRuns.values) {
      for (final waiter in pending) {
        waiter.onDisposed();
      }
    }
    _pendingRuns.clear();
    _runEpochs.clear();
    _inFlightRuns.clear();
    _runQueues.clear();
    for (final handle in _keyedWatches.values.toList()) {
      handle.cancel();
    }
    _keyedWatches.clear();
    for (final cleanup in _cleanups.reversed) {
      try {
        cleanup();
      } catch (error, stackTrace) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'chassis_flutter',
          context: ErrorDescription(
            'while disposing a resource of ViewModel<$T, $E>',
          ),
        ));
      }
    }
    _cleanups.clear();
    _pendingEvents.clear();
    _events.close();
    super.dispose();
  }

  /// Subscribes to a [Stream] and manages its lifecycle with [Async] state
  /// updates. See the class documentation for the callback contract.
  ///
  /// - [key]: if provided, a previous [watch] with the same key is cancelled
  ///   and replaced. Without a key, subscriptions are additive and live until
  ///   the ViewModel is disposed (or the returned [WatchHandle] is cancelled).
  /// - [current]: the current [Async] state, if any. The initial loading
  ///   emission and error transitions carry its data ([AsyncData]), so a
  ///   refetch does not blank the UI.
  /// - [emitLoading]: whether to emit a loading state immediately.
  /// - [onDone]: invoked when the stream itself completes — never on
  ///   cancellation (keyed replacement, [WatchHandle.cancel], or disposal).
  ///   Without it, a finite stream ending is invisible: the state stays
  ///   frozen on the last emission. The handle is cancelled before [onDone]
  ///   runs, so re-watching with the same key from inside it is safe.
  ///
  /// Example:
  /// ```dart
  /// watch(
  ///   mediator.watchUser('123'),
  ///   key: #user,
  ///   current: state.user,
  ///   onState: (user) => setState(state.copyWith(user: user)),
  /// );
  /// ```
  @protected
  WatchHandle watch<R>(
    Stream<R> stream, {
    Object? key,
    Async<R>? current,
    bool emitLoading = true,
    void Function(Async<R> state)? onState,
    void Function(R data)? onData,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) {
    assert(
      onState != null || onData != null || onError != null || onDone != null,
      'watch() called without any callback: provide onState, onData, '
      'onError, and/or onDone.',
    );

    // A new keyed watch replaces the previous one.
    if (key != null) {
      _keyedWatches.remove(key)?.cancel();
    }

    var last = current?.toLoading() ?? Async<R>.loading();
    if (emitLoading) {
      onState?.call(last);
    }

    late final WatchHandle handle;
    final subscription = stream.listen(
      (data) {
        if (disposed) return;
        final dataState = AsyncData(data);
        last = dataState;
        onState?.call(dataState);
        onData?.call(data);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (disposed) return;
        // Carry the last known data through the error (soft error).
        final errorState = last.toError(error, stackTrace);
        last = errorState;
        onState?.call(errorState);
        onError?.call(error);
      },
      onDone: () {
        if (disposed) return;
        // The subscription is over: release the handle (and its key) before
        // reporting, so onDone can start a replacement watch.
        handle.cancel();
        onDone?.call();
      },
    );

    handle = WatchHandle._(() {
      if (key != null && identical(_keyedWatches[key], handle)) {
        _keyedWatches.remove(key);
      }
      return subscription.cancel();
    });

    if (key != null) {
      _keyedWatches[key] = handle;
    } else {
      _cleanups.add(handle.cancel);
    }
    return handle;
  }

  /// Executes an async [operation], reporting its lifecycle as [Async]
  /// states. See the class documentation for the callback contract.
  ///
  /// - [key] and [policy]: control how runs sharing the same [key] interact
  ///   (see [RunPolicy]). Every policy except [RunPolicy.concurrent] requires
  ///   a [key], and all runs sharing a key must have the same result type
  ///   `R`.
  /// - [current]: the current [Async] state, if any. The initial loading
  ///   emission and an error result carry its data ([AsyncData]), so a
  ///   refetch does not blank the UI.
  /// - [emitLoading]: whether to emit a loading state when the operation
  ///   dispatches (for a debounced run, that is when the debounce window
  ///   fires, not at the call).
  ///
  /// Returns the final [Async] state ([AsyncData] or [AsyncError]). A
  /// dropped or debounce-coalesced call resolves with the winning run's
  /// result. If the ViewModel is disposed while awaiting, callbacks are not
  /// invoked.
  @protected
  Future<Async<R>> run<R>(
    Future<R> Function() operation, {
    Object? key,
    RunPolicy policy = const RunPolicy.concurrent(),
    Async<R>? current,
    bool emitLoading = true,
    void Function(Async<R> state)? onState,
    void Function(R value)? onSuccess,
    void Function(Object error)? onError,
  }) {
    assert(
      onState != null || onSuccess != null || onError != null,
      'run() called without any callback: provide onState, onSuccess, '
      'and/or onError.',
    );
    assert(
      policy is ConcurrentRunPolicy || key != null,
      'RunPolicy.${policy.name} requires a key: policies are scoped per key.',
    );

    Future<Async<R>> execute({int? epoch}) => _executeRun(
          operation,
          key: key,
          epoch: epoch,
          current: current,
          emitLoading: emitLoading,
          onState: onState,
          onSuccess: onSuccess,
          onError: onError,
        );

    switch (policy) {
      case ConcurrentRunPolicy():
        return execute();

      case RestartableRunPolicy(:final debounce):
        final k = key!;
        final epoch = (_runEpochs[k] ?? 0) + 1;
        _runEpochs[k] = epoch;
        if (debounce == Duration.zero) {
          return execute(epoch: epoch);
        }
        _debounceTimers.remove(k)?.cancel();
        final completer = Completer<Async<R>>();
        (_pendingRuns[k] ??= []).add(_PendingRun(
          onDispatch: (result) =>
              completer.complete(result.then((r) => r as Async<R>)),
          onDisposed: () => completer.complete(Async<R>.error(StateError(
            'ViewModel<$T, $E> was disposed before the run debounced on '
            'key "$k" dispatched.',
          ))),
        ));
        _debounceTimers[k] = Timer(debounce, () {
          _debounceTimers.remove(k);
          final waiters = _pendingRuns.remove(k) ?? const [];
          final result = execute(epoch: epoch);
          for (final waiter in waiters) {
            waiter.onDispatch(result);
          }
        });
        return completer.future;

      case DroppableRunPolicy():
        final k = key!;
        final existing = _inFlightRuns[k];
        if (existing != null) {
          return existing.then((r) => r as Async<R>);
        }
        final result = execute();
        _inFlightRuns[k] = result;
        result.whenComplete(() {
          if (identical(_inFlightRuns[k], result)) {
            _inFlightRuns.remove(k);
          }
        });
        return result;

      case SequentialRunPolicy():
        final k = key!;
        final tail = _runQueues[k];
        // _executeRun never throws (operation errors become AsyncError), so
        // the chain cannot break.
        final result = tail == null ? execute() : tail.then((_) => execute());
        _runQueues[k] = result;
        result.whenComplete(() {
          if (identical(_runQueues[k], result)) {
            _runQueues.remove(k);
          }
        });
        return result;
    }
  }

  Future<Async<R>> _executeRun<R>(
    Future<R> Function() operation, {
    required Object? key,
    required int? epoch,
    required Async<R>? current,
    required bool emitLoading,
    required void Function(Async<R> state)? onState,
    required void Function(R value)? onSuccess,
    required void Function(Object error)? onError,
  }) async {
    // Superseded ([RunPolicy.restartable]) or disposed runs still execute,
    // but stop reporting: their transitions no longer describe the current
    // intent.
    bool invalidated() =>
        disposed || (epoch != null && _runEpochs[key] != epoch);

    if (emitLoading && !invalidated()) {
      onState?.call(current?.toLoading() ?? Async<R>.loading());
    }

    Async<R> result;
    try {
      result = AsyncData(await operation());
    } catch (error, stackTrace) {
      result = current != null
          ? current.toError(error, stackTrace)
          : Async<R>.error(error, stackTrace: stackTrace);
    }

    // Callbacks run OUTSIDE the try/catch: an exception thrown by a callback
    // is a bug in the callback and must propagate, not be reported as an
    // AsyncError of the operation (which would turn a success into an error).
    if (invalidated()) return result;
    switch (result) {
      case AsyncData<R>(:final value):
        onState?.call(result);
        onSuccess?.call(value);
      case AsyncError<R>(:final error):
        onState?.call(result);
        onError?.call(error);
      case AsyncLoading<R>():
        break; // unreachable: result is data or error.
    }
    return result;
  }
}

/// How concurrent [ViewModel.run] calls sharing the same `key` interact.
///
/// A policy answers one question — when several runs collide on a key, who
/// wins?
///
/// - [RunPolicy.concurrent] — everyone: all runs execute and report; the
///   last completion writes last, which may be the oldest dispatch.
/// - [RunPolicy.restartable] — the latest: a new run invalidates the
///   callbacks of any in-flight run on the same key. An optional [debounce]
///   window additionally coalesces bursts of calls before dispatching.
/// - [RunPolicy.droppable] — the first: while a run is in flight on the
///   key, new calls do not dispatch and resolve with the in-flight result.
/// - [RunPolicy.sequential] — everyone, in order: runs are queued per key.
///
/// Every policy except [RunPolicy.concurrent] requires a `key`, and all runs
/// sharing a key must have the same result type.
sealed class RunPolicy {
  const RunPolicy();

  /// All runs execute independently. Results may interleave.
  const factory RunPolicy.concurrent() = ConcurrentRunPolicy._;

  /// Latest wins: a newer run on the same key invalidates the callbacks of
  /// in-flight ones.
  ///
  /// With a non-zero [debounce], dispatch additionally waits for a quiet
  /// window: each new call resets the timer, and only the latest operation
  /// dispatches once the window elapses (coalesced callers resolve with its
  /// result). There is no separate "debounce" policy because debouncing
  /// alone would not fix result races — a debounced dispatch still needs
  /// latest-wins invalidation once in flight. With the default
  /// `Duration.zero`, the operation dispatches synchronously.
  const factory RunPolicy.restartable({Duration debounce}) =
      RestartableRunPolicy._;

  /// First wins: calls made while a run is in flight on the key are dropped
  /// and complete with the in-flight run's result.
  const factory RunPolicy.droppable() = DroppableRunPolicy._;

  /// All runs execute, one at a time, in call order (per key).
  ///
  /// Note that `current` is captured when [ViewModel.run] is called, not
  /// when the queued operation starts; prefer reading fresh state inside
  /// `onState`.
  const factory RunPolicy.sequential() = SequentialRunPolicy._;

  /// Human-readable policy name, for assertion messages.
  String get name => switch (this) {
        ConcurrentRunPolicy() => 'concurrent',
        RestartableRunPolicy() => 'restartable',
        DroppableRunPolicy() => 'droppable',
        SequentialRunPolicy() => 'sequential',
      };
}

/// See [RunPolicy.concurrent].
final class ConcurrentRunPolicy extends RunPolicy {
  const ConcurrentRunPolicy._();
}

/// See [RunPolicy.restartable].
final class RestartableRunPolicy extends RunPolicy {
  const RestartableRunPolicy._({this.debounce = Duration.zero});

  /// Quiet window to wait for before dispatching. [Duration.zero] dispatches
  /// synchronously.
  final Duration debounce;
}

/// See [RunPolicy.droppable].
final class DroppableRunPolicy extends RunPolicy {
  const DroppableRunPolicy._();
}

/// See [RunPolicy.sequential].
final class SequentialRunPolicy extends RunPolicy {
  const SequentialRunPolicy._();
}

/// A caller coalesced by a [RunPolicy.restartable] debounce window.
class _PendingRun {
  _PendingRun({required this.onDispatch, required this.onDisposed});

  /// Called with the winning run's result when the window fires.
  final void Function(Future<Async<Object?>> result) onDispatch;

  /// Called if the ViewModel is disposed before the window fires.
  final void Function() onDisposed;
}

/// {@template base_utils}
/// Extension that provides utility methods for managing resources and subscriptions
/// in view models with automatic cleanup.
///
/// These methods help manage the lifecycle of various resources and ensure they
/// are properly disposed when the view model is disposed.
/// {@endtemplate}
extension BaseUtils on ViewModel<Object?, Object?> {
  /// {@macro base_utils}
  /// Automatically disposes a [Disposable] object when the view model is disposed.
  @protected
  void autoDispose(Disposable disposable) {
    _cleanups.add(disposable.dispose);
  }

  /// {@macro base_utils}
  /// Automatically cancels a stream subscription when the view model is disposed.
  @protected
  void autoDisposeStreamSubscription(StreamSubscription<Object?> sub) {
    _cleanups.add(() => sub.cancel());
  }

  /// {@macro base_utils}
  /// Listens to a [Listenable] and automatically removes the listener when disposed.
  @protected
  void listenTo(Listenable listenable, void Function() listener) {
    listenable.addListener(listener);
    _cleanups.add(() => listenable.removeListener(listener));
  }

  /// {@macro base_utils}
  /// Merges multiple [Listenable] objects and listens to the combined result.
  @protected
  void mergeAndListenTo(
    Iterable<Listenable> listenables,
    void Function() listener,
  ) {
    final merge = Listenable.merge(listenables);
    listenTo(merge, listener);
  }
}
