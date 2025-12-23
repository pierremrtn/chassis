# Quick Start

This guide builds a complete counter application to introduce the Chassis framework. By implementing each component manually, you'll understand how data flows from the UI through business logic to the repository and back. This foundation prepares you to leverage code generation effectively in production applications. Expect to complete this tutorial in approximately 15 minutes, ending with a working application that demonstrates the core architectural patterns.

## Installation

### Adding Dependencies

Chassis consists of three core packages that work together. The `chassis` package provides pure Dart primitives for Commands, Queries, and the Mediator. The `chassis_flutter` package integrates with Flutter's widget tree through ViewModels and reactive widgets. The `chassis_builder` package generates boilerplate code from annotations, though we won't use it in this Quick Start.

Add these dependencies to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  chassis: ^0.0.1
  chassis_flutter: ^0.0.1
  provider: ^6.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  chassis_builder: ^0.0.1
  build_runner: ^2.4.0
```

## The Counter Example

### Creating the Repository Interface

In the simplest terms, a repository defines what data operations are possible without specifying how they're implemented. This abstraction enables testing and allows you to swap implementations—in-memory for development, Firebase for production, or a mock for tests—without changing business logic or UI code.

Create `lib/data/counter_repository.dart`:

```dart
import 'dart:async';

abstract interface class ICounterRepository {
  Stream<int> watchCount();
  Future<void> increment();
  Future<void> reset();
}

class InMemoryCounterRepository implements ICounterRepository {
  final _controller = StreamController<int>.broadcast();
  int _count = 0;

  InMemoryCounterRepository() {
    _controller.add(_count);
  }

  @override
  Stream<int> watchCount() => _controller.stream;

  @override
  Future<void> increment() async {
    _count++;
    _controller.add(_count);
  }

  @override
  Future<void> reset() async {
    _count = 0;
    _controller.add(_count);
  }

  void dispose() {
    _controller.close();
  }
}
```

The interface `ICounterRepository` declares what operations are available (watchCount, increment, reset) without specifying how they work. The implementation `InMemoryCounterRepository` uses a `StreamController` to broadcast count changes reactively. By programming to the interface, your application can work with any implementation—swap `InMemoryCounterRepository` for a Firebase version without changing your business logic.

### Writing Business Logic

Now that you've defined your data layer, it's time to implement the business logic—the code that decides what happens when users interact with your application. This is where you define the actual behavior: what to do when a user increments the counter, what validation to apply before resetting, or how to transform data before presenting it to the UI.

Business logic should be independent of Flutter widgets, making it fast to test and easy to reason about. By isolating this code from UI concerns, you can verify behavior without rendering widgets, navigate complex scenarios with simple unit tests, and refactor with confidence knowing tests will catch breaking changes.

#### Commands and queries

Chassis organizes business logic using Command-Query Responsibility Segregation (CQRS), distinguishing between operations that read data (Queries) and operations that change state (Commands). This separation clarifies intent—when you see a Query, you know it's safe to call repeatedly without side effects. When you see a Command, you know state will change.

The benefits become evident as applications grow:
- **Queries** return data without side effects, making them safe to cache, retry, or call in parallel
- **Commands** represent intent to change state, making it clear where mutations occur and enabling audit logging or undo functionality

This separation allows different optimization strategies: aggressive caching for Queries, transaction handling for Commands

See [Core Architecture](01_core_architecture.md#command-query-separation) for deeper exploration of CQRS principles.

#### Implementing Handlers

In Chassis, business logic lives in stateless handlers classes that receive messages from the Mediator and coordinate with repositories to fulfill requests. Each handler focuses on a single responsibility: receive a message, execute business logic, call repositories as needed, and return results.

Messages are pure data containers that carry intent. The `WatchCountQuery` message says "I want to watch the counter," while the `IncrementCommand` says "I want to increment the counter." The actual implementation lives in the corresponding handler.

> **Note:** In real-world applications, many Handlers are only wrappers around repository methods. The `@generateHandler` annotation allows to generates them automatically. We write them manually here to understand what the code generation produces. See [Code Generation](03_code_generation.md) to learn how to eliminate this boilerplate.

Create `lib/domain/counter_handlers.dart`:

```dart
import 'package:chassis/chassis.dart';
import '../data/counter_repository.dart';

// Query to reactively watch the counter value
class WatchCountQuery implements WatchQuery<int> {
  const WatchCountQuery();
}

@chassisHandler // Enables automatic registration and type-safe extensions
class WatchCountQueryHandler implements WatchHandler<WatchCountQuery, int> {
  final ICounterRepository _repository;

  WatchCountQueryHandler(this._repository);

  @override
  Stream<int> watch(WatchCountQuery query) {
    return _repository.watchCount();
  }
}

// Command to increment the counter
class IncrementCommand implements Command<void> {
  const IncrementCommand();
}

@chassisHandler
class IncrementCommandHandler implements CommandHandler<IncrementCommand, void> {
  final ICounterRepository _repository;

  IncrementCommandHandler(this._repository);

