---
name: chassis-organize-feature
description: Lay out the directory and file structure for a Chassis feature or shared module — Presentation, Application, Domain, and Infrastructure folders, one Command/Query-Handler pair per file, ViewModel + State + Event colocated under the screen they serve, the multi-package split (Flutter-free domain package vs app package), and the `@chassisModule` + barrel convention that makes out-of-package handlers discoverable. Use when starting a new feature, splitting an app into packages, extracting a feature into a shared module package, refactoring a folder that has drifted, or deciding where a new file should live.
---
# Organizing a Chassis Feature

## Contents
- [Core Concepts](#core-concepts)
- [The Four Layers](#the-four-layers)
- [Two Layouts: Layer-First vs Feature-First](#two-layouts-layer-first-vs-feature-first)
- [Multi-Package Split: Domain Package + App Package](#multi-package-split-domain-package--app-package)
- [Shared Modules: `@chassisModule`](#shared-modules-chassismodule)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

Chassis enforces a layered architecture. The directory structure should make those layers visible at a glance — opening any feature folder should immediately answer "what does this feature *do*" by listing its commands and queries, and "how does it talk to the outside world" by listing its repositories and adapters.

> Each message-handler pair should live in its own file. Co-locating the message definition with its handler makes it easy to navigate: finding a Command immediately reveals the logic that handles it, and vice versa. (...) Splitting each pair into its own file enforces the single-responsibility principle at the file level and makes the project's capabilities scannable from the directory listing alone.
> — `docs/coding_rules.md`

The layout is not bureaucracy. The capabilities of a feature are the list of files in `application/<feature>/`. The contract with the outside world is the list of files in `domain/<feature>/`. A new contributor can read those two folders and know what the feature can do.

The structure also feeds code generation: handler discovery walks the import graph from the `@ChassisApp` (or `@chassisModule`) library, so a per-feature barrel that exports the application layer is what makes handlers reachable. The walk **never crosses a package boundary** — a handler living in another package is invisible to `@ChassisApp` even when the app imports that package's barrel; it enters the mediator only through a `@chassisModule` declared in its own package. See `chassis-register-handler-with-codegen`.

## The Four Layers

| Layer | Lives in | Owns | Depends on |
|---|---|---|---|
| **Presentation** | `presentation/` | Widgets, ViewModels, State, Events | the generated mediator (typed methods) |
| **Application** | `application/` | Commands, Queries, Handlers | repository **interfaces** from `domain/` |
| **Domain** | `domain/` | Entities, value objects, repository interfaces, domain exceptions | nothing inside the project |
| **Infrastructure** | `infrastructure/` | Repository implementations, third-party adapters | external SDKs (Firebase, Dio, isar) |

`domain/` is the inner-most layer with no inward dependencies. `application/` depends on `domain/` interfaces. `presentation/` depends on the generated mediator (produced from `application/` annotations). `infrastructure/` implements `domain/` interfaces and is wired into the composition root.

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

## Multi-Package Split: Domain Package + App Package

When an app outgrows a single package — or a repo standard mandates a package boundary between business logic and Flutter — split along the **Flutter dependency line**, not along layer intuition or feature lines:

| Package | Contains | Depends on |
|---|---|---|
| **Domain package** (e.g. `domain`) | Everything Flutter-free: entities, value objects, ports (repository interfaces), domain exceptions, **and the entire application layer** — Commands, Queries, Handlers | `chassis` only (pure Dart) |
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
// generates lib/domain.chassis.dart: abstract interface class DomainMediator
```

```dart
// app package — composition root library
@ChassisApp(modules: [DomainModule], mediatorName: 'AppMediator')
library;
```

Both packages list `chassis_builder` and `build_runner` as dev dependencies. Build the domain package first — the app's generated mediator `implements DomainMediator` from `domain.chassis.dart`, so that file must exist before the app compiles.

Two differences from a cross-app shared module:

- **ViewModels keep the concrete `AppMediator`.** Presentation lives in the app package, so nothing forces the interface indirection; `DomainMediator` exists only as the composition contract that makes a missing handler a compile error.
- **The domain package has no `presentation/` and no `infrastructure/`.** It ships ports; the app implements them and passes the implementations to `AppMediator`'s generated constructor.

Inside each package, keep the feature-first sub-structure: `src/domain/orders/`, `src/application/orders/` in the domain package; `presentation/orders/`, `infrastructure/orders/` in the app.

## Shared Modules: `@chassisModule`

When a feature must be shared across applications (an auth flow, a billing engine), it becomes its own **package** with the same layers, plus two module-specific pieces:

1. **A barrel that reaches every handler.** The package's entry library (`lib/auth.dart`) exports the application layer. Handler discovery walks the import graph from the module declaration, so the barrel is what makes handlers reachable.
2. **A `@chassisModule` declaration class** in that barrel. The generator emits `lib/auth.chassis.dart` next to it, containing `abstract interface class AuthMediator` (name = class name minus trailing `Module`, plus `Mediator`) with one typed method per handler.

```dart
// package auth — lib/auth.dart
import 'package:chassis/chassis.dart';

export 'src/application/login_command.dart';
export 'src/application/watch_session_query.dart';
export 'src/domain/auth_repository.dart';

@chassisModule
final class AuthModule {}
// generates lib/auth.chassis.dart: abstract interface class AuthMediator
```

The app composes the module at build time:

```dart
@ChassisApp(modules: [AuthModule], mediatorName: 'AppMediator')
library;
// generates: class AppMediator extends Mediator implements AuthMediator
```

Because the generated app mediator `implements AuthMediator`, a handler missing from the module is a compile error in the app — completeness is compiler-enforced, and there is no runtime merge step.

**Shared ViewModels depend on the interface**, not on any app's concrete mediator. `AuthMediator` is importable from `package:auth/auth.chassis.dart`, so the module's presentation layer stays app-agnostic:

```dart
// package auth — lib/src/presentation/login/login_view_model.dart
class LoginViewModel extends ViewModel<LoginState, LoginEvent> {
  LoginViewModel(this._auth) : super(LoginState.initial());

  final AuthMediator _auth;

  void submit(String username, String password) {
    run(
      () => _auth.login(username, password),
      onSuccess: (_) => sendEvent(const LoginSucceededEvent()),
      onError: (error) => sendEvent(LoginFailedEvent(error)),
    );
  }
}

// App side: the AppMediator instance satisfies the AuthMediator parameter.
// create: (_) => LoginViewModel(mediator)
```

The module ships without knowing which app hosts it; the app supplies its `AppMediator`, which implements `AuthMediator`.

## Rules

- **DO** organize code into the four layers (Presentation, Application, Domain, Infrastructure). *The architecture rests on this separation; every other rule assumes it.*
- **DO** put each Command / Query and its handler in **one file** — `<message_name>_command.dart` or `<message_name>_query.dart`. *Co-location maps the application's capabilities to the directory listing.*
- **DO** use snake_case file names matching the message name: `create_order_command.dart` for `CreateOrderCommand`, `watch_user_profile_query.dart` for `WatchUserProfileQuery`.
- **DO** maintain a per-feature barrel (`features/orders/orders.dart`) exporting the application layer, and import every feature barrel from the `@ChassisApp` library. *Handler discovery walks the import graph; a handler no barrel reaches is silently absent from the generated mediator.*
- **DO** colocate a screen's `ViewModel`, `State`, and `Event` files under the screen folder. *They evolve together; splitting them across the project creates merge conflicts and navigation friction.*
- **DO** put repository **interfaces** in `domain/<feature>/<resource>_repository.dart`. *The interface is part of the domain contract; the implementation is infrastructure.*
- **DO** put repository **implementations** in `infrastructure/<feature>/<provider>_<resource>_repository.dart` (e.g. `firestore_user_repository.dart`, `dio_payment_gateway.dart`). *Naming the provider in the file name makes swap-out obvious.*
- **DO** declare entities, value objects, and domain exceptions under `domain/<feature>/`. *They are the language the rest of the layers speak.*
- **DO** keep test files mirroring the source structure: `test/<feature>/application/<handler>_test.dart`, `test/<feature>/presentation/<view_model>_test.dart`. See `chassis-write-handler-test`.
- **DO** split a multi-package app along the Flutter dependency line: entities, value objects, ports, and all Command/Query-Handler files go to the Flutter-free domain package; screens, ViewModels, repository implementations, and the composition root stay in the app package. *Handlers orchestrate ports and entities and never import Flutter — they belong with the domain; implementations and widgets belong with the app that wires them.*
- **DO** declare `@chassisModule` in the barrel of every package that contains handlers, and list it in the app's `@ChassisApp(modules: [...])`. *Handler discovery never crosses a package boundary — without the module, out-of-package handlers are silently absent from the generated mediator.*
- **DO** extract a feature shared across apps into its own package with a `@chassisModule` class in the barrel, and make shared ViewModels depend on the generated `<Name>Mediator` interface. *The module stays app-agnostic; the app's `@ChassisApp(modules: [...])` composition makes missing handlers a compile error.*
- **PREFER** the feature-first layout for any application beyond a tutorial. *Layer-first scales poorly past a handful of features.*
- **PREFER** naming repository interfaces after the resource (`OrderRepository`) and implementations after the provider (`FirestoreOrderRepository`). *The generated mediator constructor names its parameter after the dependency's type, decapitalized — an `I` prefix leaks into the wiring API as `iOrderRepository:`.*
- **DON'T** put two unrelated commands in the same file. *Each command's file is its own SRP boundary; one growing file becomes a junk drawer.*
- **DON'T** put repository implementations under `application/` or `domain/`. *Implementations belong to infrastructure; mixing them in inner layers reverses the Dependency Rule.*
- **DON'T** make a shared module's ViewModels depend on an app's concrete `AppMediator`. *That inverts the dependency: the module would import the app. Depend on the module's generated interface (`AuthMediator`) instead.*
- **DON'T** add Flutter, `chassis_flutter`, or infrastructure SDKs to the domain package's dependencies. *Flutter-freedom is the point of the split: handlers stay testable with plain `dart test` and the package stays consumable from any runner.*
- **DON'T** scatter ViewModel and State across `presentation/` and `state/`. *They are one logical unit; keep them in the same folder as the screen.*
- **DON'T** create a separate `models/` folder for domain entities. *Entities are part of `domain/`; a flat `models/` folder erases the layer boundary the architecture relies on.*

## Workflow

- [ ] **Step 1 — Pick or follow the project's layout.** If the project already has `lib/features/...`, keep using feature-first. If it has top-level `lib/presentation/`, `lib/application/`, etc., keep layer-first. If the feature is shared across apps, create a package and follow the module workflow below.
- [ ] **Step 2 — Create the feature folder** (feature-first) or skip (layer-first). Inside it, create `presentation/`, `application/`, `domain/`, `infrastructure/` only as needed — empty folders are noise.
- [ ] **Step 3 — Define the domain.** `domain/<feature>/` gets the entities, value objects, repository interfaces (`<resource>_repository.dart`), and domain exceptions. *No imports from `application/`, `presentation/`, or `infrastructure/`.*
- [ ] **Step 4 — Implement the repositories.** `infrastructure/<feature>/<provider>_<resource>_repository.dart` implements the domain interface and maps infrastructure exceptions to domain exceptions. See `chassis-handle-errors`.
- [ ] **Step 5 — Author the application layer.** `application/<feature>/<message_name>_command.dart` (or `_query.dart`) — one Command/Query + its handler per file, co-located. See `chassis-create-command`, `chassis-create-read-query`, `chassis-create-watch-query`.
- [ ] **Step 6 — Update the feature barrel** to export the new application files, so the `@ChassisApp` (or `@chassisModule`) library reaches the handlers. Then run `dart run build_runner build --delete-conflicting-outputs`.
- [ ] **Step 7 — Build the presentation layer.** `presentation/<screen_name>/<screen_name>_screen.dart`, `<screen_name>_view_model.dart`, `<screen_name>_state.dart`, `<screen_name>_event.dart` — co-located. See `chassis-create-view-model`.
- [ ] **Step 8 — Mirror the structure under `test/`** for unit tests of handlers and view models.

For a multi-package app split (domain package + app package):

- [ ] **Step P1 — Create the domain package** (e.g. `packages/domain/`) depending on `chassis` only, with `chassis_builder` + `build_runner` as dev dependencies. Lay out `lib/src/domain/<feature>/` and `lib/src/application/<feature>/`.
- [ ] **Step P2 — Move the Flutter-free layers.** Entities, value objects, ports, and domain exceptions go to `src/domain/<feature>/`; Command/Query-Handler files go to `src/application/<feature>/`. Presentation and infrastructure do not move.
- [ ] **Step P3 — Write the barrel and declare the module.** `lib/domain.dart` exports every application file and domain contract, and declares `@chassisModule final class DomainModule {}`. Run `dart run build_runner build --delete-conflicting-outputs` in the domain package to generate `domain.chassis.dart`.
- [ ] **Step P4 — Compose in the app.** Add the domain package dependency, switch the composition root to `@ChassisApp(modules: [DomainModule], mediatorName: 'AppMediator')`, fix imports (app code now imports `package:domain/domain.dart`), and rebuild the app package. The generated `AppMediator` implements `DomainMediator`, so any handler lost in the move is a compile error, not a runtime gap.

For a shared module package:

- [ ] **Step M1 — Create the package** (`packages/auth/`) with the same layers under `lib/src/`, minus `infrastructure/` when the app owns the implementations (the module then exports the repository interface for the app to implement).
- [ ] **Step M2 — Write the barrel** (`lib/auth.dart`) exporting the application layer and the domain contract, and declare `@chassisModule final class AuthModule {}` in it.
- [ ] **Step M3 — Run `dart run build_runner build`** in the module package to generate `lib/auth.chassis.dart` with the `AuthMediator` interface.
- [ ] **Step M4 — Keep shared ViewModels on the interface.** They import `package:auth/auth.chassis.dart` and take an `AuthMediator`.
- [ ] **Step M5 — Compose in the app** with `@ChassisApp(modules: [AuthModule])` and rebuild. The app's composition root now also provides the module handlers' dependencies. See `chassis-bootstrap-app`.

## Examples

### Feature-first layout for a complete feature

```
lib/features/orders/
  ├── domain/
  │   ├── order.dart                            # entity
  │   ├── order_item.dart                       # value object
  │   ├── order_status.dart                     # enum
  │   ├── order_exceptions.dart                 # InsufficientInventoryException, PaymentDeclinedException
  │   └── order_repository.dart                 # interface
  ├── application/
  │   ├── create_order_command.dart             # CreateOrderCommand + CreateOrderHandler
  │   ├── cancel_order_command.dart             # CancelOrderCommand + CancelOrderCommandHandler
  │   ├── get_order_query.dart                  # GetOrderQuery + GetOrderHandler
  │   └── watch_order_status_query.dart         # WatchOrderStatusQuery + WatchOrderStatusHandler
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
  │   ├── domain.dart                           # barrel + @chassisModule DomainModule
  │   ├── domain.chassis.dart                   # generated: abstract interface class DomainMediator
  │   └── src/
  │       ├── domain/
  │       │   └── orders/
  │       │       ├── order.dart                # entity
  │       │       ├── order_item.dart           # value object
  │       │       ├── order_exceptions.dart
  │       │       └── order_repository.dart     # port — the app implements it
  │       └── application/
  │           └── orders/
  │               ├── create_order_command.dart
  │               └── watch_order_status_query.dart
  └── pubspec.yaml                              # deps: chassis; dev: chassis_builder, build_runner

app/                                            # Flutter
  ├── lib/
  │   ├── mediator.dart                         # @ChassisApp(modules: [DomainModule], mediatorName: 'AppMediator')
  │   ├── mediator.chassis.dart                 # generated: class AppMediator implements DomainMediator
  │   ├── infrastructure/
  │   │   └── orders/
  │   │       └── firestore_order_repository.dart   # implements the domain package's port
  │   └── presentation/
  │       └── orders/
  │           └── order_list/
  │               ├── order_list_screen.dart
  │               ├── order_list_view_model.dart    # depends on the concrete AppMediator
  │               ├── order_list_state.dart
  │               └── order_list_event.dart
  └── pubspec.yaml                              # deps: flutter, chassis, chassis_flutter, domain, firebase...
```

The dependency arrow points one way: `app → domain`. The domain package never names the app, Flutter, or any SDK; the app supplies the port implementations to `AppMediator`'s generated constructor:

```dart
// app: lib/main.dart
mediator = AppMediator(
  orderRepository: FirestoreOrderRepository(), // implements domain's OrderRepository
)..addMiddleware(LoggingMiddleware());
```

### Shared module package

```
packages/auth/
  ├── lib/
  │   ├── auth.dart                             # barrel + @chassisModule AuthModule
  │   ├── auth.chassis.dart                     # generated: abstract interface class AuthMediator
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
  │               ├── login_view_model.dart     # depends on AuthMediator
  │               ├── login_state.dart
  │               └── login_event.dart
  └── pubspec.yaml                              # depends on chassis; dev: chassis_builder, build_runner
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
// app: lib/app/app.dart
@ChassisApp(modules: [AuthModule], mediatorName: 'AppMediator')
library;

// app: lib/main.dart
mediator = AppMediator(
  authRepository: FirebaseAuthRepository(), // implements the module's AuthRepository
  orderRepository: FirestoreOrderRepository(),
)..addMiddleware(LoggingMiddleware());
```

### A single command-handler file

```dart
// lib/features/orders/application/create_order_command.dart
import 'package:chassis/chassis.dart';

import '../domain/order.dart';
import '../domain/order_item.dart';
import '../domain/order_exceptions.dart';
import '../domain/order_repository.dart';
import '../../payments/domain/payment_gateway.dart';

final class CreateOrderCommand extends Command<Order> {
  CreateOrderCommand({
    required this.userId,
    required this.items,
    required this.shippingAddress,
  });

  final String userId;
  final List<OrderItem> items;
  final Address shippingAddress;

  @override
  Map<String, Object?> get params =>
      {'userId': userId, 'items': items.length};
}

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
class CreateOrderHandler implements CommandHandler<CreateOrderCommand, Order> { /* ... */ }
final class CancelOrderCommand extends Command<void> { /* ... */ }
class CancelOrderCommandHandler implements CommandHandler<CancelOrderCommand, void> { /* ... */ }
final class GetOrderQuery extends ReadQuery<Order> { /* ... */ }
class GetOrderHandler implements ReadHandler<GetOrderQuery, Order> { /* ... */ }
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
