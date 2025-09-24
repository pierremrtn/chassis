---
icon: bolt
---

# Quickstart Guide

Welcome! This guide will walk you through building your first feature with Chassis, from writing core business logic in pure Dart to creating a fully reactive Flutter UI.

## What You'll Build

You'll create a simple screen with a button. When pressed, the app will fetch a greeting message, display a loading indicator while it works, show an error if something goes wrong, and then display the final message. This example covers the essential end-to-end flow of the Chassis architecture.

***

## The Core Philosophy 🎯

Chassis is built on the principle of **Command-Query Separation (CQS)**, which organizes your logic into two distinct categories:

* **Queries**: These are requests to **read or fetch data**. Think of them as asking a question. They are side-effect-free and do not alter the state of the application.
* **Commands**: These are requests to **change state or perform an action**. Think of them as giving an order, like saving data, logging a user in, or updating a profile.

This separation is the key to creating predictable, scalable, and highly testable applications.

***

## Step 1: Setup & Project Structure

First, add the necessary packages to your `pubspec.yaml`. The `provider` package is a peer dependency of `chassis_flutter`.

```bash
dart pub add chassis chassis_flutter provider
```

**A Layered Architecture 🏗️**

Chassis thrives on a clean, layered architecture. For this guide, we'll organize our code into three distinct layers:

* **Domain Layer**: The heart of your application. It contains your core business logic, including use cases (**Handlers**) and data contracts (**Interfaces**). This layer is **pure Dart** and is completely independent of Flutter or any database.
* **Data Layer**: This layer implements the contracts from the Domain layer. It's responsible for all communication with the outside world, containing concrete **Repository** implementations that talk to APIs, databases, or other data sources.
* **Presentation Layer**: The Flutter UI. This layer is responsible for displaying state to the user and capturing their input. It contains your **Widgets** and **ViewModels**.

***

## Step 2: The Domain Layer (The "What")

Let's define the business logic for our feature. This layer describes _what_ our app can do, not _how_ it does it. It has **no Flutter or infrastructure dependencies**.

### Define the Query

A **Query** is a data-carrying object that represents a request for information. It defines the inputs required and the expected type of the output.

```dart
// domain/use_cases/get_greeting_query.dart
import 'package:chassis/chassis.dart';

// This class is a message that says: "I need to fetch a String."
// It implements ReadQuery<String>, specifying the expected return type.
class GetGreetingQuery implements ReadQuery<String> {
  const GetGreetingQuery();
}
```

### Define the Repository Interface

A Repository **Interface** (or "contract") defines the data operations required by the domain. It's an abstraction that allows the domain layer to remain ignorant of where the data comes from.

```dart
// domain/repositories/greeting_repository.dart

// This contract says: "I need something that can perform greeting operations."
abstract class IGreetingRepository {
  Future<String> getGreeting();
}
```

### Write the Handler

A **Handler** is your **Use Case**. It contains the core logic that orchestrates a query or command. When overriding the `read` or `write` method directly, you `implement` the handler interface.

```dart
// domain/use_cases/get_greeting_query_handler.dart
import 'package:chassis/chassis.dart';
import 'package:my_app/domain/repositories/greeting_repository.dart';
import 'package:my_app/domain/use_cases/get_greeting_query.dart';

// This handler's job is to process the GetGreetingQuery.
class GetGreetingQueryHandler implements ReadHandler<GetGreetingQuery, String> {
  final IGreetingRepository _repository;
  GetGreetingQueryHandler(this._repository);

  // The core logic lives here.
  @override
  Future<String> read(GetGreetingQuery query) {
    // For this use case, the logic is simple: delegate to the repository.
    return _repository.getGreeting();
  }
}
```

***

## Step 3: The Data Layer (The "How")

Now, we provide the concrete implementation for the interfaces defined in the domain layer. This is where you connect to real-world data sources.

### Implement the Repository

Here, we fulfill the `IGreetingRepository` contract. This is where you would place your `http` API calls or database queries.

```dart
// data/repositories/greeting_repository.dart
import 'package:my_app/domain/repositories/greeting_repository.dart';

class GreetingRepository implements IGreetingRepository {
  @override
  Future<String> getGreeting() async {
    // In a real app, this is where you'd make an API call.
    // We'll simulate a network delay.
    await Future.delayed(const Duration(seconds: 2));
    
    // To test error handling, uncomment the following line:
    // throw Exception('Failed to load greeting.');

    return 'Hello, Chassis! ✨';
  }
}
```

***

## Step 4: Wire It Up with the Mediator

The **Mediator** is a central dispatcher that connects messages (like `GetGreetingQuery`) to their corresponding `Handler`. This decouples the sender from the receiver. You register your dependencies and handlers at application startup.

