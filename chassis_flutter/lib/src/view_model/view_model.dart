import 'dart:async';

import 'package:chassis/chassis.dart';
import 'package:flutter/foundation.dart';

class ViewModel<T> extends ChangeNotifier with Disposable {
  ViewModel(T initial) : _state = initial;

  final List<void Function()> _cleanup = [];

  T _state;

  T get state => _state;

  void emit(T state) {
    _state = state;
  }

  @override
  void dispose() {
    for (final cleanup in _cleanup) {
      cleanup();
    }
    super.dispose();
  }
}

extension BaseUtils on ViewModel {
  void autoDispose(Disposable disposable) {
    _cleanup.add(() => disposable.dispose);
  }

  void autoDisposeStreamSubscription(StreamSubscription sub) {
    _cleanup.add(() => sub.cancel());
  }

  void listenTo(Listenable listenable, void Function() listener) {
    listenable.addListener(listener);
    _cleanup.add(() => listenable.removeListener(listener));
  }

  void listenToAll(
    Iterable<Listenable> listenables,
    void Function() listener,
  ) {
    final merge = Listenable.merge(listenables);
    merge.addListener(listener);
    _cleanup.add(() => merge.removeListener(listener));
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
  }) {
    final handle = FutureHandle<Q, R>((query) => handler.read(query));
    _cleanup.add(handle.dispose);
    if (executeImmediately case Q query) {
      handle.execute(
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
  }) {
    final handle = StreamHandle<Q, R>((query) => handler.watch(query));
    _cleanup.add(handle.dispose);
    if (executeImmediately case Q query) {
      handle.execute(
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
  }) {
    final handle = FutureHandle<C, R>((params) => handler.run(params));
    _cleanup.add(handle.dispose);
    if (executeImmediately case C query) {
      handle.execute(
        query,
        onLoading: onLoading,
        onSuccess: onSuccess,
        onError: onError,
        onCancelled: onCancelled,
      );
    }
    return handle;
  }
}
