import 'dart:async';

import 'package:chassis/chassis.dart';
import 'package:chassis_flutter/src/safe_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/streams.dart';

class ViewModel<T> extends SafeChangeNotifier {
  ViewModel(T initial) : _state = initial;

  final List<void Function()> _cleanups = [];

  T _state;

  T get state => _state;

  /// Emit a new state
  /// This method notify every time it's called. it does not perform any equality check
  /// If the view model is disposed, state will be updated but listener won't be notified
  void emit(T state) {
    _state = state;
    notifyListeners();
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
}

extension BaseUtils on ViewModel {
  void autoDispose(Disposable disposable) {
    _cleanups.add(() => disposable.dispose);
  }

  void autoDisposeStreamSubscription(StreamSubscription sub) {
    _cleanups.add(() => sub.cancel());
  }

  void listenTo(Listenable listenable, void Function() listener) {
    listenable.addListener(listener);
    _cleanups.add(() => listenable.removeListener(listener));
  }

  void mergeAndListenTo(
    Iterable<Listenable> listenables,
    void Function() listener,
  ) {
    final merge = Listenable.merge(listenables);
    listenTo(merge, listener);
  }

  void listenToStreams(
    Iterable<Stream> streams,
    void Function() listener,
  ) {
    final merge = MergeStream(streams);
    autoDisposeStreamSubscription(merge.listen((_) => listener()));
  }

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

extension HandleUtils on ViewModel {
  FutureHandle<Q, R> readHandle<Q extends Read<R>, R>(
    ReadHandler<Q, R> handler, {
    Q? executeImmediately,
    HandleLoadingCallback<void>? onLoading,
    HandleSuccessCallback<R, void>? onSuccess,
    HandleErrorCallback<void>? onError,
    HandleCancelationCallback<void>? onCancelled,
    void Function(HandleState<R> state)? listener,
  }) {
    final handle = FutureHandle<Q, R>((query) => handler.read(query));
    autoDispose(handle);
    if (listener != null) {
      autoDisposeStreamSubscription(
        handle.stream.listen(listener),
      );
    }
    if (executeImmediately case Q query) {
      handle.run(
        query,
        onLoading: onLoading,
        onSuccess: onSuccess,
        onError: onError,
        onCancelled: onCancelled,
      );
    }
    return handle;
  }

  StreamHandle<Q, R> watchHandle<Q extends Watch<R>, R>(
    WatchHandler<Q, R> handler, {
    Q? executeImmediately,
    HandleLoadingCallback<void>? onLoading,
    HandleSuccessCallback<R, void>? onSuccess,
    HandleErrorCallback<void>? onError,
    HandleCancelationCallback<void>? onCancelled,
    void Function(HandleState<R> state)? listener,
  }) {
    final handle = StreamHandle<Q, R>((query) => handler.watch(query));
    autoDispose(handle);
    if (listener != null) {
      autoDisposeStreamSubscription(
        handle.stream.listen(listener),
      );
    }
    if (executeImmediately case Q query) {
      handle.watch(
        query,
        onLoading: onLoading,
        onSuccess: onSuccess,
        onError: onError,
        onCancelled: onCancelled,
      );
    }
    return handle;
  }

  CommandHandle<C, R> commandHandle<C extends Command<R>, R>(
    CommandHandler<C, R> handler, {
    C? executeImmediately,
    HandleLoadingCallback<void>? onLoading,
    HandleSuccessCallback<R, void>? onSuccess,
    HandleErrorCallback<void>? onError,
    HandleCancelationCallback<void>? onCancelled,
    void Function(HandleState<R> state)? listener,
  }) {
    final handle = FutureHandle<C, R>((params) => handler.run(params));
    autoDispose(handle);
    if (listener != null) {
      autoDisposeStreamSubscription(
        handle.stream.listen(listener),
      );
    }
    if (executeImmediately case C command) {
      handle.run(
        command,
        onLoading: onLoading,
        onSuccess: onSuccess,
        onError: onError,
        onCancelled: onCancelled,
      );
    }
    return handle;
  }

  void listenToHandle<P, R>(
    Handle<P, R> handle,
    void Function(HandleState<R>) listener,
  ) {
    autoDisposeStreamSubscription(handle.stream.listen(listener));
  }

  void listenToHandles(
    Iterable<Handle> handles,
    void Function() listener,
  ) {
    final merge = MergeStream(handles.map((h) => h.stream));
    autoDisposeStreamSubscription(merge.listen((_) => listener()));
  }

  void combineHandles(
    Iterable<Handle> handles,
    void Function(List<HandleState> states) listener,
  ) {
    combineStreams(
      handles.map((h) => h.stream),
      listener,
    );
  }

  void combineHandles2<R1, R2>(
    Handle<dynamic, R1> a,
    Handle<dynamic, R2> b,
    void Function(HandleState<R1> a, HandleState<R2> b) listener,
  ) {
    combineStreams2(
      a.stream,
      b.stream,
      listener,
    );
  }

  void combineHandles3<R1, R2, R3>(
    Handle<dynamic, R1> a,
    Handle<dynamic, R2> b,
    Handle<dynamic, R3> c,
    void Function(HandleState<R1> a, HandleState<R2> b, HandleState<R3> c)
        listener,
  ) {
    combineStreams3(
      a.stream,
      b.stream,
      c.stream,
      listener,
    );
  }
}
