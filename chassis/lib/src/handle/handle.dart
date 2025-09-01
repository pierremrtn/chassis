import 'dart:async';

import 'package:chassis/chassis.dart';
import 'package:rxdart/subjects.dart';

export 'handle_utils.dart';

part 'future_handle.dart';
part 'stream_handle.dart';

abstract interface class HandleState<R> {}

typedef ReadHandle<Q extends Read<R>, R> = FutureHandle<Q, R>;
typedef WatchHandle<Q extends Watch<R>, R> = StreamHandle<Q, R>;
typedef CommandHandle<C extends Command<R>, R> = FutureHandle<C, R>;

abstract base class Handle<P, R> with Disposable {
  StreamSubscription<HandleState<R>>? _executorSubscription;

  _HandleExecutor<P, R>? _executor;

  void _replaceExecutorWith(_HandleExecutor<P, R> executor) {
    _cancelExecutor();
    _listenToExecutor(executor);
  }

  void _cancelExecutor() {
    _executorSubscription?.cancel();
    _executor = null;
  }

  void _listenToExecutor(covariant _HandleExecutor<P, R> executor);

  // --- Public API Implementation ---

  HandleState<R> get state;
  Stream<HandleState<R>> get stream;

  @override
  void dispose() {
    _cancelExecutor();
    super.dispose();
  }
}

typedef HandleInitialCallback<U> = U Function();
typedef HandleLoadingCallback<U> = U Function();
typedef HandleSuccessCallback<T, U> = U Function(T data);
typedef HandleErrorCallback<U> = U Function(
  Object error, [
  StackTrace stackTrace,
]);
typedef HandleCancelationCallback<U> = U Function();
typedef HandleDoneCallback<U> = U Function();

/// stream of [HandleState].
abstract base class _HandleExecutor<P, R> with Disposable {
  /// [onLoading], [onSuccess], [onError] can be used to register callback for execution event.
  /// if the handle is canceled, they **won't** be called and [onCancelled] instead.
  _HandleExecutor(
    this.params, {
    this.onDone,
    this.onCancelled,
  });

  /// The query or command used to create this executor.
  final P params;

  final HandleCancelationCallback<void>? onDone;
  final HandleCancelationCallback<void>? onCancelled;

  bool _done = false;

  @override
  void dispose() {
    final wasDone = _done;
    _markDone();
    if (!wasDone) {
      onCancelled?.call();
    }
    super.dispose();
  }

  /// Mark this executor as done
  /// When the executor is done, onCancelled is not called when the executor is disposed
  void _markDone() {
    if (!_done) {
      _done = true;
      onDone?.call();
    }
  }

  void _safeCallback(void Function() callback) {
    if (!_done) {
      callback.call();
    }
  }
}
