---
name: chassis-register-handler-with-codegen
description: Register a hand-written Chassis handler in the generated `AppMediator` by annotating it with `@chassisHandler`, configuring `build.yaml` if needed, and running `dart run build_runner build --delete-conflicting-outputs`. Use after authoring or modifying any handler — the AppMediator must be regenerated for the new handler to be wired into the dependency graph and exposed as a type-safe extension method. Do NOT use the `@generateCommandHandler` / `@generateQueryHandler` annotations on repository methods — those are reserved for human authors and being phased out.
---
# Registering a Handler via `@chassisHandler` and `build_runner`

## Contents
- [Core Concepts](#core-concepts)
- [What the Generator Produces](#what-the-generator-produces)
- [The Annotation You Use vs The Annotations You Don't](#the-annotation-you-use-vs-the-annotations-you-dont)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Core Concepts

`chassis_builder` is a `build_runner` package that scans the codebase for `@chassisHandler`-annotated classes and produces:

1. The `AppMediator` subclass — its constructor accepts every repository / service injected by every annotated handler, and its body registers each handler with the right dependencies.
2. Type-safe extension methods on `Mediator` — one per command / query — exposing a clean `mediator.<verbResource>(...)` API in place of `mediator.run(<Command>(...))`.

Without the annotation, a handler exists but the Mediator does not know about it. Without re-running `build_runner`, the `AppMediator` source is stale and dispatch fails (or, in the worst case, silently routes through a previous version of the handler).

> The `chassis_builder` scans for this annotation and produces the Mediator subclass, handler registrations, and type-safe extension methods. Without this annotation, the generator has no knowledge of the handler and it will not be wired into the dependency graph.
> — `docs/coding_rules.md`

## What the Generator Produces

For each `@chassisHandler` it finds, the generator:

- registers the handler in `AppMediator`'s constructor,
- adds the handler's named-constructor dependencies to `AppMediator`'s constructor signature,
- generates an extension method on `Mediator` that builds the message and dispatches through `run` / `read` / `watch` based on the handler type.

```dart
// Hand-written handler:
@chassisHandler
class CreateOrderCommandHandler
    implements CommandHandler<CreateOrderCommand, Order> {
  CreateOrderCommandHandler({required IOrderRepository orderRepository})
      : _orderRepository = orderRepository;
  final IOrderRepository _orderRepository;
  // ...
}

// Generated (in app_mediator.g.dart or app_mediator.chassis.dart):
class AppMediator extends Mediator {
  AppMediator({required IOrderRepository orderRepository, /* others */}) {
    registerCommandHandler(
      CreateOrderCommandHandler(orderRepository: orderRepository),
    );
    // ...
  }
}

extension AppMediatorExtensions on Mediator {
  Future<Order> createOrder({
    required String userId,
    required List<OrderItem> items,
    required Address shippingAddress,
  }) =>
      run(CreateOrderCommand(
        userId: userId,
        items: items,
        shippingAddress: shippingAddress,
      ));
  // ...
}
```

## The Annotation You Use vs The Annotations You Don't

Two families of annotations exist. Only one is in scope for AI-authored code.

| Annotation | Used by AI? | Purpose |
|---|---|---|
| `@chassisHandler` | **Yes** | Marks a hand-written handler for registration in `AppMediator`. |
| `@generateCommandHandler` | **No** — reserved for human authors | Auto-generates a Command + CommandHandler from a repository method. Being phased out. |
| `@generateQueryHandler` | **No** — reserved for human authors | Auto-generates a ReadQuery / WatchQuery + handler from a repository method. Being phased out. |

The `@generate*Handler` annotations remove a few lines of boilerplate at the cost of hiding the handler's implementation behind code generation. For an AI assistant, that trade-off goes the wrong way: writing the handler explicitly takes the same time, and the resulting class is right there in source for review and extension. The framework owners reserve those annotations for cases where a human deliberately chooses the trade-off, and intend to remove them. **Never produce them.**

## Rules

- **DO** annotate every hand-written handler with `@chassisHandler`. *Without it the handler is not registered and the type-safe extension is not generated.*
- **DO** declare handler constructor parameters as **named** parameters typed against repository / service interfaces. *The generator copies the constructor signature into `AppMediator`'s constructor; named parameters keep the generated constructor readable, and interfaces keep test-time substitution possible.*
- **DO** run `dart run build_runner build --delete-conflicting-outputs` after adding, removing, or modifying any handler. *Stale generated code routes through old versions of the handler, or fails to compile against new constructor signatures.*
- **PREFER** `dart run build_runner watch --delete-conflicting-outputs` during active development. *Re-runs the generator on every save, eliminating the wait-and-rerun loop.*
- **CONSIDER** committing the generated files to source control. *Reviewers see the actual code that runs, not only the annotations that produce it. Build-time-only generation makes review harder and exposes the build pipeline as a single point of failure.*
- **DON'T** use `@generateCommandHandler` or `@generateQueryHandler` on a repository method. *Those annotations are reserved for human authors and are being phased out — write the command / query / handler classes by hand and annotate the manual handler with `@chassisHandler`.*
- **DON'T** edit generated files directly. *Edits are overwritten on the next build. Change the source annotation or the handler class instead.*
- **DON'T** mix manual `mediator.registerCommandHandler(...)` calls with the generated `AppMediator`. *Manual registration silently shadows generated registration and re-introduces wiring drift.*
- **DON'T** ignore generator errors. *They are usually telling you that a handler's constructor signature changed and a downstream caller needs updating — not that the build is "flaky".*

## Workflow

- [ ] **Step 1 — Add `chassis_builder` and `build_runner`** to `dev_dependencies` in `pubspec.yaml`. They are already present in any Chassis-bootstrapped project; check before adding.
- [ ] **Step 2 — Confirm `build.yaml` is present** at the project root and enables the relevant builders. The default content enables both `repositoryGenerator` (handles the `@generate*Handler` family for human-authored code, harmless when you do not use those annotations) and `mediatorGenerator` (the one you actually need).
- [ ] **Step 3 — Author or modify the handler** following `chassis-create-command`, `chassis-create-read-query`, or `chassis-create-watch-query`. Place `@chassisHandler` on the class.
- [ ] **Step 4 — Run the generator.**
  - One-shot: `dart run build_runner build --delete-conflicting-outputs`.
  - Watch mode: `dart run build_runner watch --delete-conflicting-outputs`.
- [ ] **Step 5 — Read the output.** The generator prints which files it produced and any errors. A red error usually points to a constructor signature mismatch or a missing import — fix at the source, not in generated files.
- [ ] **Step 6 — Update the composition root** if `AppMediator`'s constructor gained a new parameter (because the new handler depends on a new repository). See `chassis-bootstrap-app`.
- [ ] **Step 7 — Use the generated extension** from ViewModels: `mediator.createOrder(...)` instead of `mediator.run(CreateOrderCommand(...))`. The extension is the discoverable surface; manual `run`/`read`/`watch` calls bypass it.

## Examples

### `pubspec.yaml`

```yaml
dependencies:
  flutter:
    sdk: flutter
  chassis: ^0.0.1
  chassis_flutter: ^0.0.1
  provider: ^6.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  chassis_builder: ^0.0.1
  build_runner: ^2.4.0
```

### `build.yaml`

```yaml
targets:
  $default:
    builders:
      chassis_builder|repositoryGenerator:
        enabled: true
      chassis_builder|mediatorGenerator:
        enabled: true
```

The `repositoryGenerator` only acts on `@generate*Handler` annotations, which AI-authored code does not produce — so it is a no-op for you. Leave it enabled; it does not hurt.

### Annotated handler

```dart
import 'package:chassis/chassis.dart';
import '../../domain/orders/i_order_repository.dart';
import '../../domain/orders/order.dart';

final class CreateOrderCommand extends Command<Order> {
  CreateOrderCommand({required this.userId, required this.items});
  final String userId;
  final List<OrderItem> items;
}

@chassisHandler
class CreateOrderCommandHandler
    implements CommandHandler<CreateOrderCommand, Order> {
  CreateOrderCommandHandler({required IOrderRepository orderRepository})
      : _orderRepository = orderRepository;

  final IOrderRepository _orderRepository;

  @override
  Future<Order> run(CreateOrderCommand command) =>
      _orderRepository.create(userId: command.userId, items: command.items);
}
```

### Running the generator

```bash
# One-shot, suitable for CI and explicit regeneration
dart run build_runner build --delete-conflicting-outputs

# Watch mode for active development — re-runs on every save
dart run build_runner watch --delete-conflicting-outputs
```

`--delete-conflicting-outputs` removes stale generated files when method signatures change. Without it, manual cleanup is required after every refactor.

### Anti-pattern: `@generateCommandHandler` on the repository

```dart
// ❌ Do NOT produce this. The annotation is reserved for human authors and is being phased out.
abstract interface class IOrderRepository {
  @generateCommandHandler
  Future<Order> create({
    required String userId,
    required List<OrderItem> items,
  });
}
```

```dart
// ✅ Write the command and handler by hand; annotate the manual handler.
final class CreateOrderCommand extends Command<Order> { /* ... */ }

@chassisHandler
class CreateOrderCommandHandler
    implements CommandHandler<CreateOrderCommand, Order> { /* ... */ }
```

### Anti-pattern: editing generated files

Generated files are overwritten on every build. If something looks wrong in the output, the fix is upstream — usually in the handler's constructor or the annotation site. Editing the generated file is throwaway work and a recipe for "it worked yesterday".

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `MediatorException: no handler registered for <Command>` at runtime | Handler missing `@chassisHandler`, or generator was not re-run after authoring it. | Add the annotation; run `dart run build_runner build --delete-conflicting-outputs`. |
| Compile error in `app_mediator.g.dart` after a refactor | Stale generated file references an old constructor / method signature. | Re-run with `--delete-conflicting-outputs`. |
| New repository in `AppMediator(...)` causes compile error at the call site | `chassis_builder` correctly added a required parameter; the composition root has not been updated. | Construct the new repository in `initializeDependencies()` and pass it to `AppMediator(...)`. See `chassis-bootstrap-app`. |
| Generator runs but no output appears | Annotation typo (`@ChassisHandler` instead of `@chassisHandler`), or the file is not reachable from `lib/`. | Check the import resolves and the annotation matches the symbol exported by `package:chassis/chassis.dart`. |
