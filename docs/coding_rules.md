# Chassis Implementation Rules

This document formalizes the implementation rules embedded in the Chassis framework using the DO / DON'T / PREFER / AVOID / CONSIDER classification. Each guideline is written as a valid imperative sentence, and the reasoning is explained immediately below.

---

## Architecture & Layering

### DO organize code into three distinct layers: Presentation, Application, and Infrastructure

Chassis enforces a layered architecture where each layer has clearly defined responsibilities. The Presentation layer contains widgets and ViewModels. The Application layer houses Commands, Queries, and Handlers. The Infrastructure layer manages repositories and data sources. This separation ensures that changes in one layer do not cascade unpredictably into others.

```
lib/
  ├── presentation/        # ViewModels, Widgets
  ├── application/         # Commands, Queries, Handlers
  └── infrastructure/      # Repositories, Data Sources
```

### DO point source code dependencies inward, toward higher-level policies

The Dependency Rule states that Handlers depend on Repository interfaces (not implementations), ViewModels depend on the Mediator (not Handlers directly), and Widgets depend on ViewModels (not domain logic). This inversion of control enables testing, as you can substitute implementations without modifying consumers.

```dart
// ✅ Correct: Handler depends on abstraction
class CreateUserHandler implements CommandHandler<CreateUserCommand, User> {
  final IUserRepository _repository; // Interface dependency
  CreateUserHandler(this._repository);

  @override
  Future<User> run(CreateUserCommand command) async {
    return await _repository.create(command.name, command.email);
  }
}

// ❌ Incorrect: Handler depends on concrete implementation
class CreateUserHandler {
  final FirestoreUserRepository _repository; // Tight coupling
}
```

### DON'T allow ViewModels to access Repositories directly

The ViewModel is architecturally restricted to being a transformation layer for the UI. It must delegate to a Handler via the Mediator, which creates a natural checkpoint where logic belongs in tested, reusable components. This prevention of logic leaks maintains the integrity of your architecture over time.

### DO follow the unidirectional data flow: UI → ViewModel → Mediator → Handler → Repository

Chassis enforces a specific path for all data operations. This guardrail ensures that a junior developer and a senior architect produce code with the same structural footprint, reducing code review friction and technical debt accumulation.

---

## Command-Query Separation

### DO separate operations into Commands (writes) and Queries (reads)

Command-Query Separation states that methods should either change state or return data, never both. When you see a Query in code, you know it's safe to call multiple times without unintended consequences. When you see a Command, you understand that state will change and execution should be deliberate.

```dart
// Command: Mutates state
final class UpdateUserEmailCommand extends Command<void> {
  UpdateUserEmailCommand({required this.userId, required this.newEmail});
  final String userId;
  final String newEmail;
}

// Query (Read): One-time data fetch without mutation
final class GetUserQuery extends ReadQuery<User> {
  GetUserQuery({required this.userId});
  final String userId;
}

// Query (Watch): Continuous stream without mutation
final class WatchUserQuery extends WatchQuery<User> {
  WatchUserQuery({required this.userId});
  final String userId;
}
```

### DO use `ReadQuery` for one-time data fetches and `WatchQuery` for reactive streams

This distinction enables the Mediator to route requests to the appropriate handler type. Attempting to watch a `ReadQuery` results in a compile error, preventing accidental stream subscriptions for one-time operations.

```dart
// One-time fetch
final user = await mediator.read(GetUserQuery(userId: '123'));

// Continuous stream
mediator.watch(WatchUserQuery(userId: '123')).listen((user) {
  print('User updated: ${user.name}');
});
```

### PREFER `WatchQuery` streams for most data in reactive Flutter applications

In modern reactive Flutter applications, most data should come from `WatchQuery` streams to keep the UI automatically synchronized with data changes. Reserve `ReadQuery` for cases where you need the current state only once, such as loading a profile when a screen opens.

---

## Messages (Commands & Queries)

### DO declare messages as `final class` using `extends`

