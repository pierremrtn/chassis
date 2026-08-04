# chassis

Core architectural primitives for building structured Flutter applications. This pure Dart package provides the foundation for the Chassis framework, enabling testable business logic independent of the Flutter UI layer.

## Overview

The `chassis` package implements three foundational patterns:

* **Command-Query Separation (CQS)** - Separates write operations (Commands) from read operations (Queries)
* **Mediator Pattern** - Decouples message senders from handlers
* **Async State Modeling** - Represents asynchronous operation lifecycle as a sealed union

| Export | Purpose |
|--------|---------|
| `Command<R>`, `ReadQuery<T>`, `WatchQuery<T>` | Messages describing operations |
| `CommandHandler`, `ReadHandler`, `WatchHandler` | Business logic that executes messages |
| `Mediator` | Routes messages to handlers, applies middlewares |
| `MediatorMiddleware`, `LoggingMiddleware`, `ChassisLogSink` | Cross-cutting interception and tracing |
| `Async<T>` (`AsyncData`, `AsyncLoading`, `AsyncError`) | Async operation state as a sealed union |
| `ChassisException` (`DuplicateHandlerException`, `HandlerNotRegisteredException`) | Wiring-mistake exceptions |
| `@chassisHandler`, `@chassisModule`, `@ChassisApp` | Code generation annotations |

## Core Exports

### Messages

**Command** - Represents an intent to modify state:

```dart
final class CreateUserCommand extends Command<User> {
  CreateUserCommand({
    required this.name,
    required this.email,
  });

  final String name;
  final String email;
}
```

**ReadQuery** - One-time data fetch:

```dart
final class GetUserQuery extends ReadQuery<User> {
  GetUserQuery({required this.userId});

  final String userId;
}
```

**WatchQuery** - Continuous stream of updates:

```dart
final class WatchUserQuery extends WatchQuery<User> {
  WatchUserQuery({required this.userId});

  final String userId;
}
```

### Handlers

**CommandHandler** - Executes business logic for Commands:

```dart
class CreateUserHandler implements CommandHandler<CreateUserCommand, User> {
  CreateUserHandler(this._repository);

  final UserRepository _repository;

  @override
  Future<User> run(CreateUserCommand command) async {
    // Validation and business logic
    if (command.email.isEmpty) {
      throw ValidationException('Email is required');
    }

    return await _repository.create(command.name, command.email);
  }
}
```

**ReadHandler** - Executes one-time queries:

```dart
class GetUserHandler implements ReadHandler<GetUserQuery, User> {
  GetUserHandler(this._repository);
  final UserRepository _repository;

  @override
  Future<User> read(GetUserQuery query) async {
    return await _repository.findById(query.userId);
  }
}
```

**WatchHandler** - Executes streaming queries:

```dart
class WatchUserHandler implements WatchHandler<WatchUserQuery, User> {
  WatchUserHandler(this._repository);
  final UserRepository _repository;

  @override
  Stream<User> watch(WatchUserQuery query) {
    return _repository.watchById(query.userId);
  }
}
```

### Mediator

The central router that dispatches messages to handlers:

```dart
final mediator = Mediator();

// Register handlers
mediator.registerCommandHandler(CreateUserHandler(userRepository));
mediator.registerQueryHandler(GetUserHandler(userRepository));
mediator.registerQueryHandler(WatchUserHandler(userRepository));

// Dispatch operations
final user = await mediator.run(CreateUserCommand(
  name: 'John Doe',
  email: 'john@example.com',
));

final fetchedUser = await mediator.read(GetUserQuery(userId: user.id));

final userUpdates = mediator.watch(WatchUserQuery(userId: user.id));
```

