---
name: chassis-write-handler-test
description: Write a unit test for a Chassis handler (`CommandHandler`, `ReadHandler`, or `WatchHandler`) by instantiating it directly with mocked repository interfaces — no Mediator, no Flutter, no widget tree. Use when adding a `*_handler_test.dart` file, when a handler gains a new branch (validation, recovery, error path) that needs coverage, or when a handler's logic is complex enough to verify in isolation before integration tests.
---
# Testing a Chassis Handler

## Contents
- [Core Concepts](#core-concepts)
- [Why Direct Instantiation, Not Mediator](#why-direct-instantiation-not-mediator)
- [Tooling: `package:test` + `package:mocktail`](#tooling-packagetest--packagemocktail)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

Handlers are pure Dart classes. They have no Flutter dependency, no `BuildContext`, no Mediator setup at construction time. The whole architectural point of putting business logic in handlers is that this layer is testable in complete isolation — instantiate the handler with mock repositories injected through the constructor, dispatch commands or queries directly to its `run` / `read` / `watch` method, and assert on the return value or thrown exceptions.

> Handlers are the ideal unit for testing business logic because they are pure Dart classes with no Flutter dependencies. Use mocks for repository interfaces to control test conditions precisely, simulating success cases, error conditions, and edge cases without touching real databases or networks.
> — `docs/02_business_logic.md`

The same shape applies to all three handler types:

- `CommandHandler` → `await handler.run(<Command>(...))`
- `ReadHandler` → `await handler.read(<Query>(...))`
- `WatchHandler` → `handler.watch(<Query>(...))` returns a `Stream<T>` you assert against with `expectLater(stream, emitsInOrder([...]))`.

## Why Direct Instantiation, Not Mediator

Some tests want to verify *wiring* — that a `CreateOrderCommand` dispatched on the Mediator actually reaches `CreateOrderCommandHandler`. That is an integration test, and it is useful, but it is not what this skill is about.

For handler-level unit tests, **construct the handler directly** with mock repositories. Going through `mediator.run(...)` adds setup (registration, type resolution, middleware) that is irrelevant to the business logic you are testing, and any failure in that setup will look like a test failure in the wrong place. Direct instantiation isolates the unit under test.

## Tooling: `package:test` + `package:mocktail`

Chassis tests use the standard Dart `package:test` plus `package:mocktail` for mocks (no code generation, supports null safety cleanly). Add to `dev_dependencies`:

```yaml
dev_dependencies:
  test: ^1.24.0
  mocktail: ^1.0.0
```

Mocks are declared as `class Mock<T> extends Mock implements <T> {}`, then stubbed with `when(() => mock.method(...)).thenAnswer(...)` and verified with `verify(() => mock.method(...)).called(n)`.

## Rules

- **DO** instantiate the handler directly in `setUp(...)` with mock repositories. *No `Mediator`, no `MaterialApp`, no `WidgetsFlutterBinding` — that is the point of the handler abstraction.*
- **DO** mock against repository **interfaces** (`IUserRepository`, `IOrderRepository`), never concrete implementations. *Interfaces are the contract the handler depends on; concrete classes drag in infrastructure that should not exist in unit tests.*
- **DO** put each test file next to nothing — group them under `test/<feature>/<handler_name>_test.dart` mirroring `lib/`'s structure.
- **DO** organize tests in `setUp` (build the mocks and the handler), one `test(...)` per logical branch (happy path, validation failure, recovery from a domain exception, propagation of an unexpected failure).
- **DO** verify both that the right repository methods were called (`verify(() => mock.create(...)).called(1)`) **and** that the wrong ones were not (`verifyNever(() => mock.charge(...))`). *The latter catches bugs where validation passes but the handler still calls payment.*
- **DO** test thrown domain exceptions with `expect(() => handler.run(...), throwsA(isA<TException>()))` and assert on typed fields when they exist.
- **DO** test stream handlers with `expectLater(stream, emitsInOrder([value1, value2, emitsDone]))` for ordered values and `emitsError(isA<TException>())` for errors.
- **CONSIDER** writing one happy-path test per handler at minimum. Add tests for each error / recovery branch the handler explicitly implements.
- **CONSIDER** colocating test data builders (`OrderItem testItem(...)`, `User testUser(...)`) in a shared `test/_fixtures/` directory when the same shapes appear across many tests.
- **DON'T** test the Mediator wiring at this layer. *Use a separate integration test file (`test/integration/<feature>_mediator_test.dart`) — see the bottom example.*
- **DON'T** mock the handler under test. *That is what you are trying to verify.*
- **DON'T** assert on log output, telemetry calls, or middleware behavior in a handler unit test. *Those are observable through middleware and tested separately.*

## Workflow

- [ ] **Step 1 — Place the file** at `test/<feature>/<handler_name>_test.dart`, mirroring the source path.
- [ ] **Step 2 — Declare mocks** for every repository / service the handler injects: `class MockOrderRepository extends Mock implements IOrderRepository {}`.
- [ ] **Step 3 — Set up** in `setUp(...)`. Construct each mock, then construct the handler with the mocks as named arguments.
- [ ] **Step 4 — Cover the happy path** in the first test. Stub each mock method with `when(...).thenAnswer(...)`, dispatch the command / query, assert on the return value, verify the right methods were called.
- [ ] **Step 5 — Cover the failure paths.** One test per business rule failure (`InsufficientInventoryException`), one per recoverable domain exception the handler converts (`CartNotFoundException` → empty cart), one per propagated unexpected failure if the assertion is meaningful.
- [ ] **Step 6 — For stream handlers**, use `emitsInOrder` with the expected sequence including `emitsDone` if the stream is finite.
- [ ] **Step 7 — Run** with `dart test test/<feature>/`.

## Examples

### Happy path + business-rule failure for a CommandHandler

```dart
// test/orders/create_order_command_handler_test.dart
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:my_app/application/orders/create_order_command.dart';
import 'package:my_app/domain/orders/order.dart';
import 'package:my_app/domain/orders/order_item.dart';
import 'package:my_app/domain/orders/order_exceptions.dart';
import 'package:my_app/domain/orders/i_order_repository.dart';
import 'package:my_app/domain/payments/i_payment_gateway.dart';
import 'package:my_app/domain/inventory/i_inventory_service.dart';

class MockOrderRepository extends Mock implements IOrderRepository {}
class MockPaymentGateway extends Mock implements IPaymentGateway {}
class MockInventoryService extends Mock implements IInventoryService {}

void main() {
  late CreateOrderCommandHandler handler;
  late MockOrderRepository orderRepo;
  late MockPaymentGateway paymentGateway;
  late MockInventoryService inventory;

  final items = [
    const OrderItem(productId: 'p1', quantity: 2, price: 10.0),
  ];
  final address = const Address(street: '123 Main St');

  setUp(() {
    orderRepo = MockOrderRepository();
    paymentGateway = MockPaymentGateway();
    inventory = MockInventoryService();

    handler = CreateOrderCommandHandler(
      orderRepository: orderRepo,
      paymentGateway: paymentGateway,
      inventoryService: inventory,
    );
  });

  test('charges payment and persists order on the happy path', () async {
    when(() => inventory.available(any())).thenAnswer((_) async => 10);
    when(() => paymentGateway.charge(
          userId: any(named: 'userId'),
          amount: any(named: 'amount'),
        )).thenAnswer((_) async => const PaymentResult(transactionId: 'tx_1'));
    when(() => orderRepo.create(
          userId: any(named: 'userId'),
          items: any(named: 'items'),
          shippingAddress: any(named: 'shippingAddress'),
          paymentId: any(named: 'paymentId'),
        )).thenAnswer((_) async => const Order(id: 'order_1', status: OrderStatus.confirmed));

    final result = await handler.run(CreateOrderCommand(
      userId: 'u1',
      items: items,
      shippingAddress: address,
    ));

    expect(result.id, 'order_1');
    verify(() => paymentGateway.charge(userId: 'u1', amount: 20.0)).called(1);
    verify(() => orderRepo.create(
          userId: 'u1',
          items: items,
          shippingAddress: address,
          paymentId: 'tx_1',
        )).called(1);
  });

  test('throws InsufficientInventoryException and skips payment when stock is short', () async {
    when(() => inventory.available('p1')).thenAnswer((_) async => 1);

    expect(
      () => handler.run(CreateOrderCommand(
        userId: 'u1',
        items: items,
        shippingAddress: address,
      )),
      throwsA(isA<InsufficientInventoryException>()
          .having((e) => e.productId, 'productId', 'p1')
          .having((e) => e.requested, 'requested', 2)
          .having((e) => e.available, 'available', 1)),
    );

    verifyNever(() => paymentGateway.charge(
          userId: any(named: 'userId'),
          amount: any(named: 'amount'),
        ));
    verifyNever(() => orderRepo.create(
          userId: any(named: 'userId'),
          items: any(named: 'items'),
          shippingAddress: any(named: 'shippingAddress'),
          paymentId: any(named: 'paymentId'),
        ));
  });
}
```

The `having(...)` chain on `throwsA(isA<...>())` asserts on the typed fields of the exception — exactly what the UI translation will pattern-match on.

### Recovering from an expected exception in a WatchHandler

```dart
// test/cart/watch_cart_query_handler_test.dart
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:my_app/application/cart/watch_cart_query.dart';
import 'package:my_app/domain/cart/cart_exceptions.dart';
import 'package:my_app/domain/cart/i_cart_repository.dart';
import 'package:my_app/domain/cart/shopping_cart.dart';

class MockCartRepository extends Mock implements ICartRepository {}

void main() {
  late WatchCartQueryHandler handler;
  late MockCartRepository cartRepo;

  setUp(() {
    cartRepo = MockCartRepository();
    handler = WatchCartQueryHandler(cartRepository: cartRepo);
  });

  test('yields the repository stream when the cart exists', () {
    final cart = ShoppingCart(userId: 'u1', items: [/* ... */]);
    when(() => cartRepo.watchCart('u1'))
        .thenAnswer((_) => Stream.fromIterable([cart]));

    expectLater(
      handler.watch(WatchCartQuery(userId: 'u1')),
      emitsInOrder([cart, emitsDone]),
    );
  });

  test('yields an empty cart when the repository throws CartNotFoundException', () {
    when(() => cartRepo.watchCart('u1'))
        .thenAnswer((_) => Stream.error(const CartNotFoundException('u1')));

    expectLater(
      handler.watch(WatchCartQuery(userId: 'u1')),
      emitsInOrder([
        predicate<ShoppingCart>((c) => c.isEmpty && c.userId == 'u1'),
        emitsDone,
      ]),
    );
  });

  test('propagates an unexpected exception', () {
    final error = NetworkException(originalError: 'socket-closed');
    when(() => cartRepo.watchCart('u1'))
        .thenAnswer((_) => Stream.error(error));

    expectLater(
      handler.watch(WatchCartQuery(userId: 'u1')),
      emitsInOrder([emitsError(isA<NetworkException>())]),
    );
  });
}
```

The three tests cover the three categories from `chassis-handle-errors`: happy path, recoverable exception → default value, unexpected exception → propagate.

### A pure ReadHandler test

```dart
// test/users/get_user_query_handler_test.dart
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:my_app/application/users/get_user_query.dart';
import 'package:my_app/domain/users/user.dart';
import 'package:my_app/domain/users/i_user_repository.dart';

class MockUserRepository extends Mock implements IUserRepository {}

void main() {
  late GetUserQueryHandler handler;
  late MockUserRepository userRepo;

  setUp(() {
    userRepo = MockUserRepository();
    handler = GetUserQueryHandler(userRepository: userRepo);
  });

  test('returns the user fetched from the repository', () async {
    const user = User(id: 'u1', name: 'Alice', email: 'a@example.test');
    when(() => userRepo.getUser('u1')).thenAnswer((_) async => user);

    final result = await handler.read(GetUserQuery(userId: 'u1'));

    expect(result, user);
    verify(() => userRepo.getUser('u1')).called(1);
  });
}
```

### Optional: Mediator integration test

If you want to verify that `CreateOrderCommand` actually routes to `CreateOrderCommandHandler` through the Mediator — including any registered middleware — write a separate test. This is *not* a handler unit test and belongs under `test/integration/`.

```dart
// test/integration/orders_mediator_test.dart
test('CreateOrderCommand routes to its handler', () async {
  final orderRepo = MockOrderRepository();
  final paymentGateway = MockPaymentGateway();
  final inventory = MockInventoryService();

  final mediator = AppMediator(
    orderRepository: orderRepo,
    paymentGateway: paymentGateway,
    inventoryService: inventory,
  );

  // ...stub the mocks the same way as the unit test...

  final result = await mediator.createOrder(
    userId: 'u1',
    items: [/* ... */],
    shippingAddress: const Address(street: '123 Main St'),
  );

  expect(result.id, 'order_1');
});
```

The integration test catches wiring errors (missing `@chassisHandler`, stale build_runner output) that handler-level tests miss.

### Anti-pattern: instantiating through Mediator for a handler unit test

```dart
// ❌ Pulls in handler registration, type resolution, and middleware — all
// irrelevant to the business logic under test. A failure in any of these
// surfaces as a misleading test name.
test('creates order on happy path', () async {
  final mediator = AppMediator(
    orderRepository: orderRepo,
    paymentGateway: paymentGateway,
    inventoryService: inventory,
  );
  await mediator.createOrder(/* ... */);
});
```

```dart
// ✅ Construct the handler directly. No Mediator, no registration.
final handler = CreateOrderCommandHandler(
  orderRepository: orderRepo,
  paymentGateway: paymentGateway,
  inventoryService: inventory,
);
await handler.run(CreateOrderCommand(/* ... */));
```
