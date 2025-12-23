# Quick Start

This guide builds a complete todo list application to introduce the Chassis framework. By implementing each component manually, you'll understand how data flows from the UI through business logic to the repository and back. This foundation prepares you to leverage code generation effectively in production applications. Expect to complete this tutorial in approximately 15 minutes, ending with a working application that demonstrates the core architectural patterns.

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

## The Todo List Example

### Creating the Repository Interface

In the simplest terms, a repository defines what data operations are possible without specifying how they're implemented. This abstraction enables testing and allows you to swap implementations—in-memory for development, Firebase for production, or a mock for tests—without changing business logic or UI code.

First, create the data model in `lib/data/todo.dart`:

```dart
class Todo {
  const Todo({
    required this.id,
    required this.title,
    required this.isCompleted,
  });

  final String id;
  final String title;
  final bool isCompleted;

  Todo copyWith({
    String? id,
    String? title,
    bool? isCompleted,
  }) {
    return Todo(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
```

Then create `lib/data/todo_repository.dart`:

```dart
import 'dart:async';
import 'todo.dart';

abstract interface class ITodoRepository {
  Stream<List<Todo>> watchTodos();
  Future<void> addTodo(String title);
  Future<void> toggleTodo(String id);
}

class InMemoryTodoRepository implements ITodoRepository {
  final _controller = StreamController<List<Todo>>.broadcast();
  final List<Todo> _todos = [];
  int _nextId = 0;

  InMemoryTodoRepository() {
    _controller.add(List.unmodifiable(_todos));
  }

  @override
  Stream<List<Todo>> watchTodos() => _controller.stream;

  @override
  Future<void> addTodo(String title) async {
    final todo = Todo(
      id: (_nextId++).toString(),
      title: title,
      isCompleted: false,
    );
    _todos.add(todo);
    _controller.add(List.unmodifiable(_todos));
  }

  @override
  Future<void> toggleTodo(String id) async {
    final index = _todos.indexWhere((t) => t.id == id);
    if (index != -1) {
      _todos[index] = _todos[index].copyWith(
        isCompleted: !_todos[index].isCompleted,
      );
      _controller.add(List.unmodifiable(_todos));
    }
  }

  void dispose() {
    _controller.close();
  }
}
```

The interface `ITodoRepository` declares what operations are available (watchTodos, addTodo, toggleTodo) without specifying how they work. The implementation `InMemoryTodoRepository` uses a `StreamController` to broadcast todo list changes reactively. The `Todo` model uses the `copyWith` pattern to ensure immutability—rather than modifying todos in place, we create new instances with updated values. By programming to the interface, your application can work with any implementation—swap `InMemoryTodoRepository` for a Firebase version without changing your business logic.

### Writing Business Logic

Now that you've defined your data layer, it's time to implement the business logic—the code that decides what happens when users interact with your application. This is where you define the actual behavior: what to do when a user adds a todo, what validation to apply before persisting, or how to transform data before presenting it to the UI.

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

Messages are pure data containers that carry intent. The `WatchTodosQuery` message says "I want to watch the todo list," while the `AddTodoCommand` says "I want to add a todo." The actual implementation lives in the corresponding handler.

> **Note:** In real-world applications, many Handlers are only wrappers around repository methods. The `@generateHandler` annotation allows to generates them automatically. We write them manually here to understand what the code generation produces. See [Code Generation](03_code_generation.md) to learn how to eliminate this boilerplate.

Create `lib/domain/todo_handlers.dart`:

```dart
import 'package:chassis/chassis.dart';
import '../data/todo.dart';
import '../data/todo_repository.dart';

// Query to reactively watch the todo list
class WatchTodosQuery implements WatchQuery<List<Todo>> {
  const WatchTodosQuery();
}

@chassisHandler // Enables automatic registration and type-safe extensions
class WatchTodosQueryHandler implements WatchHandler<WatchTodosQuery, List<Todo>> {
  final ITodoRepository _repository;

  WatchTodosQueryHandler(this._repository);

  @override
  Stream<List<Todo>> watch(WatchTodosQuery query) {
    return _repository.watchTodos();
  }
}

// Command to add a new todo
class AddTodoCommand implements Command<void> {
  const AddTodoCommand({required this.title});

  final String title;
}

@chassisHandler
class AddTodoCommandHandler implements CommandHandler<AddTodoCommand, void> {
  final ITodoRepository _repository;

  AddTodoCommandHandler(this._repository);

  @override
  Future<void> run(AddTodoCommand command) async {
    await _repository.addTodo(command.title);
  }
}

// Command to toggle todo completion status
class ToggleTodoCommand implements Command<void> {
  const ToggleTodoCommand({required this.id});

  final String id;
}

@chassisHandler
class ToggleTodoCommandHandler implements CommandHandler<ToggleTodoCommand, void> {
  final ITodoRepository _repository;

  ToggleTodoCommandHandler(this._repository);

  @override
  Future<void> run(ToggleTodoCommand command) async {
    await _repository.toggleTodo(command.id);
  }
}
```

