import 'dart:async';

import 'package:chassis/chassis.dart';
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:chassis_flutter/src/safe_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/streams.dart';

class ViewModel<T, E> extends SafeChangeNotifier {
  ViewModel(T initial) : _state = initial;

  Mediator get mediator => Mediator.instance;
  final List<void Function()> _cleanups = [];

  final StreamController<E> _events = StreamController.broadcast();

  T _state;

  T get state => _state;

  Stream<E> get events => _events.stream;

  /// Emit a new state
  /// This method notify every time it's called. it does not perform any equality check
  /// If the view model is disposed, state will be updated but listener won't be notified
  @protected
  void setState(T state) {
    _state = state;
    notifyListeners();
  }

  @protected
  void sendEvent(E event) {
    _events.add(event);
  }

  @override
  void dispose() {
    for (final cleanup in _cleanups.reversed) {
      try {
        cleanup();
      } catch (e) {
        continue;
      }
    }
    _cleanups.clear();
    super.dispose();
  }

  @protected
  void watch<Q extends Watch<R>, R>(
    Q query,
    void Function(StreamState<R>) onState,
  ) {
    autoDisposeStreamSubscription(
      mediator.watch(query).listen(
            (data) => onState(StreamStateData(data)),
            onError: (e, s) => onState(StreamStateError(e, s)),
          ),
    );
  }

  Future<AsyncResult<R>> _runAsyncOperation<P, R>(
    P param,
    Future<R> Function(P params) executor, {
    void Function(AsyncState<R>)? onState,
  }) async {
    onState?.call(AsyncLoading());
    try {
      final res = await executor(param);
      final state = AsyncSuccess(res);
      onState?.call(state);
      return state;
    } catch (e, s) {
      final res = AsyncError<R>(e, s);
      onState?.call(res);
      return res;
    }
  }

  @protected
  Future<AsyncResult<R>> read<Q extends Read<R>, R>(
    Q query, [
    void Function(AsyncState<R>)? onState,
  ]) async {
    return await _runAsyncOperation(query, mediator.read<R>);
  }

  @protected
  Future<AsyncResult<R>> run<C extends Command<R>, R>(
    C command, [
    void Function(CommandState<R>)? onState,
  ]) async {
    return await _runAsyncOperation(command, mediator.run<R>);
  }
}

extension BaseUtils on ViewModel {
  @protected
  void autoDispose(Disposable disposable) {
    _cleanups.add(() => disposable.dispose);
  }

  @protected
  void autoDisposeStreamSubscription(StreamSubscription sub) {
    _cleanups.add(() => sub.cancel());
  }

  @protected
  void listenTo(Listenable listenable, void Function() listener) {
    listenable.addListener(listener);
    _cleanups.add(() => listenable.removeListener(listener));
  }

  @protected
  void mergeAndListenTo(
    Iterable<Listenable> listenables,
    void Function() listener,
  ) {
    final merge = Listenable.merge(listenables);
    listenTo(merge, listener);
  }

  @protected
  void listenToStreams(
    Iterable<Stream> streams,
    void Function() listener,
  ) {
    final merge = MergeStream(streams);
    autoDisposeStreamSubscription(merge.listen((_) => listener()));
  }

  @protected
  void combineStreams<R>(
    Iterable<Stream<R>> streams,
    void Function(List<R>) listener,
  ) {
    autoDisposeStreamSubscription(
      CombineLatestStream.list<R>(streams).listen(
        listener,
      ),
    );
  }

  @protected
  void combineStreams2<R1, R2>(
    Stream<R1> a,
    Stream<R2> b,
    void Function(R1 a, R2 b) listener,
  ) {
    final combinedStream = CombineLatestStream.combine2(
      a,
      b,
      (a, b) => (a, b),
    );
    autoDisposeStreamSubscription(
      combinedStream.listen(
        (data) => listener(data.$1, data.$2),
      ),
    );
  }

