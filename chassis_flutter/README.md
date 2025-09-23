# chassis_flutter 🏎️

**Rigid in Structure, Flexible in Implementation.**

This package provides Flutter widgets and helpers to integrate the core [`chassis`](https://pub.dev/packages/chassis) architecture. It connects your business logic to the UI using the `provider` package, giving you the necessary tools to create a clean, reactive, and highly testable presentation layer following the **MVVM** pattern.

Learn more from the full [documentation](https://affordant.gitbook.io/chassis/).

-----

## Core Components

`chassis_flutter` provides a few key components to bridge the gap between your domain logic ([`chassis`](https://pub.dev/packages/chassis)) and your user interface (Flutter).

* `ViewModel`: The bridge between your UI and your domain. It holds UI state, processes user input by sending messages to the `Mediator`, and exposes results for the View to display.
* `ViewModelProvider`: A simple widget, built on top of `provider`, for injecting your `ViewModel` into the widget tree and making it accessible to your screens.
* `ConsumerMixin`: A mixin for `StatefulWidget`s to easily listen for one-time events (like showing a dialog or navigating) from the `ViewModel` without triggering a rebuild.

-----

## Getting Started

This guide demonstrates how to build a simple feature that fetches a greeting.

### 1\. Define UI State & Events

First, create immutable classes for your UI's **State** (the data to render) and **Events** (one-time side effects like showing a snackbar).

💡 **Why Events?** Unlike state, events don't represent what the UI *is*, but rather what it *should do*. They are sent from the `ViewModel` to the `View` to trigger actions like navigation or alerts without cluttering the UI state.

```dart
// lib/features/greeting/greeting_view_model.dart
class GreetingState {
  const GreetingState({this.isLoading = false, this.message = ''});
  final bool isLoading;
  final String message;
  
  // A copyWith method is recommended for immutability
  GreetingState copyWith({bool? isLoading, String? message}) {
    return GreetingState(
      isLoading: isLoading ?? this.isLoading,
      message: message ?? this.message,
    );
  }
}

sealed class GreetingEvent {}
class ShowGreetingSuccess implements GreetingEvent {
  const ShowGreetingSuccess(this.message);
  final String message;
}
```

### 2\. Create the ViewModel

The `ViewModel` connects to the `Mediator` to fetch data and manages the `GreetingState`. It exposes methods for the UI to call, like `fetchGreeting()`.

```dart
// lib/features/greeting/greeting_view_model.dart
class GreetingViewModel extends ViewModel<GreetingState, GreetingEvent> {
  GreetingViewModel(Mediator mediator) : super(mediator, const GreetingState());

  Future<void> fetchGreeting() async {
    setState(state.copyWith(isLoading: true));
    final result = await read(const GetGreetingQuery()); // From 'chassis' core

    result.when(
      success: (greeting) {
        setState(state.copyWith(isLoading: false, message: greeting));
        sendEvent(ShowGreetingSuccess('Greeting loaded successfully!'));
      },
      failure: (error) {
        setState(state.copyWith(isLoading: false, error: error.toString()));
      },
    );
  }
}
```

### 3\. Provide the ViewModel

Use `ViewModelProvider` (usually above your `MaterialApp` or at the screen level) to make the `ViewModel` available to the widget tree.

```dart
// lib/app.dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // This makes the GreetingViewModel available to GreetingScreen and its children.
    return ViewModelProvider(
      create: (_) => GreetingViewModel(mediator), // Assumes 'mediator' is accessible
      child: const MaterialApp(home: GreetingScreen()),
    );
  }
}
```

### 4\. Consume State & Events in the View

Finally, connect your UI to the `ViewModel`.

  * Use `context.watch<T>()` in the `build` method to listen for state changes and rebuild the UI.
  * Use `context.read<T>()` in callbacks (like `onPressed`) to call methods on the `ViewModel` without rebuilding.
  * Use the `ConsumerMixin` to handle one-time events.

<!-- end list -->

```dart
// lib/features/greeting/greeting_screen.dart
class _GreetingScreenState extends State<GreetingScreen> with ConsumerMixin {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for one-off events with ConsumerMixin
    onEvent<GreetingViewModel, GreetingEvent>((event) {
      if (event is ShowGreetingSuccess) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(event.message)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // `watch` gets the ViewModel and rebuilds the widget when the state changes.
    final viewModel = context.watch<GreetingViewModel>();
    final state = viewModel.state;

    return Scaffold(
      appBar: AppBar(title: const Text('Chassis Quickstart')),
      body: Center(
        child: state.isLoading
            ? const CircularProgressIndicator()
            : Text(state.message, style: Theme.of(context).textTheme.headlineMedium),
      ),
      floatingActionButton: FloatingActionButton(
        // `read` calls a method without subscribing to state changes.
        onPressed: () => context.read<GreetingViewModel>().fetchGreeting(),
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
```

-----

## The Full Picture

The `chassis` and `chassis_flutter` packages work together to create a clean separation of concerns:

1. **View** (`GreetingScreen`) calls `fetchGreeting()` on the `ViewModel`.
2. **ViewModel** dispatches a `GetGreetingQuery` to the `Mediator`.
3. **Mediator** finds the corresponding `GetGreetingQueryHandler` in your core `chassis` layer.
4. **Handler** executes the business logic and returns the result.
5. **ViewModel** receives the result, updates its `GreetingState`, and the **View** automatically rebuilds to show the new message.

## Next Steps

For more advanced concepts, tutorials, and best practices, please see the full **[documentation](https://affordant.gitbook.io/chassis/)**.