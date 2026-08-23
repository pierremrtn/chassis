# Business Logic

This guide explores the Application layer—where your business logic lives. Handlers are the home of validation, orchestration, and business rules, and the code generator wires them rather than writing them. By the end, you'll know how to write handlers for sophisticated workflows, test them in complete isolation, and compose repositories inside them to handle intricate business requirements.

## Anatomy of Messages

### Commands

Commands represent an intent to change application state. They are immutable data structures carrying the parameters needed to perform an action, named after business operations rather than technical implementations. A command should describe what you want to accomplish—UpdateUserEmail, ProcessPayment, SubmitOrder—not how the system will accomplish it.

Commands must be immutable to prevent accidental mutations during handling. Use `final` fields so the command cannot be mutated after construction. The type parameter `R` in `Command<R>` specifies what the command returns—use `void` for operations that produce no result, or a concrete type for operations that return created or updated entities.

```dart
// Simple command (void return)
final class LogoutCommand extends Command<void> {}

// Command with parameters and return value
final class CreateOrderCommand extends Command<Order> {
  CreateOrderCommand({
    required this.userId,
    required this.items,
    required this.shippingAddress,
  });

  final String userId;
  final List<OrderItem> items;
  final Address shippingAddress;
}

// Command with validation
final class UpdateUserEmailCommand extends Command<void> {
  UpdateUserEmailCommand({
    required this.userId,
    required this.newEmail,
  }) : assert(newEmail.length > 0, 'Email cannot be empty');

  final String userId;
  final String newEmail;
}
```

Commands should be self-contained, carrying all the information needed to execute the operation. Avoid holding references to repositories or services—those belong in handlers. Validation in constructors provides early failure detection, catching invalid states before they reach handlers.

Declare one concrete `final` class per operation. The Mediator routes a message by its exact runtime type: a subclass of a registered command is not dispatched to the parent's handler, and generic message classes are unsupported (`chassis_builder` rejects them at build time). The command definition lives in `command.dart` in the chassis package.

### Queries

