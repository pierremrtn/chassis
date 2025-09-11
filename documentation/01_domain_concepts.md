## Core Principles: Building Your Domain Layer

At the heart of Chassis lies a clean, decoupled **domain layer**. This layer contains your core business logic and is completely independent of the UI (the **view layer**) or data sources (the **data layer**). It's built around a simple but powerful pattern: modeling every application feature as an explicit message that flows through a predictable, unidirectional path.

### The Two Fundamental Data Flows

Before diving into the code, it's crucial to understand how data moves through the architecture. Every interaction in your app will follow one of two patterns.

#### 1\. The Flow of Action (Commands) 🎬

When you need to change the application's state (e.g., save user data, submit a form), you use a **Command**. This is a one-way flow designed to perform an action.

**Flow:** `ViewModel` ➡️ `Command` ➡️ `Mediator` ➡️ `Handler` ➡️ `Data Layer`

1.  The **ViewModel** (in the UI layer) creates and sends a `Command` message.
2.  The central **`Mediator`** receives the `Command` and routes it to the correct `CommandHandler`.
3.  The **`CommandHandler`** contains the business logic. It executes the request, often by interacting with a repository or an API client in the **Data Layer**.

-----

#### 2\. The Flow of Data (Queries) 📊

When you need to display data in the UI, you use a **Query**. This is a read-only operation. The flow goes down to fetch the data and then comes back up with the result.

**Request Flow:** `ViewModel` ➡️ `Query` ➡️ `Mediator` ➡️ `Handler` ➡️ `Data Layer`
**Data Return Flow:** `ViewModel` ⬅️ `Data` ⬅️ `Handler` ⬅️ `Data Layer`

1.  The **ViewModel** sends a `Query` message describing the data it needs.
2.  The **`Mediator`** routes it to the appropriate `QueryHandler`.
3.  The **`QueryHandler`** fetches the data from the **Data Layer**.
4.  The requested data is returned up the chain to the **ViewModel**, which then prepares it for the UI.

This strict separation of concerns is why Chassis makes your business logic:

  * **Explicit and Discoverable**: To understand what your application does, you don't need to read UI code. You can simply look at the `Query` and `Command` files. They form a complete and clear list of all supported features, acting as self-documenting use cases.
  * **Testable**: A `Handler` is a plain Dart class. It takes a message, performs some logic, and returns a result. You can instantiate it in a unit test, give it a mock data source (like a fake repository), and verify its behavior in complete isolation from Flutter and the UI.
  * **Maintainable**: Because the data flow is always the same, you always know where to look. Need to fix a bug when creating a user? Find the `CreateUserCommandHandler`. Is user data displaying incorrectly? Check the `GetUserQueryHandler`. This predictability dramatically simplifies debugging and adding new features.
  * **Observable**: Since every request must pass through the central `Mediator`, it becomes a natural chokepoint for adding cross-cutting concerns. You can easily insert logging, analytics, performance monitoring, or caching middleware in one place without having to modify dozens of individual handlers.

Now, let's look at the building blocks that make these flows work.

### 1\. Writing Queries and Commands: The "What"

Queries and Commands are the messages that travel from the `ViewModel` to the `Mediator`. They are simple, immutable classes that describe the intent and carry the necessary data.

#### **Queries: Reading Data**

Chassis offers two types of queries:

  * **`ReadQuery<T>`**: For one-time data fetches, returning a `Future<T>`.
  * **`WatchQuery<T>`**: For subscribing to a stream of data, returning a `Stream<T>`.

<!-- end list -->

```dart
// A query to fetch a user's profile once.
// This message travels from the ViewModel to the Mediator.
class GetUserByIdQuery implements ReadQuery<User> {
  const GetUserByIdQuery(this.userId);
  final String userId;
}
```

-----

#### **Commands: Changing State**

A **`Command<T>`** represents an intent to change state and optionally returns a result of type `T`.

```dart
// A command to create a new user.
// This message also travels from the ViewModel to the Mediator.
class CreateUserCommand extends Command<User> {
  const CreateUserCommand({required this.name, required this.email});
  final String name;
  final String email;
}
```

### 2\. Writing Handlers: The "How"

A **`Handler`** is where your business logic lives. It receives a message from the `Mediator` and performs the work.

There are two common ways to define a handler:

#### **Short Syntax (`extends`)**

For simple logic, you can extend the base handler and pass your logic directly to the `super` constructor. This is concise and great for straightforward cases.

```dart
class GetGreetingQueryHandler extends ReadHandler<GetGreetingQuery, String> {
  GetGreetingQueryHandler({required IGreetingRepository repository})
      // The business logic is the callback passed to super()
      : super((query) => repository.getGreeting());
}
```

-----

#### **Long Syntax (`implements`)**

For more complex handlers with multiple dependencies or steps, implementing the handler interface provides a more structured and readable class. **This is the recommended approach for most cases.**

