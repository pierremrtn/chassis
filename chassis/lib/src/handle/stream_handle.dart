part of 'handle.dart';

sealed class StreamHandleState<T> implements HandleState<T> {
  const StreamHandleState();
}

/// The query has been created but has not yet started.
class StreamHandleStateInitial<T> extends StreamHandleState<T> {
  const StreamHandleStateInitial();
}

/// The query is actively loading data.
class StreamHandleStateLoading<T> extends StreamHandleState<T> {
  const StreamHandleStateLoading();
}

/// The query has successfully completed and holds the resulting [data].
class StreamHandleStateData<T> extends StreamHandleState<T> {
  final T data;

  const StreamHandleStateData(this.data);
}

/// The query failed to complete and resulted in an [error].
class StreamHandleStateError<T> extends StreamHandleState<T> {
  final Object error;
  final StackTrace stackTrace;

  StreamHandleStateError(this.error, [StackTrace? stackTrace])
      : stackTrace = StackTrace.current;
}

class StreamHandleStateDone<T> extends StreamHandleState<T> {
  StreamHandleStateDone();
}

/// TODO:
/// - StreamHandleState
/// - Specialized logic
final class StreamHandle<P, R> extends Handle<P, R> {
  StreamHandle(this._handler);

  final Stream<R> Function(P) _handler;

  final _stateController = BehaviorSubject<StreamHandleState<R>>.seeded(
      StreamHandleStateInitial<R>());

  @override
  StreamHandleState<R> get state => _stateController.value;

  @override
  Stream<StreamHandleState<R>> get stream => _stateController.stream;

  @override
  void _listenToExecutor(_StreamHandleExecutor<P, R> executor) {
    _executorSubscription = executor.stream.listen(
      (newState) => _stateController.add(newState),
      onError: (error, stackTrace) =>
          _stateController.add(StreamHandleStateError<R>(error, stackTrace)),
      onDone: () => _stateController.add(StreamHandleStateDone()),
    );
  }

  /// [onLoading], [onSuccess], [onError] can be used to register callback  to track this particular execution status.
  /// Those callbacks are only valid for this execute call and won't be triggered for any subsequent [watch] call
  /// if [watch] again is called before this call is done, callbacks **won't** be called and [onCancelled] will be called instead.
  void watch(
    P params, {
    HandleLoadingCallback<void>? onLoading,
    HandleSuccessCallback<R, void>? onSuccess,
    HandleErrorCallback<void>? onError,
    HandleCancelationCallback<void>? onCancelled,
  }) {
    _replaceExecutorWith(
      _StreamHandleExecutor(
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

final class _StreamHandleExecutor<Q, T> extends _HandleExecutor<Q, T> {
  final Stream<T> _sourceStream;

  _StreamHandleExecutor(
    super.params,
    this._sourceStream, {
    super.onLoading,
    super.onSuccess,
    super.onError,
    super.onCancelled,
  });

  late final Stream<StreamHandleState<T>> stream =
      _execute().asBroadcastStream();

  Stream<StreamHandleState<T>> _execute() async* {
    yield StreamHandleStateLoading<T>();
    _safeCallback(() => onLoading?.call());
    try {
      await for (final data in _sourceStream) {
        yield StreamHandleStateData<T>(data);
        _safeCallback(() => onSuccess?.call(data));
      }
      yield StreamHandleStateDone<T>();
    } catch (e, s) {
      yield StreamHandleStateError<T>(e, s);
      _safeCallback(() => onError?.call(e, s));
    } finally {
      _markDone();
    }
  }
}
