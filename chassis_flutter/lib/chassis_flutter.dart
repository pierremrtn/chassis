/// The Chassis Flutter package provides Flutter-specific extensions and utilities
/// for building scalable Flutter applications using the chassis architecture.
///
/// This package builds upon the core `chassis` package and provides:
///
/// ## ViewModel Pattern
/// The [ViewModel] class provides a reactive state management solution that integrates
/// with the chassis mediator pattern. It manages both state and events, providing
/// automatic UI updates and event handling.
///
/// ## Async State
/// The core [Async] sealed class ([AsyncData], [AsyncLoading], [AsyncError])
/// models the state of asynchronous operations, and [AsyncBuilder] renders it
/// with anti-flickering behavior (previous data is kept visible while
/// refreshing).
///
/// ## Provider Integration
/// The [ViewModelProvider] widget provides dependency injection for view models
/// using the provider package, with automatic lifecycle management.
///
/// ## Event Handling
/// The [EventListener] widget invokes a callback for each view model event —
/// the event-side counterpart of [AsyncBuilder]. `ViewModelProvider.withEventListener`
/// handles events at the provision site, and [EventListenerMixin] serves
/// StatefulWidgets that would rather not wrap their tree.
///
/// ## Safe Notifiers
/// [SafeChangeNotifier] and [SafeNotifierMixin] provide safe disposal behavior
/// that prevents common Flutter errors when notifying listeners after disposal.
///
/// ## Example Usage
/// ```dart
/// import 'package:chassis_flutter/chassis_flutter.dart';
///
/// // Initialize once, before runApp
/// void main() {
///   Chassis.initialize(AppMediator(userRepository: UserRepository()));
///   runApp(const MyApp());
/// }
///
/// // Define a view model — it dispatches messages, never a concrete mediator
/// class UserViewModel extends ViewModel<UserState, UserEvent> {
///   UserViewModel({super.mediator}) : super(UserState.initial());
///
///   void loadUser(String userId) => read(
///         GetUserQuery(userId: userId),
///         policy: const RunPolicy.restartable(),
///         current: state.user,
///         onState: (user) => setState(state.copyWith(user: user)),
///       );
/// }
///
/// // Use in a widget
/// class const UserScreen({super.key}) extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     return ViewModelProvider(
///       create: (context) => UserViewModel()..loadUser('42'),
///       child: Consumer<UserViewModel>(
///         builder: (context, viewModel, child) {
///           return switch (viewModel.state.user) {
///             AsyncData(:final value) => Text('User: ${value.name}'),
///             AsyncLoading() => const CircularProgressIndicator(),
///             AsyncError() => const Text('Something went wrong'),
///           };
///         },
///       ),
///     );
///   }
/// }
/// ```
library;

export 'package:chassis/chassis.dart';
export 'package:provider/provider.dart';

export 'src/safe_notifier.dart';
export 'src/telemetry/chassis_telemetry.dart';
export 'src/view_model/view_model.dart';
export 'src/view_model/view_model_provider.dart';
export 'src/widgets/async_builder.dart';
export 'src/widgets/event_listener.dart';