Commands and Queries must be declared as `final class` and use `extends` (not `implements`) for their base type. The Mediator performs handler lookup based on the runtime type hierarchy, and `extends` preserves the type relationship that this lookup depends on. Using `implements` breaks the resolution chain and causes runtime dispatch failures.

```dart
// ✅ Correct: final class + extends
final class CreateOrderCommand extends Command<Order> {
  CreateOrderCommand({
    required this.userId,
    required this.items,
  });

  final String userId;
  final List<OrderItem> items;
}

final class GetOrderQuery extends ReadQuery<Order> {
  GetOrderQuery({required this.orderId});
  final String orderId;
}

// ❌ Incorrect: implements — Mediator lookup will fail
class CreateOrderCommand implements Command<Order> { /* ... */ }

// ❌ Incorrect: not final — allows subclassing which breaks type resolution
class CreateOrderCommand extends Command<Order> { /* ... */ }
```

### DO make messages immutable data structures

Both Commands and Queries must be immutable to prevent accidental mutations during handling. Use `final` fields so the message cannot be mutated after construction. Immutability also makes messages safe to log, serialize, or replay without worrying about shared mutable state.

### DO make messages self-contained with all information needed to execute

Commands and Queries should carry all the information needed to execute the operation. Avoid holding references to repositories or services — those belong in Handlers.

### DO name messages after business operations, not technical implementations

A Command should describe what you want to accomplish — `UpdateUserEmail`, `ProcessPayment`, `SubmitOrder` — not how the system will accomplish it. A Query should describe the data being requested — `GetOrderSummary`, `WatchActiveTickets` — not the underlying data source.

### CONSIDER adding validation in message constructors for early failure detection

Validation in constructors provides early failure detection, catching invalid states before they reach Handlers. This applies equally to Commands and Queries whose parameters have known constraints.

```dart
final class UpdateUserEmailCommand extends Command<void> {
  UpdateUserEmailCommand({
    required this.userId,
    required this.newEmail,
  }) : assert(newEmail.length > 0, 'Email cannot be empty');

  final String userId;
  final String newEmail;
}
```

---

## Naming Conventions

### DO follow the `[Verb][Resource]Command` pattern for Command names

Use an imperative, present-tense verb describing the business operation (e.g., `Create`, `Update`, `Register`, `Assign`, `Delete`), followed by the entity the command acts upon, and always end with `Command`.

```dart
// good
CreateProjectCommand
UpdateProjectNameCommand
SubmitOrderCommand

// bad
ProjectCreator
DoProjectUpdate
```

### DO follow the `[Get/Find][Resource]Query` pattern for ReadQuery names

Use `Get` as the standard verb, or `Find` if the result might not exist. Append `By[Criteria]` if the resource is queried by a specific parameter.

```dart
// good
GetProjectByIdQuery
GetAllUsersQuery
FindCustomerByEmailQuery
```

### DO follow the `Watch[Resource]Query` pattern for WatchQuery names

Use `Watch` as the standard verb for continuous stream subscriptions. `Observe` is an acceptable alternative.

```dart
// good
WatchProjectByIdQuery
WatchAllActiveTicketsQuery
WatchOrderStatusQuery
```

### DO name Handlers by appending `Handler` to the full message name

The Handler's name is created by taking the full name of the Command or Query it handles and appending `Handler`. This mechanical naming convention ensures absolute predictability and discoverability.

```dart
// good
CreateProjectCommandHandler
GetProjectByIdQueryHandler
WatchOrderStatusQueryHandler
```

---

## Handlers

### DO keep Handlers stateless

Handlers are plain Dart classes that receive and process messages. They must be stateless and testable in complete isolation from the UI and the framework, allowing for pure logic verification with no Flutter dependencies.

### DO use `implements` (not `extends`) for the Handler interface

Handlers must use `implements` for their base type (`CommandHandler`, `ReadHandler`, `WatchHandler`). This is the inverse of the message rule: messages use `extends` for Mediator type resolution, while Handlers use `implements` because they fulfill a behavioral contract rather than inheriting shared state. The `implements` keyword also forces you to provide explicit method signatures, preventing accidental reliance on base class internals.

