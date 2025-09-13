# chassis_flutter

**Rigid in the structure, Flexible in the implementation.**

Widgets and helpers that make it easy to integrate the `chassis` architecture into Flutter. It provides the necessary tools to create a clean, reactive, and highly testable presentation layer.

Learn more from the full **[documentation](https://affordant.gitbook.io/chassis/)**.

This package is built to work with:

  * [`chassis`](https://pub.dev/packages/chassis)
  * [`provider`](https://pub.dev/packages/provider)

## Overview

While the `chassis` package provides the core domain logic, `chassis_flutter` provides the MVVM components to connect that logic to the user interface.

  * **`ViewModel`**: The bridge between your UI and your domain. It holds UI state, processes user input by sending messages to the `Mediator`, and exposes results for the View to display.
  * **`ViewModelProvider`**: A simple widget, built on top of `provider`, for injecting your `ViewModel` into the widget tree.
  * **`ConsumerMixin`**: A mixin for `StatefulWidget`s to easily listen for one-time events from the `ViewModel`, perfect for showing dialogs or navigating.

## Usage

Let's look at how to use `ViewModelProvider` to provide a `GreetingViewModel` to a screen and react to state changes.

#### 1\. Define State & Events

First, define immutable classes for your UI's **State** (the data to render) and **Events** (one-time side effects like showing a snackbar).

```dart
// lib/features/greeting_view_model.dart
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

#### 2\. Create the ViewModel

The `ViewModel` manages the state and uses helper methods like `read`, `watch`, and `run` to communicate with the `Mediator`.

```dart
// lib/features/greeting_view_model.dart
class GreetingViewModel extends ViewModel<GreetingState, GreetingEvent> {
  GreetingViewModel(Mediator mediator) : super(mediator, const GreetingState());

  Future<void> fetchGreeting() async {
    setState(state.copyWith(isLoading: true));
    final result = await read(const GetGreetingQuery());

    result.when(
      success: (greeting) {
        setState(state.copyWith(isLoading: false, message: greeting));
        sendEvent(ShowGreetingSuccess('Greeting loaded successfully!'));
      },
      failure: (error) {
        // You would typically update the state with an error message
        setState(state.copyWith(isLoading: false, error: error.toString()));
      },
    );
  }
}
```

#### 3\. Provide and Consume in Flutter

Use `ViewModelProvider` to make the `ViewModel` available to your UI. Then, use `context.watch` to listen for state changes and `ConsumerMixin` to handle events.

```dart
// lib/app.dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // ViewModelProvider makes the GreetingViewModel available to GreetingScreen
    return ViewModelProvider(
      create: (_) => GreetingViewModel(mediator), // assumes 'mediator' is accessible
      child: const MaterialApp(home: GreetingScreen()),
    );
  }
}

// lib/features/greeting_screen.dart
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
    // Use `watch` to get the ViewModel and rebuild when state changes
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
        // Use `read` in callbacks to trigger actions without subscribing to changes
        onPressed: () => context.read<GreetingViewModel>().fetchGreeting(),
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
```