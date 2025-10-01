# Chassis 🏎️

An opinionated architectural framework for Flutter that provides a solid foundation for professional, scalable, and maintainable applications.

**Rigid in Structure, Flexible in Implementation.**

Chassis guides your project's structure by combining the clarity of MVVM with a pragmatic, front-end friendly implementation of CQRS principles. It's designed to make best practices the easiest path forward.

Learn more from the full [documentation](https://affordant.gitbook.io/chassis/).

-----

## Why Use Chassis?

  * 🏛️ **Structure by Design**: Don't rely on developer discipline to maintain a clean codebase. Chassis enforces a clean data flow, making the code intuitive and organized by default.
  * 🧠 **Explicit Logic**: By separating Commands and Queries, your business logic becomes explicit, discoverable, and easier to reason about.
  * ✅ **Testability First**: Every layer is decoupled and designed to be easily testable in isolation, from business logic handlers to your data layer.
  * 🔌 **Observable & Pluggable**: Easily plug-in middleware to observe every Command and Query in your application for logging, analytics, or debugging.

-----

## The Chassis Ecosystem

Chassis is designed as a modular set of packages to enforce a strong separation between business logic and UI.

  * **`chassis` (this package)**: The core, pure Dart library. It contains the foundational building blocks (`Mediator`, `Command`, `Query`, etc.) and has no dependency on Flutter. This is where all your application's business logic lives.
  * [**`chassis_flutter`**](https://pub.dev/packages/chassis_flutter): Provides Flutter-specific widgets and helpers to integrate the core `chassis` logic by following the `MVVM` pattern.

-----

## Core Concepts

Chassis is built around the Command Query Responsibility Segregation (CQRS) pattern, adjusted for front-end development needs. Fundamentally, this means separating the act of writing data from reading data.

* Writes (Commands): Any operation that mutates domain state (as opposite to view state) is a Command. Commands are objects representing an intent to change something (e.g., CreateUserCommand). They are processed by a single handler containing all the necessary business logic and validation, which ensures data consistency and integrity.

* Reads (Queries): All data retrieval is done through Queries. A query asks for information and returns a domain object but is strictly forbidden from changing state.

These messages are routed through a central Mediator, which decouples the sender from the handler. This design provides a clear separation of concerns, enhances scalability, and simplifies complex business domains.

**The Flow of Action (Commands) 🎬**

When you need to change the application's state, you send a `Command`.

```
ViewModel ➡️ Command ➡️ Mediator ➡️ Handler ➡️ Data Layer
```

**The Flow of Data (Queries) 📊**

When you need to read or subscribe to data, you send a `Query`.

```
ViewModel ➡️ Query ➡️ Mediator ➡️ Handler ➡️ Data Layer ➡️ Returns Data
```

-----

## Core API in Action

This example demonstrates the fundamental pattern of defining and handling a message. Note that this code is pure Dart and lives in your core logic, completely independent of Flutter.

#### 1\. Define a Query

A Query is an immutable message describing the data you want.

```dart
// domain/use_cases/get_greeting_query.dart
import 'package:chassis/chassis.dart';

// Implement WatchQuery for reactive data streams that update over time.
class WatchGreetingsQuery implements WatchQuery<String> {
  const WatchGreetingsQuery();
}
```

#### 2\. Create the Handler

A Handler contains the business logic to process the Query.

```dart
// app/use_cases/get_greeting_query_handler.dart
import 'package:chassis/chassis.dart';

// Each message type has a corresponding handler:
// ReadQuery -> ReadHandler
// WatchQuery -> WatchHandler
// Command -> CommandHandler
class WatchGreetingsQueryHandler implements WatchHandler<WatchGreetingsQuery, String> {
  final IGreetingRepository greetingRepository;
  
  WatchGreetingsQueryHandler({
    required this.greetingRepository,
  });

  @override
  Stream<String> watch(WatchGreetingsQuery query) {
    // Your business logic lives here
    return greetingRepository.getGreetingStream();
  }
}
```

#### 3\. Register and Dispatch with the Mediator

At your application's startup, register your handler. Then, from your application logic, dispatch the query to get data.

```dart
// At application startup
final mediator = Mediator();
final greetingRepository = GreetingRepository();

mediator.registerQueryHandler(
  WatchGreetingsQueryHandler(greetingRepository: greetingRepository),
);

// From your application layer
final subscription = mediator.watch(const WatchGreetingsQuery()).listen((greeting) {
  print(greeting); // Outputs each greeting from your repository stream
});
```

-----

## Next Steps

You've now seen the core pattern of the `chassis` library. To see how to integrate this logic with your Flutter UI, please check out:
* **The full [documentation](https://affordant.gitbook.io/chassis/)** for advanced concepts, tutorials, and best practices.
* The **[`chassis_flutter`](https://pub.dev/packages/chassis_flutter)** package to connect your logic to widgets.