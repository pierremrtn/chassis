# Business Logic

This guide explores the Application layer—where your business logic lives. While Chassis is able to automates 90% of standard CRUD operations, understanding manual implementation is essential for the complex scenarios that inevitably arise in production applications. By the end, you'll know how to write handlers for sophisticated workflows, test them in complete isolation, and compose them to handle intricate business requirements. This knowledge forms the foundation for making informed decisions about when to leverage automation and when to implement logic by hand.

## Anatomy of Messages

### Commands

Commands represent an intent to change application state. They are immutable data structures carrying the parameters needed to perform an action, named after business operations rather than technical implementations. A command should describe what you want to accomplish—UpdateUserEmail, ProcessPayment, SubmitOrder—not how the system will accomplish it.

Commands must be immutable to prevent accidental mutations during handling. Use `final` fields and `const` constructors wherever possible. The type parameter `R` in `Command<R>` specifies what the command returns—use `void` for operations that produce no result, or a concrete type for operations that return created or updated entities.

```dart
// Simple command (void return)
class LogoutCommand implements Command<void> {
  const LogoutCommand();
}

// Command with parameters and return value
class CreateOrderCommand implements Command<Order> {
  const CreateOrderCommand({
    required this.userId,
    required this.items,
    required this.shippingAddress,
  });

  final String userId;
  final List<OrderItem> items;
  final Address shippingAddress;
}

// Command with validation
class UpdateUserEmailCommand implements Command<void> {
  const UpdateUserEmailCommand({
    required this.userId,
    required this.newEmail,
  }) : assert(newEmail.length > 0, 'Email cannot be empty');

  final String userId;
  final String newEmail;
}
```