```dart
// ✅ Correct: implements
@chassisHandler
class CreateOrderHandler implements CommandHandler<CreateOrderCommand, Order> {
  @override
  Future<Order> run(CreateOrderCommand command) async { /* ... */ }
}

// ❌ Incorrect: extends
@chassisHandler
class CreateOrderHandler extends CommandHandler<CreateOrderCommand, Order> {
  @override
  Future<Order> run(CreateOrderCommand command) async { /* ... */ }
}
```

### DO inject dependencies via the Handler constructor

Handlers receive Repositories and Services via constructor injection, following the Dependency Inversion Principle. This pattern keeps handlers testable and prevents them from creating their own dependencies.

```dart
@chassisHandler
class CreateOrderHandler implements CommandHandler<CreateOrderCommand, Order> {
  final IOrderRepository _orderRepository;
  final IPaymentGateway _paymentGateway;

  CreateOrderHandler({
    required IOrderRepository orderRepository,
    required IPaymentGateway paymentGateway,
  })  : _orderRepository = orderRepository,
        _paymentGateway = paymentGateway;

  @override
  Future<Order> run(CreateOrderCommand command) async {
    // Business logic here
  }
}
```

### DO implement a single responsibility per Handler

Each Handler focuses on a single responsibility: receive a message, execute business logic, call repositories as needed, and return results. Unlike patterns like Bloc that encourage coarse-grained classes handling many events, Chassis enforces one Handler per Command or Query.

### DO create business-specific error classes for domain failures

Handlers should throw typed exceptions that represent meaningful business failures rather than relying on generic exceptions. Typed errors allow the ViewModel to react differently to distinct failure modes (e.g., showing a retry button for a network error versus a validation message for bad input), and they make error-handling logic explicit and exhaustive.

```dart
// ✅ Business-specific errors
class InsufficientInventoryException implements Exception {
  const InsufficientInventoryException(this.missingItems);
  final List<String> missingItems;
}

class PaymentDeclinedException implements Exception {
  const PaymentDeclinedException(this.reason);
  final String reason;
}

// ❌ Generic errors obscure intent
throw Exception('Not enough items'); // What kind of failure? How should the UI react?
```

### DO document thrown exceptions using `///` doc comments in Handlers and Repositories

Every Handler and Repository method that can throw should declare its failure modes in its documentation comment. Consumers of these methods — other Handlers, ViewModels — need to know which exceptions to anticipate without reading the implementation. This also serves as a contract between layers.

```dart
/// Creates an order by validating inventory, processing payment, and persisting the result.
///
/// Throws [InsufficientInventoryException] if any requested item is out of stock.
/// Throws [PaymentDeclinedException] if the payment gateway rejects the charge.
class CreateOrderHandler implements CommandHandler<CreateOrderCommand, Order> {
  @override
  Future<Order> run(CreateOrderCommand command) async {
    // ...
  }
}
```

---

## File Organization

### DO define each Command or Query alongside its Handler in a dedicated file

Each message-handler pair should live in its own file. Co-locating the message definition with its handler makes it easy to navigate: finding a Command immediately reveals the logic that handles it, and vice versa. This also prevents large files from accumulating unrelated handlers.

```
lib/
  └── application/
      └── orders/
          ├── create_order_command.dart       # CreateOrderCommand + CreateOrderCommandHandler
          ├── get_order_query.dart            # GetOrderQuery + GetOrderQueryHandler
          └── watch_order_status_query.dart   # WatchOrderStatusQuery + WatchOrderStatusQueryHandler
```

### DO create one file per Command/Query-Handler pair

Splitting each pair into its own file enforces the single-responsibility principle at the file level and makes the project's capabilities scannable from the directory listing alone. When a new developer opens the `application/orders/` folder, they immediately see every operation the order domain supports.

---

## Code Generation

### DO annotate Handlers with `@chassisHandler` to trigger code generation

The `@chassisHandler` annotation marks a handler for automatic registration in the generated Mediator. The `chassis_builder` scans for this annotation and produces the Mediator subclass, handler registrations, and type-safe extension methods. Without this annotation, the generator has no knowledge of the handler and it will not be wired into the dependency graph.

