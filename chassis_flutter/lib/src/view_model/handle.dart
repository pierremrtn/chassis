import 'dart:async';

import 'package:chassis/chassis.dart';
import 'package:rxdart/subjects.dart';

abstract base class Handle<P, R> with Disposable {
  final BehaviorSubject<HandleState<R>> _stateController =
      BehaviorSubject.seeded(HandleStateInitial<R>());

  StreamSubscription<HandleState<R>>? _executorSubscription;

  HandleExecutor<P, R>? _executor;

  void _replaceExecutorWith(HandleExecutor<P, R> executor) {
    _cancelExecutor();
    _listenToExecutor(executor);
  }

  void _cancelExecutor() {
    _executorSubscription?.cancel();
    _executor = null;
  }

  void _listenToExecutor(HandleExecutor<P, R> executor) {
    _executorSubscription = executor.stream.listen(
      (newState) => _stateController.add(newState),
      onError: (error, stackTrace) =>
          _stateController.add(HandleStateError<R>(error, stackTrace)),
    );
  }

  // --- Public API Implementation ---

  HandleState<R> get state => _stateController.value;
  Stream<HandleState<R>> get stream => _stateController.stream;

  Future<void> refresh() async {
    if (_executor?.params case P params) {
      execute(params);
    }
  }

  @override
  void dispose() {
    _cancelExecutor();
    super.dispose();
  }

  /// [onLoading], [onSuccess], [onError] can be used to register callback  to track this particular execution status.
  /// Those callbacks are only valid for this execute call and won't be triggered for any subsequent [execute] call
  /// if [execute] again is called before this call is done, callbacks **won't** be called and [onCancelled] will be called instead.
  void execute(
    P params, {
    HandleLoadingCallback<void>? onLoading,
    HandleSuccessCallback<R, void>? onSuccess,
    HandleErrorCallback<void>? onError,
    HandleCancelationCallback<void>? onCancelled,
  });
}

sealed class HandleState<T> {
  const HandleState();
}

/// The query has been created but has not yet started.
class HandleStateInitial<T> extends HandleState<T> {
  const HandleStateInitial();
}

/// The query is actively loading data.
class HandleStateLoading<T> extends HandleState<T> {
  const HandleStateLoading();
}

/// The query has successfully completed and holds the resulting [data].
class HandleStateSuccess<T> extends HandleState<T> {
  final T data;

  const HandleStateSuccess(this.data);
}

/// The query failed to complete and resulted in an [error].
class HandleStateError<T> extends HandleState<T> {
  final Object error;
  final StackTrace stackTrace;

  HandleStateError(this.error, [StackTrace? stackTrace])
      : stackTrace = StackTrace.current;
}

extension HandleStateUtils<T> on HandleState<T> {
  bool get isInitial => this is HandleStateInitial;
  bool get isLoading => this is HandleStateLoading;
  bool get isSuccess => this is HandleStateSuccess;
  bool get isFailure => this is HandleStateError;
  bool get isDone => isSuccess || isFailure;

  U when<U>({
    required HandleInitialCallback<U> initial,
    required HandleLoadingCallback<U> loading,
    required HandleSuccessCallback<T, U> success,
    required HandleErrorCallback<U> failure,
  }) =>
      switch (this) {
        HandleStateInitial<T>() => initial(),
        HandleStateLoading<T>() => loading(),
        final HandleStateSuccess<T> state => success(state.data),
        final HandleStateError<T> state =>
          failure(state.error, state.stackTrace),
      };

  U? whenOrNull<U>({
    HandleInitialCallback<U>? initial,
    HandleLoadingCallback<U>? loading,
    HandleSuccessCallback<T, U>? success,
    HandleErrorCallback<U>? failure,
  }) =>
      switch (this) {
        HandleStateInitial<T>() => initial?.call(),
        HandleStateLoading<T>() => loading?.call(),
        final HandleStateSuccess<T> state => success?.call(state.data),
        final HandleStateError<T> state =>
          failure?.call(state.error, state.stackTrace),
      };
}

typedef HandleInitialCallback<U> = U Function();
typedef HandleLoadingCallback<U> = U Function();
typedef HandleSuccessCallback<T, U> = U Function(T data);
typedef HandleErrorCallback<U> = U Function(
  Object error, [
  StackTrace stackTrace,
]);
typedef HandleCancelationCallback<U> = U Function();

