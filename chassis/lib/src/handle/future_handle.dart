part of "handle.dart";

sealed class FutureHandleState<T> implements HandleState<T> {
  const FutureHandleState();
}

/// The query has been created but has not yet started.
class FutureHandleStateInitial<T> extends FutureHandleState<T> {
  const FutureHandleStateInitial();
}

/// The query is actively loading data.
class FutureHandleStateLoading<T> extends FutureHandleState<T> {
  const FutureHandleStateLoading();
}

/// The query has successfully completed and holds the resulting [data].
class FutureHandleStateSuccess<T> extends FutureHandleState<T> {
  final T data;

  const FutureHandleStateSuccess(this.data);
}

/// The query failed to complete and resulted in an [error].
class FutureHandleStateError<T> extends FutureHandleState<T> {
  final Object error;
  final StackTrace stackTrace;

  FutureHandleStateError(this.error, [StackTrace? stackTrace])
      : stackTrace = StackTrace.current;
}

final class FutureHandle<P, R> extends Handle<P, R> {
  FutureHandle(this._handler);

  final Future<R> Function(P) _handler;

  final _stateController = BehaviorSubject<FutureHandleState<R>>.seeded(
      FutureHandleStateInitial<R>());

  @override
  FutureHandleState<R> get state => _stateController.value;

  @override
  Stream<FutureHandleState<R>> get stream => _stateController.stream;

  Future<void> refresh() async {
    if (_executor?.params case P params) {
      run(params);
    }
  }

  /// [onLoading], [onSuccess], [onError] can be used to register callback  to track this particular execution status.
  /// Those callbacks are only valid for this execute call and won't be triggered for any subsequent [run] call
  /// if [run] again is called before this call is done, callbacks **won't** be called and [onCancelled] will be called instead.
  void run(
    P params, {
    HandleLoadingCallback<void>? onLoading,
    HandleSuccessCallback<R, void>? onSuccess,
    HandleErrorCallback<void>? onError,
    HandleCancelationCallback<void>? onCancelled,
  }) {
    _replaceExecutorWith(
      _FutureHandleExecutor(
        params,
        _handler(params),
        onLoading: onLoading,
        onSuccess: onSuccess,
        onError: onError,
        onCancelled: onCancelled,
      ),
    );
  }

  @override
  void _listenToExecutor(_FutureHandleExecutor<P, R> executor) {
    _executorSubscription = executor.stream.listen(
      (newState) => _stateController.add(newState),
      onError: (error, stackTrace) =>
          _stateController.add(FutureHandleStateError<R>(error, stackTrace)),
    );
  }
}

final class _FutureHandleExecutor<Q, T> extends _HandleExecutor<Q, T> {
  final Future<T> _future;

  _FutureHandleExecutor(
    super.params,
    this._future, {
    super.onLoading,
    super.onSuccess,
    super.onError,
    super.onCancelled,
  });

  late final Stream<FutureHandleState<T>> stream =
      _execute().asBroadcastStream();

  Stream<FutureHandleState<T>> _execute() async* {
    yield FutureHandleStateLoading<T>();
    _safeCallback(() => onLoading?.call());
    try {
      final data = await _future;
      yield FutureHandleStateSuccess<T>(data);
      _safeCallback(() => onSuccess?.call(data));
    } catch (e, s) {
      yield FutureHandleStateError<T>(e, s);
      _safeCallback(() => onError?.call(e, s));
    } finally {
      _markDone();
    }
  }
}