In practice you rarely write registrations by hand: [chassis_builder](https://pub.dev/packages/chassis_builder) generates a mediator class that registers every `@chassisHandler` and exposes one typed method per handler.

For conditional logic or debugging, `mediator.hasHandlerAvailableFor<T>()` reports whether any handler (command, read, or watch) is registered for the message type `T`.

### Exceptions

Registration and dispatch throw `ChassisException` subtypes on wiring mistakes — identically in debug and release builds. These are programming errors, never runtime conditions to recover from: fix the registration, don't catch.

| Exception | Thrown by | When |
|-----------|-----------|------|
| `DuplicateHandlerException` | `registerCommandHandler`, `registerQueryHandler` | A handler is already registered for the same message type. Always thrown — a duplicate registration silently replacing a handler is never intended. |
| `HandlerNotRegisteredException` | `run`, `read`, `watch` | No handler is registered for the dispatched message type. The message names the missing handler interface and the registration call that fixes it. |

Both extend `sealed class ChassisException`.

### Async&lt;T&gt; Sealed Union

Models the complete lifecycle of asynchronous operations. An `Async<T>` is always one of three states:

```dart
sealed class Async<T> {
  const factory Async.data(T value) = AsyncData<T>;
  const factory Async.loading({AsyncData<T>? previous}) = AsyncLoading<T>;
  const factory Async.error(Object error,
      {StackTrace? stackTrace, AsyncData<T>? previous}) = AsyncError<T>;
}
```

`AsyncLoading` and `AsyncError` can carry the last known `AsyncData<T>` in `previous`. Carrying the whole `AsyncData` (rather than a bare `T?`) makes "a value existed" provable by the type system, even when `T` is nullable and the value itself is `null`:

```dart
const state = Async<int?>.data(null);
state.hasValue; // true — data was produced, its value happens to be null.
```

**Members:**

| Member | Description |
|--------|-------------|
| `hasValue` | Whether a value is available: fresh (`AsyncData`) or carried in `previous` while loading / in error. Correct for nullable `T`, unlike a null-check on `valueOrNull`. |
| `valueOrNull` | The current data, fresh or carried over. `null` is ambiguous for nullable `T` — prefer `hasValue` or pattern matching. |
| `requireValue` | The available value, or throws a `StateError` if there is none. |
| `isLoading`, `hasError`, `errorOrNull` | State checks; `errorOrNull` is the error if the last operation failed. |
| `toLoading()`, `toData(value)`, `toError(error, stack)` | Transitions that carry the current data forward (refetching, soft errors). |
| `==` / `hashCode` | Value equality is implemented for all three states — states compare naturally in tests. |

**Prefer exhaustive pattern matching** over flag checks:

```dart
void handleUser(Async<User> asyncUser) {
  switch (asyncUser) {
    case AsyncData(:final value):
      print('User: ${value.name}');
    case AsyncLoading():
      print('Loading...');
    case AsyncError(:final error):
      print('Error: $error');
  }
}
```

## Middleware

Every operation flows through the mediator, giving one interception point for the whole app. Middlewares are executed in the order they are added.

### LoggingMiddleware

The built-in `LoggingMiddleware` traces every operation — dispatch, outcome, duration, and errors with stack traces. Errors are always rethrown; logging never swallows failures.

```dart
final mediator = Mediator()..addMiddleware(LoggingMiddleware());
// [chassis] run CreateUserCommand{name: John} succeeded after 34ms
```

By default a trace shows only the message's type name. Override `params` (empty by default) on a command or query to include its fields in `toString()` and trace output, as in `CreateUserCommand{name: John}` above. Never include secrets (passwords, tokens) in `params`.

```dart
final class CreateUserCommand extends Command<User> {
  // ...

  @override
  Map<String, Object?> get params => {'name': name, 'email': email};
}
```

Options:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `sink` | `ChassisLogSink` destination for records | `PrintLogSink()` |
| `logStart` | Also emit a record when an operation is dispatched | `false` |
| `logStreamEvents` | Emit a record for every stream emission of a watch query | `false` |

Implement `ChassisLogSink` to route `ChassisLogRecord`s (event, kind, request, params, elapsed, error, stackTrace) to your own logger — `dart:developer`, `package:logging`, Sentry breadcrumbs, etc.:

```dart
class CrashReportingSink implements ChassisLogSink {
  @override
  void write(ChassisLogRecord record) {
    if (record.event == ChassisLogEvent.error) {
      // Sentry.captureException(record.error, stackTrace: record.stackTrace);
    }
  }
}

mediator.addMiddleware(LoggingMiddleware(sink: CrashReportingSink()));
```

### Custom Middleware

Extend `MediatorMiddleware` and override any of `onRun`, `onRead`, `onWatch`:

```dart
class TimingMiddleware extends MediatorMiddleware {
  @override
  Future<R> onRun<C extends Command<R>, R>(C command, NextRun<C, R> next) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await next(command);
    } finally {
      print('${command.runtimeType} took ${stopwatch.elapsedMilliseconds}ms');
    }
  }
}

mediator.addMiddleware(TimingMiddleware());
```

## Annotations

Mark classes for code generation with [chassis_builder](https://pub.dev/packages/chassis_builder):

```dart
// Handler picked up by generation and wired into the generated mediator
@chassisHandler
class CreateUserHandler implements CommandHandler<CreateUserCommand, User> {
  // Implementation
}

// Module declaration in a shared package — generates the AuthMediator interface
@chassisModule
final class AuthModule {}

// App composition root — annotates the library directive and generates
// the concrete AppMediator
@ChassisApp(modules: [AuthModule], mediatorName: 'AppMediator')
library;
```

`@ChassisApp` accepts `modules:` (module declaration classes to compose, default `[]`) and `mediatorName:` (name of the generated mediator class, default `'AppMediator'`).

## Testing

Handlers are pure Dart classes testable without Flutter:

```dart
test('CreateUserHandler validates email', () async {
  final mockRepository = MockUserRepository();
  final handler = CreateUserHandler(mockRepository);

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
  chassis: ^1.0.0
```

For Flutter UI integration, also add:

```yaml
dependencies:
  chassis_flutter: ^1.0.0
```

For code generation:

```yaml
dev_dependencies:
  chassis_builder: ^1.0.0
  build_runner: ^2.15.0
```

## LLM Skills

The package bundles [LLM skills](https://github.com/pierremrtn/chassis/tree/main/chassis/skills) — DO/DON'T rules, workflow checklists, and runnable examples that keep an AI coding assistant on the framework's rails (an agent that forgets a handler gets a build error, and these skills teach it the conventions the build can't check). Install them into a project with:

```bash
dart run chassis:install_skills
```

Each skill is symlinked from the resolved chassis package into `.claude/skills/` (Claude Code's project-scoped location), so the skills always track the pinned chassis version — re-run after upgrading. Pass a target directory for other agents (Cursor, etc.), or `--copy` to copy instead of symlinking.

## Next Steps

* **[Quick Start](https://github.com/pierremrtn/chassis/blob/main/docs/00_quick_start.md)** - Build a complete application
* **[Core Architecture](https://github.com/pierremrtn/chassis/blob/main/docs/01_core_architecture.md)** - Understand the architectural principles
* **[Business Logic Layer](https://github.com/pierremrtn/chassis/blob/main/docs/02_business_logic.md)** - Learn when to use each component
* **[Code Generation](https://github.com/pierremrtn/chassis/blob/main/docs/03_code_generation.md)** - Compose handlers, modules, and apps
* **[chassis_flutter](https://pub.dev/packages/chassis_flutter)** - Integrate with Flutter UI

## License

MIT License - See [LICENSE](https://github.com/pierremrtn/chassis/blob/main/LICENSE) for details.
