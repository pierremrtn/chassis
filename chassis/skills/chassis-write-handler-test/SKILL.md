---
name: chassis-write-handler-test
description: Write a unit test for a Chassis handler (`CommandHandler`, `ReadHandler`, or `WatchHandler`) by instantiating it directly with mocked repository interfaces — no Mediator, no Flutter, no widget tree — and test ViewModels through the `mediator:` constructor seam, registering fake handlers on a real `Mediator` (never `Chassis.initialize` in tests). Use when adding a `*_handler_test.dart` file, when a handler gains a new branch (validation, recovery, error path) that needs coverage, or when a ViewModel test needs a controlled dispatch path.
---
# Testing a Chassis Handler

## Contents
- [Core Concepts](#core-concepts)
- [Why Direct Instantiation, Not Mediator](#why-direct-instantiation-not-mediator)
- [Tooling: `package:test` + `package:mocktail`](#tooling-packagetest--packagemocktail)
- [Testing a ViewModel Through the Mediator Seam](#testing-a-viewmodel-through-the-mediator-seam)
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

Mocks are declared as `class MockUserRepository extends Mock implements UserRepository {}`, then stubbed with `when(() => mock.method(...)).thenAnswer(...)` and verified with `verify(() => mock.method(...)).called(n)`. When a custom type (an entity, a value object) is matched with `any(...)`, register a fallback instance once in `setUpAll` with `registerFallbackValue(...)`.

## Testing a ViewModel Through the Mediator Seam

Handler tests need no Mediator. ViewModel tests do — a ViewModel dispatches message objects, so the test must control where they land. The seam is the constructor:

```dart
ViewModel(T initial, {Mediator? mediator});
```

The `mediator:` override always wins over the application-wide one, so the recommended setup is a **real `Mediator()` with fake handlers registered** — not a mock of the `Mediator` class:

- A fake handler is ~5 lines and needs no mocking framework; stubbing the generic `run<R>`/`read<R>`/`watch<R>` methods of a mocked Mediator fights type inference.
- Real dispatch keeps the real semantics: keyed watches, `RunPolicy` arbitration, and failures surfacing as soft `AsyncError`s behave exactly as in production.

For dedicated ViewModel test suites, prefer `TestMediator` from `package:chassis/testing.dart` — a `Mediator` subclass that replaces the fake handler classes with closure stubs (`whenRun`/`whenRead`/`whenWatch`) and records every dispatched message for assertions. See `chassis-test-view-model` for the full workflow (state transitions, events, `RunPolicy`, watches).

**Never call `Chassis.initialize` in a test.** It is process-global state that leaks across test cases; the constructor seam exists precisely so tests never touch it. (If a legacy suite did touch it, `Chassis.reset()` is available, `@visibleForTesting` — but prefer the seam.)

ViewModel methods are synchronous (`void submit() => run(...)`), so a test calls the method, settles the queue with `await pumpEventQueue()`, and asserts on `vm.state` and `vm.events`. Events emitted before the first subscription are buffered for the first listener, so `expectLater(vm.events, emits(...))` after the fact still works. These tests run under `flutter_test` (chassis_flutter depends on Flutter foundation), but need no widget tree.

## Rules

- **DO** instantiate the handler directly in `setUp(...)` with mock repositories. *No `Mediator`, no `MaterialApp`, no `WidgetsFlutterBinding` — that is the point of the handler abstraction.*
- **DO** mock against repository **interfaces** (`UserRepository`, `OrderRepository`), never concrete implementations. *Interfaces are the contract the handler depends on; concrete classes drag in infrastructure that should not exist in unit tests.*
- **DO** mirror `lib/`'s structure: `test/<feature>/<handler_name>_test.dart`.
- **DO** organize tests in `setUp` (build the mocks and the handler), one `test(...)` per logical branch (happy path, validation failure, recovery from a domain exception, propagation of an unexpected failure).
- **DO** verify both that the right repository methods were called (`verify(() => mock.create(...)).called(1)`) **and** that the wrong ones were not (`verifyNever(() => mock.charge(...))`). *The latter catches bugs where validation passes but the handler still calls payment.*
- **DO** test thrown domain exceptions with `expect(() => handler.run(...), throwsA(isA<TException>()))` and assert on typed fields when they exist.
- **DO** test stream handlers with `expectLater(stream, emitsInOrder([value1, value2, emitsDone]))` for ordered values and `emitsError(isA<TException>())` for errors.
- **DO** test a ViewModel through its `mediator:` constructor parameter, registering fake handlers on a real `Mediator()`. *The override always wins over the global, and real dispatch keeps keys, policies, and soft errors behaving as in production.*
- **DON'T** call `Chassis.initialize` in tests. *It is process-global state that leaks across test cases; the constructor seam exists so tests never touch it.*
- **CONSIDER** writing one happy-path test per handler at minimum. Add tests for each error / recovery branch the handler explicitly implements.
- **CONSIDER** colocating test data builders (`OrderItem testItem(...)`, `User testUser(...)`) in a shared `test/_fixtures/` directory when the same shapes appear across many tests.
- **DON'T** test the Mediator wiring at this layer. *Use a separate integration test file (`test/integration/<feature>_mediator_test.dart`) — see the bottom example.*
- **DON'T** mock the handler under test. *That is what you are trying to verify.*
- **DON'T** assert on log output, telemetry calls, or middleware behavior in a handler unit test. *Those are observable through middleware and tested separately.*

## Workflow

- [ ] **Step 1 — Place the file** at `test/<feature>/<handler_name>_test.dart`, mirroring the source path.
- [ ] **Step 2 — Declare mocks** for every repository / service the handler injects: `class MockOrderRepository extends Mock implements OrderRepository {}`. Register fallback values for custom types matched with `any(...)`.
- [ ] **Step 3 — Set up** in `setUp(...)`. Construct each mock, then construct the handler with the mocks through its ordinary constructor (named parameters for 2+ dependencies, positional for one). See `chassis-register-handler-with-codegen`.
- [ ] **Step 4 — Cover the happy path** in the first test. Stub each mock method with `when(...).thenAnswer(...)`, dispatch the command / query, assert on the return value, verify the right methods were called.
- [ ] **Step 5 — Cover the failure paths.** One test per business rule failure (`InsufficientInventoryException`), one per recoverable domain exception the handler converts (`CartNotFoundException` → empty cart), one per propagated unexpected failure if the assertion is meaningful.
- [ ] **Step 6 — For stream handlers**, use `emitsInOrder` with the expected sequence including `emitsDone` if the stream is finite.
- [ ] **Step 7 — For ViewModel tests**, build `Mediator()..registerCommandHandler(...)..registerQueryHandler(...)` with fake handlers, pass it via `mediator:`, call the synchronous ViewModel method, `await pumpEventQueue()`, then assert on `state` and `events`.
- [ ] **Step 8 — Run** with `dart test test/<feature>/` (or `flutter test` for ViewModel tests).

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
import 'package:my_app/domain/orders/order_repository.dart';
import 'package:my_app/domain/payments/payment_gateway.dart';
import 'package:my_app/domain/inventory/inventory_service.dart';

class MockOrderRepository extends Mock implements OrderRepository {}
class MockPaymentGateway extends Mock implements PaymentGateway {}
class MockInventoryService extends Mock implements InventoryService {}

void main() {
  late CreateOrderCommandHandler handler;
  late MockOrderRepository orderRepo;
  late MockPaymentGateway paymentGateway;
  late MockInventoryService inventory;

  final items = [
    const OrderItem(productId: 'p1', quantity: 2, price: 10.0),
  ];
  final address = const Address(street: '123 Main St');

  setUpAll(() {
    // mocktail needs a fallback instance for custom types matched with any().
    registerFallbackValue(const Address(street: ''));
    registerFallbackValue(const OrderItem(productId: '', quantity: 0, price: 0));
  });

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
import 'package:my_app/domain/cart/cart_repository.dart';
import 'package:my_app/domain/cart/shopping_cart.dart';

class MockCartRepository extends Mock implements CartRepository {}

void main() {
  late WatchCartQueryHandler handler;
  late MockCartRepository cartRepo;

  setUp(() {
    cartRepo = MockCartRepository();
    handler = WatchCartQueryHandler(cartRepo);
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
import 'package:my_app/domain/users/user_repository.dart';

class MockUserRepository extends Mock implements UserRepository {}

void main() {
  late GetUserQueryHandler handler;
  late MockUserRepository userRepo;

  setUp(() {
    userRepo = MockUserRepository();
    handler = GetUserQueryHandler(userRepo);
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

### Testing a ViewModel: real Mediator, fake handlers

*`TestMediator` (`package:chassis/testing.dart`) supersedes the hand-rolled fakes below with `whenRun`/`whenRead`/`whenWatch` closure stubs — see `chassis-test-view-model`. The hand-rolled version remains valid and shows the mechanics the helper wraps.*

```dart
// test/user_profile/user_profile_view_model_test.dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/application/users/get_user_query.dart';
import 'package:my_app/application/users/update_user_email_command.dart';
import 'package:my_app/domain/users/user.dart';
import 'package:my_app/domain/users/user_exceptions.dart';
import 'package:my_app/presentation/user_profile/user_profile_view_model.dart';

// The ViewModel under test dispatches message objects; its methods are
// synchronous and expression-bodied:
//
//   class UserProfileViewModel
//       extends ViewModel<UserProfileState, UserProfileEvent> {
//     UserProfileViewModel({required this.userId, super.mediator})
//         : super(UserProfileState.initial());
//
//     final String userId;
//
//     void loadUser() => read(
//           GetUserQuery(userId: userId),
//           current: state.user,
//           onState: (user) => setState(state.copyWith(user: user)),
//         );
//
//     void updateEmail(String email) => run(
//           UpdateUserEmailCommand(userId: userId, newEmail: email),
//           onSuccess: (_) => sendEvent(const UserUpdatedEvent()),
//           onError: (error, stack) => sendEvent(UserUpdateFailedEvent(error)),
//         );
//   }

/// Fake handlers: ~5 lines each, no mocking framework needed.
class FakeGetUserHandler(
  final Future<User> Function(GetUserQuery query) onRead,
) implements ReadHandler<GetUserQuery, User> {
  @override
  Future<User> read(GetUserQuery query) => onRead(query);
}

class FakeUpdateUserEmailHandler(
  final Future<void> Function(UpdateUserEmailCommand command) onRun,
) implements CommandHandler<UpdateUserEmailCommand, void> {
  @override
  Future<void> run(UpdateUserEmailCommand command) => onRun(command);
}

void main() {
  const user = User(id: 'u1', name: 'Alice', email: 'a@example.test');

  test('loadUser publishes loading then data into state', () async {
    final mediator = Mediator()
      ..registerQueryHandler(FakeGetUserHandler((_) async => user));
    final vm = UserProfileViewModel(userId: 'u1', mediator: mediator);

    vm.loadUser();
    expect(vm.state.user, const Async<User>.loading());

    await pumpEventQueue();
    expect(vm.state.user, const Async.data(user));
  });

  test('a failing handler surfaces as AsyncError in state', () async {
    final mediator = Mediator()
      ..registerQueryHandler(
          FakeGetUserHandler((_) async => throw NetworkException()));
    final vm = UserProfileViewModel(userId: 'u1', mediator: mediator);

    vm.loadUser();
    await pumpEventQueue();

    expect(vm.state.user.errorOrNull, isA<NetworkException>());
  });

  test('a failed command emits an event carrying the error object', () async {
    final mediator = Mediator()
      ..registerQueryHandler(FakeGetUserHandler((_) async => user))
      ..registerCommandHandler(
          FakeUpdateUserEmailHandler((_) async => throw NetworkException()));
    final vm = UserProfileViewModel(userId: 'u1', mediator: mediator);

    vm.updateEmail('new@example.test');

    // Events sent before the first subscription are buffered for it.
    await expectLater(
      vm.events,
      emits(isA<UserUpdateFailedEvent>()
          .having((e) => e.error, 'error', isA<NetworkException>())),
    );
  });
}
```

No `Chassis.initialize` anywhere: the `mediator:` override wins over the global, and each test owns a fresh, isolated dispatch path. Because the Mediator is real, keyed watches, `RunPolicy` arbitration, and soft `AsyncError`s behave exactly as in production.

### Optional: Mediator integration test

If you want to verify that `CreateOrderCommand` actually routes to `CreateOrderCommandHandler` through the Mediator — including any registered middleware — write a separate test against the generated `AppMediator`. The generated mediator is *only* a registration constructor: every handler dependency is a required named parameter (named after the dependency's type, decapitalized), so mocks slot straight in; dispatch itself goes through the inherited `run`/`read`/`watch`. This is *not* a handler unit test and belongs under `test/integration/`.

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

  final order = await mediator.run(CreateOrderCommand(
    userId: 'u1',
    items: [/* ... */],
    shippingAddress: const Address(street: '123 Main St'),
  ));

  expect(order.id, 'order_1');
});
```

The integration test catches wiring drift (stale `build_runner` output, hand-registered handlers diverging from the generated constructor) that handler-level tests miss. Most wiring mistakes never get this far: a message reachable from the `@ChassisApp` graph with no handler is a *build* error (see `chassis-register-handler-with-codegen`). At runtime, dispatching an unregistered type throws `HandlerNotRegisteredError` — a Dart `Error`, a wiring bug to fix, never a case to catch.

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
  await mediator.run(CreateOrderCommand(/* ... */));
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
