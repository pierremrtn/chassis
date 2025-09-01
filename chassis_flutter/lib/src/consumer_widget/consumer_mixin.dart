import 'dart:async';

import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

mixin ConsumerMixin<Widget extends StatefulWidget> on State<Widget> {
  Object? _viewModel;
  StreamSubscription? _eventSubscription;

  @override
  void dispose() {
    _cleanupSubscription();
    super.dispose();
  }

  void _setupSubscription<E>(
      ViewModel<dynamic, E> vm, void Function(E) callback) {
    _viewModel = vm;
    _eventSubscription = vm.events.listen(callback);
  }

  void _cleanupSubscription() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _viewModel = null;
  }

  void onEvent<T extends ViewModel<dynamic, E>, E>(
    void Function(E event) onEvent,
  ) {
    final newViewModel = context.read<T>();
    if (_viewModel != newViewModel) {
      _cleanupSubscription();
      _setupSubscription(newViewModel, onEvent);
    }
  }
}