```dart
class GetGreetingQueryHandler implements ReadHandler<GetGreetingQuery, String> {
  final IGreetingRepository repository;

  GetGreetingQueryHandler({required this.repository});

  @override
  Future<String> read(GetGreetingQuery query) {
    // The business logic lives inside the read method.
    return repository.getGreeting();
  }
}
```

### 3\. The `Mediator`: The Central Hub

The `Mediator` connects the "what" (the message) to the "how" (the handler). At your application's startup, you create a `Mediator` instance and register all your handlers with it.

```dart
// In your application's setup/injection file:

// 1. Create the mediator instance.
final mediator = Mediator();

// 2. Register all your handlers.
mediator.registerQueryHandler(GetGreetingQueryHandler(GreetingRepository()));
mediator.registerCommandHandler(CreateUserCommandHandler(UserRepository()));
// ... register all other handlers
```

From this point on, other parts of your application (like `ViewModels`) can simply send a message to the `Mediator` without ever knowing which handler will process it.

Of course. Here is the final part of the "Core Principles" section, which provides a complete, runnable example to demonstrate how all the pieces work together.

-----

### 4\. Putting It All Together: A Pure Dart Example

This example demonstrates the entire flow within a simple command-line application. It shows how the domain layer operates independently of any UI framework, making it portable and easy to test.

```dart
import 'package:chassis/chassis.dart';

// --- 1. Define Models (Plain Dart Objects) ---
// Models are simple data structures with no business logic.
// They are passed between layers.
class User {
  const User({required this.id, required this.name});
  final String id;
  final String name;

  @override
  String toString() => 'User(id: $id, name: $name)';
}


// --- 2. Define Queries & Commands (The Messages) ---
class GetUserByIdQuery implements ReadQuery<User> {
  const GetUserByIdQuery(this.id);
  final String id;
}

class CreateUserCommand extends Command<User> {
  const CreateUserCommand(this.name);
  final String name;
}


// --- 3. Define the Data Layer (How to Access Data) ---
// In a real app, this would be in a separate 'data' or 'infrastructure' layer.
// This interface defines the contract for our user data source.
abstract class IUserRepository {
  Future<User?> findById(String id);
  Future<User> create(String name);
}

// A mock implementation of the repository that uses an in-memory map.
// This simulates a database for our example.
class InMemoryUserRepository implements IUserRepository {
  final Map<String, User> _userDatabase = {};
  int _nextId = 1;

  @override
  Future<User> create(String name) async {
    await Future.delayed(const Duration(milliseconds: 50)); // Simulate latency
    final newUser = User(id: (_nextId++).toString(), name: name);
    _userDatabase[newUser.id] = newUser;
    return newUser;
  }

  @override
  Future<User?> findById(String id) async {
    await Future.delayed(const Duration(milliseconds: 50));
    return _userDatabase[id];
  }
}


// --- 4. Define Handlers (The Business Logic) ---
// Handlers connect the messages (Queries/Commands) to the data layer.
class GetUserByIdQueryHandler implements ReadHandler<GetUserByIdQuery, User> {
  final IUserRepository _repository;
  GetUserByIdQueryHandler(this._repository);

  @override
  Future<User> read(GetUserByIdQuery query) async {
    print('Handler: Executing GetUserByIdQuery for id: ${query.id}...');
    final user = await _repository.findById(query.id);
    if (user == null) {
      throw Exception('User not found!');
    }
    return user;
  }
}

class CreateUserCommandHandler implements CommandHandler<CreateUserCommand, User> {
  final IUserRepository _repository;
  CreateUserCommandHandler(this._repository);

  @override
  Future<User> run(CreateUserCommand command) async {
    print('Handler: Executing CreateUserCommand for name: ${command.name}...');
    return await _repository.create(command.name);
  }
}


// --- 5. Wire up and Use the Mediator ---
void main() async {
  // --- Application Startup (Composition Root) ---
  print('Application starting...');
  
  // 1. Instantiate dependencies (like repositories).
  final userRepository = InMemoryUserRepository();
  
  // 2. Create the Mediator instance.
  final mediator = Mediator();

  // 3. Register all handlers with their dependencies.
  mediator.registerQueryHandler(GetUserByIdQueryHandler(userRepository));
  mediator.registerCommandHandler(CreateUserCommandHandler(userRepository));
  
  print('Dependencies wired up and handlers registered!');
  print('-------------------------------------------');

  // --- Application Logic (Simulating calls from a ViewModel) ---

  // Use the mediator to run a command to create a user.
  print('Client: Sending CreateUserCommand...');
  final createdUser = await mediator.run(const CreateUserCommand('Alice'));
  print('✅ Success! Command returned: $createdUser');
  print('-------------------------------------------');

  // Use the mediator to read the user back with a query.
  print('Client: Sending GetUserByIdQuery...');
  final fetchedUser = await mediator.read(GetUserByIdQuery(createdUser.id));
  print('✅ Success! Query returned: $fetchedUser');
}
```

This example shows the complete, end-to-end flow within the domain and data layers. By strictly following this pattern, you build a robust and testable core for your application, ready to be connected to a user interface.