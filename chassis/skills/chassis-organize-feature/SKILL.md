---
name: chassis-organize-feature
description: Lay out the directory and file structure for a Chassis feature — Presentation, Application, Domain, and Infrastructure folders, one Command/Query-Handler pair per file, ViewModel + State + Event colocated under the screen they serve. Use when starting a new feature, refactoring an existing folder that has drifted, or deciding where a new file should live.
---
# Organizing a Chassis Feature

## Contents
- [Core Concepts](#core-concepts)
- [The Four Layers](#the-four-layers)
- [Two Layouts: Layer-First vs Feature-First](#two-layouts-layer-first-vs-feature-first)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

Chassis enforces a layered architecture. The directory structure should make those layers visible at a glance — opening any feature folder should immediately answer "what does this feature *do*" by listing its commands and queries, and "how does it talk to the outside world" by listing its repositories and adapters.

> Each message-handler pair should live in its own file. Co-locating the message definition with its handler makes it easy to navigate: finding a Command immediately reveals the logic that handles it, and vice versa. (...) Splitting each pair into its own file enforces the single-responsibility principle at the file level and makes the project's capabilities scannable from the directory listing alone.
> — `docs/coding_rules.md`

The layout is not bureaucracy. The capabilities of a feature are the list of files in `application/<feature>/`. The contract with the outside world is the list of files in `domain/<feature>/`. A new contributor can read those two folders and know what the feature can do.

## The Four Layers

| Layer | Lives in | Owns | Depends on |
|---|---|---|---|
| **Presentation** | `presentation/` | Widgets, ViewModels, State, Events | the Mediator (via the generated extension) |
| **Application** | `application/` | Commands, Queries, Handlers | repository **interfaces** from `domain/` |
| **Domain** | `domain/` | Entities, value objects, repository interfaces, domain exceptions | nothing inside the project |
| **Infrastructure** | `infrastructure/` | Repository implementations, third-party adapters | external SDKs (Firebase, Dio, isar) |

`domain/` is the inner-most layer with no inward dependencies. `application/` depends on `domain/` interfaces. `presentation/` depends on the Mediator (which is generated from `application/` annotations). `infrastructure/` implements `domain/` interfaces and is wired into the composition root.

## Two Layouts: Layer-First vs Feature-First

Both layouts respect the architecture; pick one and stay consistent across the project.

**Feature-first** (recommended for medium and large apps): each feature owns its four layers under one folder.

```
lib/features/orders/
  ├── presentation/
  ├── application/
  ├── domain/
  └── infrastructure/
```

Adding a feature means creating one folder. Removing a feature means deleting one folder. Cross-feature dependencies — when a handler in `orders/application/` needs `users/domain/i_user_repository.dart` — are explicit imports across feature boundaries.

**Layer-first** (acceptable for small apps and tutorials): the four layers are top-level folders.

```
lib/
  ├── presentation/
  ├── application/
  ├── domain/
  └── infrastructure/
```

Simpler at small scale; harder to keep tidy as features multiply. The Quick Start tutorial uses this layout for brevity.

## Rules

- **DO** organize code into the four layers (Presentation, Application, Domain, Infrastructure). *The architecture rests on this separation; every other rule assumes it.*
- **DO** put each Command / Query and its handler in **one file** — `<message_name>_command.dart` or `<message_name>_query.dart`. *Co-location maps the application's capabilities to the directory listing.*
- **DO** use snake_case file names matching the message name: `create_order_command.dart` for `CreateOrderCommand`, `watch_user_profile_query.dart` for `WatchUserProfileQuery`.
- **DO** colocate a screen's `ViewModel`, `State`, and `Event` files under the screen folder. *They evolve together; splitting them across the project creates merge conflicts and navigation friction.*
- **DO** put repository **interfaces** in `domain/<feature>/i_<resource>_repository.dart`. *The interface is part of the domain contract; the implementation is infrastructure.*
- **DO** put repository **implementations** in `infrastructure/<feature>/<provider>_<resource>_repository.dart` (e.g. `firestore_user_repository.dart`, `dio_payment_gateway.dart`). *Naming the provider in the file name makes swap-out obvious.*
- **DO** declare entities, value objects, and domain exceptions under `domain/<feature>/`. *They are the language the rest of the layers speak.*
- **DO** keep test files mirroring the source structure: `test/<feature>/application/<handler>_test.dart`, `test/<feature>/presentation/<view_model>_test.dart`. See `chassis-write-handler-test`.
- **PREFER** the feature-first layout for any application beyond a tutorial. *Layer-first scales poorly past a handful of features.*
- **CONSIDER** prefixing repository interfaces with `I` (`IOrderRepository`). The Chassis docs use this convention; follow what the rest of the project uses.
- **CONSIDER** a per-feature `barrel` file (`features/orders/orders.dart`) re-exporting the public-facing classes if the feature is consumed from many places. *Optional — avoid if it adds noise.*
- **DON'T** put two unrelated commands in the same file. *Each command's file is its own SRP boundary; one growing file becomes a junk drawer.*
- **DON'T** put repository implementations under `application/` or `domain/`. *Implementations belong to infrastructure; mixing them in inner layers reverses the Dependency Rule.*
- **DON'T** scatter ViewModel and State across `presentation/` and `state/`. *They are one logical unit; keep them in the same folder as the screen.*
- **DON'T** create a separate `models/` folder for domain entities. *Entities are part of `domain/`; a flat `models/` folder erases the layer boundary the architecture relies on.*

## Workflow

- [ ] **Step 1 — Pick or follow the project's layout.** If the project already has `lib/features/...`, keep using feature-first. If it has top-level `lib/presentation/`, `lib/application/`, etc., keep layer-first.
- [ ] **Step 2 — Create the feature folder** (feature-first) or skip (layer-first). Inside it, create `presentation/`, `application/`, `domain/`, `infrastructure/` only as needed — empty folders are noise.
- [ ] **Step 3 — Define the domain.** `domain/<feature>/` gets the entities, value objects, repository interfaces (`i_<resource>_repository.dart`), and domain exceptions. *No imports from `application/`, `presentation/`, or `infrastructure/`.*
- [ ] **Step 4 — Implement the repositories.** `infrastructure/<feature>/<provider>_<resource>_repository.dart` implements the domain interface and maps infrastructure exceptions to domain exceptions. See `chassis-handle-errors`.
- [ ] **Step 5 — Author the application layer.** `application/<feature>/<message_name>_command.dart` (or `_query.dart`) — one Command/Query + its handler per file, co-located. See `chassis-create-command`, `chassis-create-read-query`, `chassis-create-watch-query`.
- [ ] **Step 6 — Build the presentation layer.** `presentation/<screen_name>/<screen_name>_screen.dart`, `<screen_name>_view_model.dart`, `<screen_name>_state.dart`, `<screen_name>_event.dart` — co-located. See `chassis-create-view-model`.
- [ ] **Step 7 — Mirror the structure under `test/`** for unit tests of handlers and view models.

## Examples

### Feature-first layout for a complete feature

```
lib/features/orders/
  ├── domain/
  │   ├── order.dart                            # entity
  │   ├── order_item.dart                       # value object
  │   ├── order_status.dart                     # enum
  │   ├── order_exceptions.dart                 # InsufficientInventoryException, PaymentDeclinedException
  │   └── i_order_repository.dart               # interface
  ├── application/
  │   ├── create_order_command.dart             # CreateOrderCommand + CreateOrderCommandHandler
  │   ├── cancel_order_command.dart             # CancelOrderCommand + CancelOrderCommandHandler
  │   ├── get_order_query.dart                  # GetOrderQuery + GetOrderQueryHandler
  │   └── watch_order_status_query.dart         # WatchOrderStatusQuery + WatchOrderStatusQueryHandler
  ├── infrastructure/
  │   └── firestore_order_repository.dart       # FirestoreOrderRepository implements IOrderRepository
  └── presentation/
      ├── order_list/
      │   ├── order_list_screen.dart
      │   ├── order_list_view_model.dart
      │   ├── order_list_state.dart
      │   └── order_list_event.dart
      └── order_detail/
          ├── order_detail_screen.dart
          ├── order_detail_view_model.dart
          ├── order_detail_state.dart
          └── order_detail_event.dart
```

The `application/` listing alone — `create_order_command.dart`, `cancel_order_command.dart`, `get_order_query.dart`, `watch_order_status_query.dart` — answers the question "what does the orders feature do?".

### Layer-first layout (small project)

```
lib/
  ├── domain/
  │   ├── orders/
  │   │   ├── order.dart
  │   │   ├── order_exceptions.dart
  │   │   └── i_order_repository.dart
  │   └── users/
  │       ├── user.dart
  │       └── i_user_repository.dart
  ├── application/
  │   ├── orders/
  │   │   ├── create_order_command.dart
  │   │   └── get_order_query.dart
  │   └── users/
  │       └── get_user_query.dart
  ├── infrastructure/
  │   ├── firestore_order_repository.dart
  │   └── firestore_user_repository.dart
  └── presentation/
      ├── orders/
      │   └── order_detail_screen.dart
      └── users/
          └── user_profile_screen.dart
```

Same layers, different top-level orientation. Pick one and apply consistently.

### A single command-handler file

```dart
// lib/features/orders/application/create_order_command.dart
import 'package:chassis/chassis.dart';

import '../domain/order.dart';
import '../domain/order_item.dart';
import '../domain/order_exceptions.dart';
import '../domain/i_order_repository.dart';
import '../../payments/domain/i_payment_gateway.dart';

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

@chassisHandler
class CreateOrderCommandHandler
    implements CommandHandler<CreateOrderCommand, Order> {
  CreateOrderCommandHandler({
    required IOrderRepository orderRepository,
    required IPaymentGateway paymentGateway,
  })  : _orderRepository = orderRepository,
        _paymentGateway = paymentGateway;

  final IOrderRepository _orderRepository;
  final IPaymentGateway _paymentGateway;

  @override
  Future<Order> run(CreateOrderCommand command) async {
    // ... business logic
  }
}
```

The Command is the public surface; the Handler is the implementation that fulfills it. Putting them together means the file is the unit of "what this operation does and how".

### Test layout mirroring source

```
test/features/orders/
  ├── application/
  │   ├── create_order_command_handler_test.dart
  │   ├── cancel_order_command_handler_test.dart
  │   └── watch_order_status_query_handler_test.dart
  └── presentation/
      └── order_list/
          └── order_list_view_model_test.dart
```

Mirroring lets you find the test for a file by replacing `lib/` with `test/` and adding `_test.dart`.

### Anti-pattern: a junk-drawer file

```dart
// ❌ lib/application/orders/handlers.dart — multiple unrelated handlers
final class CreateOrderCommand extends Command<Order> { /* ... */ }
class CreateOrderCommandHandler implements CommandHandler<CreateOrderCommand, Order> { /* ... */ }
final class CancelOrderCommand extends Command<void> { /* ... */ }
class CancelOrderCommandHandler implements CommandHandler<CancelOrderCommand, void> { /* ... */ }
final class GetOrderQuery extends ReadQuery<Order> { /* ... */ }
class GetOrderQueryHandler implements ReadHandler<GetOrderQuery, Order> { /* ... */ }
```

```dart
// ✅ One file per command/query-handler pair
// lib/application/orders/create_order_command.dart
// lib/application/orders/cancel_order_command.dart
// lib/application/orders/get_order_query.dart
```

The directory listing is the feature's table of contents — keep it readable.

### Anti-pattern: implementation in `domain/`

```
// ❌ Repository implementation in the domain layer.
lib/domain/users/firestore_user_repository.dart
```

```
// ✅ Domain owns the interface; infrastructure owns the implementation.
lib/domain/users/i_user_repository.dart
lib/infrastructure/users/firestore_user_repository.dart
```

This split is what lets a test substitute a mock without re-implementing Firebase.
