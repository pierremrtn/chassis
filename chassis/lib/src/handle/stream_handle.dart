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
  /// Those callbacks are only valid for this execute call and won't be triggered for any subsequent [startListening] call
  /// if [startListening] again is called before this call is done, callbacks **won't** be called and [onCancelled] will be called instead.
  void startListening(
    P params, {
    HandleSuccessCallback<R, void>? onData,
    HandleErrorCallback<void>? onError,
    HandleCancelationCallback<void>? onCancelled,
    HandleDoneCallback<void>? onDone,
  }) {
    _replaceExecutorWith(
      _StreamHandleExecutor(
        params,
        _handler(params),
        onData: onData,
        onError: onError,
        onCancelled: onCancelled,
        onDone: onDone,
      ),
    );
  }
}

final class _StreamHandleExecutor<Q, T> extends _HandleExecutor<Q, T> {
  final Stream<T> _sourceStream;

  _StreamHandleExecutor(
    super.params,
    this._sourceStream, {
    this.onData,
    this.onError,
    super.onDone,
    super.onCancelled,
  });

  final HandleSuccessCallback<T, void>? onData;
  final HandleErrorCallback<void>? onError;

  late final Stream<StreamHandleState<T>> stream =
      _execute().asBroadcastStream();

  Stream<StreamHandleState<T>> _execute() async* {
    yield StreamHandleStateLoading<T>();
    try {
      await for (final data in _sourceStream) {
        yield StreamHandleStateData<T>(data);
        _safeCallback(() => onData?.call(data));
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
