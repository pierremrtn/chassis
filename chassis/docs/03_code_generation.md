# Code Generation

Code generation in Chassis automates the mediator wiring and the creation of handlers for standard operations. This section demonstrates how to reduce boilerplate of your application using `chassis_builder` while preserving type safety and testability. By the end, you'll know which annotations to use, how to configure the build process, and how the generated code integrates seamlessly with your manual implementations when business logic requires it.

## Type-safe mediator generation

`chassis_builder` generates a type-safe wrapper around the default mediator provided by `chassis`. This wrapper automate the handler registration and provides type-safe extensions to the mediator class that improves command/queries discoverability and dx.

### Automated Dependency Injection

The generator creates a Mediator subclass with a constructor accepting all required repositories and services. Handler instantiation and registration happens automatically in the constructor, eliminating the manual registration shown in the Quick Start guide.

```dart
@chassisHandler
class GetUserHandler implements QueryHandler<GetUserQuery, User> {
  final IUserRepository _userRepository;
  GetUserHandler(this._userRepository);

  @override
  Future<Order> run(CreateOrderCommand command) async {
    return await _userRepository.getUser(
      command.userId,
    );
  }
}


@chassisHandler
class CreateOrderHandler implements CommandHandler<CreateOrderCommand, Order> {
  final IOrderRepository _orderRepository;
  CreateOrderHandler(this._orderRepository);

  @override
  Future<Order> run(CreateOrderCommand command) async {
    return await _orderRepository.createOrder(
      command.userId,
      command.items,
    );
  }
}

// Generated Mediator (in app_mediator_impl.dart)
class AppMediator extends Mediator {
  AppMediator({
    required IUserRepository userRepository,
    required IOrderRepository orderRepository,
  }) {
    // Auto-generated handler registration
    registerQueryHandler(GetUserQueryHandler(userRepository));
    registerCommandHandler(CreateOrderHandler(orderRepository));
  }
}
```

The generator scans all annotated handlers to determine constructor parameters. This eliminates manual registration boilerplate while maintaining compile-time type safety. If you add a new handler with `@chassisHandler`, rebuilding updates the Mediator constructor to require that repository, causing compile errors until you provide it. This catches wiring mistakes at compile time rather than runtime.

### Type-Safe Extension Methods

The generator also creates extension methods on the Mediator for each command and query, providing an IDE-friendly, discoverable API. These methods serve as alternatives to the generic `run()`, `read()`, and `watch()` methods, offering better autocomplete and clearer code.

```dart
// Generated extension methods
extension AppMediatorExtensions on Mediator {
  // Instead of: mediator.read(GetUserQuery(userId: '123'))
  Future<User> getUserQuery(String userId) =>
      read(GetUserQuery(userId: userId));

  // Instead of: mediator.watch(WatchUserQuery(userId: '123'))
  Stream<User> watchUserQuery(String userId) =>
      watch(WatchUserQuery(userId: userId));
}

// Usage in ViewModel
class UserViewModel extends ViewModel<UserState, UserEvent> {
  void loadUser(String userId) {
    // Using mediator extension method with run()
    run(
      mediator.getUser(userId: userId),
      onState: (asyncUser) {
        setState(state.copyWith(user: asyncUser));
      },
    );
  }
}
```

Extension methods improve discoverability through IDE autocomplete. Typing `mediator.` shows all available operations as methods, making it easy to discover what the application can do. This creates a type-safe internal SDK without manual registration overhead, one of the key benefits of code generation in Chassis.

## Generating simple CRUD Handlers

Most applications consist of predictable CRUD operations—fetching a user profile, updating settings, listing products, deleting items. These operations follow a consistent pattern: receive parameters, call a repository method, return the result. There is no complex validation, no multi-service orchestration, no conditional logic. They exist purely to satisfy the architectural requirement that ViewModels cannot call repositories directly.

Chassis's code generation allow generating this repetitive code automatically, freeing developers to focus on the 10% that contains unique business logic like payment processing, order workflows, or complex calculations. The framework remains extensible—manual handlers coexist seamlessly with generated ones, all registered in the same Mediator.

Compare the manual approach from the Quick Start guide with the generated approach:

```dart
// MANUAL (approximately 80 lines for simple CRUD)
class GetUserQuery implements ReadQuery<User> {
  const GetUserQuery({required this.userId});
  final String userId;
}

class GetUserQueryHandler implements ReadHandler<GetUserQuery, User> {
  final IUserRepository _repository;
  GetUserQueryHandler(this._repository);

  @override
  Future<User> read(GetUserQuery query) async {
    return await _repository.getUser(query.userId);
  }
}

// GENERATED (1 annotation)
abstract interface class IUserRepository {
  @generateQueryHandler
  Future<User> getUser(String userId);
}

// Generates GetUserQuery and GetUserQueryHandler automatically
```

