# Chassis

An opinionated architectural framework for Flutter that enforces Clean Architecture, CQRS, and the Mediator pattern. Chassis provides structural guardrails that promote testability, maintainability, and discoverability in Flutter applications.

## Overview

Chassis organizes applications into three distinct layers—UI, Logic, and Data—with strict unidirectional dependency flow. Operations are explicit Commands and Queries, and code generation composes their handlers into a fully typed mediator: a missing handler is a compile error. On the UI side, `run` and `watch` report each ViewModel operation as `Async<T>` states (loading, data, error), and `AsyncBuilder` renders those states in widgets.

## Quick Links

- 📖 **[Documentation](docs/00_quick_start.md)** - Get started in 15 minutes
- 📦 **[Pub.dev - chassis](https://pub.dev/packages/chassis)** - Core architectural primitives
- 📦 **[Pub.dev - chassis_flutter](https://pub.dev/packages/chassis_flutter)** - Flutter UI integration
- 📦 **[Pub.dev - chassis_builder](https://pub.dev/packages/chassis_builder)** - Code generation tools
- 🔗 **[API Reference](https://pub.dev/documentation/chassis/latest/)** - Complete API documentation

## Package Ecosystem

Chassis consists of three packages that work together:

| Package | Purpose | Dependencies |
|---------|---------|--------------|
| **[chassis](chassis/)** | Core architectural primitives (Command, Query, Mediator, Middleware, Async&lt;T&gt;) | Pure Dart |
| **[chassis_builder](chassis_builder/)** | Code generation: module interfaces and the app mediator | Dev dependency |
| **[chassis_flutter](chassis_flutter/)** | Flutter UI components (ViewModel, ViewModelProvider, AsyncBuilder) | Flutter + chassis |

## Architecture

Chassis enforces a layered architecture with strict separation of concerns:

```
┌─────────────────────────────────────────────────┐
│  UI Layer (Presentation)                        │
│  • Widgets                                      │
│  • ViewModels                                   │
└──────────────────┬──────────────────────────────┘
                   │ Depends on
                   ▼
┌─────────────────────────────────────────────────┐
│  Logic Layer (Application)                      │
│  • Commands / Queries (use cases)               │
│  • Handlers (business logic)                    │
│  • Mediator (orchestration)                     │
└──────────────────┬──────────────────────────────┘
                   │ Depends on
                   ▼
┌─────────────────────────────────────────────────┐
│  Data Layer (Infrastructure)                    │
│  • Repository interfaces                        │
│  • Repository implementations                   │
│  • Data sources (API, Database)                 │
└─────────────────────────────────────────────────┘
```

### Core Principles

**Command-Query Separation (CQS)**
Operations are separated into Commands (writes that modify state) and Queries (reads that retrieve data). This distinction makes data flow explicit and side effects predictable.

**Mediator Pattern**
ViewModels dispatch Commands and Queries through the Mediator, which routes them to appropriate Handlers. This decoupling enables testing ViewModels without implementing Repositories.

**Compile-Time Composition**
Handlers are marked with `@chassisHandler` and composed by code generation. A module package generates a typed mediator interface; the app generates a concrete mediator that implements every module interface. If a handler is missing, the app does not compile — completeness is guaranteed by the type system, not by runtime checks.

## Key Features

### Testability
ViewModels depend on the Mediator (or on a module's generated interface), enabling tests with a single mock instead of full dependency trees. Handlers are pure Dart classes testable without the Flutter framework.

### Async State Management
`run` executes an operation and `watch` subscribes to a stream; both report the full lifecycle as `Async<T>` states (loading, data, error), so ViewModels contain no hand-written `isLoading` flags or try/catch blocks. When concurrent calls can collide, `RunPolicy` decides which one wins: drop the new call, restart the in-flight one, or queue them, with optional debouncing. On the UI side, `AsyncBuilder` maps each state to a widget, keeping previous data visible while a refresh is in flight, and its event-side counterpart `EventListener` turns one-shot events such as snackbars and navigation into side effects — `ViewModelProvider.withEventListener` fuses provider and listener for the common case where both live at the same place.

### Discoverability
Command and Query classes serve as a catalog of application capabilities. Searching for all `Command` classes reveals every write operation the application supports. The generated mediator turns that catalog into an IDE-autocompletable API: `mediator.login(...)` instead of string-and-type plumbing.

### Observability
Every operation flows through the mediator, giving one interception point for the whole app. The built-in `LoggingMiddleware` traces each command and query with its parameters, duration, and errors: `[chassis] run CreateUserCommand{name: John} failed after 34ms: ...`.

### Modularity
Feature packages export handlers and ViewModels against their own generated interface (`AuthMediator`), without knowing anything about the app that composes them. The app declares `@ChassisApp(modules: [AuthModule, PaymentModule])` and the generator wires everything, rejecting conflicts at build time.

### Standardization
Every Chassis application follows identical structure. Developers — and AI coding agents — navigate any Chassis codebase by locating Command, Query, and Handler classes. There is exactly one correct way to add a feature, which makes generated diffs predictable and reviewable.

## When to Use Chassis

Chassis is designed for scenarios where architectural consistency is a primary requirement:

* Large teams requiring structural standardization
* Complex applications with strict layer separation
* Projects where testability is critical
* Codebases that prioritize maintainability over initial development speed
* Teams relying on AI agents, which benefit from a rigid, verifiable structure

**Trade-off**: Chassis introduces more upfront structure than unopinionated state management solutions. This structure pays dividends in long-term maintainability but requires adherence to the framework's patterns.

## Quick Example

**1. Write a Command and its Handler:**

```dart
final class CreateUserCommand extends Command<User> {
  CreateUserCommand({required this.name, required this.email});

  final String name;
  final String email;
}

@chassisHandler
class CreateUserHandler implements CommandHandler<CreateUserCommand, User> {
  CreateUserHandler(this._repository);

  final UserRepository _repository;

  @override
  Future<User> run(CreateUserCommand command) =>
      _repository.create(command.name, command.email);
}
```

**2. Declare the composition root and generate:**

```dart
@ChassisApp(mediatorName: 'AppMediator')
library;
```

```bash
dart run build_runner build
```

The generator emits `AppMediator` with a typed method per handler, and asks for each handler's dependencies in its constructor:

```dart
final mediator = AppMediator(userRepository: UserRepository())
  ..addMiddleware(LoggingMiddleware());
```

**3. Define the state and events, then create a ViewModel:**

```dart
class UserState {
  const UserState({required this.user});

  // Async<User?> lets the UI render the whole createUser lifecycle
  // (loading / data / error). The inner User? is nullable because no user
  // exists before the first call: the initial state is AsyncData(null) —
  // "no user yet" is data, not loading.
  final Async<User?> user;

  static UserState initial() => const UserState(user: AsyncData(null));

  UserState copyWith({Async<User?>? user}) => UserState(user: user ?? this.user);
}

sealed class UserEvent {}

class UserCreatedEvent implements UserEvent {}
```

```dart
class UserViewModel extends ViewModel<UserState, UserEvent> {
  UserViewModel(this._mediator) : super(UserState.initial());

  final AppMediator _mediator;

  void createUser(String name, String email) {
    run(
      () => _mediator.createUser(name: name, email: email),
      onState: (user) => setState(state.copyWith(user: user)),
      onSuccess: (_) => sendEvent(UserCreatedEvent()),
    );
  }
}
```

`run` reports the whole lifecycle as `Async<T>` states — loading, data, error — so there are no hand-written `isLoading` flags or try/catch blocks. When concurrent calls can collide, an optional `key` and `RunPolicy` decide who wins (`RunPolicy.restartable(debounce: ...)` fits search-as-you-type). `watch` offers the same contract for streams.

**4. Provide the ViewModel and render the state:**

```dart
ViewModelProvider.withEventListener<UserViewModel, UserEvent>(
  create: (context) => UserViewModel(mediator),
  onEvent: (context, viewModel, event) {
    switch (event) {
      case UserCreatedEvent():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User created')),
        );
    }
  },
  child: const UserScreen(),
)
```

```dart
AsyncBuilder<User?>(
  state: context.select((UserViewModel vm) => vm.state.user),
  builder: (context, user) =>
      user == null ? const Text('No user yet') : Text('Created ${user.name}'),
  loadingBuilder: (context) => const CircularProgressIndicator(),
  errorBuilder: (context, error) => Text('Error: $error'),
)
```

State drives the widgets through `AsyncBuilder`; `context.select` subscribes the widget to exactly the field it renders, so unrelated state changes don't rebuild it. One-shot side effects (snackbars, navigation) are handled as events at the provider level.

## Modules

Shared feature packages declare a module; apps compose them:

```dart
// package auth — generates AuthMediator (auth.chassis.dart)
@chassisModule
final class AuthModule {}

// app — generates AppMediator implements AuthMediator
@ChassisApp(modules: [AuthModule], mediatorName: 'AppMediator')
library;
```

Shared ViewModels depend on `AuthMediator` only, so they can be reused by any app that composes `AuthModule`. See [Code Generation](docs/03_code_generation.md).

## Documentation Structure

The documentation is organized progressively:

1. **[Quick Start](docs/00_quick_start.md)** - Build a Todo app
2. **[Core Architecture](docs/01_core_architecture.md)** - Understand Layered Architecture, CQRS, and Mediator patterns
3. **[Business Logic Layer](docs/02_business_logic.md)** - Implement Commands, Queries, and Handlers
4. **[Code Generation](docs/03_code_generation.md)** - Compose handlers, modules, and apps with the generator
5. **[UI Integration](docs/04_ui_integration.md)** - Build reactive UIs with ViewModel and AsyncBuilder

## Package Documentation

Detailed package-specific documentation:

* **[chassis](chassis/README.md)** - Core primitives (Command, Query, Handler, Mediator, Middleware, Async&lt;T&gt;)
* **[chassis_builder](chassis_builder/README.md)** - Code generation usage and error reference
* **[chassis_flutter](chassis_flutter/README.md)** - ViewModel, AsyncBuilder, and presentation layer components

## Installation

Add dependencies to `pubspec.yaml`:

```yaml
dependencies:
  chassis: ^1.0.0
  chassis_flutter: ^1.0.0

dev_dependencies:
  build_runner: ^2.15.0
  chassis_builder: ^1.0.0
```

Run code generation:

```bash
dart run build_runner build
```

## Community & Support

* **Issues**: [GitHub Issues](https://github.com/pierremrtn/chassis/issues)
* **Discussions**: [GitHub Discussions](https://github.com/pierremrtn/chassis/discussions)

## License

Chassis is released under the MIT License. See [LICENSE](LICENSE) for details.
