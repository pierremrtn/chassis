# Chassis

An opinionated architectural framework for Flutter that enforces Clean Architecture, CQRS, and the Mediator pattern. Chassis provides structural guardrails that promote testability, maintainability, and discoverability in Flutter applications.

## Overview

Chassis organizes applications into three distinct layers—UI, Logic, and Data—with strict unidirectional dependency flow. The framework implements Command-Query Separation to make data flow explicit and uses the Mediator pattern to decouple presentation logic from business rules. Code generation automates handler registration and reduces boilerplate for standard CRUD operations.

## Quick Links

📖 **[Documentation](documentation/00_quick_start.md)** - Get started in 5 minutes
📦 **[Pub.dev - chassis](https://pub.dev/packages/chassis)** - Core architectural primitives
📦 **[Pub.dev - chassis_flutter](https://pub.dev/packages/chassis_flutter)** - Flutter UI integration
📦 **[Pub.dev - chassis_builder](https://pub.dev/packages/chassis_builder)** - Code generation tools
🔗 **[API Reference](https://pub.dev/documentation/chassis/latest/)** - Complete API documentation

## Package Ecosystem

Chassis consists of three packages that work together:

| Package | Purpose | Dependencies |
|---------|---------|--------------|
| **[chassis](chassis/)** | Core architectural primitives (Command, Query, Mediator, Async<T>) | Pure Dart |
| **[chassis_builder](chassis_builder/)** | Code generation for handlers and mediator wiring | Dev dependency |
| **[chassis_flutter](chassis_flutter/)** | Flutter UI components (ViewModel, AsyncBuilder) | Flutter + chassis |

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

**Code Generation**
Standard CRUD operations generate Handlers automatically from repository method annotations. The 90/10 principle applies: 90% of operations are generated, 10% are handwritten for complex logic.

## Key Features

### Testability
ViewModels depend on the Mediator interface, enabling tests with mocked Mediators instead of full dependency trees. Handlers are pure Dart classes testable without the Flutter framework.

### Discoverability
Command and Query classes serve as a catalog of application capabilities. Searching for all `Command` classes reveals every write operation the application supports.

### Enforced Architecture
The framework prevents logic from leaking into widgets. ViewModels cannot directly access Repositories—the only path to data flows through the Mediator.

### Standardization
Every Chassis application follows identical structure. Developers navigate any Chassis codebase by locating Command, Query, and Handler classes.

## When to Use Chassis

Chassis is designed for scenarios where architectural consistency is a primary requirement:

* Large teams requiring structural standardization
* Complex applications with strict layer separation
* Projects where testability is critical
* Codebases that prioritize maintainability over initial development speed

**Trade-off**: Chassis introduces more upfront structure than unopinionated state management solutions. This structure pays dividends in long-term maintainability but requires adherence to the framework's patterns.

## Quick Example

**1. Define repository with annotations:**

```dart
class UserRepository {
  @generateQueryHandler
  Future<User> getUser(String id) async {
    return await database.findById(id);
  }

  @generateCommandHandler
  Future<void> createUser(String name, String email) async {
    await database.insert(User(name: name, email: email));
  }
}
```

**2. Generate handlers:**

```bash
dart run build_runner build
```

**3. Create ViewModel:**

```dart
class UserViewModel extends ViewModel<UserState, UserEvent> {
  void loadUser(String id) {
    read(GetUserQuery(id: id), (asyncUser) {
      setState(state.copyWith(user: asyncUser));
    });
  }

  void createUser(String name, String email) {
    run(CreateUserCommand(name: name, email: email), (result) {
      if (result case AsyncData()) {
        sendEvent(UserCreatedEvent());
      }
    });
  }
}
```

**4. Render UI:**

```dart
AsyncBuilder<User>(
  state: viewModel.state.user,
  builder: (context, user) => Text(user.name),
  loadingBuilder: (context) => CircularProgressIndicator(),
  errorBuilder: (context, error) => Text('Error: $error'),
)
```

## Documentation Structure

The documentation is organized progressively:

1. **[Quick Start](documentation/00_quick_start.md)** - Build a Counter app in 5 minutes
2. **[Core Architecture](documentation/01_core_architecture.md)** - Understand Layered Architecture, CQRS, and Mediator patterns
3. **[Business Logic Layer](documentation/02_business_logic.md)** - Implement Commands, Queries, and Handlers
4. **[Code Generation](documentation/03_code_generation.md)** - Automate handler creation with annotations
5. **[UI Integration](documentation/04_ui_integration.md)** - Build reactive UIs with ViewModel and AsyncBuilder

Each section follows the principle-first approach: explain the software engineering concept, show how Chassis implements it, demonstrate usage, and conclude with benefits.

## Package Documentation

Detailed package-specific documentation:

* **[chassis](chassis/README.md)** - Core primitives (Command, Query, Handler, Mediator, Async<T>)
* **[chassis_builder](chassis_builder/README.md)** - Code generation configuration and usage
* **[chassis_flutter](chassis_flutter/README.md)** - ViewModel, AsyncBuilder, and presentation layer components

## Installation

Add dependencies to `pubspec.yaml`:

```yaml
dependencies:
  chassis: ^0.0.1
  chassis_flutter: ^0.0.1

dev_dependencies:
  build_runner: ^2.4.0
  chassis_builder: ^0.0.1
```

Create `build.yaml`:

```yaml
targets:
  $default:
    builders:
      chassis_builder|repository_builder:
        enabled: true
      chassis_builder|chassis_builder:
        enabled: true
        options:
          mediator_name: AppMediator
```

Run code generation:

```bash
dart run build_runner build
```

## Community & Support

* **Issues**: [GitHub Issues](https://github.com/affordant-consulting/chassis/issues)
* **Discussions**: [GitHub Discussions](https://github.com/affordant-consulting/chassis/discussions)

## License

Chassis is released under the MIT License. See [LICENSE](LICENSE) for details.
