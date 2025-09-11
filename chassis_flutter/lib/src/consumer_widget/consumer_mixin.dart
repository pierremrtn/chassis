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
  Object? _viewModel;
  StreamSubscription? _eventSubscription;

  /// {@macro consumer_mixin}
  @override
  void dispose() {
    _cleanupSubscription();
    super.dispose();
  }

  /// Sets up a subscription to the view model's events stream.
  void _setupSubscription<E>(
      ViewModel<dynamic, E> vm, void Function(E) callback) {
    _viewModel = vm;
    _eventSubscription = vm.events.listen(callback);
  }

  /// Cleans up the current event subscription.
  void _cleanupSubscription() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _viewModel = null;
  }

  /// {@macro consumer_mixin}
  /// Listens to events from a view model of type [T] and calls [onEvent] when events are emitted.
  ///
  /// This method automatically manages the subscription lifecycle and will
  /// re-subscribe if the view model instance changes. The subscription is
  /// automatically disposed when the widget is disposed.
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