```dart
@chassisHandler
class CreateOrderHandler implements CommandHandler<CreateOrderCommand, Order> {
  const CreateOrderHandler({
    required this.orderRepository,
    required this.paymentGateway,
  });

  final IOrderRepository orderRepository;
  final IPaymentGateway paymentGateway;

  @override
  Future<Order> run(CreateOrderCommand command) async {
    // Business logic
  }
}
```

### DO use named parameters for constructor dependencies in Handlers

Handler constructors should use named parameters for all injected dependencies (repositories, services, other handlers). The `chassis_builder` reads these constructor signatures to produce the generated Mediator's own constructor, so named parameters result in a clear, self-documenting dependency graph at the Mediator level.

```dart
// ✅ Named parameters — generated Mediator constructor is readable
@chassisHandler
class CreateOrderHandler implements CommandHandler<CreateOrderCommand, Order> {
  const CreateOrderHandler({
    required this.orderRepository,
    required this.inventoryService,
  });

  final IOrderRepository orderRepository;
  final IInventoryService inventoryService;
}

// ❌ Positional parameters — generated Mediator constructor becomes ambiguous
@chassisHandler
class CreateOrderHandler implements CommandHandler<CreateOrderCommand, Order> {
  const CreateOrderHandler(this.orderRepository, this.inventoryService);

  final IOrderRepository orderRepository;
  final IInventoryService inventoryService;
}
```

### DO use the generated `AppMediator` and its type-safe extension methods

The `chassis_builder` produces a Mediator subclass (e.g., `AppMediator`) that handles all handler registration and dependency injection, along with extension methods that provide a type-safe, autocomplete-friendly API. Always use this generated output rather than wiring handlers manually or dispatching raw message types. The generated extensions are the primary discoverability mechanism for your application's capabilities.

```dart
// Generated by chassis_builder — use this directly
final mediator = AppMediator(
  orderRepository: orderRepository,
  paymentGateway: paymentGateway,
);

// Type-safe access via generated extensions
await mediator.createOrder(userId: userId, items: items);
final order = await mediator.getOrder(orderId: orderId);
mediator.watchOrderStatus(orderId: orderId).listen((status) { /* ... */ });
```

### DO write Handlers by hand when using AI-assisted development

When working with an AI coding assistant, write Handlers manually rather than relying on `@generateHandler` annotations on repository methods. AI can produce the full handler implementation — including validation, orchestration, and error handling — just as quickly as a pass-through handler, and the result is more explicit, more flexible, and easier to review. Manual handlers also give you a natural place to add business logic later without migrating away from a generated handler.

### CONSIDER using `@generateHandler` on repository methods when writing code by hand

When writing code without AI assistance, the `@generateHandler` annotation on repository methods eliminates boilerplate for standard CRUD operations that simply delegate to the repository. This is a convenience trade-off: you save time on repetitive handlers, but the generated code is less visible during review and harder to extend if the operation later requires business logic.

---

## ViewModel

### DO use the `ViewModel<State, Event>` base class for all ViewModels

ViewModels serve as the bridge between business logic and the widget tree. They hold current UI state, translate user actions into Commands or Queries dispatched through the Mediator, and emit events for one-time occurrences.

```dart
class UserProfileViewModel extends ViewModel<UserProfileState, UserProfileEvent> {
  UserProfileViewModel(Mediator mediator)
      : super(mediator, initial: UserProfileState.initial());
}
```

### DO use immutable state classes with `copyWith` for state updates

State immutability ensures predictable behavior. The `copyWith` pattern creates new state objects rather than mutating existing ones, making state transitions explicit and debuggable.

```dart
class UserProfileState {
  const UserProfileState({required this.user, required this.isEditing});

  final Async<User> user;
  final bool isEditing;

  UserProfileState copyWith({Async<User>? user, bool? isEditing}) {
    return UserProfileState(
      user: user ?? this.user,
      isEditing: isEditing ?? this.isEditing,
    );
  }

  static UserProfileState initial() {
    return UserProfileState(user: Async.loading(), isEditing: false);
  }
}
```