This reduction eliminates transcription errors and ensures consistency across your codebase. When you rename a repository method, the generated query and handler names update automatically. When you change parameter types, the generated code reflects those changes immediately after rebuilding.

## Annotations Reference

### @generateQueryHandler

Apply `@generateQueryHandler` to repository methods that return `Future<T>` or `Stream<T>`. The generator inspects the return type to determine whether to create a `ReadQuery` or `WatchQuery`. Parameters become query properties with identical names and types, maintaining a clear correspondence between repository methods and generated queries.

```dart
abstract interface class IUserRepository {
  // Generates: GetUserQuery (ReadQuery<User>) + GetUserQueryHandler
  @generateQueryHandler
  Future<User> getUser(String userId);

  // Generates: WatchUserQuery (WatchQuery<User>) + WatchUserQueryHandler
  @generateQueryHandler
  Stream<User> watchUser(String userId);

  // Generates: SearchUsersQuery (ReadQuery<List<User>>) + SearchUsersQueryHandler
  @generateQueryHandler
  Future<List<User>> searchUsers({
    required String searchTerm,
    String? department,
    int? limit,
  });
}
```

The generator produces complete query classes and handlers:

```dart
// Generated in user_repository.handlers.dart

class GetUserQuery implements ReadQuery<User> {
  const GetUserQuery({required this.userId});
  final String userId;
}

@chassisHandler
class GetUserQueryHandler implements ReadHandler<GetUserQuery, User> {
  final IUserRepository _repository;
  GetUserQueryHandler(this._repository);

  @override
  Future<User> read(GetUserQuery query) async {
    return await _repository.getUser(query.userId);
  }
}

class WatchUserQuery implements WatchQuery<User> {
  const WatchUserQuery({required this.userId});
  final String userId;
}

@chassisHandler
class WatchUserQueryHandler implements WatchHandler<WatchUserQuery, User> {
  final IUserRepository _repository;
  WatchUserQueryHandler(this._repository);

  @override
  Stream<User> watch(WatchUserQuery query) {
    return _repository.watchUser(query.userId);
  }
}
```

Named and optional parameters are preserved exactly as declared in the repository method. Required parameters become required in the query, optional parameters remain optional. This maintains the parameter semantics you've already defined.

### @generateCommandHandler

Apply `@generateCommandHandler` to repository methods that mutate state. The generator supports both `Future<void>` for operations with no return value and `Future<T>` for operations that return created or updated entities. The command name derives from the method name using standard naming conventions.

```dart
abstract interface class IUserRepository {
  // Generates: CreateUserCommand (Command<User>) + CreateUserCommandHandler
  @generateCommandHandler
  Future<User> createUser(String name, String email);

  // Generates: UpdateUserEmailCommand (Command<void>) + UpdateUserEmailCommandHandler
  @generateCommandHandler
  Future<void> updateUserEmail(String userId, String newEmail);

  // Generates: DeleteUserCommand (Command<void>) + DeleteUserCommandHandler
  @generateCommandHandler
  Future<void> deleteUser(String userId);
}
```

The generated commands mirror the parameter structure:

```dart
class CreateUserCommand implements Command<User> {
  const CreateUserCommand({
    required this.name,
    required this.email,
  });

  final String name;
  final String email;
}

@chassisHandler
class CreateUserCommandHandler implements CommandHandler<CreateUserCommand, User> {
  final IUserRepository _repository;
  CreateUserCommandHandler(this._repository);

  @override
  Future<User> run(CreateUserCommand command) async {
    return await _repository.createUser(command.name, command.email);
  }
}
```

The `@chassisHandler` annotation marks the generated handler for automatic registration in the Mediator, connecting the entire pipeline without manual intervention.

## Build Configuration and Workflow

### Setup

Code generation requires `build_runner` and `chassis_builder` as dev dependencies. These tools run during development to produce handler and mediator code from your annotated repositories.

```yaml
# pubspec.yaml
dependencies:
  chassis: ^0.0.1
  chassis_flutter: ^0.0.1

dev_dependencies:
  chassis_builder: ^0.0.1
  build_runner: ^2.4.0
```

Configure which generators run using `build.yaml` in your project root:

```yaml
# build.yaml
targets:
  $default:
    builders:
      chassis_builder|repositoryGenerator:
        enabled: true
      chassis_builder|mediatorGenerator:
        enabled: true
```

The `repositoryGenerator` creates queries, commands, and handlers from annotated repository methods. The `mediatorGenerator` creates the Mediator subclass with automatic dependency injection. Both generators work together to produce a complete, wired system.

### Running the Generator

Generate code using `build_runner` commands. The build command runs once and exits, suitable for CI/CD pipelines. The watch command monitors file changes and regenerates automatically, ideal for development.

