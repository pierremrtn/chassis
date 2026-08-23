---
name: chassis-create-command
description: Implement a state-mutating operation in a Chassis application as a `Command` paired with a hand-written `CommandHandler`, registered via `@chassisHandler`. Use when adding a write operation — create, update, delete, submit, process, or any side-effect-producing action — to the application layer.
---
# Creating a Chassis Command

## Contents
- [Core Concepts](#core-concepts)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

A **Command** is an immutable message that expresses intent to change application state. A **CommandHandler** is the stateless class that executes that intent — it receives the command, calls one or more repositories, and returns the result. Commands and handlers live in the Application layer, dispatched through the Mediator.

Command-Query Separation is the underlying principle:

> Methods should either change state or return data, never both. When you see a Query in code, you know it's safe to call multiple times without unintended consequences. When you see a Command, you understand that state will change and execution should be deliberate.
> — `docs/coding_rules.md`

The runtime contract is mechanical: the Mediator looks up handlers by the command's runtime type. Messages must `extend Command<T>` (`Command` is a base class — `implements` breaks dispatch); handlers must `implement CommandHandler<C, T>` (they fulfill a behavioral contract without inheriting state).

`Command` exposes `Map<String, Object?> get params => const {}` for observability **and identity**. Overriding it makes `toString()` render `CreateOrderCommand{userId: u1}` and makes `LoggingMiddleware` traces useful instead of a bare type name — and it is also the message's identity: `==` and `hashCode` are derived from the runtime type plus `params`. **Two messages of the same type with equal `params` are the same operation.** Caching and deduplication middlewares (and tooling) rely on this contract, so a field that affects the operation but is left out of `params` breaks it.

## Rules

- **DO** declare the message as `final class <Verb><Resource>Command extends Command<TReturn>`. *The Mediator's runtime type lookup depends on the `extends` chain; `Command` is a base class, so `implements` does not compile in consuming packages and would break dispatch anyway.*
- **DO** make the command immutable — declare its fields as `required final` named parameters in the primary-constructor header (`final class FooCommand({required final String userId}) extends Command<void>`). *Commands are data carriers with structural equality; mutability after construction breaks identity, caching, and log/replay safety. `Command` has no const constructor, so subclasses cannot be `const` either.*
- **DO** override `params` with **every field that affects the operation** (`{'userId': userId}`). *`params` is both the trace (`toString()` and `LoggingMiddleware` render `CreateOrderCommand{userId: u1}`) and the identity: same type + equal `params` = same operation. A field left out of `params` makes two different operations compare equal — broken caching and deduplication.* **Never include secrets — passwords, tokens, card numbers — in `params`.**
- **DO** name commands after business operations (`SubmitOrderCommand`, `UpdateUserEmailCommand`), not technical implementations (`DoUpdate`, `OrderProcessor`). *The command name is the application's discoverable capability surface: it is what ViewModels dispatch and what every log line shows.*
- **DO** make the command self-contained — carry every parameter the handler needs. *Handlers must not reach for external context the command did not declare.*
- **CONSIDER** validating constructor inputs with `assert` or guard throws when constraints are known. *Catches invalid state at the call site before the handler runs.*
- **DO** declare the handler as `class <CommandName>Handler implements CommandHandler<TCommand, TReturn>`. *The naming is mechanical: command name + `Handler` (`CreateOrderCommand` → `CreateOrderCommandHandler`). The `implements` keyword forces explicit method signatures.*
- **DO** keep the handler stateless — no fields outside injected dependencies. *Stateless handlers are testable in isolation with no Flutter or Mediator setup.*
- **DO** give the handler a primary constructor — the unnamed generative constructor — whose `final` parameters are its dependencies, and **PREFER named parameters** (`class CreateOrderCommandHandler({required final OrderRepository orderRepository}) implements ...`), especially with two or more dependencies. *`chassis_builder` instantiates handlers itself and passes each dependency back the way it is declared; named parameters keep call sites and tests unambiguous.* See `chassis-register-handler-with-codegen`.
- **DO** annotate the handler with `@chassisHandler` so it is picked up by the code generator and registered in the generated mediator's constructor. *A concrete command reachable from the `@ChassisApp` graph with no handler is a **build error** — dispatching it could only throw at runtime, so the build fails instead. Annotate the message with `@unhandledMessage` to opt out while the handler is being written.*
- **DO** depend on repository **interfaces** (e.g. `UserRepository`), never concrete implementations (`FirestoreUserRepository`). *The Dependency Rule keeps the Application layer independent of infrastructure choices.*
- **DON'T** put business logic on the Command class itself. *The command is a DTO; logic lives in the handler.*
- **DON'T** catch infrastructure exceptions inside the handler. *Repositories map infrastructure errors to domain exceptions; the handler propagates them.* See `chassis-handle-errors`.
- **DON'T** inject the `Mediator` (or the generated mediator) into a handler to dispatch other commands or queries — the generator rejects it at build time. *A multi-step flow is one command whose handler composes the repositories it needs; behavior shared between handlers lives in a service injected into both. Handler-to-handler dispatch would hide the dependency graph from constructor signatures and re-enter the middleware chain.*
- **DON'T** reference the generated mediator from a ViewModel — dispatch the command object itself with the ViewModel's `run(...)`. *ViewModels never name the generated class: `run` routes the message through the mediator installed by `Chassis.initialize` (or the constructor override, in tests), so middlewares always apply. The generated mediator appears only at the composition root.*

## Workflow

- [ ] **Step 1 — Name the command.** Use `[Verb][Resource]Command` with an imperative present-tense verb (`Create`, `Update`, `Submit`, `Delete`, `Process`). The handler name is mechanically `<CommandName>Handler`.
- [ ] **Step 2 — Choose the return type.** `Command<void>` for fire-and-forget operations, `Command<TEntity>` when the operation produces a value the caller needs (the created entity, a transaction id, etc.).
- [ ] **Step 3 — Declare the message.** `final class <Name>Command({required final T field, ...}) extends Command<TReturn>` — the primary-constructor header's `final` named parameters declare the fields. Override `params` with every operation-affecting field (no secrets). A constructor `assert` needs an initializer list, so a message that validates its inputs keeps a classic constructor instead.
- [ ] **Step 4 — Write the handler.** `class <Name>CommandHandler(...) implements CommandHandler<<Name>Command, TReturn>`. Inject repositories and services as `final` primary-constructor parameters typed against their interfaces (prefer named). Implement `Future<TReturn> run(<Name>Command command)`.
- [ ] **Step 5 — Document thrown exceptions** on the handler class with a `///` doc comment listing every domain exception `run()` may throw. *This is the contract consumers (ViewModels routing errors to state or events) read.*
- [ ] **Step 6 — Annotate the handler.** Place `@chassisHandler` on the class so `chassis_builder` registers it.
- [ ] **Step 7 — Co-locate the file.** Put the message and handler together: `application/<feature>/<command_name>_command.dart`, exported from the feature barrel so the composition root reaches it. One command-handler pair per file. See `chassis-organize-feature`.
- [ ] **Step 8 — Regenerate the mediator.** Run `dart run build_runner build --delete-conflicting-outputs`. The build fails if a reachable concrete command has no handler — that is the point: missing wiring surfaces at build time, not at first dispatch. See `chassis-register-handler-with-codegen` for details, watch mode, and build errors.
- [ ] **Step 9 — Dispatch from a ViewModel** by passing the command object to the ViewModel's `run(...)` in a synchronous, expression-bodied method. Always cover the error path — provide `onState` or `onError`. See `chassis-create-view-model`.

## Examples

### Command with a return value

```dart
// application/orders/create_order_command.dart
import 'package:chassis/chassis.dart';
import '../../domain/orders/order_repository.dart';
import '../../domain/orders/order.dart';
import '../../domain/orders/order_item.dart';
import '../../domain/orders/order_exceptions.dart';
import '../../domain/payments/payment_gateway.dart';

final class CreateOrderCommand extends Command<Order> {
  // The assert needs an initializer list, so this message keeps a classic
  // constructor instead of a primary one.
  CreateOrderCommand({
    required this.userId,
    required this.items,
    required this.shippingAddress,
  }) : assert(items.length > 0, 'Order must contain at least one item');

  final String userId;
  final List<OrderItem> items;
  final Address shippingAddress;

  @override
  Map<String, Object?> get params =>
      {'userId': userId, 'items': items, 'shippingAddress': shippingAddress};
}

/// Creates an order by validating inventory, processing payment, and persisting the result.
///
/// Throws [InsufficientInventoryException] if any requested item is out of stock.
/// Throws [PaymentDeclinedException] if the payment gateway rejects the charge.
@chassisHandler
class CreateOrderCommandHandler({
  required final OrderRepository orderRepository,
  required final PaymentGateway paymentGateway,
}) implements CommandHandler<CreateOrderCommand, Order> {
  @override
  Future<Order> run(CreateOrderCommand command) async {
    final total = command.items.fold<double>(
      0,
      (sum, item) => sum + item.price * item.quantity,
    );

    final payment = await paymentGateway.charge(
      userId: command.userId,
      amount: total,
    );

    return orderRepository.create(
      userId: command.userId,
      items: command.items,
      shippingAddress: command.shippingAddress,
      paymentId: payment.transactionId,
    );
  }
}
```

### Command with no return value

```dart
// application/users/update_user_email_command.dart
import 'package:chassis/chassis.dart';
import '../../domain/users/user_repository.dart';

final class UpdateUserEmailCommand extends Command<void> {
  // assert → initializer list → classic constructor.
  UpdateUserEmailCommand({
    required this.userId,
    required this.newEmail,
  }) : assert(newEmail.length > 0, 'Email cannot be empty');

  final String userId;
  final String newEmail;

  @override
  Map<String, Object?> get params =>
      {'userId': userId, 'newEmail': newEmail};
}

@chassisHandler
class UpdateUserEmailCommandHandler({
  required final UserRepository userRepository,
}) implements CommandHandler<UpdateUserEmailCommand, void> {
  @override
  Future<void> run(UpdateUserEmailCommand command) =>
      userRepository.updateEmail(command.userId, command.newEmail);
}
```

### `params` is identity — include every operation-affecting field

```dart
// ❌ quantity affects the operation but is missing from params:
// SetQuantityCommand(itemId: 'a', quantity: 1)
//     == SetQuantityCommand(itemId: 'a', quantity: 5)
// A deduplicating middleware would treat them as the same operation.
final class SetQuantityCommand({
  required final String itemId,
  required final int quantity,
}) extends Command<void> {
  @override
  Map<String, Object?> get params => {'itemId': itemId};
}
```

```dart
// ✅ Every field that shapes the operation is part of the identity.
final class SetQuantityCommand({
  required final String itemId,
  required final int quantity,
}) extends Command<void> {
  @override
  Map<String, Object?> get params => {'itemId': itemId, 'quantity': quantity};
}
```

`==` and `hashCode` are derived from the runtime type plus `params` — the base class does it; never hand-roll equality on a message.

### Never log secrets

```dart
final class LoginCommand({
  required final String username,
  required final String password,
}) extends Command<Session> {
  // ✅ The password is deliberately absent from params.
  @override
  Map<String, Object?> get params => {'username': username};
}
```

`params` flows into `toString()`, `LoggingMiddleware` records, and any crash-reporting middleware. A password included here would end up in console logs and telemetry.

### Dispatching from a ViewModel

```dart
class CheckoutViewModel extends ViewModel<CheckoutState, CheckoutEvent> {
  CheckoutViewModel({super.mediator}) : super(CheckoutState.initial());

  void submit(List<OrderItem> items, Address address) => run(
        CreateOrderCommand(
          userId: state.userId,
          items: items,
          shippingAddress: address,
        ),
        policy: const RunPolicy.droppable(), // a double-tap cannot dispatch twice
        onSuccess: (order) => sendEvent(OrderConfirmedEvent(order.id)),
        onError: (error, stack) => sendEvent(OrderFailedEvent(error)),
      );
}
```

The ViewModel dispatches the command object itself — it holds no mediator field and never names the generated class. `run` routes the message through the mediator installed by `Chassis.initialize(...)` at startup (or the `mediator:` constructor override, the testing seam), wraps the result in `Async<Order>` lifecycle handling, and reports through the callbacks. The run key defaults to the command's runtime type, so every `CreateOrderCommand` dispatch shares the droppable policy. `onError` receives the error **object** — `OrderFailedEvent(error)` carries it as-is, never `error.toString()`, so listeners can still pattern-match.

### Anti-pattern: no unnamed generative constructor

```dart
// ❌ Build error: "has no unnamed generative constructor." The generator
// instantiates handlers itself; a factory or named constructor gives it
// nothing to call.
@chassisHandler
class UpdateUserEmailCommandHandler
    implements CommandHandler<UpdateUserEmailCommand, void> {
  UpdateUserEmailCommandHandler.create({required this.userRepository});
  final UserRepository userRepository;
  // ...
}
```

```dart
// ✅ Primary constructor — unnamed, generative; dependencies as named
// parameters.
@chassisHandler
class UpdateUserEmailCommandHandler({
  required final UserRepository userRepository,
}) implements CommandHandler<UpdateUserEmailCommand, void> {
  // ...
}
```

Write the command and handler by hand, even when the handler is a one-line pass-through to the repository. The manual handler keeps room for validation, multi-step orchestration, and error mapping to grow into.
