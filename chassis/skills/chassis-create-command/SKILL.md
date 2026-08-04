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

`Command` also exposes `Map<String, Object?> get params => const {}` for observability. Overriding it makes `toString()` render `CreateOrderCommand{userId: u1}` and makes `LoggingMiddleware` traces useful instead of a bare type name.

## Rules

- **DO** declare the message as `final class <Verb><Resource>Command extends Command<TReturn>`. *The Mediator's runtime type lookup depends on the `extends` chain; `Command` is a base class, so `implements` does not compile in consuming packages and would break dispatch anyway.*
- **DO** make the command immutable with `final` fields and a named-parameter constructor (unnamed, generative — the generated typed method rebuilds the message from its own parameters). *Commands are data carriers; mutability after construction breaks log/replay safety. `Command` has no const constructor, so subclasses cannot be `const` either.*
- **DO** override `params` to expose the command's fields for logging (`{'userId': userId}`). *`toString()` and `LoggingMiddleware` render it, turning a trace into `CreateOrderCommand{userId: u1}`.* **Never include secrets — passwords, tokens, card numbers — in `params`.**
- **DO** name commands after business operations (`SubmitOrderCommand`, `UpdateUserEmailCommand`), not technical implementations (`DoUpdate`, `OrderProcessor`). *The command name is part of the application's discoverable capability surface — it also derives the generated method name (`SubmitOrderCommandHandler` → `mediator.submitOrder(...)`).*
- **DO** make the command self-contained — carry every parameter the handler needs. *Handlers must not reach for external context the command did not declare.*
- **CONSIDER** validating constructor inputs with `assert` or guard throws when constraints are known. *Catches invalid state at the call site before the handler runs.*
- **DO** declare the handler as `class <CommandName>Handler implements CommandHandler<TCommand, TReturn>`. *The naming is mechanical: command name + `Handler`. The `implements` keyword forces explicit method signatures.*
- **DO** keep the handler stateless — no fields outside injected dependencies. *Stateless handlers are testable in isolation with no Flutter or Mediator setup.*
- **DO** give the handler an unnamed generative constructor whose parameters are its dependencies, and **PREFER named parameters** (`CreateOrderHandler({required this.orderRepository})`), especially with two or more dependencies. *`chassis_builder` instantiates handlers itself and passes each dependency back the way it is declared; named parameters keep call sites and tests unambiguous.* See `chassis-register-handler-with-codegen`.
- **DO** annotate the handler with `@chassisHandler` so it is picked up by the code generator and registered in the generated mediator. *Without the annotation, the handler exists but the Mediator does not know about it.*
- **DO** depend on repository **interfaces** (e.g. `UserRepository`), never concrete implementations (`FirestoreUserRepository`). *The Dependency Rule keeps the Application layer independent of infrastructure choices.*
- **DON'T** put business logic on the Command class itself. *The command is a DTO; logic lives in the handler.*
- **DON'T** catch infrastructure exceptions inside the handler. *Repositories map infrastructure errors to domain exceptions; the handler propagates them.* See `chassis-handle-errors`.
- **DON'T** dispatch raw command instances from ViewModels — use the typed method on the generated mediator (`mediator.submitOrder(...)`). *The typed method is the discoverability surface and keeps the call site compile-checked; both routes dispatch through `run`, so middlewares apply either way.*

## Workflow