### DO use `Async<T>` to wrap all asynchronous data in state

The `Async<T>` sealed union models the complete lifecycle of asynchronous operations — `Loading`, `Data`, and `Error` — preventing common UI bugs where loading states are not handled.

### DO use `watch()` for reactive stream subscriptions and `run()` for one-time futures

The `watch()` method subscribes to streams with automatic disposal. The `run()` method handles futures. Both support `onState` for full lifecycle control, or `onData`/`onError` for simpler handling.

```dart
void loadUser(String userId) {
  watch(
    mediator.watchUser(userId: userId),
    onState: (asyncUser) => setState(state.copyWith(user: asyncUser)),
  );
}

void deleteUser(String userId) {
  run(
    mediator.deleteUser(userId: userId),
    onData: (_) => sendEvent(UserDeletedEvent()),
    onError: (error) => sendEvent(DeleteFailedEvent(error.toString())),
  );
}
```

### DON'T implement business logic directly inside ViewModels

ViewModels cannot accidentally implement business logic because they lack direct access to repositories. They must delegate to a Handler via the Mediator. This prevents logic leaks and ensures that business rules live in tested, reusable Handlers.

---

## State vs Events

### DO use state for persistent data that determines UI rendering

State represents what should appear on screen. It is held by the ViewModel and observed by widgets through `ChangeNotifier`.

### DO use events for one-time occurrences like navigation, snackbars, and dialogs

Events fire once per occurrence through a stream, regardless of widget rebuilds. No manual cleanup is required.

```dart
sealed class CheckoutEvent {}
class PaymentSuccessEvent implements CheckoutEvent {
  const PaymentSuccessEvent(this.orderId);
  final String orderId;
}
class NavigateToOrderConfirmationEvent implements CheckoutEvent {
  const NavigateToOrderConfirmationEvent(this.orderId);
  final String orderId;
}
```

### DON'T model one-time occurrences as nullable state properties

Modeling events as nullable state properties (e.g., `String? snackbarMessage`) causes rebuilds to replay events, requires manual cleanup by nulling out properties after consumption, and pollutes the state object with ephemeral data.

```dart
// ❌ Don't do this
class BadState {
  final String? snackbarMessage;  // Will replay on every rebuild
  final String? navigationRoute;  // Causes navigation loops
  BadState({this.snackbarMessage, this.navigationRoute});
}

// ✅ Do this
sealed class GoodEvent {}
class ShowSnackbarEvent implements GoodEvent {
  const ShowSnackbarEvent(this.message);
  final String message;
}
```

---

## UI Integration

### DO use `AsyncBuilder` to render `Async<T>` states in the widget tree

`AsyncBuilder` automatically renders the appropriate UI based on whether data is loading, available, or errored. This eliminates manual state checking in build methods.

```dart
AsyncBuilder<User>(
  state: viewModel.state.user,
  builder: (context, user) => Text(user.name),
  loadingBuilder: (context) => CircularProgressIndicator(),
  errorBuilder: (context, error) => Text('Error: $error'),
)
```

### DO use `ViewModelProvider.withEvents` to listen to events from a ViewModel you provide

`ViewModelProvider.withEvents` co-locates event handling with ViewModel provision and manages the subscription lifecycle automatically. Use `ConsumerMixin` only when a descendant widget needs to listen to a ViewModel provided by an ancestor, or when the event handler needs access to local state (controllers, local variables) held inside a `State` object.

```dart
ViewModelProvider.withEvents<CheckoutViewModel, CheckoutEvent>(
  create: (_) => CheckoutViewModel(mediator),
  onEvent: (context, viewModel, event) {
    switch (event) {
      case PaymentSuccessEvent(:final orderId):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment successful! Order #$orderId')),
        );
      // ...
    }
  },
  child: const CheckoutScreen(),
);
```

### DO use `ViewModelProvider` for ViewModel dependency injection

`ViewModelProvider` integrates with the `provider` package and manages the ViewModel lifecycle automatically, ensuring proper creation and disposal.

```dart
ViewModelProvider<TodoViewModel>(
  create: (_) => TodoViewModel(mediator),
  child: const TodoScreen(),
)
```