Notice the dependency injection pattern—each handler receives its repository through the constructor. This ensures testability and loose coupling, enabling testing handlers in isolation. The commands carry the data they need—`AddTodoCommand` has a title, and `ToggleTodoCommand` has an id to identify which todo to toggle.

While this todo example shows simple pass-through handlers, real applications contain validation, transformation, and coordination logic here. You might validate that the title isn't empty before persisting, combine data from multiple repositories, or apply business rules before returning results. This is where business complexity lives—not scattered across widgets, but concentrated in testable, framework-independent handlers.

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
import '../data/todo.dart';
import '../data/todo_repository.dart';
import '../domain/todo_handlers.dart';

class AppMediator extends Mediator {
  AppMediator({required ITodoRepository todoRepository}) {
    registerQueryHandler(WatchTodosQueryHandler(todoRepository));
    registerCommandHandler(AddTodoCommandHandler(todoRepository));
    registerCommandHandler(ToggleTodoCommandHandler(todoRepository));
  }
}

// Extension methods provide type-safe access to operations
extension AppMediatorExtensions on Mediator {
  Stream<List<Todo>> watchTodos() => watch(WatchTodosQuery());
  Future<void> addTodo(String title) => run(AddTodoCommand(title: title));
  Future<void> toggleTodo(String id) => run(ToggleTodoCommand(id: id));
}
```

The extension methods transform generic message dispatching into a clean, type-safe API. Instead of `mediator.run(AddTodoCommand(title: title))`, you call `mediator.addTodo(title)`. Your IDE autocompletes available operations, making the application's capabilities immediately discoverable.

This entire file —the Mediator class, handler registrations, and extension methods- is automatically generated from your `@chassisHandler` annotations. See [Code Generation](03_code_generation.md) to learn how to eliminate this boilerplate entirely.

### Preparing data for the view

The ViewModel transforms domain data into UI-ready state and handles user interactions by dispatching commands. It sits between the Mediator and the widget tree, translating business operations into state changes that widgets can observe.

Create `lib/presentation/todo_view_model.dart`:

```dart
import 'package:chassis/chassis.dart';
import 'package:chassis_flutter/chassis_flutter.dart';
import '../data/todo.dart';
import '../app/app_mediator.dart';

class TodoState {
  const TodoState({required this.todos});

  final Async<List<Todo>> todos;

  TodoState copyWith({Async<List<Todo>>? todos}) {
    return TodoState(todos: todos ?? this.todos);
  }

  static TodoState initial() {
    return TodoState(todos: Async.loading());
  }
}

sealed class TodoEvent {}

class TodoAddedEvent implements TodoEvent {
  const TodoAddedEvent();
}

class TodoViewModel extends ViewModel<TodoState, TodoEvent> {
  TodoViewModel(Mediator mediator)
      : super(mediator, initial: TodoState.initial()) {
    // Start watching the todo list immediately
    watchStream(
      mediator.watchTodos(),
      (asyncTodos) => setState(state.copyWith(todos: asyncTodos)),
    );
  }

  void addTodo(String title) {
    runCommand(
      mediator.addTodo(title),
      onSuccess: (_) => sendEvent(TodoAddedEvent()),
    );
  }

  void toggleTodo(String id) {
    runCommand(mediator.toggleTodo(id));
  }
}
```

The ViewModel demonstrates Chassis's complete data flow cycle. The `watchStream()` call establishes a subscription to the repository's todo stream through the Mediator. When the repository emits a new list, the ViewModel receives it and wraps it in `Async<T>`, then updates its state. The UI automatically rebuilds to reflect the new todo list.

When a user adds a todo, the flow is:
1. UI calls `viewModel.addTodo(title)`
2. ViewModel calls `mediator.addTodo(title)` which dispatches the command
3. Mediator routes to `AddTodoCommandHandler`
4. Handler calls `repository.addTodo(title)`
5. Repository emits new todo list through its stream
6. ViewModel's `watchStream` callback receives the update
7. UI rebuilds with new todo list

State immutability ensures predictable behavior — the `copyWith` pattern creates new state objects rather than mutating existing ones. The `Async<List<Todo>>` wrapper handles loading, data, and error states automatically, eliminating manual state checking in the UI. Events provide a channel for one-time occurrences like clearing the input field or showing a snackbar, separate from persistent state.

### Building the UI

The UI layer observes state changes and dispatches user interactions to the ViewModel. The `AsyncBuilder` widget automatically renders appropriate UI based on whether data is loading, available, or errored. The `ConsumerMixin` handles event subscriptions, ensuring proper cleanup when widgets dispose.

Create `lib/presentation/todo_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:chassis_flutter/chassis_flutter.dart';
import '../data/todo.dart';
import 'todo_view_model.dart';