- [ ] **Step 1 — Name the command.** Use `[Verb][Resource]Command` with an imperative present-tense verb (`Create`, `Update`, `Submit`, `Delete`, `Process`). The handler name is mechanically `<CommandName>Handler`, and the generated method name is the command name minus `Command`, decapitalized.
- [ ] **Step 2 — Choose the return type.** `Command<void>` for fire-and-forget operations, `Command<TEntity>` when the operation produces a value the caller needs (the created entity, a transaction id, etc.).
- [ ] **Step 3 — Declare the message.** `final class <Name>Command extends Command<TReturn>` with `final` fields and a named-parameter constructor. Override `params` with the loggable fields (no secrets). Optionally add `assert` validation in the initializer list.
- [ ] **Step 4 — Write the handler.** `class <Name>CommandHandler implements CommandHandler<<Name>Command, TReturn>`. Inject repositories and services as constructor parameters typed against their interfaces (prefer named). Implement `Future<TReturn> run(<Name>Command command)`.
- [ ] **Step 5 — Document thrown exceptions** on the handler class with a `///` doc comment listing every domain exception `run()` may throw. *This is the contract consumers (other handlers, ViewModels) read.*
- [ ] **Step 6 — Annotate the handler.** Place `@chassisHandler` on the class so `chassis_builder` registers it.
- [ ] **Step 7 — Co-locate the file.** Put the message and handler together: `application/<feature>/<command_name>_command.dart`, exported from the feature barrel so the composition root reaches it. One command-handler pair per file. See `chassis-organize-feature`.
- [ ] **Step 8 — Regenerate the mediator.** Run `dart run build_runner build --delete-conflicting-outputs`. See `chassis-register-handler-with-codegen` for details, watch mode, and build errors.
- [ ] **Step 9 — Dispatch from a ViewModel** through the generated typed method (`mediator.submitOrder(...)`), wrapped by the ViewModel's `run()`. See `chassis-create-view-model`.

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
      {'userId': userId, 'items': items.length};
}

/// Creates an order by validating inventory, processing payment, and persisting the result.
///
/// Throws [InsufficientInventoryException] if any requested item is out of stock.
/// Throws [PaymentDeclinedException] if the payment gateway rejects the charge.
@chassisHandler
class CreateOrderHandler
    implements CommandHandler<CreateOrderCommand, Order> {
  CreateOrderHandler({
    required this.orderRepository,
    required this.paymentGateway,
  });

  final OrderRepository orderRepository;
  final PaymentGateway paymentGateway;

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
class UpdateUserEmailCommandHandler
    implements CommandHandler<UpdateUserEmailCommand, void> {
  UpdateUserEmailCommandHandler({required this.userRepository});

  final UserRepository userRepository;

  @override
  Future<void> run(UpdateUserEmailCommand command) =>
      userRepository.updateEmail(command.userId, command.newEmail);
}
```

### Never log secrets

```dart
final class LoginCommand extends Command<Session> {
  LoginCommand({required this.username, required this.password});

  final String username;
  final String password;

  // ✅ The password is deliberately absent from params.
  @override
  Map<String, Object?> get params => {'username': username};
}
```

`params` flows into `toString()`, `LoggingMiddleware` records, and any crash-reporting middleware. A password included here would end up in console logs and telemetry.

### Dispatching from a ViewModel

```dart
class CheckoutViewModel extends ViewModel<CheckoutState, CheckoutEvent> {
  CheckoutViewModel(this._mediator) : super(CheckoutState.initial());

  final AppMediator _mediator;

  void submit(List<OrderItem> items, Address address) {
    run(
      () => _mediator.createOrder(
        userId: state.userId,
        items: items,
        shippingAddress: address,
      ),
      onSuccess: (order) => sendEvent(OrderConfirmedEvent(order.id)),
      onError: (error) => sendEvent(OrderFailedEvent(error)),
    );
  }
}
```

`_mediator.createOrder(...)` is the typed instance method generated from the `@chassisHandler`-annotated handler; the ViewModel keeps an `AppMediator`-typed field to reach it. It returns `Future<Order>`, which the ViewModel's `run()` wraps with `Async<T>` lifecycle handling.

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
// ✅ Unnamed constructor; dependencies as named parameters.
@chassisHandler
class UpdateUserEmailCommandHandler
    implements CommandHandler<UpdateUserEmailCommand, void> {
  UpdateUserEmailCommandHandler({required this.userRepository});
  final UserRepository userRepository;
  // ...
}
```

Write the command and handler by hand, even when the handler is a one-line pass-through to the repository. The manual handler keeps room for validation, multi-step orchestration, and error mapping to grow into.