Queries retrieve data without causing side effects, adhering to the Command-Query Separation principle discussed in [Core Architecture](01_core_architecture.md#command-query-separation). Chassis provides two query types based on consumption pattern. Use ReadQuery for one-time data fetches and WatchQuery for reactive data streams.

In modern reactive Flutter applications, most data should come from WatchQuery streams to keep the UI automatically synchronized with data changes. However, ReadQuery remains useful for specific scenarios: non-interactive operations like report generation or data exports that produce files, one-time validation checks that don't affect displayed data, or initial bootstrapping operations that run before the UI renders. If the data might change and the UI should reflect those changes, prefer WatchQuery.

```dart
// One-time data export operation
final class ExportUserDataQuery extends ReadQuery<ExportFile> {
  ExportUserDataQuery({
    required this.userId,
    required this.format,
  });

  final String userId;
  final ExportFormat format; // CSV, JSON, PDF
}

// Validation check that doesn't need reactivity
final class ValidatePromoCodeQuery extends ReadQuery<PromoCodeValidation> {
  ValidatePromoCodeQuery({
    required this.code,
    required this.userId,
  });

  final String code;
  final String userId;
}
```

WatchQuery handles reactive data streams that update over time. This should be your default choice for any data displayed in the UI. User profiles, product lists, shopping carts, notification counts, and search results all benefit from automatic updates when underlying data changes. The stream remains active until explicitly cancelled, keeping the UI synchronized with the data layer without manual refresh logic.

```dart
// User profile that updates when data changes
final class WatchUserProfileQuery extends WatchQuery<UserProfile> {
  WatchUserProfileQuery({required this.userId});

  final String userId;
}

// Product search results that update as inventory changes
final class WatchProductSearchQuery extends WatchQuery<List<Product>> {
  WatchProductSearchQuery({
    required this.searchTerm,
    this.category,
    this.maxPrice,
  });

  final String searchTerm;
  final String? category;
  final double? maxPrice;
}

// Shopping cart that updates when items are added/removed
final class WatchCartQuery extends WatchQuery<ShoppingCart> {
  WatchCartQuery({required this.userId});

  final String userId;
}
```

The type system enforces correct usage. Attempting to watch a ReadQuery results in a compile error, preventing accidental stream subscriptions for one-time operations. This distinction enables the Mediator to route requests appropriately and avoid common bugs like memory leaks from uncancelled subscriptions. Query definitions are in `query.dart` in the chassis package.

### Message Identity

Commands and Queries share an identity contract: **two messages of the same type with equal `params` are the same operation**. `params` is a `Map<String, Object?>` getter that defaults to an empty map; override it to expose the message's fields. It serves two purposes at once:

- **Identity.** `==` and `hashCode` are derived from the runtime type and `params`. This is the contract that caching and deduplication middlewares (and tooling) rely on: a message is fully described by its type and its `params`. A field that affects the operation but is left out of `params` breaks that contract.
- **Logging.** `toString` and the `LoggingMiddleware` render `params`, so a trace reads `UpdateUserEmailCommand{userId: u1, newEmail: new@example.com}` instead of a bare type name.

```dart
final class UpdateUserEmailCommand extends Command<void> {
  UpdateUserEmailCommand({
    required this.userId,
    required this.newEmail,
  });

  final String userId;
  final String newEmail;

  @override
  Map<String, Object?> get params => {'userId': userId, 'newEmail': newEmail};
}
```

Entries are compared with `==`, so expose fields with value equality—strings, numbers, enums, value objects. Never include secrets—passwords, tokens—in `params`: everything in the map ends up in logs.

## The Handler Contract

Handlers are plain Dart classes receiving and processing commands and queries. They are stateless and testable in complete isolation from the UI and the framework, allowing for pure logic verification with no Flutter dependencies. This is one of the key testability benefits of the Chassis architecture.

A handler is named after its message: `CreateOrderCommand` is handled by `CreateOrderCommandHandler`, `WatchUserPresenceQuery` by `WatchUserPresenceQueryHandler`. The message is the identity of the operation—the handler is its implementation.

### CommandHandler Structure

A CommandHandler implements the `CommandHandler<C, R>` interface (using `implements`), where `C` is the command type and `R` is the return type. Handlers receive dependencies via constructor injection, following the Dependency Inversion Principle from the layered architecture. This pattern keeps handlers testable and prevents them from creating their own dependencies. Declare dependencies as parameters of an unnamed constructor — the code generator injects them, whichever form they take; prefer named parameters once a handler has more than one dependency (see [Code Generation](03_code_generation.md)).

```dart
@chassisHandler
class CreateOrderCommandHandler implements CommandHandler<CreateOrderCommand, Order> {
  final OrderRepository orderRepository;
  final InventoryService inventoryService;
  final PaymentGateway paymentGateway;
  final NotificationService notificationService;

  CreateOrderCommandHandler({
    required this.orderRepository,
    required this.inventoryService,
    required this.paymentGateway,
    required this.notificationService,
  });

  @override
  Future<Order> run(CreateOrderCommand command) async {
    // Multi-step business logic

    // 1. Validate inventory
    final available = await inventoryService.checkAvailability(command.items);
    if (!available) {
      throw InsufficientInventoryException();
    }

    // 2. Calculate total
    final total = command.items.fold<double>(
      0,
      (sum, item) => sum + (item.price * item.quantity),
    );

    // 3. Process payment
    final paymentResult = await paymentGateway.charge(
      userId: command.userId,
      amount: total,
    );

    // 4. Create order
    final order = await orderRepository.create(
      userId: command.userId,
      items: command.items,
      shippingAddress: command.shippingAddress,
      paymentId: paymentResult.transactionId,
    );

    // 5. Send confirmation
    await notificationService.sendOrderConfirmation(order);

    return order;
  }
}
```

A multi-step flow is one handler composing several repositories and services—handlers never dispatch other commands or queries. Chaining handlers through the mediator would hide the workflow across files and make the pieces untestable in isolation; composing repositories inside a single handler keeps the whole business rule in one readable, testable place.

Error handling occurs at the handler level: throwing causes the dispatching ViewModel to receive an `AsyncError` state carrying the error object itself—`InsufficientInventoryException` above, not a message string—so the UI can pattern-match on its type to decide what to render. Throw typed domain errors for expected failures and let infrastructure exceptions propagate; see [Error Management](error_management.md) for the full doctrine. The handler contract is defined in `command.dart` in the chassis package.

### QueryHandler Structure

Query handlers follow the same dependency injection pattern as command handlers, but implement different methods based on their type. ReadHandler implements a `read()` method returning `Future<R>`, while WatchHandler implements a `watch()` method returning `Stream<R>`. Both patterns enable the same testability benefits through interface dependencies.

ReadHandlers often incorporate caching logic, since queries do not mutate state. Checking a cache before hitting the database or network can dramatically improve performance for frequently accessed data.

```dart
// ReadHandler - One-time fetch
@chassisHandler
class GetUserProfileQueryHandler implements ReadHandler<GetUserProfileQuery, UserProfile> {
  final UserRepository userRepository;
  final CacheService cacheService;

  GetUserProfileQueryHandler({
    required this.userRepository,
    required this.cacheService,
  });

  @override
  Future<UserProfile> read(GetUserProfileQuery query) async {
    // Check cache first
    final cached = await cacheService.get<UserProfile>('profile_${query.userId}');
    if (cached != null) return cached;

    // Fetch from repository
    final profile = await userRepository.getProfile(query.userId);

    // Cache for 5 minutes
    await cacheService.set(
      'profile_${query.userId}',
      profile,
      ttl: Duration(minutes: 5),
    );

    return profile;
  }
}

// WatchHandler - Reactive stream
@chassisHandler
class WatchUserPresenceQueryHandler implements WatchHandler<WatchUserPresenceQuery, PresenceStatus> {
  final RealtimeService realtimeService;
  final UserRepository userRepository;

  WatchUserPresenceQueryHandler({
    required this.realtimeService,
    required this.userRepository,
  });

  @override
  Stream<PresenceStatus> watch(WatchUserPresenceQuery query) async* {
    // Emit initial state
    final initial = await userRepository.getPresenceStatus(query.userId);
    yield initial;

    // Stream real-time updates
    await for (final update in realtimeService.watchPresence(query.userId)) {
      yield update;
    }
  }
}
```

The WatchHandler's async generator pattern (`async*` and `yield`) provides elegant stream composition. You can emit an initial value immediately, then merge in real-time updates from external sources. This pattern appears frequently in applications consuming WebSockets, Firebase, or other streaming data sources. The query handler contract is defined in `query.dart` in the chassis package.

### Dependency Injection

Handlers receive dependencies through constructors, not through service locators or global singletons. This explicit dependency declaration improves testability by making dependencies visible and mockable. It also prevents the hidden coupling that service locators introduce, where a class's dependencies are only discoverable by reading its implementation.

The Mediator construction site becomes your composition root—the single place where you wire together your entire dependency graph. In a real-world application this class is generated by `chassis_builder` from a `@ChassisApp` declaration: every distinct handler dependency becomes a required named parameter of the generated constructor, deduplicated across handlers. Registration is the constructor's entire job—the generated mediator exposes no per-message methods, because ViewModels dispatch message objects directly. The generated code is equivalent to:

```dart
// Dependency composition at app startup (generated from @ChassisApp)
class AppMediator extends Mediator {
  AppMediator({
    required UserRepository userRepository,
    required CacheService cacheService,
    required RealtimeService realtimeService,
    required OrderRepository orderRepository,
    required InventoryService inventoryService,
    required PaymentGateway paymentGateway,
    required NotificationService notificationService,
  }) {
    // Register handlers with their dependencies
    registerCommandHandler(
      CreateOrderCommandHandler(
        orderRepository: orderRepository,
        inventoryService: inventoryService,
        paymentGateway: paymentGateway,
        notificationService: notificationService,
      ),
    );

    registerQueryHandler(
      GetUserProfileQueryHandler(
        userRepository: userRepository,
        cacheService: cacheService,
      ),
    );

    registerQueryHandler(
      WatchUserPresenceQueryHandler(
        realtimeService: realtimeService,
        userRepository: userRepository,
      ),
    );
  }
}
```

`main()` constructs the infrastructure implementations, hands them to the generated constructor, and installs the result with `Chassis.initialize` before `runApp`:

```dart
void main() {
  Chassis.initialize(AppMediator(
    userRepository: FirestoreUserRepository(),
    cacheService: HiveCacheService(),
    realtimeService: WebSocketRealtimeService(),
    orderRepository: FirestoreOrderRepository(),
    inventoryService: HttpInventoryService(),
    paymentGateway: StripePaymentGateway(),
    notificationService: PushNotificationService(),
  ));
  runApp(const MyApp());
}
```

This is the only place in the application that names `AppMediator`. See [Code Generation](03_code_generation.md) for the `@ChassisApp` declaration and the build-time guarantee that every reachable message has a handler.

## Dispatching Messages

The presentation layer triggers business logic by dispatching the message itself: a ViewModel method calls `run(SomeCommand(...))`, `read(SomeQuery(...))`, or `watch(SomeQuery(...))`, and the mediator installed by `Chassis.initialize` routes the message to its handler. ViewModels never reference the generated mediator class—they depend only on message types.

```dart
class CheckoutViewModel extends ViewModel<CheckoutState, CheckoutEvent> {
  CheckoutViewModel({super.mediator}) : super(CheckoutState.initial());

  void submitOrder() => run(
        CreateOrderCommand(
          userId: state.userId,
          items: state.items,
          shippingAddress: state.shippingAddress,
        ),
        onState: (order) => setState(state.copyWith(order: order)),
        onError: (error, stack) => sendEvent(OrderFailedEvent(error)),
      );
}

sealed class CheckoutEvent {}

final class OrderFailedEvent extends CheckoutEvent {
  OrderFailedEvent(this.error);

  /// The error object — never a string — so the UI can pattern-match on
  /// its type (InsufficientInventoryException, PaymentDeclinedError, ...).
  final Object error;
}
```

A ViewModel method is synchronous and expression-bodied—all asynchrony lives in the dispatch machinery. Two rules from this example are non-negotiable. First, the error path is always covered: provide `onState` or `onError` on every dispatch, never `onSuccess` alone, or failures become invisible. Second, failure events carry the error **object**, never `error.toString()`—a stringified error can only be displayed, not matched on, which destroys the typed error handling that handlers throwing domain errors makes possible (see [Error Management](error_management.md)).

If a dispatched message has no registered handler, the failure surfaces as an `AsyncError` (wrapping a `HandlerNotRegisteredError`) through the same callbacks rather than crashing the call site—but with `chassis_builder`, you should never see it: a reachable message without a handler is already a build error. The full dispatch API—`Async` states, `RunPolicy` concurrency control, optimistic updates, watch lifecycles—is covered in [UI Integration](04_ui_integration.md).

## Testing Strategy

### Unit Testing Handlers

Handlers are the ideal unit for testing business logic because they are pure Dart classes with no Flutter dependencies. Use mocks for repository interfaces to control test conditions precisely, simulating success cases, error conditions, and edge cases without touching real databases or networks.

```dart
// test/handlers/create_order_command_handler_test.dart
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

class MockOrderRepository extends Mock implements OrderRepository {}
class MockInventoryService extends Mock implements InventoryService {}
class MockPaymentGateway extends Mock implements PaymentGateway {}
class MockNotificationService extends Mock implements NotificationService {}

void main() {
  late CreateOrderCommandHandler handler;
  late MockOrderRepository mockOrderRepo;
  late MockInventoryService mockInventory;
  late MockPaymentGateway mockPayment;
  late MockNotificationService mockNotification;

  setUp(() {
    mockOrderRepo = MockOrderRepository();
    mockInventory = MockInventoryService();
    mockPayment = MockPaymentGateway();
    mockNotification = MockNotificationService();

    handler = CreateOrderCommandHandler(
      orderRepository: mockOrderRepo,
      inventoryService: mockInventory,
      paymentGateway: mockPayment,
      notificationService: mockNotification,
    );
  });

  test('creates order successfully when inventory available', () async {
    // Arrange
    final command = CreateOrderCommand(
      userId: 'user123',
      items: [OrderItem(productId: 'prod1', quantity: 2, price: 10.0)],
      shippingAddress: Address(street: '123 Main St'),
    );

    when(() => mockInventory.checkAvailability(any()))
        .thenAnswer((_) async => true);

    when(() => mockPayment.charge(
          userId: any(named: 'userId'),
          amount: any(named: 'amount'),
        )).thenAnswer((_) async => PaymentResult(transactionId: 'txn123'));

    when(() => mockOrderRepo.create(
          userId: any(named: 'userId'),
          items: any(named: 'items'),
          shippingAddress: any(named: 'shippingAddress'),
          paymentId: any(named: 'paymentId'),
        )).thenAnswer((_) async => Order(id: 'order123', status: OrderStatus.confirmed));

    when(() => mockNotification.sendOrderConfirmation(any()))
        .thenAnswer((_) async {});

    // Act
    final result = await handler.run(command);

    // Assert
    expect(result.id, equals('order123'));
    verify(() => mockInventory.checkAvailability(command.items)).called(1);
    verify(() => mockPayment.charge(userId: 'user123', amount: 20.0)).called(1);
    verify(() => mockNotification.sendOrderConfirmation(any())).called(1);
  });

  test('throws exception when inventory unavailable', () async {
    // Arrange
    final command = CreateOrderCommand(
      userId: 'user123',
      items: [OrderItem(productId: 'prod1', quantity: 2, price: 10.0)],
      shippingAddress: Address(street: '123 Main St'),
    );

    when(() => mockInventory.checkAvailability(any()))
        .thenAnswer((_) async => false);

    // Act & Assert
    expect(
      () => handler.run(command),
      throwsA(isA<InsufficientInventoryException>()),
    );

    verifyNever(() => mockPayment.charge(
          userId: any(named: 'userId'),
          amount: any(named: 'amount'),
        ));
    verifyNever(() => mockOrderRepo.create(
          userId: any(named: 'userId'),
          items: any(named: 'items'),
          shippingAddress: any(named: 'shippingAddress'),
          paymentId: any(named: 'paymentId'),
        ));
  });
}
```

Notice the test requires no Flutter TestWidgets or Mediator setup. The handler is tested in complete isolation with only the dependencies it explicitly declares. Mock verification ensures business logic executes in the correct order—inventory check before payment, payment before order creation. This precision is difficult to achieve in end-to-end tests but straightforward in focused unit tests.

### Integration Testing with Mediator

Integration tests verify that handlers are correctly registered and messages are routed properly through the Mediator. Use a real Mediator instance with mock repositories to test the wiring between components without involving the UI.

```dart
// test/integration/mediator_integration_test.dart
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  test('CreateOrderCommand routes to CreateOrderCommandHandler', () async {
    // Arrange
    final mockOrderRepo = MockOrderRepository();
    final mockInventory = MockInventoryService();
    final mockPayment = MockPaymentGateway();
    final mockNotification = MockNotificationService();

    final mediator = Mediator();
    mediator.registerCommandHandler(
      CreateOrderCommandHandler(
        orderRepository: mockOrderRepo,
        inventoryService: mockInventory,
        paymentGateway: mockPayment,
        notificationService: mockNotification,
      ),
    );

    final command = CreateOrderCommand(
      userId: 'user123',
      items: [OrderItem(productId: 'prod1', quantity: 2, price: 10.0)],
      shippingAddress: Address(street: '123 Main St'),
    );

    when(() => mockInventory.checkAvailability(any())).thenAnswer((_) async => true);
    when(() => mockPayment.charge(
          userId: any(named: 'userId'),
          amount: any(named: 'amount'),
        )).thenAnswer((_) async => PaymentResult(transactionId: 'txn123'));
    when(() => mockOrderRepo.create(
          userId: any(named: 'userId'),
          items: any(named: 'items'),
          shippingAddress: any(named: 'shippingAddress'),
          paymentId: any(named: 'paymentId'),
        )).thenAnswer((_) async => Order(id: 'order123', status: OrderStatus.confirmed));
    when(() => mockNotification.sendOrderConfirmation(any()))
        .thenAnswer((_) async {});

    // Act
    final result = await mediator.run(command);

    // Assert
    expect(result.id, equals('order123'));
  });

  test('throws HandlerNotRegisteredError when handler not registered', () {
    final mediator = Mediator();
    final command = UnregisteredCommand();

    expect(
      () => mediator.run(command),
      throwsA(isA<HandlerNotRegisteredError>()),
    );
  });

  test('throws DuplicateHandlerError on double registration', () {
    final mediator = Mediator();
    CreateOrderCommandHandler buildHandler() => CreateOrderCommandHandler(
          orderRepository: MockOrderRepository(),
          inventoryService: MockInventoryService(),
          paymentGateway: MockPaymentGateway(),
          notificationService: MockNotificationService(),
        );

    mediator.registerCommandHandler(buildHandler());

    expect(
      () => mediator.registerCommandHandler(buildHandler()),
      throwsA(isA<DuplicateHandlerError>()),
    );
  });
}
```

Integration tests catch wiring errors that unit tests miss. They verify that commands route to the correct handlers and that the Mediator's type resolution works as expected. These tests run quickly because they use mocks rather than real infrastructure. Note that both wiring failures extend the sealed `ChassisError` type, which is a Dart `Error`, not an `Exception`: they signal programming mistakes, are thrown unconditionally—debug and release builds behave identically—and must never be caught in application code. Fix the registration instead.

The same real-Mediator-with-mocks setup also serves ViewModel tests: pass it through the constructor seam—`CheckoutViewModel(mediator: mediator)`—and never call `Chassis.initialize` in tests. See [UI Integration](04_ui_integration.md) for ViewModel testing patterns.

## Summary

Handlers give you complete control over business logic, enabling complex workflows in plain, testable Dart. Commands and Queries express intent through immutable, well-named types whose identity is their type plus their `params`. Each message has exactly one handler, named after it, which composes repositories to fulfill the intent—handlers never dispatch other messages. ViewModels trigger the whole pipeline by dispatching the message object itself. The testing strategy isolates handlers for unit tests, verifies wiring with integration tests, and hands a mediator to ViewModels through their constructor seam.

With this foundation, the next section explores how [Code Generation](03_code_generation.md) automates the wiring around your handlers — the mediator class and its dependency-injecting constructor, plus the build-time guarantee that no message goes unhandled — while the logic itself stays in the handlers you just learned to write.