/// stream of [HandleState].
abstract base class HandleExecutor<P, R> with Disposable {
  /// [onLoading], [onSuccess], [onError] can be used to register callback for execution event.
  /// if the handle is canceled, they **won't** be called and [onCancelled] instead.
  HandleExecutor(
    this.params, {
    this.onLoading,
    this.onSuccess,
    this.onError,
    this.onCancelled,
  });

  /// The query or command used to create this executor.
  final P params;

  final HandleLoadingCallback<void>? onLoading;
  final HandleSuccessCallback<R, void>? onSuccess;
  final HandleErrorCallback<void>? onError;
  final HandleCancelationCallback<void>? onCancelled;

  /// The normalized stream of query states.
  Stream<HandleState<R>> get stream;

  bool _canceled = false;
  bool _done = false;

  @override
  void dispose() {
    _canceled = true;
    if (!_done) onCancelled?.call();
    super.dispose();
  }

  /// Mark this executor as done
  /// When the executor is done, onCancelled is not called when the executor is disposed
  void _markDone() {
    _done = true;
  }

  void _safeCallback(void Function() callback) {
    if (!_canceled) {
      callback.call();
    }
  }

  /// Creates an executor that wraps a [Future].
  ///
  /// It will emit:
  /// 1. [HandleStateLoading] immediately.
  /// 2. [HandleStateSuccess] on completion or [HandleStateError] on error.
  factory HandleExecutor.fromFuture(
    P params,
    Future<R> future, {
    HandleLoadingCallback<void>? onLoading,
    HandleSuccessCallback<R, void>? onSuccess,
    HandleErrorCallback<void>? onError,
    HandleCancelationCallback<void>? onCancelled,
  }) {
    return _FutureHandleExecutor(params, future);
  }

  /// Creates an executor that wraps a [Stream].
  ///
  /// It will emit:
  /// 1. [HandleStateLoading] immediately.
  /// 2. [HandleStateSuccess] for each data event from the source stream.
  /// 3. [HandleStateError] if the source stream emits an error.
  factory HandleExecutor.fromStream(
    P params,
    Stream<R> stream, {
    HandleLoadingCallback<void>? onLoading,
    HandleSuccessCallback<R, void>? onSuccess,
    HandleErrorCallback<void>? onError,
    HandleCancelationCallback<void>? onCancelled,
  }) {
    return _StreamHandleExecutor(params, stream);
  }
}

final class _FutureHandleExecutor<Q, T> extends HandleExecutor<Q, T> {
  final Future<T> _future;

  _FutureHandleExecutor(
    super.params,
    this._future, {
    super.onLoading,
    super.onSuccess,
    super.onError,
    super.onCancelled,
  });

  @override
  late final Stream<HandleState<T>> stream = _execute().asBroadcastStream();

  Stream<HandleState<T>> _execute() async* {
    yield HandleStateLoading<T>();
    _safeCallback(() => onLoading?.call());
    try {
      final data = await _future;
      yield HandleStateSuccess<T>(data);
      _safeCallback(() => onSuccess?.call(data));
    } catch (e, s) {
      yield HandleStateError<T>(e, s);
      _safeCallback(() => onError?.call(e, s));
    } finally {
      _markDone();
    }
  }
}

final class _StreamHandleExecutor<Q, T> extends HandleExecutor<Q, T> {
  final Stream<T> _sourceStream;

  _StreamHandleExecutor(
    super.params,
    this._sourceStream, {
    super.onLoading,
    super.onSuccess,
    super.onError,
    super.onCancelled,
  });

  @override
  late final Stream<HandleState<T>> stream = _execute().asBroadcastStream();

  Stream<HandleState<T>> _execute() async* {
    yield HandleStateLoading<T>();
    _safeCallback(() => onLoading?.call());
    try {
      await for (final data in _sourceStream) {
        yield HandleStateSuccess<T>(data);
        _safeCallback(() => onSuccess?.call(data));
      }
    } catch (e, s) {
      yield HandleStateError<T>(e, s);
      _safeCallback(() => onError?.call(e, s));
    } finally {
      _markDone();
    }
  }
}

final class FutureHandle<P, R> extends Handle<P, R> {
  FutureHandle(this._handler);

  final Future<R> Function(P) _handler;

  @override
  void execute(
    P params, {
    HandleLoadingCallback<void>? onLoading,
    HandleSuccessCallback<R, void>? onSuccess,
    HandleErrorCallback<void>? onError,
    HandleCancelationCallback<void>? onCancelled,
  }) {
    _replaceExecutorWith(
      HandleExecutor.fromFuture(
        params,
        _handler(params),
        onLoading: onLoading,
        onSuccess: onSuccess,
        onError: onError,
        onCancelled: onCancelled,
      ),
    );
  }
}

final class StreamHandle<P extends Watch<R>, R> extends Handle<P, R> {
  StreamHandle(this._handler);

  final Stream<R> Function(P) _handler;

  @override
  void execute(
    P params, {
    HandleLoadingCallback<void>? onLoading,
    HandleSuccessCallback<R, void>? onSuccess,
    HandleErrorCallback<void>? onError,
    HandleCancelationCallback<void>? onCancelled,
  }) {
    _replaceExecutorWith(
      HandleExecutor.fromStream(
        params,
        _handler(params),
        onLoading: onLoading,
        onSuccess: onSuccess,
        onError: onError,
        onCancelled: onCancelled,
      ),
    );
  }
}

typedef CommandHandle<C extends Command<R>, R> = FutureHandle<C, R>;
