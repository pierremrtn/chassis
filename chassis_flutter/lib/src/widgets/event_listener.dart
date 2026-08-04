import 'dart:async';

import 'package:chassis_flutter/src/view_model/view_model.dart';
import 'package:chassis_flutter/src/view_model/view_model_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// {@template event_listener}
/// Invokes [onEvent] for each event emitted by the [T] provided above this
/// widget.
///
/// The event-side counterpart of `AsyncBuilder`: state maps to widgets,
/// events map to one-shot side effects (snackbars, navigation, dialogs).
/// Place it anywhere below the [ViewModelProvider]:
///
/// ```dart
/// EventListener<UserViewModel, UserEvent>(
///   onEvent: (context, event) {
///     switch (event) {
///       case UserCreatedEvent(:final user):
///         ScaffoldMessenger.of(context).showSnackBar(
///           SnackBar(content: Text('${user.name} created')),
///         );
///     }
///   },
///   child: const UserScreen(),
/// );
/// ```
///
/// The callback's [BuildContext] sits *below* the provider, so
/// `context.read<T>()` resolves the emitting view model — unlike
/// `ViewModelProvider.withEventListener`, whose context sits above it.
///
/// If the provider above swaps its view model instance, the listener
/// resubscribes to the new instance. Events emitted before the view model's
/// first listener are buffered and delivered to it, so an [EventListener]
/// mounted in the same frame as the provider receives events sent during the
/// view model's construction.
///
/// To listen from a widget that is already a [StatefulWidget] without
/// wrapping its tree, use [EventListenerMixin] instead. To listen at the
/// provision site, use `ViewModelProvider.withEventListener`.
/// {@endtemplate}
class EventListener<T extends ViewModel<Object?, E>, E> extends StatefulWidget {
  /// {@macro event_listener}
  const EventListener({
    required this.onEvent,
    required this.child,
    super.key,
  });

  /// Called for each event emitted by the [T] above this widget.
  final void Function(BuildContext context, E event) onEvent;

  /// The subtree below the listener; passed through untouched.
  final Widget child;

  @override
  State<EventListener<T, E>> createState() => _EventListenerState<T, E>();
}

class _EventListenerState<T extends ViewModel<Object?, E>, E>
    extends State<EventListener<T, E>> {
  T? _viewModel;
  StreamSubscription<E>? _subscription;

  void _subscribe(T viewModel) {
    if (identical(viewModel, _viewModel)) return;
    _subscription?.cancel();
    _viewModel = viewModel;
    _subscription = viewModel.events.listen((event) {
      if (!mounted) return;
      widget.onEvent(context, event);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Selecting the instance itself keeps this widget passive: state
    // notifications re-run the (identity) selector without rebuilding, and
    // only a provider swapping its view model instance rebuilds this widget
    // and resubscribes.
    _subscribe(context.select<T, T>((viewModel) => viewModel));
    return widget.child;
  }
}

/// {@template event_listener_mixin}
/// A mixin that provides easy access to view model events in StatefulWidgets.
///
/// The alternative to [EventListener] when the widget is already a
/// [StatefulWidget] and wrapping its tree is not convenient. The mixin
/// manages event subscriptions and cancels them when the widget is disposed.
///
/// Example usage:
/// ```dart
/// class UserScreen extends StatefulWidget {
///   @override
///   _UserScreenState createState() => _UserScreenState();
/// }
///
/// class _UserScreenState extends State<UserScreen> with EventListenerMixin {
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
mixin EventListenerMixin<W extends StatefulWidget> on State<W> {
  /// Subscriptions keyed by ViewModel *instance*: if the provider above
  /// recreates the ViewModel, a new instance can be listened to without
  /// clashing with the (now stale) previous registration.
  final Map<ViewModel<dynamic, dynamic>, StreamSubscription<Object?>>
      _subscriptions = {};

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
    final vm = context.read<T>();

    if (_subscriptions.containsKey(vm)) {
      throw StateError(
        'Event listener already registered for this $T instance',
      );
    }

    // A registration for another instance of the same type is stale: the
    // provider above replaced its view model, and the old subscription would
    // otherwise linger until this State is disposed.
    _subscriptions.removeWhere((existing, subscription) {
      if (existing is! T) return false;
      subscription.cancel();
      return true;
    });

    _subscriptions[vm] = vm.events.listen((event) {
      if (!mounted) return;
      onEvent(event);
    });
  }
}
