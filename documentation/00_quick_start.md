# Quickstart Guide

This guide provides a brief overview of the `chassis` and `chassis_flutter` packages. You'll learn how to define your business logic using Queries and Commands, connect it to your Flutter UI with a ViewModel, and see how all the pieces fit together.

## The Core Idea: Queries and Commands 🎯

Chassis is built around **Queries** and **Commands**. This simple pattern helps you organize your code cleanly.

* A **Query** is a request to **read data**. Use it when you need to fetch information without changing anything. For example, getting a user's profile or a list of products. There are two types: `ReadQuery` for one-off fetches and `WatchQuery` for subscribing to a stream of data.
* A **Command** is a request to **change state**. Use it when you want to create, update, or delete data. For example, submitting a form or adding an item to a cart.

In your app, these requests are typically sent from a `ViewModel` and dispatched to the correct business logic by a central component called the **`Mediator`**. Let's see how it works in practice.

---

## Step 1: Installation

First, add `chassis` and `chassis_flutter` to your `pubspec.yaml` dependencies.

```bash
dart pub add chassis chassis_flutter
```

---

## Step 2: Define Your Domain Logic

Now, let's build the business logic for a feature that fetches a greeting message. This is the "domain" layer, which should be pure Dart code without any Flutter dependencies.

### Create Your First Query

Think of a `Query` as a structured message that describes the data you want. We'll create a `GetGreetingQuery` that represents a request for a `String` result.

```dart
// domain/features/get_greeting_query.dart
import 'package:chassis/chassis.dart';

// This class defines the request: "I want to read data that results in a String."
class GetGreetingQuery implements ReadQuery<String> {
  const GetGreetingQuery();
}
```

### Implement the Data Fetching (Repository)

To get the data, our logic will use a **`Repository`**. A repository's job is to abstract the data source—it hides the details of whether the data comes from an API, a database, or a simple text file. We define the repository interface in the domain layer, and keep the implementation details in the application package.

```dart
// domain/data/greeting_repository.dart
abstract class IGreetingRepository {
  Future<String> getGreeting();
}

// your_app/data/greeting_repository.dart
class GreetingRepository implements IGreetingRepository {
  @override
  Future<String> getGreeting() async {
    // In a real app, you'd make an API call or query a database here.
    await Future.delayed(const Duration(seconds: 1));
    return 'Hello, Chassis! ✨';
  }
}
```

### Write the Handler

Now we need a **`Handler`** to process our `GetGreetingQuery`. The handler is the actual piece of business logic that runs when the query is sent. It uses the repository to fetch the data and return the result.

```dart
// lib/features/greeting_handler.dart
import 'package:chassis/chassis.dart';
import 'get_greeting_query.dart';
import 'greeting_repository.dart';

class GetGreetingQueryHandler extends ReadHandler<GetGreetingQuery, String> {
  GetGreetingQueryHandler({
    required IGreetingRepository repository,
  }) : super((query) async {
      // The handler contains the core logic.
      // In more complex scenarios you may want to fetch multiple repositories, transform data, perform some check, etc
      return await repository.getGreeting();
    });
}
```

---

## Step 3: Wire It Up with the Mediator

We have our `Query` and our `Handler`, but how does the application know to pair them together? That's the job of the **`Mediator`**.

The `Mediator` acts as a central hub. You register all your handlers with it at startup. Later, when you send a query, the `Mediator` finds the matching handler and executes it for you.

Let's set it up in `main.dart`.

```dart
// lib/main.dart
import 'package:chassis/chassis.dart';
import 'package:flutter/material.dart';
import 'injection.dart'; 
import 'app.dart';

// 1. Define a global Mediator instance
final mediator = Mediator();

void main() {
  // 2. Register all your handlers with the Mediator
  registerHandlers(mediator);
  
  runApp(const MyApp());
}
```

The registration logic is kept in a separate file to stay organized.

```dart
// lib/injection.dart
import 'package:chassis/chassis.dart';
import 'features/greeting_handler.dart'; 
import 'features/greeting_repository.dart';

void registerHandlers(Mediator mediator) {
  // Create an instance of our repository
  final greetingRepository = GreetingRepository();
  
  // Tell the Mediator that GetGreetingQueryHandler is responsible for GetGreetingQuery
  mediator.registerQueryHandler(GetGreetingQueryHandler(greetingRepository));

  // Register other handlers here...
}
```

---

## Step 4: Define the ViewModel and Consume It in Flutter

With the business logic and wiring complete, we can now connect it to the Flutter UI. This is where `chassis_flutter` comes in, providing a `ViewModel` to bridge the gap between your domain and your widgets.

### Create State and Event Classes

First, define the data classes that will represent your UI's state and the one-off events you want to send.

* **State (`GreetingState`)**: A simple class that holds all the data needed to render your screen, such as a loading flag, the greeting message, or an error.
* **Event (`GreetingEvent`)**: A sealed class representing temporary, one-time actions, like showing a snackbar or navigating to another screen.