  @protected
  void combineStreams3<R1, R2, R3>(
    Stream<R1> a,
    Stream<R2> b,
    Stream<R3> c,
    void Function(R1 a, R2 b, R3 c) listener,
  ) {
    final combinedStream = CombineLatestStream.combine3(
      a,
      b,
      c,
      (a, b, c) => (a, b, c),
    );
    autoDisposeStreamSubscription(
      combinedStream.listen(
        (data) => listener(data.$1, data.$2, data.$3),
      ),
    );
  }
}

// extension HandleUtils on ViewModel {
//   StreamHandle<Q, R> watchHandle<Q extends Watch<R>, R>({
//     Q? executeImmediately,
//     HandleSuccessCallback<R, void>? onData,
//     HandleErrorCallback<void>? onError,
//     HandleCancelationCallback<void>? onCancelled,
//     HandleDoneCallback<void>? onDone,
//   }) {
//     final handle = StreamHandle<Q, R>(mediator.watch);
//     autoDispose(handle);
//     if (executeImmediately case Q query) {
//       handle.startListening(
//         query,
//         onData: onData,
//         onError: onError,
//         onCancelled: onCancelled,
//         onDone: onDone,
//       );
//     }
//     return handle;
//   }

//   FutureHandle<Q, R> readHandle<Q extends Read<R>, R>({
//     Q? executeImmediately,
//     HandleLoadingCallback<void>? onLoading,
//     HandleSuccessCallback<R, void>? onSuccess,
//     HandleErrorCallback<void>? onError,
//     HandleCancelationCallback<void>? onCancelled,
//     void Function(HandleState<R> state)? listener,
//   }) {
//     final handle = FutureHandle<Q, R>(mediator.read);
//     autoDispose(handle);
//     if (listener != null) {
//       autoDisposeStreamSubscription(
//         handle.stream.listen(listener),
//       );
//     }
//     if (executeImmediately case Q query) {
//       handle.run(
//         query,
//         onLoading: onLoading,
//         onSuccess: onSuccess,
//         onError: onError,
//         onCancelled: onCancelled,
//       );
//     }
//     return handle;
//   }

//   CommandHandle<C, R> commandHandle<C extends Command<R>, R>({
//     C? executeImmediately,
//     HandleLoadingCallback<void>? onLoading,
//     HandleSuccessCallback<R, void>? onSuccess,
//     HandleErrorCallback<void>? onError,
//     HandleCancelationCallback<void>? onCancelled,
//     void Function(HandleState<R> state)? listener,
//   }) {
//     final handle = FutureHandle<C, R>(mediator.run);
//     autoDispose(handle);
//     if (listener != null) {
//       autoDisposeStreamSubscription(
//         handle.stream.listen(listener),
//       );
//     }
//     if (executeImmediately case C command) {
//       handle.run(
//         command,
//         onLoading: onLoading,
//         onSuccess: onSuccess,
//         onError: onError,
//         onCancelled: onCancelled,
//       );
//     }
//     return handle;
//   }

//   void listenToHandles(
//     Iterable<Handle> handles,
//     void Function() listener,
//   ) {
//     final merge = MergeStream(handles.map((h) => h.stream));
//     autoDisposeStreamSubscription(merge.listen((_) => listener()));
//   }

//   void combineHandles(
//     Iterable<Handle> handles,
//     void Function(List<HandleState> states) listener,
//   ) {
//     combineStreams(
//       handles.map((h) => h.stream),
//       listener,
//     );
//   }

//   void combineHandles2<R1, R2>(
//     Handle<dynamic, R1> a,
//     Handle<dynamic, R2> b,
//     void Function(HandleState<R1> a, HandleState<R2> b) listener,
//   ) {
//     combineStreams2(
//       a.stream,
//       b.stream,
//       listener,
//     );
//   }

//   void combineHandles3<R1, R2, R3>(
//     Handle<dynamic, R1> a,
//     Handle<dynamic, R2> b,
//     Handle<dynamic, R3> c,
//     void Function(HandleState<R1> a, HandleState<R2> b, HandleState<R3> c)
//         listener,
//   ) {
//     combineStreams3(
//       a.stream,
//       b.stream,
//       c.stream,
//       listener,
//     );
//   }
// }
