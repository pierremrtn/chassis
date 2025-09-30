import 'dart:async';

import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

/// {@template consumer_mixin}
/// A mixin that provides easy access to view model events in StatefulWidgets.
///
/// This mixin automatically manages event subscriptions and cleanup, making it
/// easy to listen to view model events without manual subscription management.
/// It handles the lifecycle of event subscriptions and ensures they are properly
/// disposed when the widget is disposed.
///
/// Example usage:
/// ```dart
/// class UserScreen extends StatefulWidget {
///   @override
///   _UserScreenState createState() => _UserScreenState();
/// }
///
/// class _UserScreenState extends State<UserScreen> with ConsumerMixin {
///   @override
///   void initState() {
///     super.initState();
///     onEvent<UserViewModel, UserEvent>((event) {
///       switch (event) {
///         case UserCreatedEvent(:final user):
///           ScaffoldMessenger.of(context).showSnackBar(
///             SnackBar(content: Text('User ${user.name} created!')),
///           );
///         case UserCreationFailedEvent(:final error):
///           ScaffoldMessenger.of(context).showSnackBar(
///             SnackBar(content: Text('Error: $error')),
///           );
///       }
///     });
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     return Scaffold(
///       body: Consumer<UserViewModel>(
///         builder: (context, viewModel, child) {
///           return Text('User: ${viewModel.state.name}');
///         },
///       ),
///     );
///   }
/// }
/// ```
/// {@endtemplate}
mixin ConsumerMixin<Widget extends StatefulWidget> on State<Widget> {
  final Map<Type, StreamSubscription> _subscriptions = {};

  @override
  void dispose() {
    for (var sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }

  void onEvent<T extends ViewModel<dynamic, E>, E>(
    void Function(E event) onEvent,
  ) {
    final key = T;

    if (_subscriptions.containsKey(key)) {
      throw StateError('Event listener already registered for $T');
    }

    final vm = context.read<T>();
    _subscriptions[key] = vm.events.listen(onEvent);
  }
}