  @override
  Future<void> run(IncrementCommand command) async {
    await _repository.increment();
  }
}

// Command to reset the counter
class ResetCommand implements Command<void> {
  const ResetCommand();
}

@chassisHandler
class ResetCommandHandler implements CommandHandler<ResetCommand, void> {
  final ICounterRepository _repository;

  ResetCommandHandler(this._repository);

  @override
  Future<void> run(ResetCommand command) async {
    await _repository.reset();
  }
}
```

Notice the dependency injection pattern—each handler receives its repository through the constructor. This ensures testability and loose coupling, enabling testing handlers in isolation.

While this counter example shows simple pass-through handlers, real applications contain validation, transformation, and coordination logic here. You might validate user input before persisting, combine data from multiple repositories, or apply business rules before returning results. This is where business complexity lives—not scattered across widgets, but concentrated in testable, framework-independent handlers.

The handler's logic is pure business code with no Flutter dependencies, making it fast and easy to test. See [Business Logic](02_business_logic.md#unit-testing-handlers) for detailed testing strategies and examples of more complex handler implementations.

### Accessing business logic

Your UI needs a single entry point to execute business logic—this is the Mediator. Instead of ViewModels depending directly on multiple repositories or handlers, they depend only on the Mediator. This centralization provides several benefits:

- **Single dependency for UI**: ViewModels only need the Mediator, simplifying their constructor signatures
- **Dependency injection**: The Mediator wires handlers to their dependencies at startup, managing the object graph
- **Extensibility**: Middleware can intercept Commands and Queries for logging, validation, or caching without changing handlers
- **Discoverability**: Type-safe extension methods make all available operations autocomplete-friendly

In production applications, `chassis_builder` automatically generates the Mediator implementation, handler registration, and type-safe extension methods by scanning for `@chassisHandler` annotations. We'll create this manually here to understand what gets generated.

Create `lib/app/app_mediator.dart`:

```dart
import 'package:chassis/chassis.dart';
import '../data/counter_repository.dart';
import '../domain/counter_handlers.dart';

class AppMediator extends Mediator {
  AppMediator({required ICounterRepository counterRepository}) {
    registerQueryHandler(WatchCountQueryHandler(counterRepository));
    registerCommandHandler(IncrementCommandHandler(counterRepository));
    registerCommandHandler(ResetCommandHandler(counterRepository));
  }
}

// Extension methods provide type-safe access to operations
extension AppMediatorExtensions on Mediator {
  Stream<int> watchCount() => watch(WatchCountQuery());
  Future<void> increment() => run(IncrementCommand());
  Future<void> reset() => run(ResetCommand());
}
```

The extension methods transform generic message dispatching into a clean, type-safe API. Instead of `mediator.run(IncrementCommand())`, you call `mediator.increment()`. Your IDE autocompletes available operations, making the application's capabilities immediately discoverable.

This entire file —the Mediator class, handler registrations, and extension methods- is automatically generated from your `@chassisHandler` annotations. See [Code Generation](03_code_generation.md) to learn how to eliminate this boilerplate entirely.

### Preparing data for the view

The ViewModel transforms domain data into UI-ready state and handles user interactions by dispatching commands. It sits between the Mediator and the widget tree, translating business operations into state changes that widgets can observe.

Create `lib/presentation/counter_view_model.dart`:

```dart
import 'package:chassis/chassis.dart';
import 'package:chassis_flutter/chassis_flutter.dart';
import '../domain/counter_handlers.dart';

class CounterState {
  const CounterState({required this.count});

  final Async<int> count;

  CounterState copyWith({Async<int>? count}) {
    return CounterState(count: count ?? this.count);
  }

  static CounterState initial() {
    return CounterState(count: Async.loading());
  }
}

sealed class CounterEvent {}

class CounterResetEvent implements CounterEvent {
  const CounterResetEvent();
}

class CounterViewModel extends ViewModel<CounterState, CounterEvent> {
  CounterViewModel(Mediator mediator)
      : super(mediator, initial: CounterState.initial()) {
    // Start watching the counter stream immediately
    watchStream(
      mediator.watchCount(),
      (asyncCount) => setState(state.copyWith(count: asyncCount)),
    );
  }

  void increment() {
    runCommand(mediator.increment());
  }

  void reset() {
    runCommand(
      mediator.reset(),
      onSuccess: (_) => sendEvent(CounterResetEvent()),
    );
  }
}
```

The ViewModel demonstrates Chassis's complete data flow cycle. The `watchStream()` call establishes a subscription to the repository's count stream through the Mediator. When the repository emits a new value, the ViewModel receives it and wraps it in `Async<T>`, then updates its state. The UI automatically rebuilds to reflect the new count.

When a user taps the increment button, the flow is:
1. UI calls `viewModel.increment()`
2. ViewModel calls `mediator.increment()` which dispatches the command
3. Mediator routes to `IncrementCommandHandler`
4. Handler calls `repository.increment()`
5. Repository emits new count through its stream
6. ViewModel's `watchStream` callback receives the update
7. UI rebuilds with new count

State immutability ensures predictable behavior — the `copyWith` pattern creates new state objects rather than mutating existing ones. The `Async<int>` wrapper handles loading, data, and error states automatically, eliminating manual state checking in the UI. Events provide a channel for one-time occurrences like showing a snackbar, separate from persistent state.

### Building the UI

The UI layer observes state changes and dispatches user interactions to the ViewModel. The `AsyncBuilder` widget automatically renders appropriate UI based on whether data is loading, available, or errored. The `ConsumerMixin` handles event subscriptions, ensuring proper cleanup when widgets dispose.

Create `lib/presentation/counter_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:chassis_flutter/chassis_flutter.dart';
import 'counter_view_model.dart';