```dart
// lib/features/greeting_state_and_event.dart

// Represents the data needed to build the UI
class GreetingState {
  const GreetingState({
    this.isLoading = false,
    this.message = '',
    this.error,
  });

  final bool isLoading;
  final String message;
  final String? error;

  factory GreetingState.initial() => const GreetingState();

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

// Represents one-off events for the UI to handle
sealed class GreetingEvent {}
class ShowGreetingSuccessSnackbar implements GreetingEvent {
  const ShowGreetingSuccessSnackbar(this.message);
  final String message;
}
```

### Create the ViewModel

A **`ViewModel`** is a class that manages the UI's state and communicates with the domain layer through the `Mediator`.

* It extends `ViewModel<State, Event>`.
* It calls `setState()` with a new state object to trigger UI rebuilds.
* It calls `sendEvent()` to notify the UI of side effects that shouldn't be part of the state (like showing a dialog).
* It uses convenience methods like **`read`**, **`watch`**, and **`run`** to send requests to the `Mediator`.

```dart
// lib/features/greeting_view_model.dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'get_greeting_query.dart';
import 'greeting_state_and_event.dart';

class GreetingViewModel extends ViewModel<GreetingState, GreetingEvent> {
  // Initialize the ViewModel with the mediator and starting state.
  GreetingViewModel(Mediator mediator) : super(mediator, GreetingState.initial());

  Future<void> fetchGreeting() async {
    // 1. Set loading state to show a progress indicator in the UI.
    setState(state.copyWith(isLoading: true, error: null));
    
    // 2. Use the `read` helper to send the query to the Mediator.
    final result = await read(const GetGreetingQuery());

    // 3. Handle the success or failure result.
    result.when(
      success: (greeting) {
        // On success, update the state with the message.
        setState(state.copyWith(message: greeting, isLoading: false));
        // Also, send a one-off event to show a confirmation.
        sendEvent(const ShowGreetingSuccessSnackbar('Greeting loaded!'));
      },
      failure: (error) {
        // On failure, update the state with the error details.
        setState(state.copyWith(error: error.toString(), isLoading: false));
      },
    );
  }
}
```

### Provide and Build the UI

Finally, use `ViewModelProvider` to make the `ViewModel` available to your widget tree. Then, use `context.watch` to listen for state changes and the `ConsumerMixin` to handle events.

#### Provide the ViewModel

Wrap your `MaterialApp` or a specific screen route with `ViewModelProvider`. This injects your `GreetingViewModel` into the widget tree.

```dart
// lib/app.dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';
import 'features/greeting_view_model.dart';
import 'features/greeting_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ViewModelProvider makes the GreetingViewModel available to GreetingScreen
    // and any of its children.
    return ViewModelProvider(
      create: (_) => GreetingViewModel(mediator),
      child: const MaterialApp(
        home: GreetingScreen(),
      ),
    );
  }
}
```

#### Build the Screen

Your widget can now listen to the `ViewModel` for state changes and events.

* Use **`context.watch<T>()`** inside your `build` method to get the `ViewModel` instance and automatically rebuild your widget whenever `setState` is called.
* Use the **`ConsumerMixin`** on your `State` class to easily handle events sent via `sendEvent`.
* Use **`context.read<T>()`** inside callbacks (like `onPressed`) to get the `ViewModel` without subscribing to changes.

```dart
// lib/features/greeting_screen.dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';
import 'greeting_view_model.dart';
import 'greeting_state_and_event.dart';

class GreetingScreen extends StatefulWidget {
  const GreetingScreen({super.key});

  @override
  State<GreetingScreen> createState() => _GreetingScreenState();
}

// Use ConsumerMixin to easily handle events from the ViewModel.
class _GreetingScreenState extends State<GreetingScreen> with ConsumerMixin<GreetingScreen> {
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for events from the GreetingViewModel.
    // You can use this mechanism to show modals, trigger navigation, animations, ...
    onEvent<GreetingViewModel, GreetingEvent>((event) {
      switch (event) {
        case ShowGreetingSuccessSnackbar(:final message):
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Use `watch` to get the ViewModel and rebuild when its state changes.
    // Chassis uses provider under the hood, so all the standard provider utilities are available
    final viewModel = context.watch<GreetingViewModel>();
    final state = viewModel.state;

    return Scaffold(
      appBar: AppBar(title: const Text('Chassis Quickstart')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (state.isLoading)
              const CircularProgressIndicator()
            else if (state.error != null)
              Text('Error: ${state.error}', style: const TextStyle(color: Colors.red))
            else
              Text(state.message, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 20),
            ElevatedButton(
              // Use `read` in callbacks to trigger actions.
              onPressed: () => context.read<GreetingViewModel>().fetchGreeting(),
              child: const Text('Get Greeting'),
            ),
          ],
        ),
      ),
    );
  }
}
```

And that's it! You've now seen the full end-to-end flow: defining domain logic with a **Query** and **Handler**, wiring them up with the **Mediator**, and consuming the logic in a Flutter UI via a **ViewModel**. This separation keeps your business logic clean, testable, and independent of your UI framework. 🚀