```bash
# One-time generation
dart run build_runner build --delete-conflicting-outputs

# Watch mode (auto-regenerates on file changes)
dart run build_runner watch --delete-conflicting-outputs
```

The `--delete-conflicting-outputs` flag ensures stale generated files are removed when method signatures change. Without this flag, manual cleanup becomes necessary when refactoring repository interfaces. Watch mode provides immediate feedback during development—changes to repository interfaces trigger automatic regeneration within seconds.

Regarding version control, committing generated files is recommended. While some teams prefer generating code during CI/CD, committing generated files makes code review easier and prevents build-time surprises. Reviewers can see exactly what code executes, not just the annotations that produce it. This transparency aids debugging and understanding system behavior.

## Todo List Example - Code Generation Version

Revisiting the Quick Start todo list example demonstrates the dramatic reduction in boilerplate that code generation provides. The manual version required approximately 150 lines of handler code across multiple files. The generated version reduces this to just three repository annotations.

```dart
// lib/data/todo.dart
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

// lib/data/todo_repository.dart
import 'dart:async';
import 'package:chassis/chassis.dart';
import 'todo.dart';

abstract interface class ITodoRepository {
  @generateQueryHandler
  Stream<List<Todo>> watchTodos();

  @generateCommandHandler
  Future<void> addTodo(String title);

  @generateCommandHandler
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

Running `dart run build_runner build` generates:

```dart
// lib/data/todo_repository.handlers.dart (generated)
import 'package:chassis/chassis.dart';
import 'todo.dart';
import 'todo_repository.dart';

class WatchTodosQuery implements WatchQuery<List<Todo>> {
  const WatchTodosQuery();
}

@chassisHandler
class WatchTodosQueryHandler implements WatchHandler<WatchTodosQuery, List<Todo>> {
  final ITodoRepository _repository;
  WatchTodosQueryHandler(this._repository);

  @override
  Stream<List<Todo>> watch(WatchTodosQuery query) {
    return _repository.watchTodos();
  }
}

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

The ViewModel and UI code remain identical to the manual version. They still dispatch `WatchTodosQuery`, `AddTodoCommand`, and `ToggleTodoCommand`, but those classes are now generated rather than hand-written. This demonstrates an important principle: code generation changes how you write infrastructure code, not how you consume it.

The repository interface serves as the source of truth. Method signatures define commands and queries automatically, ensuring consistency between what the repository offers and what the application can request. Notice how the parameters (title, id) automatically become properties on the generated command classes. This approach maintains full type safety—renaming a repository method updates the generated command or query name, causing compile errors in consuming ViewModels until you update them.

Implementing a "Use Case" pattern manually requires defining the class, registering it in a service locator, and injecting it into the ViewModel. Chassis automates this entire pipeline through annotations, reducing the code footprint dramatically while preserving architectural benefits.

## Architectural Enforcement

Code generation enforces architectural constraints at compile time, preventing common mistakes before they reach production. Attempting to create a handler without a corresponding repository method is impossible—the generator only produces code from annotated methods. This prevents architectural drift where handlers exist independently of data layer contracts.

```dart
// ❌ Cannot exist without repository method
class OrphanedQueryHandler implements ReadHandler<OrphanedQuery, String> {
  // Generator won't register this because no @generateQueryHandler exists
  // The Mediator has no knowledge of this handler
}

// ✅ Enforced contract
abstract interface class IRepository {
  @generateQueryHandler
  Future<String> getData();
}
// Generator creates GetDataQuery and GetDataQueryHandler
// Both are guaranteed to exist and be registered
```

This compile-time enforcement prevents mistakes like forgetting to register handlers or creating commands with no corresponding handler. The type system ensures that every query and command has a handler, and every handler is registered in the Mediator. You cannot dispatch a command that has no handler, as the generator would have never created that command class.

The generator prevents wiring errors at compile time, catching issues during development rather than at runtime. This architectural guardrail maintains consistency as teams grow and developers rotate, ensuring that everyone follows the same patterns regardless of experience level.

## Summary

Code generation reduces boilerplate by for standard CRUD operations while maintaining type safety and architectural enforcement. Annotations like `@generateQueryHandler` and `@generateCommandHandler` transform repository methods into complete query-handler or command-handler pairs automatically. The generated Mediator handles dependency injection and registration without manual intervention. Type-safe extension methods improve discoverability through IDE autocomplete.


Simple delegation benefits from generation, while complex orchestration requires manual implementation. The two approaches coexist seamlessly through the `@chassisHandler` annotation, which registers manual handlers alongside generated ones.

With business logic automated through code generation, the next section focuses on connecting this architecture to Flutter's widget tree through ViewModels and reactive widgets in [UI Integration](04_ui_integration.md).
