# chassis

**Rigid in the structure, Flexible in the implementation.**

An opinionated architectural framework for Flutter that provides a solid foundation for professional, scalable, and maintainable applications. It guides your project's structure by combining the clarity of MVVM with a pragmatic, front-end friendly implementation of CQRS principles.

Learn more from the full **[documentation](https://affordant.gitbook.io/chassis/)**.

This package is built to work with:

  * [`chassis_flutter`](https://pub.dev/packages/chassis_flutter)
  * [`provider`](https://pub.dev/packages/provider)

## Overview

Chassis is designed to make best practices the easiest path forward. It enforces a clear separation of concerns, ensuring your business logic is explicit, discoverable, and highly testable.

  * **Structure by Design:** Do not rely on developer discipline to maintain a clean codebase. Chassis enforces a clean data flow, making the code intuitive and organized by default.
  * **Rigid Structure, Flexible Logic:** The overall architecture is predictable, but unopinionated about your business logic.
  * **Testability First:** Every layer is decoupled and designed to be easily testable in isolation.
  * **Observable:** You can easily plug-in middleware to observe changes in your application.

Chassis is built around two fundamental concepts: **Commands** for changing state and **Queries** for reading data. These messages are dispatched through a central `Mediator`, which decouples the sender from the handler.

#### 1\. The Flow of Action (Commands) 🎬

When you need to change the application's state, you send a **Command**.

**Flow:** `ViewModel` ➡️ `Command` ➡️ `Mediator` ➡️ `Handler` ➡️ `Data Layer`

#### 2\. The Flow of Data (Queries) 📊

When you need to display data, you send a **Query**.

**Request Flow:** `ViewModel` ➡️ `Query` ➡️ `Mediator` ➡️ `Handler` ➡️ `Data Layer`
**Data Return Flow:** `ViewModel` ⬅️ `Data` ⬅️ `Handler` ⬅️ `Data Layer`

### Core Building Blocks

`chassis` is a pure Dart package that provides the foundational pieces for your application's business logic.

  * **`Command`, `ReadQuery`, `WatchQuery`**: Simple, immutable classes that represent your use cases. A `Command` is an intent to change state, a `ReadQuery` is for a one-time data fetch, and a `WatchQuery` is for subscribing to a data stream.
  * **`Handlers`**: The classes where your actual business logic lives, processing a single Command or Query.
  * **`Mediator`**: The central dispatcher that decouples your presentation layer from your business logic handlers.

## Usage

#### 1\. Define a Query

A `Query` is a structured message describing the data you want.

```dart
// domain/use_cases/get_greeting_query.dart
import 'package:chassis/chassis.dart';

class GetGreetingQuery implements ReadQuery<String> {
  const GetGreetingQuery();
}
```

#### 2\. Write the Handler

A `Handler` contains the business logic to process the `Query`. It receives the message from the `Mediator` and performs the work.

```dart
// app/use_cases/get_greeting_query_handler.dart
import 'package:chassis/chassis.dart';

class GetGreetingQueryHandler implements ReadHandler<GetGreetingQuery, String> {
  final IGreetingRepository _repository;
  GetGreetingQueryHandler(this._repository);

  @override
  Future<String> read(GetGreetingQuery query) {
    // Business logic lives here
    return _repository.getGreeting();
  }
}
```

#### 3\. Wire It Up with the Mediator

At your application's startup, register all your handlers with the `Mediator`.

```dart
// app/main.dart
final mediator = Mediator();

void main() {
  // Instantiate dependencies
  final greetingRepository = GreetingRepository();
  
  // Register handlers
  mediator.registerQueryHandler(GetGreetingQueryHandler(greetingRepository));
  
  runApp(const MyApp());
}
```

Now, from your `ViewModel` (or anywhere else), you can send the request:

```dart
final String greeting = await mediator.read(const GetGreetingQuery());
```

For more information about how to chassis integrates with flutter, see chassis_flutter or the full documentation