// We assume the ViewModel is injected above this widget
class CounterScreen extends StatefulWidget {
  const CounterScreen({Key? key}) : super(key: key);

  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen> with ConsumerMixin {
  @override
  void initState() {
    super.initState();

    // ConsumerMixin provides easy to uses method to subscribes to view-models events
    onEvent<CounterViewModel, CounterEvent>((event) {
      if (event is CounterResetEvent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Counter reset to 0')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<CounterViewModel>();

    return Scaffold(
      appBar: AppBar(title: const Text('Counter Example')),
      body: Center(
        child: AsyncBuilder<int>(
          state: viewModel.state.count,
          builder: (context, count) {
            return Text(
              '$count',
              style: Theme.of(context).textTheme.displayLarge,
            );
          },
          loadingBuilder: (context) => const CircularProgressIndicator(),
          errorBuilder: (context, error) => Text('Error: $error'),
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: viewModel.increment,
            heroTag: 'increment',
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            onPressed: viewModel.reset,
            heroTag: 'reset',
            child: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}
```

The `AsyncBuilder` widget eliminates manual state checking. It automatically renders the appropriate UI based on whether data is loading, available, or errored, simplifying your build methods significantly. The `ConsumerMixin` handles event subscriptions and ensures proper cleanup when the widget disposes, preventing memory leaks.

### Putting It All Together

The main entry point wires together your dependency tree from the bottom up: Repository → Mediator → ViewModel → UI. This composition happens once at startup, creating the object graph that your application uses throughout its lifecycle.

Create `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:chassis_flutter/chassis_flutter.dart';
import 'data/counter_repository.dart';
import 'app/app_mediator.dart';
import 'presentation/counter_screen.dart';
import 'presentation/counter_view_model.dart';


// We declare the mediator globally so all our app can access it
late final AppMediator mediator;

void initializeDependencies() {
  // Initialize dependencies
  final counterRepository = InMemoryCounterRepository();
  mediator = AppMediator(counterRepository: counterRepository);
}

void main() {

  initializedDependencies();

  runApp(
    MaterialApp(
      title: 'Counter Example',
      home: ViewModelProvider<CounterViewModel>(
        create: (_) => CounterViewModel(mediator),
        child: const CounterScreen(),
      ),
    ),
  );
}
```

The dependency tree flows naturally — repositories have no dependencies, the Mediator depends on repositories, ViewModels depend on the Mediator, and widgets depend on ViewModels. This unidirectional dependency graph makes the application easy to reason about and test.

## What You Just Built

You've created a complete Chassis application with clear separation of concerns. The architecture flows naturally through distinct layers:

- **Repository layer**: Defines data operations through interfaces, implemented by concrete classes
- **Handler layer**: Coordinates business logic, translating messages into repository calls
- **Mediator layer**: Routes messages to handlers, provides type-safe API through extensions
- **ViewModel layer**: Manages UI state reactively, wrapping async operations in `Async<T>`
- **UI layer**: Observes state and dispatches user actions, automatically handling loading/error states

The key benefits of this architecture:
- **Testability**: Each layer can be tested in isolation with mocks
- **Discoverability**: Extension methods make available operations autocomplete-friendly
- **Maintainability**: Business logic lives in handlers, not spread across widgets
- **Scalability**: Adding features follows the same pattern, maintaining consistency

Your application's capabilities are explicitly declared — to understand what the counter can do, examine [counter_handlers.dart](lib/domain/counter_handlers.dart) to see `WatchCountQuery`, `IncrementCommand`, and `ResetCommand`. This explicit catalog of operations helps new team members quickly understand the system.

## Next Steps

This manual approach exposed the framework's internals, showing exactly how messages flow from UI to repository and back. You now understand what the `@generateQueryHandler` and `@generateCommandHandler` annotations automate. In production applications, code generation handles the repetitive handler creation and Mediator wiring, reducing this example to approximately 50 lines of code.

For deeper understanding of the architectural principles guiding these patterns, explore [Core Architecture](01_core_architecture.md). To learn about testing strategies and when to implement handlers manually versus generating them, see [Business Logic](02_business_logic.md). To eliminate the boilerplate you just wrote, discover [Code Generation](03_code_generation.md). To learn advanced UI patterns like anti-flickering and event handling, proceed to [UI Integration](04_ui_integration.md).
