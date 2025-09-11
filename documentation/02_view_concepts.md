## The Flutter Layer with `chassis_flutter`

While the `chassis` package provides the core domain logic, `chassis_flutter` connects this logic to the Flutter UI. It provides the necessary tools to implement the **Model-View-ViewModel (MVVM)** pattern, creating a clean and reactive presentation layer.

In this architecture:

  * **Model**: Represents your domain data and business logic. This layer is built using the pure Dart **`chassis`** package (defining `Queries`, `Commands`, and `Handlers`), and its logic is **accessed exclusively through the `Mediator`**.
  * **View**: Your Flutter widgets. The View is responsible for all presentation concerns: rendering the UI based on the `ViewModel`'s state, handling user input, and managing animations, navigation, localization, and theming. It forwards business actions to the `ViewModel` but contains no business logic itself.
  * **ViewModel**: The bridge between the View and the Model. It holds the UI state, processes user input by sending messages to the `Mediator`, and exposes the results for the View to display.

-----

### The `ViewModel`: Managing State and Events

The central piece of the `chassis_flutter` package is the `ViewModel<TState, TEvent>` class. It is a specialized `ChangeNotifier` designed to manage both the persistent UI state and one-time events for a screen or widget.

#### **UI State (`TState`)**

The **state** is a single, immutable object that holds all the data your View needs to render itself at any given moment. A good state object is a simple data class that might include:

  * The data to be displayed (e.g., a list of items, a user's name).
  * Flags for UI conditions (e.g., `isLoading`, `isSubmitting`).
  * Error messages.

You update the UI by calling `setState()` with a *new* instance of your state object. This notifies all listening widgets to rebuild.

```dart
// 1. Define the immutable state class for a screen
class GreetingState {
  const GreetingState({
    this.isLoading = false,
    this.message = '',
    this.error,
  });

  final bool isLoading;
  final String message;
  final String? error;

  // Helper to create new state instances
  GreetingState copyWith({
    bool? isLoading,
    String? message,
    String? error,
  }) {
    return GreetingState(
      isLoading: isLoading ?? this.isLoading,
      message: message ?? this.message,
      error: error ?? this.error,
    );
  }
}

// 2. Use it in a ViewModel
class GreetingViewModel extends ViewModel<GreetingState, GreetingEvent> {
  GreetingViewModel(Mediator mediator) : super(mediator, const GreetingState());

  void fetchGreeting() {
    // Update state to show a loading indicator
    setState(state.copyWith(isLoading: true));
    // ... logic to fetch data
  }
}
```

#### **Side Effects (`TEvent`)**

An **event** is for a one-time action or side effect that the UI should handle, but which shouldn't be stored in the state. If it were in the state, it might be re-triggered on a configuration change (like a screen rotation).

Good use cases for events include:

  * Showing a `SnackBar` or a dialog.
  * Navigating to another screen.
  * Triggering a one-off animation.

You send events using the `sendEvent()` method.

```dart
// 1. Define events using a sealed class
sealed class GreetingEvent {}
class ShowSuccessSnackbar implements GreetingEvent {
  const ShowSuccessSnackbar(this.message);
  final String message;
}

// 2. Send an event from the ViewModel
class GreetingViewModel extends ViewModel<GreetingState, GreetingEvent> {
  // ...
  void onSaveSuccess() {
    sendEvent(const ShowSuccessSnackbar('Greeting saved successfully!'));
  }
}
```

-----

### Integrating with Flutter Widgets

`chassis_flutter` provides simple tools to connect your `ViewModel` to the widget tree.

#### **1. Providing the ViewModel**

Use `ViewModelProvider` to inject your `ViewModel` into the widget tree. This makes it accessible to the screen and its children. It also automatically handles the disposal of your `ViewModel` when it's no longer needed.

```dart
// In your app's widget tree, before the screen that needs it
ViewModelProvider(
  create: (context) => GreetingViewModel(mediator),
  child: const GreetingScreen(),
);
```

Because `chassis_flutter` uses the powerful `provider` package under the hood, you have access to all its features. This means you can use familiar tools like `context.select` for fine-grained rebuilds or `MultiProvider` to compose multiple `ViewModels` cleanly.

#### **2. Listening to State and Events**

In your widget, you can now listen for changes and react accordingly.

  * To **listen to state changes**, use `context.watch<MyViewModel>()`. This will cause your widget to rebuild whenever the `ViewModel`'s state changes.
  * To **handle events**, use the `ConsumerMixin` on your `StatefulWidget`'s `State`. This provides an `onEvent` method that safely subscribes to the `ViewModel`'s event stream.

<!-- end list -->

```dart
class GreetingScreen extends StatefulWidget {
  const GreetingScreen({super.key});

  @override
  State<GreetingScreen> createState() => _GreetingScreenState();
}

// Use ConsumerMixin to easily handle events
class _GreetingScreenState extends State<GreetingScreen> with ConsumerMixin<GreetingScreen> {

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set up the event listener
    onEvent<GreetingViewModel, GreetingEvent>((event) {
      if (event is ShowSuccessSnackbar) {
        ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(event.message)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Use `watch` to get the ViewModel and rebuild when state changes
    final viewModel = context.watch<GreetingViewModel>();
    final state = viewModel.state;

    if (state.isLoading) {
      return const CircularProgressIndicator();
    }

    return Text(state.message);
  }
}
```

-----

### Communicating with the Domain Layer

The `ViewModel` uses helper methods to communicate with the `Mediator`. These methods handle the boilerplate of async operations.

#### **Handling Async Operations**

The `chassis_flutter` package provides `FutureState` and `StreamState` sealed classes to manage the lifecycle of async operations (`Loading`, `Success`/`Data`, `Error`).

**Crucially, these states are internal tools for the `ViewModel`**. They should not be exposed directly to the View. Instead, the `ViewModel` should catch these states and **map them** to its own UI-specific state. This keeps the View simple and unaware of the underlying data fetching logic.

The `read`, `run`, and `watch` methods on the `ViewModel` provide a callback that receives these internal states.

```dart
class GreetingViewModel extends ViewModel<GreetingState, GreetingEvent> {
  GreetingViewModel(Mediator mediator) : super(mediator, const GreetingState());

  // Example of fetching data with a Read query
  Future<void> fetchGreeting() async {
    // The `read` method handles calling the Mediator
    await read(const GetGreetingQuery(), (asyncState) {
      // The `asyncState` is a FutureState<String>
      // We map it to our UI-specific GreetingState
      final newState = switch (asyncState) {
        FutureLoading() => state.copyWith(isLoading: true, error: null),
        FutureSuccess(:final data) => state.copyWith(isLoading: false, message: data),
        FutureError(:final error) => state.copyWith(isLoading: false, error: error.toString()),
      };
      setState(newState);
    });
  }

  // Example of watching a stream
  void watchGreeting() {
    watch(const WatchGreetingQuery(), (streamState) {
      // The `streamState` is a StreamState<String>
      final newState = switch (streamState) {
        StreamStateLoading() => state.copyWith(isLoading: true, error: null),
        StreamStateData(:final data) => state.copyWith(isLoading: false, message: data),
        StreamStateError(:final error) => state.copyWith(isLoading: false, error: error.toString()),
      };
      setState(newState);
    });
  }
}
```

By following this pattern, you maintain a clean separation of concerns. The `View` is simple and declarative, the `ViewModel` orchestrates UI logic and state mapping, and the `Model` (your domain layer) remains pure and completely independent.