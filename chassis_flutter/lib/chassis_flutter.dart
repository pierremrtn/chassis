/// The Chassis Flutter package provides Flutter-specific extensions and utilities
/// for building scalable Flutter applications using the chassis architecture.
///
/// This package builds upon the core [chassis] package and provides:
///
/// ## ViewModel Pattern
/// The [ViewModel] class provides a reactive state management solution that integrates
/// with the chassis mediator pattern. It manages both state and events, providing
/// automatic UI updates and event handling.
///
/// ## State Management
/// - [StreamState] classes for handling streaming operations with loading, data, and error states
/// - [FutureState] classes for handling one-time async operations
/// - Type-safe state handling with pattern matching support
///
/// ## Provider Integration
/// The [ViewModelProvider] widget provides dependency injection for view models
/// using the provider package, with automatic lifecycle management.
///
/// ## Event Handling
/// The [ConsumerMixin] makes it easy to listen to view model events in StatefulWidgets
/// with automatic subscription management.
///
/// ## Safe Notifiers
/// [SafeChangeNotifier] and [SafeNotifierMixin] provide safe disposal behavior
/// that prevents common Flutter errors when notifying listeners after disposal.
///
/// ## Example Usage
/// ```dart
/// import 'package:chassis_flutter/chassis_flutter.dart';
///
/// // Define a view model
/// class UserViewModel extends ViewModel<UserState, UserEvent> {
///   UserViewModel() : super(UserState.initial());
///
///   void loadUser(String userId) {
///     read(GetUserQuery(userId: userId), (state) {
///       switch (state) {
///         case FutureLoading():
///           setState(UserState.loading());
///         case FutureSuccess(:final data):
///           setState(UserState.loaded(data));
///         case FutureError(:final error):
///           setState(UserState.error(error.toString()));
///       }
///     });
///   }
/// }
///
/// // Use in a widget
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
///       // Handle events
///     });
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     return ViewModelProvider(
///       create: (context) => UserViewModel(),
///       child: Consumer<UserViewModel>(
///         builder: (context, viewModel, child) {
///           return Text('User: ${viewModel.state.name}');
///         },
///       ),
///     );
///   }
/// }
/// ```
library;

export 'src/view_model/view_model.dart';
export 'src/view_model/view_model_provider.dart';
export 'package:provider/provider.dart';
export 'src/view_model/state.dart';
export 'src/consumer_widget/consumer_mixin.dart';
