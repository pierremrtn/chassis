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
