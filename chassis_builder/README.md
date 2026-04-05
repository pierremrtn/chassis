# chassis_builder

Code generation tools for the [Chassis](https://pub.dev/packages/chassis) framework. This package automates handler creation from repository methods and generates a Mediator class with dependency injection.

## Overview

The `chassis_builder` package provides two builders:

1. **Repository Builder** - Generates Commands, Queries, and Handlers from annotated repository methods
2. **Chassis Builder** - Generates a Mediator class that registers all handlers with dependency injection

Code generation eliminates manual handler wiring and ensures type-safe registration.

## Installation

Add to `pubspec.yaml`:

```yaml
dependencies:
  chassis: ^0.0.1

dev_dependencies:
  chassis_builder: ^0.0.1
  build_runner: ^2.4.0
```

## Configuration

Create `build.yaml` in the project root:

```yaml
targets:
  $default:
    builders:
      chassis_builder|repository_builder:
        enabled: true
        generate_for:
          - lib/**_repository.dart
      chassis_builder|chassis_builder:
        enabled: true
        options:
          mediator_name: AppMediator
          output_name: app_mediator.dart
```

### Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `mediator_name` | Name of the generated Mediator class | `AppMediator` |
| `output_name` | Name of the generated file | `app_mediator.dart` |
| `generate_for` | File patterns for repository generation | `lib/**_repository.dart` |

## Usage

### 1. Annotate Repository Methods

Use `@generateQueryHandler` and `@generateCommandHandler` on repository methods:

```dart
import 'package:chassis/chassis.dart';

class UserRepository {
  // Generates ReadQuery + ReadHandler
  @generateQueryHandler
  Future<User> getUser(String id) async {
    return await database.findById(id);
  }

  // Generates WatchQuery + WatchHandler
  @generateQueryHandler
  Stream<List<User>> watchActiveUsers() {
    return database.watchQuery('SELECT * FROM users WHERE active = 1');
  }

  // Generates Command + CommandHandler
  @generateCommandHandler
  Future<void> createUser(String name, String email) async {
    await database.insert(User(name: name, email: email));
  }

  @generateCommandHandler
  Future<User> updateUserEmail(String userId, String newEmail) async {
    await database.update('users', {'email': newEmail}, where: 'id = ?', whereArgs: [userId]);
    return await getUser(userId);
  }
}
```

### 2. Run Code Generation

Execute build_runner:

```bash
# One-time generation
dart run build_runner build

# Watch mode (regenerates on file changes)
dart run build_runner watch

# Clean and rebuild
dart run build_runner build --delete-conflicting-outputs
```

### 3. Generated Output

**Generated File**: `lib/user_repository.handlers.dart`

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:chassis/chassis.dart';
import 'package:myapp/user_repository.dart';

// Generated Query
class GetUserQuery implements ReadQuery<User> {
  const GetUserQuery({required this.id});
  final String id;
}

// Generated Handler
@chassisHandler
class GetUserQueryHandler implements ReadHandler<GetUserQuery, User> {
  GetUserQueryHandler(this._repository);
  final UserRepository _repository;

  @override
  Future<User> read(GetUserQuery query) async {
    return await _repository.getUser(query.id);
  }
}

// Generated Watch Query
class WatchActiveUsersQuery implements WatchQuery<List<User>> {
  const WatchActiveUsersQuery();
}

// Generated Watch Handler
@chassisHandler
class WatchActiveUsersQueryHandler implements WatchHandler<WatchActiveUsersQuery, List<User>> {
  WatchActiveUsersQueryHandler(this._repository);
  final UserRepository _repository;

  @override
  Stream<List<User>> watch(WatchActiveUsersQuery query) {
    return _repository.watchActiveUsers();
  }
}

// Generated Command
class CreateUserCommand implements Command<void> {
  const CreateUserCommand({
    required this.name,
    required this.email,
  });

  final String name;
  final String email;
}

// Generated Command Handler
@chassisHandler
class CreateUserCommandHandler implements CommandHandler<CreateUserCommand, void> {
  CreateUserCommandHandler(this._repository);
  final UserRepository _repository;

  @override
  Future<void> run(CreateUserCommand command) async {
    await _repository.createUser(command.name, command.email);
  }
}
```

### 4. Generated Mediator

**Generated File**: `lib/app_mediator.dart`

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:chassis/chassis.dart';
import 'package:myapp/user_repository.dart';
import 'package:myapp/user_repository.handlers.dart';

class AppMediator extends Mediator {
  AppMediator({
    required UserRepository userRepository,
  }) {
    registerQueryHandler<GetUserQuery, User>(
      GetUserQueryHandler(userRepository),
    );
    registerQueryHandler<WatchActiveUsersQuery, List<User>>(
      WatchActiveUsersQueryHandler(userRepository),
    );
    registerCommandHandler<CreateUserCommand, void>(
      CreateUserCommandHandler(userRepository),
    );
    registerCommandHandler<UpdateUserEmailCommand, User>(
      UpdateUserEmailCommandHandler(userRepository),
    );
  }
}
```

### 5. Use in Application

Initialize the generated Mediator:

```dart
import 'package:myapp/app_mediator.dart';
import 'package:myapp/user_repository.dart';

void main() {
  final userRepository = UserRepositoryImpl();

  final mediator = AppMediator(
    userRepository: userRepository,
  );

  runApp(MyApp(mediator: mediator));
}
```

## Manual Handler Registration

For handlers with custom logic, use the `@chassisHandler` annotation:

```dart
@chassisHandler
class ComplexOperationHandler implements CommandHandler<ComplexOperationCommand, Result> {
  const ComplexOperationHandler({
    required this.repository,
    required this.validator,
    required this.logger,
  });

  final IDataRepository repository;
  final IValidator validator;
  final ILogger logger;

  @override
  Future<Result> run(ComplexOperationCommand command) async {
    // Complex multi-step logic
    await validator.validate(command);
    await logger.log('Starting operation');

    final result = await repository.execute(command);

    await logger.log('Operation completed');
    return result;
  }
}
```

The generated Mediator will include this handler and require its dependencies in the constructor:

```dart
AppMediator({
  required UserRepository userRepository,
  required IDataRepository repository,
  required IValidator validator,
  required ILogger logger,
}) {
  // Generated handlers
  registerCommandHandler<CreateUserCommand, void>(
    CreateUserCommandHandler(userRepository),
  );

  // Manual handler
  registerCommandHandler<ComplexOperationCommand, Result>(
    ComplexOperationHandler(
      repository: repository,
      validator: validator,
      logger: logger,
    ),
  );
}
```

## Method Signature Rules

For generation to work correctly, repository methods must follow these conventions:

**Annotations:**
- `@generateQueryHandler` on read/watch methods → generates a `ReadQuery<T>` or `WatchQuery<T>` with its handler
- `@generateCommandHandler` on mutation methods → generates a `Command<T>` with its handler

**Return Types:**
- `Future<T>` + `@generateQueryHandler` → generates `ReadQuery<T>`
- `Stream<T>` + `@generateQueryHandler` → generates `WatchQuery<T>`
- `Future<T>` or `Future<void>` + `@generateCommandHandler` → generates `Command<T>`

**Naming Conventions (recommended, not enforced):**
The generator derives class names from the method name (e.g., `getUser` → `GetUserQuery`, `createUser` → `CreateUserCommand`). For readability, prefer descriptive prefixes:
- Read queries: `getX`, `fetchX`, `loadX`, `findX`
- Watch queries: `watchX`, `observeX`, `streamX`
- Commands: `createX`, `updateX`, `deleteX`, `removeX`, `saveX`

**Parameter Types:**
- Dart primitives and custom classes are supported
- Named and optional parameters are fully preserved in the generated DTOs
- Required parameters become `required` in the generated constructor, optional ones remain optional with their default values

## Troubleshooting

**Issue: Generated files not updating**

Solution:

```bash
dart run build_runner build --delete-conflicting-outputs
```

**Issue: Handler not registered in Mediator**

Solution: Ensure the handler has the `@chassisHandler` annotation and is in a file matching the `generate_for` pattern in `build.yaml`.

**Issue: Type mismatch errors**

Solution: Verify that handler generic types match the Query/Command types exactly.

## Next Steps

* **[Quick Start](../documentation/00_quick_start.md)** - See code generation in action
* **[Code Generation](../documentation/03_code_generation.md)** - Comprehensive guide to annotations
* **[Business Logic Layer](../documentation/02_business_logic.md)** - Learn when to generate vs write manually
* **[chassis](../chassis/README.md)** - Core package documentation

## License

MIT License - See [LICENSE](../LICENSE) for details.