```dart
// main.dart
import 'package:chassis/chassis.dart';
import 'package:flutter/material.dart';
import 'package:my_app/data/repositories/greeting_repository.dart';
import 'package:my_app/domain/use_cases/get_greeting_query_handler.dart';
import 'package:my_app/presentation/app.dart';

// 1. Create a global Mediator instance. It acts as our central message bus.
final mediator = Mediator();

void main() {
  // 2. Register all dependencies and handlers.
  // Here, we tell the Mediator which concrete classes to use.
  final greetingRepository = GreetingRepository();
  mediator.registerQueryHandler(GetGreetingQueryHandler(greetingRepository));

  runApp(const MyApp());
}
```

***

## Step 5: The Presentation Layer (The UI)

With all the logic in place, let's connect it to Flutter. Remember, the presentation layer should only depend on the **Domain Layer**, never the data layer.

### Define State and Events

Create immutable classes to represent the UI's visual state and any logical, one-off events that the UI needs to react to.

```dart
// presentation/features/greeting/greeting_state_and_event.dart
import 'package:equatable/equatable.dart';

class GreetingState extends Equatable {
  const GreetingState({
    this.isLoading = false, 
    this.message = '',
    this.error,
  });

  final bool isLoading;
  final String message;
  final String? error;
  
  GreetingState copyWith({
    bool? isLoading, 
    String? message, 
    // Allow nulling out the error
    String? Function()? error,
  }) {
    return GreetingState(
      isLoading: isLoading ?? this.isLoading,
      message: message ?? this.message,
      error: error != null ? error() : this.error,
    );
  }

  @override
  List<Object?> get props => [isLoading, message, error];
}

// Events are for business logic outcomes, like showing a snackbar or navigating.
sealed class GreetingEvent {}
class ShowGreetingSuccessSnackbar implements GreetingEvent {
  const ShowGreetingSuccessSnackbar(this.message);
  final String message;
}
```

### Create the ViewModel

The `ViewModel` is the bridge between the UI and the domain layer. It holds the UI state, sends messages to the `Mediator`, and exposes the results for widgets to consume.

```dart
// presentation/features/greeting/greeting_view_model.dart
import 'package:chassis/chassis.dart';
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:my_app/domain/use_cases/get_greeting_query.dart';
import 'greeting_state_and_event.dart';

class GreetingViewModel extends ViewModel<GreetingState, GreetingEvent> {
  GreetingViewModel(Mediator mediator) : super(mediator, const GreetingState());

  Future<void> fetchGreeting() async {
    setState(state.copyWith(isLoading: true, error: () => null));
    final result = await read(const GetGreetingQuery());

    result.when(
      success: (greeting) {
        setState(state.copyWith(message: greeting, isLoading: false));
        // Send a logical event; the view will handle the UI effect.
        sendEvent(const ShowGreetingSuccessSnackbar('Greeting loaded!'));
      },
      failure: (error) {
        setState(state.copyWith(isLoading: false, error: () => error.toString()));
      },
    );
  }
}
```

### Provide and Build the UI

Finally, use `ViewModelProvider` to make the `ViewModel` accessible to your widget tree, and then build your UI to react to its state and events.

#### 1. Provide the ViewModel

Wrap your `MaterialApp` or a specific screen route with `ViewModelProvider`. This injects your `GreetingViewModel` into the widget tree so that `GreetingScreen` and its children can access it.

```dart
// presentation/app.dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';
import 'package:my_app/main.dart'; // To access the global mediator
import 'package:my_app/presentation/features/greeting/greeting_screen.dart';
import 'package:my_app/presentation/features/greeting/greeting_view_model.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelProvider(
      create: (_) => GreetingViewModel(mediator),
      child: const MaterialApp(
        home: GreetingScreen(),
      ),
    );
  }
}
```

#### 2. Build the Screen

Your widget can now listen to the `ViewModel`. Use `context.watch` to rebuild when the state changes and the `ConsumerMixin` to react to events.

```dart
// presentation/features/greeting/greeting_screen.dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';
import 'package:my_app/presentation/features/greeting/greeting_state_and_event.dart';
import 'package:my_app/presentation/features/greeting/greeting_view_model.dart';

class GreetingScreen extends StatefulWidget {
  const GreetingScreen({super.key});

  @override
  State<GreetingScreen> createState() => _GreetingScreenState();
}

class _GreetingScreenState extends State<GreetingScreen> with ConsumerMixin {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for logical events and translate them into UI actions.
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
    // `watch` subscribes to state changes and rebuilds the widget.
    final state = context.watch<GreetingViewModel>().state;

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
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        // `read` calls a method on the ViewModel without subscribing to changes.
        onPressed: () => context.read<GreetingViewModel>().fetchGreeting(),
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
```

***

## Congratulations! 🚀

You've successfully built a feature following the Chassis architecture!

By strictly separating your **Domain** (the "what"), **Data** (the "how"), and **Presentation** (the UI), you create code that is decoupled, easier to test, and maintainable.

To learn more, dive into the full documentation to explore commands, advanced error handling, and more powerful features.
