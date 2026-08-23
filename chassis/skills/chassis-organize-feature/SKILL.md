---
name: chassis-organize-feature
description: Lay out the directory and file structure for a Chassis feature or shared module — Presentation, Application, Domain, and Infrastructure folders, one Command/Query-Handler pair per file, ViewModel + State + Event colocated under the screen they serve, the composition-root pair (`@ChassisApp` in `lib/mediator.dart`, `Chassis.initialize` in `main.dart`), the multi-package split (Flutter-free domain package vs app package), and the `@chassisModule` + barrel convention that makes out-of-package handlers discoverable. Use when starting a new feature, splitting an app into packages, extracting a feature into a shared module package, refactoring a folder that has drifted, or deciding where a new file should live.
---
# Organizing a Chassis Feature

## Contents
- [Core Concepts](#core-concepts)
- [The Four Layers](#the-four-layers)
- [Two Layouts: Layer-First vs Feature-First](#two-layouts-layer-first-vs-feature-first)
- [The Composition Root: `lib/mediator.dart` + `main.dart`](#the-composition-root-libmediatordart--maindart)
- [Multi-Package Split: Domain Package + App Package](#multi-package-split-domain-package--app-package)
- [Shared Modules: `@chassisModule`](#shared-modules-chassismodule)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

Chassis enforces a layered architecture. The directory structure should make those layers visible at a glance — opening any feature folder should immediately answer "what does this feature *do*" by listing its commands and queries, and "how does it talk to the outside world" by listing its repositories and adapters.

> Each message-handler pair should live in its own file. Co-locating the message definition with its handler makes navigation immediate: finding a Command immediately reveals the logic that handles it, and vice versa. (...) Splitting each pair into its own file enforces the single-responsibility principle at the file level and makes the project's capabilities scannable from the directory listing alone.
> — `docs/coding_rules.md`

The layout is not bureaucracy. The capabilities of a feature are the list of files in `application/<feature>/`. The contract with the outside world is the list of files in `domain/<feature>/`. A new contributor can read those two folders and know what the feature can do.

The structure also feeds code generation: handler discovery walks the import graph from the `@ChassisApp` (or `@chassisModule`) library, so a per-feature barrel that exports the application layer is what makes handlers reachable. The walk **never crosses a package boundary** — a handler living in another package is invisible to `@ChassisApp` even when the app imports that package's barrel; it enters the mediator only through a `@chassisModule` declared in its own package. Completeness is checked at build time: a concrete Command or Query reachable from the `@ChassisApp` graph with **no handler fails the build** (annotate the message with `@unhandledMessage` to opt out while its handler is being written). See `chassis-register-handler-with-codegen`.

## The Four Layers

| Layer | Lives in | Owns | Depends on |
|---|---|---|---|
| **Presentation** | `presentation/` | Widgets, ViewModels, State, Events | message types (application) and `chassis_flutter` |
| **Application** | `application/` | Commands, Queries, Handlers | repository **interfaces** from `domain/` |
| **Domain** | `domain/` | Entities, value objects, repository interfaces, domain errors | nothing inside the project |
| **Infrastructure** | `infrastructure/` | Repository implementations, third-party adapters | external SDKs (Firebase, Dio, isar); wired at the composition root |

`domain/` is the inner-most layer with no inward dependencies. `application/` depends on `domain/` interfaces. `presentation/` depends on the **message types** — ViewModels dispatch message objects (`run(CreateOrderCommand(...))`) through `chassis_flutter`'s dispatch machinery; no generated mediator is referenced anywhere outside the composition root. `infrastructure/` implements `domain/` interfaces and is wired into the composition root.

## Two Layouts: Layer-First vs Feature-First

Both layouts respect the architecture; pick one and stay consistent across the project.

**Feature-first** (recommended for medium and large apps): each feature owns its four layers under one folder.

```
lib/features/orders/
  ├── presentation/
  ├── application/
  ├── domain/
  ├── infrastructure/
  └── orders.dart          # barrel exporting the application layer
```

Adding a feature means creating one folder. Removing a feature means deleting one folder. Cross-feature dependencies — when a handler in `orders/application/` needs `users/domain/user_repository.dart` — are explicit imports across feature boundaries.

**Layer-first** (acceptable for small apps and tutorials): the four layers are top-level folders.

```
lib/
  ├── presentation/
  ├── application/
  ├── domain/
  └── infrastructure/
```

Simpler at small scale; harder to keep tidy as features multiply. The Quick Start tutorial uses this layout for brevity.

## The Composition Root: `lib/mediator.dart` + `main.dart`

The composition root is split across two files with one-way imports:

- **`lib/mediator.dart`** holds the `@ChassisApp(mediatorName: 'AppMediator') library;` directive and the imports (feature barrels) that make every handler reachable. The generator emits `lib/mediator.chassis.dart` next to it: `class AppMediator extends Mediator` with **only a registration constructor** — handler dependencies as required named parameters, all handlers registered in the constructor body. No per-message methods.
- **`lib/main.dart`** constructs the infrastructure implementations, installs the mediator once with `Chassis.initialize(AppMediator(...))`, then calls `runApp`.

```dart
// lib/mediator.dart
@ChassisApp(mediatorName: 'AppMediator')
library;

import 'package:chassis/chassis.dart';
import 'package:app/features/orders/orders.dart';
import 'package:app/features/users/users.dart';
```

```dart
// lib/main.dart
import 'package:chassis/chassis.dart';
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

import 'package:app/infrastructure/orders/firestore_order_repository.dart';
import 'package:app/mediator.chassis.dart';

void main() {
  Chassis.initialize(
    AppMediator(orderRepository: FirestoreOrderRepository())
      ..addMiddleware(LoggingMiddleware()),
  );
  runApp(const App());
}
```

There is **no app-level global mediator variable**: ViewModels dispatch message objects, and the mediator installed by `Chassis.initialize` routes them (tests inject a fake through the ViewModel's `mediator:` parameter instead). Because nothing in presentation needs to reach the mediator, presentation never imports `main.dart` or `mediator.dart` — the import graph stays one-way: `main.dart` → screens → messages. See `chassis-bootstrap-app`.

## Multi-Package Split: Domain Package + App Package

When an app outgrows a single package — or a repo standard mandates a package boundary between business logic and Flutter — split along the **Flutter dependency line**, not along layer intuition or feature lines:

| Package | Contains | Depends on |
|---|---|---|
| **Domain package** (e.g. `domain`) | Everything Flutter-free: entities, value objects, ports (repository interfaces), domain errors, **and the entire application layer** — Commands, Queries, Handlers | `chassis` only (pure Dart) |
| **App package** | Presentation **and** Infrastructure: screens, ViewModels, State, Events, repository implementations, composition root | Flutter, `chassis_flutter`, external SDKs, and the domain package |

Chassis's Domain *and* Application layers both leave the app. A handler orchestrates ports and entities and never touches Flutter, so it belongs with them — leaving handlers behind would force the domain package to be imported by code it should know nothing about. Presentation stays in the app because it is Flutter; Infrastructure stays in the app because implementations depend on external SDKs and are wired by the composition root, which must see both the ports (domain package) and their implementations.

**Wiring is the `@chassisModule` mechanism, and it is required, not optional.** The import-graph walk from `@ChassisApp` is restricted to the app's own package, so handlers in the domain package are invisible to it no matter what the app imports. The domain package therefore declares a module in its barrel, exactly like a shared module (mechanics in the next section):

```dart
// package domain — lib/domain.dart (barrel)
import 'package:chassis/chassis.dart';

export 'src/application/orders/create_order_command.dart';
export 'src/application/orders/watch_order_status_query.dart';
export 'src/domain/orders/order.dart';
export 'src/domain/orders/order_repository.dart';
// ... every application file and domain contract

@chassisModule
final class DomainModule {}
```

```dart
// app package — lib/mediator.dart
@ChassisApp(modules: [DomainModule], mediatorName: 'AppMediator')
library;

import 'package:chassis/chassis.dart';
import 'package:domain/domain.dart';
```

The module class **generates nothing** — its only role is cross-package handler discovery: listing `DomainModule` tells the app-side generator to walk the domain package's import graph from its barrel and register its handlers on `AppMediator`. There is no build-order constraint between the packages; only the app package needs `chassis_builder` + `build_runner` (keeping them as dev dependencies of the domain package is optional — running the builder there generates nothing but validates the module declaration early).

Two things stay put in the split:

- **Presentation code is identical in both setups.** ViewModels dispatch message objects imported from `package:domain/domain.dart` and never name a mediator, so moving the application layer out of the app changes nothing in `presentation/`.
- **The domain package has no `presentation/` and no `infrastructure/`.** It ships ports; the app implements them and passes the implementations to `AppMediator`'s generated constructor. A message left without its handler in the move fails the app's build — never a runtime gap.

Inside each package, keep the feature-first sub-structure: `src/domain/orders/`, `src/application/orders/` in the domain package; `presentation/orders/`, `infrastructure/orders/` in the app.

## Shared Modules: `@chassisModule`

When a feature must be shared across applications (an auth flow, a billing engine), it becomes its own **package** with the same layers, plus two module-specific pieces:

1. **A barrel that reaches every handler.** The package's entry library (`lib/auth.dart`) exports the application layer. Handler discovery walks the import graph from the module declaration, so the barrel is what makes handlers reachable.
2. **A `@chassisModule` declaration class** in that barrel. It generates nothing: its single role is cross-package handler discovery, because the import-graph walk never crosses a package boundary on its own.

```dart
// package auth — lib/auth.dart
import 'package:chassis/chassis.dart';

export 'src/application/login_command.dart';
export 'src/application/watch_session_query.dart';
export 'src/domain/auth_repository.dart';

@chassisModule
final class AuthModule {}
```

The app composes the module at build time:

```dart
// app — lib/mediator.dart
@ChassisApp(modules: [AuthModule], mediatorName: 'AppMediator')
library;

import 'package:auth/auth.dart';
import 'package:chassis/chassis.dart';
```

The generated `AppMediator` registers the module's handlers alongside the app's own and requires their dependencies in its constructor. Completeness is build-enforced: a module message without a handler — like any concrete message reachable from the `@ChassisApp` graph — fails the app's build, and a module whose barrel reaches no handler is a build error too. There is no runtime merge step.

**Shared ViewModels are message-direct and therefore app-agnostic by construction.** They dispatch the module's own message types and never name any mediator:

```dart
// package auth — lib/src/presentation/login/login_view_model.dart
class LoginViewModel extends ViewModel<LoginState, LoginEvent> {
  LoginViewModel({super.mediator}) : super(LoginState.initial());

  void submit(String username, String password) => run(
        LoginCommand(username: username, password: password),
        onSuccess: (_) => sendEvent(const LoginSucceededEvent()),
        onError: (error, stack) => sendEvent(LoginFailedEvent(error)),
      );
}
```

The module ships without knowing which app hosts it: its presentation layer depends only on the module's message types and `chassis_flutter`. The host app's `Chassis.initialize(AppMediator(...))` — where `AppMediator` has registered the module's handlers — supplies the routing at runtime; tests inject a fake through the `mediator:` parameter.

## Rules

- **DO** organize code into the four layers (Presentation, Application, Domain, Infrastructure). *The architecture rests on this separation; every other rule assumes it.*
- **DO** put each Command / Query and its handler in **one file** — `<message_name>_command.dart` or `<message_name>_query.dart`. *Co-location maps the application's capabilities to the directory listing.*
- **DO** use snake_case file names matching the message name: `create_order_command.dart` for `CreateOrderCommand`, `watch_user_profile_query.dart` for `WatchUserProfileQuery`.
- **DO** maintain a per-feature barrel (`features/orders/orders.dart`) exporting the application layer, and import every feature barrel from the `@ChassisApp` library. *Handler discovery walks the import graph. A message-handler file no barrel reaches is invisible to the generator: the handler goes unregistered, and because the missing-handler build check cannot see the message either, the failure surfaces only at runtime dispatch (`HandlerNotRegisteredError`). Complete barrels are what arm the build-time guarantee.*
- **DO** colocate a screen's `ViewModel`, `State`, and `Event` files under the screen folder. *They evolve together; splitting them across the project creates merge conflicts and navigation friction.*
- **DO** put repository **interfaces** in `domain/<feature>/<resource>_repository.dart`. *The interface is part of the domain contract; the implementation is infrastructure.*
- **DO** put repository **implementations** in `infrastructure/<feature>/<provider>_<resource>_repository.dart` (e.g. `firestore_user_repository.dart`, `dio_payment_gateway.dart`). *Naming the provider in the file name makes swap-out obvious.*
- **DO** declare entities, value objects, and domain errors under `domain/<feature>/`. *They are the language the rest of the layers speak.*
- **DO** keep test files mirroring the source structure: `test/<feature>/application/<handler>_test.dart`, `test/<feature>/presentation/<view_model>_test.dart`. See `chassis-write-handler-test`.
- **DO** split a multi-package app along the Flutter dependency line: entities, value objects, ports, and all Command/Query-Handler files go to the Flutter-free domain package; screens, ViewModels, repository implementations, and the composition root stay in the app package. *Handlers orchestrate ports and entities and never import Flutter — they belong with the domain; implementations and widgets belong with the app that wires them.*
- **DO** declare `@chassisModule` in the barrel of every package that contains handlers, and list it in the app's `@ChassisApp(modules: [...])`. *Handler discovery never crosses a package boundary — without the module, out-of-package handlers are never registered (the builder warns about reachable foreign handlers, and their reachable messages fail the build as unhandled).*
- **DO** extract a feature shared across apps into its own package with a `@chassisModule` class in the barrel. *The module is app-agnostic by construction — its ViewModels dispatch its own message types; the app's `@ChassisApp(modules: [...])` composition registers its handlers, and the missing-handler build check keeps the composition complete.*
- **PREFER** the feature-first layout for any application beyond a tutorial. *Layer-first scales poorly past a handful of features.*
- **PREFER** naming repository interfaces after the resource (`OrderRepository`) and implementations after the provider (`FirestoreOrderRepository`). *The generated mediator constructor names its parameter after the dependency's type, decapitalized — an `I` prefix leaks into the wiring API as `iOrderRepository:`.*
- **DON'T** put two unrelated commands in the same file. *Each command's file is its own SRP boundary; one growing file becomes a junk drawer.*
- **DON'T** put repository implementations under `application/` or `domain/`. *Implementations belong to infrastructure; mixing them in inner layers reverses the Dependency Rule.*
- **DON'T** reference a generated mediator from any ViewModel — app-local or shared. *Presentation depends on message types and `chassis_flutter` only; ViewModels dispatch message objects through `run`/`read`/`watch`, and the generated class appears only at the composition root (`Chassis.initialize(AppMediator(...))` in `main.dart`).*
- **DON'T** import `main.dart` (or `mediator.dart`) from presentation code. *No global mediator exists to reach; a backward import from screens to the entry point creates a cycle and couples every widget to the composition root.*
- **DON'T** add Flutter, `chassis_flutter`, or infrastructure SDKs to the domain package's dependencies. *Flutter-freedom is the point of the split: handlers stay testable with plain `dart test` and the package stays consumable from any runner.*
- **DON'T** scatter ViewModel and State across `presentation/` and `state/`. *They are one logical unit; keep them in the same folder as the screen.*
- **DON'T** create a separate `models/` folder for domain entities. *Entities are part of `domain/`; a flat `models/` folder erases the layer boundary the architecture relies on.*

## Workflow

- [ ] **Step 1 — Pick or follow the project's layout.** If the project already has `lib/features/...`, keep using feature-first. If it has top-level `lib/presentation/`, `lib/application/`, etc., keep layer-first. If the feature is shared across apps, create a package and follow the module workflow below.
- [ ] **Step 2 — Create the feature folder** (feature-first) or skip (layer-first). Inside it, create `presentation/`, `application/`, `domain/`, `infrastructure/` only as needed — empty folders are noise.
- [ ] **Step 3 — Define the domain.** `domain/<feature>/` gets the entities, value objects, repository interfaces (`<resource>_repository.dart`), and domain errors. *No imports from `application/`, `presentation/`, or `infrastructure/`.*
- [ ] **Step 4 — Implement the repositories.** `infrastructure/<feature>/<provider>_<resource>_repository.dart` implements the domain interface and maps infrastructure exceptions to domain errors. See `chassis-handle-errors`.
- [ ] **Step 5 — Author the application layer.** `application/<feature>/<message_name>_command.dart` (or `_query.dart`) — one Command/Query + its handler per file, co-located. See `chassis-create-command`, `chassis-create-read-query`, `chassis-create-watch-query`.
- [ ] **Step 6 — Update the feature barrel** to export the new application files, so the `@ChassisApp` (or `@chassisModule`) library reaches the handlers. Then run `dart run build_runner build --delete-conflicting-outputs`. A reachable message whose handler is missing fails the build — annotate it with `@unhandledMessage` if the handler intentionally comes later.
- [ ] **Step 7 — Build the presentation layer.** `presentation/<screen_name>/<screen_name>_screen.dart`, `<screen_name>_view_model.dart`, `<screen_name>_state.dart`, `<screen_name>_event.dart` — co-located. ViewModels import the feature's messages and dispatch them directly. See `chassis-create-view-model`.
- [ ] **Step 8 — Mirror the structure under `test/`** for unit tests of handlers and view models.

For a multi-package app split (domain package + app package):

- [ ] **Step P1 — Create the domain package** (e.g. `packages/domain/`) depending on `chassis` only. Lay out `lib/src/domain/<feature>/` and `lib/src/application/<feature>/`.
- [ ] **Step P2 — Move the Flutter-free layers.** Entities, value objects, ports, and domain errors go to `src/domain/<feature>/`; Command/Query-Handler files go to `src/application/<feature>/`. Presentation and infrastructure do not move.
- [ ] **Step P3 — Write the barrel and declare the module.** `lib/domain.dart` exports every application file and domain contract, and declares `@chassisModule final class DomainModule {}`. The module generates nothing; optionally keep `chassis_builder` + `build_runner` as dev dependencies so the domain package's own build validates the declaration early.
- [ ] **Step P4 — Compose in the app.** Add the domain package dependency, list the module in `lib/mediator.dart`'s `@ChassisApp(modules: [DomainModule], mediatorName: 'AppMediator')`, fix imports (app code now imports `package:domain/domain.dart`), and rebuild the app package. Any message that lost its handler in the move fails the app's build, not at runtime.

For a shared module package:

- [ ] **Step M1 — Create the package** (`packages/auth/`) with the same layers under `lib/src/`, minus `infrastructure/` when the app owns the implementations (the module then exports the repository interface for the app to implement).
- [ ] **Step M2 — Write the barrel** (`lib/auth.dart`) exporting the application layer and the domain contract, and declare `@chassisModule final class AuthModule {}` in it.
- [ ] **Step M3 — Keep shared ViewModels message-direct.** They import the module's own messages (plus `chassis_flutter`) and never name a mediator; the `mediator:` constructor parameter stays the testing seam.
- [ ] **Step M4 — Compose in the app** with `@ChassisApp(modules: [AuthModule])` in `lib/mediator.dart` and rebuild. The app's `main.dart` now also provides the module handlers' dependencies to `AppMediator(...)` inside `Chassis.initialize`. See `chassis-bootstrap-app`.

## Examples

### Feature-first layout for a complete feature

```
lib/features/orders/
  ├── domain/
  │   ├── order.dart                            # entity
  │   ├── order_item.dart                       # value object
  │   ├── order_status.dart                     # enum
  │   ├── order_errors.dart                     # InsufficientInventoryException, PaymentDeclinedException
  │   └── order_repository.dart                 # interface
  ├── application/
  │   ├── create_order_command.dart             # CreateOrderCommand + CreateOrderCommandHandler
  │   ├── cancel_order_command.dart             # CancelOrderCommand + CancelOrderCommandHandler
  │   ├── get_order_query.dart                  # GetOrderQuery + GetOrderQueryHandler
  │   └── watch_order_status_query.dart         # WatchOrderStatusQuery + WatchOrderStatusQueryHandler
  ├── infrastructure/
  │   └── firestore_order_repository.dart       # FirestoreOrderRepository implements OrderRepository
  ├── presentation/
  │   ├── order_list/
  │   │   ├── order_list_screen.dart
  │   │   ├── order_list_view_model.dart
  │   │   ├── order_list_state.dart
  │   │   └── order_list_event.dart
  │   └── order_detail/
  │       ├── order_detail_screen.dart
  │       ├── order_detail_view_model.dart
  │       ├── order_detail_state.dart
  │       └── order_detail_event.dart
  └── orders.dart                               # barrel: exports application/ + domain contract
```

The `application/` listing alone — `create_order_command.dart`, `cancel_order_command.dart`, `get_order_query.dart`, `watch_order_status_query.dart` — answers the question "what does the orders feature do?". The barrel keeps every handler reachable from the composition root:

```dart
// lib/features/orders/orders.dart
export 'application/create_order_command.dart';
export 'application/cancel_order_command.dart';
export 'application/get_order_query.dart';
export 'application/watch_order_status_query.dart';
export 'domain/order.dart';
export 'domain/order_repository.dart';
```

### Multi-package split: domain package + app package

```
packages/domain/                                # Flutter-free
  ├── lib/
  │   ├── domain.dart                           # barrel + @chassisModule DomainModule (generates nothing)
  │   └── src/
  │       ├── domain/
  │       │   └── orders/
  │       │       ├── order.dart                # entity
  │       │       ├── order_item.dart           # value object
  │       │       ├── order_errors.dart
  │       │       └── order_repository.dart     # port — the app implements it
  │       └── application/
  │           └── orders/
  │               ├── create_order_command.dart
  │               └── watch_order_status_query.dart
  └── pubspec.yaml                              # deps: chassis only

app/                                            # Flutter
  ├── lib/
  │   ├── main.dart                             # Chassis.initialize(AppMediator(...)) + runApp
  │   ├── mediator.dart                         # @ChassisApp(modules: [DomainModule], mediatorName: 'AppMediator') library;
  │   ├── mediator.chassis.dart                 # generated: class AppMediator extends Mediator — registration constructor only
  │   ├── infrastructure/
  │   │   └── orders/
  │   │       └── firestore_order_repository.dart   # implements the domain package's port
  │   └── presentation/
  │       └── orders/
  │           └── order_list/
  │               ├── order_list_screen.dart
  │               ├── order_list_view_model.dart    # dispatches messages from package:domain — no mediator type
  │               ├── order_list_state.dart
  │               └── order_list_event.dart
  └── pubspec.yaml                              # deps: flutter, chassis, chassis_flutter, domain, firebase...
                                                # dev: chassis_builder, build_runner
```

The dependency arrow points one way: `app → domain`. The domain package never names the app, Flutter, or any SDK; the app supplies the port implementations to `AppMediator`'s generated constructor and installs it once:

```dart
// app: lib/main.dart
void main() {
  Chassis.initialize(
    AppMediator(
      orderRepository: FirestoreOrderRepository(), // implements domain's OrderRepository
    )..addMiddleware(LoggingMiddleware()),
  );
  runApp(const App());
}
```

### Shared module package

```
packages/auth/
  ├── lib/
  │   ├── auth.dart                             # barrel + @chassisModule AuthModule (generates nothing)
  │   └── src/
  │       ├── domain/
  │       │   ├── session.dart
  │       │   └── auth_repository.dart          # the app implements this
  │       ├── application/
  │       │   ├── login_command.dart
  │       │   └── watch_session_query.dart
  │       └── presentation/
  │           └── login/
  │               ├── login_screen.dart
  │               ├── login_view_model.dart     # dispatches LoginCommand — no mediator type
  │               ├── login_state.dart
  │               └── login_event.dart
  └── pubspec.yaml                              # deps: flutter, chassis, chassis_flutter
```

```dart
// packages/auth/lib/auth.dart
import 'package:chassis/chassis.dart';

export 'src/application/login_command.dart';
export 'src/application/watch_session_query.dart';
export 'src/domain/auth_repository.dart';
export 'src/domain/session.dart';
export 'src/presentation/login/login_screen.dart';

@chassisModule
final class AuthModule {}
```

The app composes it and provides the repository implementation:

```dart
// app: lib/mediator.dart
@ChassisApp(modules: [AuthModule], mediatorName: 'AppMediator')
library;

import 'package:auth/auth.dart';
import 'package:chassis/chassis.dart';
import 'package:app/features/orders/orders.dart';
```

```dart
// app: lib/main.dart
void main() {
  Chassis.initialize(
    AppMediator(
      authRepository: FirebaseAuthRepository(), // implements the module's AuthRepository
      orderRepository: FirestoreOrderRepository(),
    )..addMiddleware(LoggingMiddleware()),
  );
  runApp(const App());
}
```

### A single command-handler file

```dart
// lib/features/orders/application/create_order_command.dart
import 'package:chassis/chassis.dart';

import '../domain/order.dart';
import '../domain/order_item.dart';
import '../domain/order_errors.dart';
import '../domain/order_repository.dart';
import '../../payments/domain/payment_gateway.dart';

final class CreateOrderCommand({
  required final String userId,
  required final List<OrderItem> items,
  required final Address shippingAddress,
}) extends Command<Order> {
  @override
  Map<String, Object?> get params =>
      {'userId': userId, 'items': items, 'shippingAddress': shippingAddress};
}

@chassisHandler
class CreateOrderCommandHandler({
  required final OrderRepository orderRepository,
  required final PaymentGateway paymentGateway,
}) implements CommandHandler<CreateOrderCommand, Order> {
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
lib/domain/users/user_repository.dart
lib/infrastructure/users/firestore_user_repository.dart
```

This split is what lets a test substitute a mock without re-implementing Firebase.