Commands should be self-contained, carrying all the information needed to execute the operation. Avoid holding references to repositories or services—those belong in handlers. Validation in constructors provides early failure detection, catching invalid states before they reach handlers. The command definition lives in [lib/src/mediator/command.dart:19-22](../lib/src/mediator/command.dart#L19-L22).

### Queries

Queries retrieve data without causing side effects, adhering to the Command-Query Separation principle discussed in [Core Architecture](01_core_architecture.md#command-query-separation). Chassis provides two query types based on consumption pattern. Use ReadQuery for one-time data fetches and WatchQuery for reactive data streams.

In modern reactive Flutter applications, most data should come from WatchQuery streams to keep the UI automatically synchronized with data changes. However, ReadQuery remains useful for specific scenarios: non-interactive operations like report generation or data exports that produce files, one-time validation checks that don't affect displayed data, or initial bootstrapping operations that run before the UI renders. If the data might change and the UI should reflect those changes, prefer WatchQuery.

```dart
// One-time data export operation
class ExportUserDataQuery implements ReadQuery<ExportFile> {
  const ExportUserDataQuery({
    required this.userId,
    required this.format,
  });

  final String userId;
  final ExportFormat format; // CSV, JSON, PDF
}

// Validation check that doesn't need reactivity
class ValidatePromoCodeQuery implements ReadQuery<PromoCodeValidation> {
  const ValidatePromoCodeQuery({
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
class WatchUserProfileQuery implements WatchQuery<UserProfile> {
  const WatchUserProfileQuery({required this.userId});

  final String userId;
}

// Product search results that update as inventory changes
class WatchProductSearchQuery implements WatchQuery<List<Product>> {
  const WatchProductSearchQuery({
    required this.searchTerm,
    this.category,
    this.maxPrice,
  });

  final String searchTerm;
  final String? category;
  final double? maxPrice;
}

// Shopping cart that updates when items are added/removed
class WatchCartQuery implements WatchQuery<ShoppingCart> {
  const WatchCartQuery({required this.userId});

  final String userId;
}
```

The type system enforces correct usage. Attempting to watch a ReadQuery results in a compile error, preventing accidental stream subscriptions for one-time operations. This distinction enables the Mediator to route requests appropriately and avoid common bugs like memory leaks from uncancelled subscriptions. Query definitions are in [lib/src/mediator/query.dart:9-39](../lib/src/mediator/query.dart#L9-L39).

## The Handler Contract

Handlers are plain Dart classes receiving and processing commands and queries. They are stateless and testable in complete isolation from the UI and the framework, allowing for pure logic verification with no Flutter dependencies. This is one of the key testability benefits of the Chassis architecture.

### CommandHandler Structure

A CommandHandler implements the `CommandHandler<C, R>` interface, where `C` is the command type and `R` is the return type. Handlers receive dependencies via constructor injection, following the Dependency Inversion Principle from the layered architecture. This pattern keeps handlers testable and prevents them from creating their own dependencies.

For simple handlers with a single dependency, the `extends` syntax with a lambda provides concise implementation. For complex handlers coordinating multiple services, the `implements` syntax with explicit method implementation offers more control and clarity.

```dart
// Simple handler using extends (single dependency)
@chassisHandler
class LogoutHandler extends CommandHandler<LogoutCommand, void> {
  LogoutHandler(IAuthRepository authRepository)
      : super((command) async {
          await authRepository.logout();
        });
}

// Complex handler using implements (multiple dependencies)
@chassisHandler
class CreateOrderHandler implements CommandHandler<CreateOrderCommand, Order> {
  final IOrderRepository _orderRepository;
  final IInventoryService _inventoryService;
  final IPaymentGateway _paymentGateway;
  final INotificationService _notificationService;

  CreateOrderHandler({
    required IOrderRepository orderRepository,
    required IInventoryService inventoryService,
    required IPaymentGateway paymentGateway,
    required INotificationService notificationService,
  })  : _orderRepository = orderRepository,
        _inventoryService = inventoryService,
        _paymentGateway = paymentGateway,
        _notificationService = notificationService;

  @override
  Future<Order> run(CreateOrderCommand command) async {
    // Multi-step business logic

    // 1. Validate inventory
    final available = await _inventoryService.checkAvailability(command.items);
    if (!available) {
      throw InsufficientInventoryException();
    }

    // 2. Calculate total
    final total = command.items.fold<double>(
      0,
      (sum, item) => sum + (item.price * item.quantity),
    );

    // 3. Process payment
    final paymentResult = await _paymentGateway.charge(
      userId: command.userId,
      amount: total,
    );

    // 4. Create order
    final order = await _orderRepository.create(
      userId: command.userId,
      items: command.items,
      shippingAddress: command.shippingAddress,
      paymentId: paymentResult.transactionId,
    );

    // 5. Send confirmation
    await _notificationService.sendOrderConfirmation(order);

    return order;
  }
}
```

Complex handlers orchestrate multiple services to fulfill a single command, implementing business workflows that span multiple domain boundaries. Error handling occurs at the handler level—throwing exceptions causes the ViewModel to receive an `AsyncError` state, which the UI can then render appropriately. The handler contract is defined in [lib/src/mediator/command.dart:44-78](../lib/src/mediator/command.dart#L44-L78).

### QueryHandler Structure

Query handlers follow the same dependency injection pattern as command handlers, but implement different methods based on their type. ReadHandler implements a `read()` method returning `Future<R>`, while WatchHandler implements a `watch()` method returning `Stream<R>`. Both patterns enable the same testability benefits through interface dependencies.

ReadHandlers often incorporate caching logic, since queries do not mutate state. Checking a cache before hitting the database or network can dramatically improve performance for frequently accessed data.

```dart
// ReadHandler - One-time fetch
class GetUserProfileHandler implements ReadHandler<GetUserProfileQuery, UserProfile> {
  final IUserRepository _userRepository;
  final ICacheService _cacheService;

  GetUserProfileHandler(this._userRepository, this._cacheService);

  @override
  Future<UserProfile> read(GetUserProfileQuery query) async {
    // Check cache first
    final cached = await _cacheService.get<UserProfile>('profile_${query.userId}');
    if (cached != null) return cached;

    // Fetch from repository
    final profile = await _userRepository.getProfile(query.userId);

    // Cache for 5 minutes
    await _cacheService.set(
      'profile_${query.userId}',
      profile,
      ttl: Duration(minutes: 5),
    );

    return profile;
  }
}

// WatchHandler - Reactive stream
@chassisHandler
class WatchUserPresenceHandler implements WatchHandler<WatchUserPresenceQuery, PresenceStatus> {
  final IRealtimeService _realtimeService;
  final IUserRepository _userRepository;

  WatchUserPresenceHandler(this._realtimeService, this._userRepository);

  @override
  Stream<PresenceStatus> watch(WatchUserPresenceQuery query) async* {
    // Emit initial state
    final initial = await _userRepository.getPresenceStatus(query.userId);
    yield initial;

    // Stream real-time updates
    await for (final update in _realtimeService.watchPresence(query.userId)) {
      yield update;
    }
  }
}
```

The WatchHandler's async generator pattern (`async*` and `yield`) provides elegant stream composition. You can emit an initial value immediately, then merge in real-time updates from external sources. This pattern appears frequently in applications consuming WebSockets, Firebase, or other streaming data sources. The query handler contract is defined in [lib/src/mediator/query.dart:76-178](../lib/src/mediator/query.dart#L76-L178).

### Dependency Injection

Handlers receive dependencies through constructors, not through service locators or global singletons. This explicit dependency declaration improves testability by making dependencies visible and mockable. It also prevents the hidden coupling that service locators introduce, where a class's dependencies are only discoverable by reading its implementation.

The Mediator construction site becomes your composition root—the single place where you wire together your entire dependency graph. In a real-world application, the `AppMediator` (alongside others useful extensions) is automatically generated by Chassis thank to the `@chassisHandler` annotation.

```dart
// Dependency composition at app startup
class AppMediator extends Mediator {
  AppMediator({
    required IUserRepository userRepository,
    required IAuthRepository authRepository,
    required ICacheService cacheService,
    required IRealtimeService realtimeService,
    required IOrderRepository orderRepository,
    required IInventoryService inventoryService,
    required IPaymentGateway paymentGateway,
    required INotificationService notificationService,
  }) {
    // Register handlers with their dependencies
    registerCommandHandler(
      CreateOrderHandler(
        orderRepository: orderRepository,
        inventoryService: inventoryService,
        paymentGateway: paymentGateway,
        notificationService: notificationService,
      ),
    );

    registerQueryHandler(
      GetUserProfileHandler(userRepository, cacheService),
    );

    registerQueryHandler(
      WatchUserPresenceHandler(realtimeService, userRepository),
    );
  }
}
```

## Testing Strategy

### Unit Testing Handlers

Handlers are the ideal unit for testing business logic because they are pure Dart classes with no Flutter dependencies. Use mocks for repository interfaces to control test conditions precisely, simulating success cases, error conditions, and edge cases without touching real databases or networks.

```dart
// test/handlers/create_order_handler_test.dart
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

class MockOrderRepository extends Mock implements IOrderRepository {}
class MockInventoryService extends Mock implements IInventoryService {}
class MockPaymentGateway extends Mock implements IPaymentGateway {}
class MockNotificationService extends Mock implements INotificationService {}

void main() {
  late CreateOrderHandler handler;
  late MockOrderRepository mockOrderRepo;
  late MockInventoryService mockInventory;
  late MockPaymentGateway mockPayment;
  late MockNotificationService mockNotification;

  setUp(() {
    mockOrderRepo = MockOrderRepository();
    mockInventory = MockInventoryService();
    mockPayment = MockPaymentGateway();
    mockNotification = MockNotificationService();

    handler = CreateOrderHandler(
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
        .thenAnswer((_) async => {});

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
  test('CreateOrderCommand routes to CreateOrderHandler', () async {
    // Arrange
    final mockOrderRepo = MockOrderRepository();
    final mockInventory = MockInventoryService();
    final mockPayment = MockPaymentGateway();
    final mockNotification = MockNotificationService();

    final mediator = Mediator();
    mediator.registerCommandHandler(
      CreateOrderHandler(
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
        .thenAnswer((_) async => {});

    // Act
    final result = await mediator.run(command);

    // Assert
    expect(result.id, equals('order123'));
  });

  test('throws MediatorException when handler not registered', () {
    final mediator = Mediator();
    final command = UnregisteredCommand();

    expect(
      () => mediator.run(command),
      throwsA(isA<MediatorException>()),
    );
  });
}
```

Integration tests catch wiring errors that unit tests miss. They verify that commands route to the correct handlers and that the Mediator's type resolution works as expected. These tests run quickly because they use mocks rather than real infrastructure.

## Summary

Manual handler implementation provides complete control over business logic, enabling complex workflows that code generation cannot automate. Commands and Queries express intent through immutable, well-named types. Handlers coordinate dependencies to fulfill those intents, while remaining testable through interface-based dependency injection. The testing strategy isolates handlers for unit tests, verifies wiring with integration tests, and mocks the Mediator for ViewModel tests.

With this foundation in manual implementation, the next section explores how [Code Generation](03_code_generation.md) automates the 90% of handlers that follow standard patterns, eliminating boilerplate while preserving architectural benefits.