---

## Mediator

### DO dispatch all operations through the Mediator

ViewModels depend only on the Mediator, simplifying their constructor signatures. The Mediator wires handlers to their dependencies at startup and provides a single entry point for all business logic.

### DO use the generated type-safe extension methods on the Mediator

Extension methods transform generic message dispatching into a clean, type-safe API where your IDE autocompletes every available operation. These are generated automatically by `chassis_builder` — see [Code Generation](#code-generation) for details.

### CONSIDER using Middleware for cross-cutting concerns

Middleware intercepts messages before they reach handlers, enabling logging, performance monitoring, authentication checks, and caching to be implemented once rather than duplicated across handlers.

```dart
class LoggingMiddleware implements MediatorMiddleware {
  @override
  Future<T> onRun<T>(Command<T> command, NextRun<Command<T>, T> next) async {
    print('Executing command: ${command.runtimeType}');
    final result = await next(command);
    print('Command completed');
    return result;
  }
}
```

---

## Repository

### DO define Repository interfaces to abstract data operations

A Repository interface defines what data operations are possible without specifying how they are implemented. This abstraction enables testing and allows you to swap implementations — in-memory for development, Firebase for production, or a mock for tests — without changing business logic or UI code.

---

## Testing

### DO test Handlers in complete isolation using mocked Repository interfaces

Handlers are pure Dart classes testable without the Flutter framework. Inject mock repositories via the constructor and verify business logic without UI or database dependencies.

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

### DO test ViewModels by mocking the Mediator

ViewModels depend on the Mediator interface, enabling tests with mocked Mediators instead of full dependency trees. This isolates the ViewModel from all downstream dependencies.

```dart
test('loadUser dispatches WatchUserQuery', () {
  final mockMediator = MockMediator();
  final viewModel = UserViewModel(mockMediator);

  when(() => mockMediator.watch(any<WatchUserQuery>()))
      .thenAnswer((_) => Stream.value(User(id: '1', name: 'John')));

  viewModel.loadUser('1');

  verify(() => mockMediator.watch(any<WatchUserQuery>())).called(1);
});
```

### DO test widgets by mocking the ViewModel

Widget tests verify UI rendering and user interaction handling without executing business logic. Mock the ViewModel to control state and verify method calls.

### PREFER testing events through StreamControllers in widget tests

Simulating events through a `StreamController` allows testing UI reactions to ViewModel events without executing real business logic. This verifies that snackbars, dialogs, and navigation occur correctly in response to events.

---

## Resource Management

### DO rely on `autoDisposeStreamSubscription` for automatic stream cleanup

The ViewModel's `watch()` and `run()` methods automatically register cleanup callbacks. All subscriptions are cancelled when the ViewModel is disposed, preventing memory leaks.

### DO use `autoDispose` for any `Disposable` resource the ViewModel owns

Resources registered with `autoDispose` are cleaned up in reverse order when the ViewModel is disposed. This prevents common Flutter errors from forgotten cleanups.

### DON'T manually manage stream subscriptions in ViewModels

The framework handles subscription lifecycle through `watch()` and `autoDisposeStreamSubscription`. Manual management introduces the risk of forgotten cancellations and memory leaks.

---

## Dependency Wiring

### DO compose the dependency tree from the bottom up at application startup

The dependency tree flows naturally: repositories have no dependencies, the Mediator depends on repositories, ViewModels depend on the Mediator, and widgets depend on ViewModels. This unidirectional dependency graph makes the application easy to reason about. Declare the Mediator as a global variable so it can be accessed from anywhere in the route declarations without threading it through constructor parameters.

```dart
late final AppMediator mediator;

void initializeDependencies() {
  final todoRepository = InMemoryTodoRepository();
  mediator = AppMediator(todoRepository: todoRepository);
}

void main() {
  initializeDependencies();

  runApp(
    MaterialApp(
      home: ViewModelProvider<TodoViewModel>(
        create: (_) => TodoViewModel(mediator),
        child: const TodoScreen(),
      ),
    ),
  );
}
```