// We assume the ViewModel is injected above this widget
class TodoScreen extends StatefulWidget {
  const TodoScreen({Key? key}) : super(key: key);

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> with ConsumerMixin {
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // ConsumerMixin provides easy to use method to subscribe to view-model events
    onEvent<TodoViewModel, TodoEvent>((event) {
      if (event is TodoAddedEvent) {
        _textController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Todo added')),
        );
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<TodoViewModel>();

    return Scaffold(
      appBar: AppBar(title: const Text('Todo List')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Enter todo title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final title = _textController.text.trim();
                    if (title.isNotEmpty) {
                      viewModel.addTodo(title);
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBuilder<List<Todo>>(
              state: viewModel.state.todos,
              builder: (context, todos) {
                if (todos.isEmpty) {
                  return const Center(
                    child: Text('No todos yet. Add one above!'),
                  );
                }

                return ListView.builder(
                  itemCount: todos.length,
                  itemBuilder: (context, index) {
                    final todo = todos[index];
                    return ListTile(
                      leading: Checkbox(
                        value: todo.isCompleted,
                        onChanged: (_) => viewModel.toggleTodo(todo.id),
                      ),
                      title: Text(
                        todo.title,
                        style: TextStyle(
                          decoration: todo.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    );
                  },
                );
              },
              loadingBuilder: (context) => const Center(
                child: CircularProgressIndicator(),
              ),
              errorBuilder: (context, error) => Center(
                child: Text('Error: $error'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

The `AsyncBuilder` widget eliminates manual state checking. It automatically renders the appropriate UI based on whether data is loading, available, or errored, simplifying your build methods significantly. The `ConsumerMixin` handles event subscriptions and ensures proper cleanup when the widget disposes, preventing memory leaks. The `TextEditingController` is cleared automatically when a todo is added via the `TodoAddedEvent`, demonstrating how events coordinate UI actions separate from state updates.

### Putting It All Together

The main entry point wires together your dependency tree from the bottom up: Repository → Mediator → ViewModel → UI. This composition happens once at startup, creating the object graph that your application uses throughout its lifecycle.

Create `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:chassis_flutter/chassis_flutter.dart';
import 'data/todo_repository.dart';
import 'app/app_mediator.dart';
import 'presentation/todo_screen.dart';
import 'presentation/todo_view_model.dart';

// We declare the mediator globally so all our app can access it
late final AppMediator mediator;

void initializeDependencies() {
  // Initialize dependencies
  final todoRepository = InMemoryTodoRepository();
  mediator = AppMediator(todoRepository: todoRepository);
}

void main() {
  initializeDependencies();

  runApp(
    MaterialApp(
      title: 'Todo List',
      home: ViewModelProvider<TodoViewModel>(
        create: (_) => TodoViewModel(mediator),
        child: const TodoScreen(),
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

Your application's capabilities are explicitly declared — to understand what the todo list can do, examine [todo_handlers.dart](lib/domain/todo_handlers.dart) to see `WatchTodosQuery`, `AddTodoCommand`, and `ToggleTodoCommand`. This explicit catalog of operations helps new team members quickly understand the system.

## Next Steps

This manual approach exposed the framework's internals, showing exactly how messages flow from UI to repository and back. You now understand what the `@generateQueryHandler` and `@generateCommandHandler` annotations automate. In production applications, code generation handles the repetitive handler creation and Mediator wiring, reducing this example to approximately 50 lines of code.

For deeper understanding of the architectural principles guiding these patterns, explore [Core Architecture](01_core_architecture.md). To learn about testing strategies and when to implement handlers manually versus generating them, see [Business Logic](02_business_logic.md). To eliminate the boilerplate you just wrote, discover [Code Generation](03_code_generation.md). To learn advanced UI patterns like anti-flickering and event handling, proceed to [UI Integration](04_ui_integration.md).
