# chassis

Core architectural primitives for building structured Flutter applications. This pure Dart package provides the foundation for the Chassis framework, enabling testable business logic independent of the Flutter UI layer.

## Overview

The `chassis` package implements three foundational patterns:

* **Command-Query Separation (CQS)** - Separates write operations (Commands) from read operations (Queries)
* **Mediator Pattern** - Decouples message senders from handlers
* **Async State Modeling** - Represents asynchronous operation lifecycle as a sealed union

## Core Exports

### Messages

**Command** - Represents an intent to modify state:

```dart
class CreateUserCommand extends Command<User> {
  const CreateUserCommand({
    required this.name,
    required this.email,
  });

  final String name;
  final String email;
}
```

**ReadQuery** - One-time data fetch:

```dart
class GetUserQuery implements ReadQuery<User> {
  const GetUserQuery({required this.userId});
  final String userId;
}
```

**WatchQuery** - Continuous stream of updates:

```dart
class WatchUserQuery implements WatchQuery<User> {
  const WatchUserQuery({required this.userId});
  final String userId;
}
```

### Handlers

**CommandHandler** - Executes business logic for Commands:

```dart
class CreateUserCommandHandler implements CommandHandler<CreateUserCommand, User> {
  const CreateUserCommandHandler(this.repository);

  final IUserRepository repository;

  @override
  Future<User> run(CreateUserCommand command) async {
    // Validation and business logic
    if (command.email.isEmpty) {
      throw ValidationException('Email is required');
    }

    return await repository.create(command.name, command.email);
  }
}
```

**ReadHandler** - Executes one-time queries:

```dart
final handler = ReadHandler<GetUserQuery, User>(
  (query) async => await repository.findById(query.userId),
);
```

**WatchHandler** - Executes streaming queries:

```dart
final handler = WatchHandler<WatchUserQuery, User>(
  (query) => repository.watchById(query.userId),
);
```

### Mediator

The central router that dispatches messages to handlers:

```dart
final mediator = Mediator();

// Register handlers
mediator.registerCommandHandler<CreateUserCommand, User>(
  CreateUserCommandHandler(userRepository),
);

mediator.registerQueryHandler<GetUserQuery, User>(
  ReadHandler<GetUserQuery, User>(
    (query) async => await userRepository.findById(query.userId),
  ),
);

// Dispatch operations
final user = await mediator.run(CreateUserCommand(
  name: 'John Doe',
  email: 'john@example.com',
));

final fetchedUser = await mediator.read(GetUserQuery(userId: user.id));
```

### Async<T> Sealed Union

Models the complete lifecycle of asynchronous operations:

```dart
sealed class Async<T> {
  const Async();

  const factory Async.data(T value) = AsyncData<T>;
  const factory Async.loading([T? previous]) = AsyncLoading<T>;
  const factory Async.error(Object error, {StackTrace? stackTrace, T? previous}) = AsyncError<T>;
}
```

**Usage with pattern matching:**

```dart
void handleUser(Async<User> asyncUser) {
  switch (asyncUser) {
    case AsyncLoading():
      print('Loading...');
    case AsyncData(:final value):
      print('User: ${value.name}');
    case AsyncError(:final error):
      print('Error: $error');
  }
}
```

## Middleware

Intercept operations for cross-cutting concerns:

```dart
class LoggingMiddleware extends MediatorMiddleware {
  @override
  Future<R> onRun<C extends Command<R>, R>(C command, NextRun<C, R> next) async {
    print('Executing command: ${command.runtimeType}');
    final result = await next(command);
    print('Command completed');
    return result;
  }

  @override
  Future<R> onRead<Q extends ReadQuery<R>, R>(Q query, NextRead<Q, R> next) async {
    print('Executing query: ${query.runtimeType}');
    return await next(query);
  }
}

final mediator = Mediator();
mediator.addMiddleware(LoggingMiddleware());
```

## Annotations

Mark classes for code generation:

```dart
// Mark manually written handlers for auto-registration
@chassisHandler
class CreateUserCommandHandler implements CommandHandler<CreateUserCommand, User> {
  // Implementation
}

// Generate handlers from repository methods
class UserRepository {
  @generateQueryHandler
  Future<User> getUser(String id) async {
    return await database.findById(id);
  }

  @generateCommandHandler
  Future<void> deleteUser(String id) async {
    await database.delete(id);
  }
}
```

## Testing

Handlers are pure Dart classes testable without Flutter:

```dart
test('CreateUserCommandHandler validates email', () async {
  final mockRepository = MockUserRepository();
  final handler = CreateUserCommandHandler(mockRepository);

  final command = CreateUserCommand(name: 'John', email: '');

  expect(
    () => handler.run(command),
    throwsA(isA<ValidationException>()),
  );

  verifyNever(() => mockRepository.create(any(), any()));
});
```

## Installation

Add to `pubspec.yaml`:

```yaml
dependencies:
  chassis: ^0.0.1
```

For Flutter UI integration, also add:

```yaml
dependencies:
  chassis_flutter: ^0.0.1
```

For code generation:

```yaml
dev_dependencies:
  chassis_builder: ^0.0.1
  build_runner: ^2.4.0
```

## Next Steps

* **[Quick Start](../documentation/00_quick_start.md)** - Build a complete application
* **[Core Architecture](../documentation/01_core_architecture.md)** - Understand the architectural principles
* **[Business Logic Layer](../documentation/02_business_logic.md)** - Learn when to use each component
* **[Code Generation](../documentation/03_code_generation.md)** - Automate handler creation
* **[chassis_flutter](../chassis_flutter/README.md)** - Integrate with Flutter UI

## License

MIT License - See [LICENSE](../LICENSE) for details.
