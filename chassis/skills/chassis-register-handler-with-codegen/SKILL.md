---
name: chassis-register-handler-with-codegen
description: Register a hand-written Chassis handler in the generated mediator by annotating it with `@chassisHandler` and running `dart run build_runner build --delete-conflicting-outputs`. Use after authoring or modifying any handler — the mediator must be regenerated for the new handler to be wired into the dependency graph and exposed as a typed instance method. Also use when a chassis_builder build fails: this skill lists every build-time error the generator can raise and what each one means.
---
# Registering a Handler via `@chassisHandler` and `build_runner`

## Contents
- [Core Concepts](#core-concepts)
- [What the Generator Produces](#what-the-generator-produces)
- [The Handler Contract](#the-handler-contract)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)
- [Build-Time Errors](#build-time-errors)
- [Troubleshooting](#troubleshooting)

## Core Concepts

`chassis_builder` is a `build_runner` package that generates mediators from three annotations:

- `@chassisHandler` marks a handler class for registration.
- `@ChassisApp(modules: [...])` on the app's composition-root library directive produces the concrete mediator (`AppMediator` by default; override with `mediatorName:`) in `<file>.chassis.dart` — see `chassis-bootstrap-app`.
- `@chassisModule` on a shared package's declaration class produces an `abstract interface class <Name>Mediator` — see `chassis-organize-feature`.

Discovery walks the import graph: a handler is registered when it is reachable, through imports or exports, from the library carrying `@ChassisApp` (for app-own handlers) or `@chassisModule` (for module handlers), within that package. The walk **never crosses a package boundary** — a handler in another package is invisible to `@ChassisApp` even if the app imports that package's barrel; it enters the app mediator only through a `@chassisModule` declared in its own package and listed in `modules: [...]`. No `build.yaml` is needed — the builder applies automatically to any package that lists `chassis_builder` as a dev dependency.

Completeness is compiler-enforced. The generated app mediator `implements` every module interface, so a missing module handler makes the generated class fail to implement the interface — a compile error, never a runtime gap. Wiring mistakes the generator itself can detect fail the build with an actionable error; the generator never emits a partial mediator.

Without the annotation, a handler exists but no mediator knows about it. Without re-running `build_runner`, the generated mediator is stale and dispatch throws `HandlerNotRegisteredException` at runtime.

## What the Generator Produces

For each `@chassisHandler` reachable from the `@ChassisApp` library, the generator:

- adds the handler's constructor dependencies (deduplicated across all handlers) to the mediator constructor as required **named** parameters, named after the dependency's type, decapitalized (`TodoRepository` → `todoRepository:`),
- instantiates and registers the handler in the constructor body,
- emits one typed **instance method** on the generated class per handler. The method name derives from the **message** class name — never the handler, so renaming a handler does not change the API: strip a trailing `Query` or `Command`, decapitalize. `GetProfileQuery` → `getProfile`, `CreateOrderCommand` → `createOrder`, `WatchUserProfileQuery` → `watchUserProfile`. The method's parameters mirror the message constructor exactly.

```dart
// Hand-written handler:
@chassisHandler
class CreateOrderHandler
    implements CommandHandler<CreateOrderCommand, Order> {
  CreateOrderHandler({required this.orderRepository});
  final OrderRepository orderRepository;
  // ...
}

// Generated (in <composition-root-file>.chassis.dart):
class AppMediator extends Mediator {
  AppMediator({required OrderRepository orderRepository}) {
    registerCommandHandler(
      CreateOrderHandler(orderRepository: orderRepository),
    );
    // ...
  }

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

Every generated method dispatches through `run` / `read` / `watch`, so middlewares (logging, crash reporting) always apply — there is no way to bypass them through the typed surface.

## The Handler Contract

The generator instantiates handlers itself, so the handler constructor has a mechanical shape:

- an **unnamed generative constructor** (no factory, no named constructor),
- each parameter — positional or named — is a dependency the generated mediator constructor will require and pass through, the way it is declared. **Prefer named parameters**, especially with two or more dependencies: call sites and tests stay unambiguous.

```dart
@chassisHandler
class GetProfileHandler implements ReadHandler<GetProfileQuery, String> {
  GetProfileHandler({required this.repository}); // unnamed constructor

  final AuthRepository repository;

  @override
  Future<String> read(GetProfileQuery query) =>
      repository.profileOf(query.userId);
}
```

The message class needs an unnamed generative constructor too — the generated method rebuilds the message from its own parameters.

## Rules

- **DO** annotate every hand-written handler with `@chassisHandler`. *Without it the handler is not registered and no typed method is generated.*
- **DO** give the handler an unnamed generative constructor whose parameters are its dependencies, typed against repository / service interfaces, and **PREFER named parameters** (required `this.` fields), especially with two or more dependencies. *The generator passes each dependency back the way it is declared; named parameters keep registration sites and tests unambiguous. Interfaces keep test-time substitution possible.*
- **DO** keep the handler reachable from the `@ChassisApp` (or `@chassisModule`) library through imports — a feature barrel is the standard way. *Discovery walks the import graph within the package; an unreachable handler is silently absent from the generated mediator.*
- **DO** run `dart run build_runner build --delete-conflicting-outputs` after adding, removing, or modifying any handler. *Stale generated code routes through old versions of the handler, or fails to compile against new constructor signatures.*
- **PREFER** `dart run build_runner watch --delete-conflicting-outputs` during active development. *Re-runs the generator on every save, eliminating the wait-and-rerun loop.*
- **CONSIDER** committing the generated `.chassis.dart` files to source control. *Reviewers see the actual code that runs, not only the annotations that produce it.*
- **DON'T** write a `build.yaml`. *The builder applies automatically to dependents of `chassis_builder`; pre-1.0 builder configuration no longer resolves.*
- **DON'T** edit generated files directly. *Edits are overwritten on the next build. Change the handler or the annotation site instead.*
- **DON'T** mix manual `mediator.registerCommandHandler(...)` calls with the generated mediator. *The constructor already registered every reachable handler; a duplicate registration throws `DuplicateHandlerException` — always, not only in debug builds.*
- **DON'T** ignore generator errors. *Each one names the exact handler and contract violation — see [Build-Time Errors](#build-time-errors). The build never emits a partial mediator, so the error is the only way forward.*

## Workflow

- [ ] **Step 1 — Add `chassis_builder: ^1.0.0` and `build_runner: ^2.15.0`** to `dev_dependencies` in `pubspec.yaml`. They are already present in any Chassis-bootstrapped project; check before adding. No `build.yaml`.
- [ ] **Step 2 — Author or modify the handler** following `chassis-create-command`, `chassis-create-read-query`, or `chassis-create-watch-query`. Place `@chassisHandler` on the class; give it an unnamed constructor whose parameters are its dependencies (prefer named).
- [ ] **Step 3 — Make the handler reachable.** Export it from the feature barrel (or import it) so the `@ChassisApp` / `@chassisModule` library reaches it through the import graph.
- [ ] **Step 4 — Run the generator.**
  - One-shot: `dart run build_runner build --delete-conflicting-outputs`.
  - Watch mode: `dart run build_runner watch --delete-conflicting-outputs`.
- [ ] **Step 5 — Read the output.** A generator error names the offending handler and the violated contract — fix at the source, not in generated files. See [Build-Time Errors](#build-time-errors).
- [ ] **Step 6 — Update the composition root** if the mediator constructor gained a new parameter (because the new handler depends on a new repository). See `chassis-bootstrap-app`.
- [ ] **Step 7 — Use the generated typed method** from ViewModels: `mediator.createOrder(...)` instead of `mediator.run(CreateOrderCommand(...))`. The typed method is the discoverable, compile-checked surface; both routes pass through middlewares.

## Examples

### `pubspec.yaml`

```yaml
dependencies:
  flutter:
    sdk: flutter
  chassis: ^1.0.0
  chassis_flutter: ^1.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  chassis_builder: ^1.0.0
  build_runner: ^2.15.0
```

No `build.yaml` — the builder configures itself.

### Annotated handler

```dart
import 'package:chassis/chassis.dart';
import '../../domain/orders/order_repository.dart';
import '../../domain/orders/order.dart';

final class CreateOrderCommand extends Command<Order> {
  CreateOrderCommand({required this.userId, required this.items});

  final String userId;
  final List<OrderItem> items;

  @override
  Map<String, Object?> get params => {'userId': userId, 'items': items.length};
}

@chassisHandler
class CreateOrderHandler
    implements CommandHandler<CreateOrderCommand, Order> {
  CreateOrderHandler({required this.orderRepository});

  final OrderRepository orderRepository;

  @override
  Future<Order> run(CreateOrderCommand command) =>
      orderRepository.create(userId: command.userId, items: command.items);
}
```

### Running the generator

```bash
# One-shot, suitable for CI and explicit regeneration
dart run build_runner build --delete-conflicting-outputs

# Watch mode for active development — re-runs on every save
dart run build_runner watch --delete-conflicting-outputs
```

`--delete-conflicting-outputs` removes stale generated files when signatures change. Without it, manual cleanup is required after every refactor.

### Anti-pattern: no unnamed generative constructor

```dart
// ❌ Build error: "has no unnamed generative constructor." The generator
// instantiates handlers itself; a factory or named constructor gives it
// nothing to call.
@chassisHandler
class CreateOrderHandler
    implements CommandHandler<CreateOrderCommand, Order> {
  CreateOrderHandler.create({required this.orderRepository});
  final OrderRepository orderRepository;
  // ...
}
```

```dart
// ✅ Unnamed constructor; dependencies as named parameters.
@chassisHandler
class CreateOrderHandler
    implements CommandHandler<CreateOrderCommand, Order> {
  CreateOrderHandler({required this.orderRepository});
  final OrderRepository orderRepository;
  // ...
}
```

### Anti-pattern: editing generated files

Generated `.chassis.dart` files are overwritten on every build. If something looks wrong in the output, the fix is upstream — usually in the handler's constructor, the message's constructor, or the annotation site. Editing the generated file is throwaway work.

## Build-Time Errors

The generator fails the build — never emitting a partial mediator — with one of these errors. Each one is a contract violation at a named element:

| Error message (abridged) | Meaning | Fix |
|---|---|---|
| `<Handler> ... has no unnamed generative constructor` | The generator instantiates handlers itself and found no constructor it can call. | Add an unnamed generative constructor (no factory). |
| `<Handler> ... implements none of CommandHandler, ReadHandler, or WatchHandler` | `@chassisHandler` sits on a class that is not a handler. | Implement the matching handler interface, or remove the annotation. |
| `Both <HandlerA> and <HandlerB> handle <MessageType>` | Two handlers (across app + modules) claim the same command/query type. | Delete one, or split the message into two types. |
| `<HandlerA> and <HandlerB> both derive the method name ...` | Two message class names reduce to the same generated method name. | Rename one message class. |
| `... both produce the method <name> with an identical signature` | Two modules generate indistinguishable methods; one implementation would silently satisfy both interfaces. | Rename one handler or its message to disambiguate. |
| `No @chassisHandler class is reachable from the library declaring <Module>` | The `@chassisModule` library does not import any handler. | Declare the module in the package barrel (or import the handlers). |
| `@ChassisApp on library <uri> found no @chassisHandler class` | Nothing reachable in the app package and no modules declared. | Import the handlers (directly or via a barrel) or declare modules. |
| `@ChassisApp on library <uri> lists <X> in modules, which is not a class annotated with @chassisModule` | `modules:` contains a non-module type. | List only `@chassisModule`-annotated declaration classes. |
| `@ChassisApp annotates the class <X>, but it must annotate the library directive` | `@ChassisApp` sits on a class (pre-1.0 form). | Remove the class and put the annotation on `library;` at the top of the file. |
| `<Message> ... has no unnamed generative constructor, so no typed mediator method can be generated` | The command/query class cannot be rebuilt from the generated method's parameters. | Give the message an unnamed generative constructor. |

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `HandlerNotRegisteredException` at runtime | Handler missing `@chassisHandler`, not reachable from the `@ChassisApp` library, or the generator was not re-run. | Add the annotation, export the handler from the barrel, run `dart run build_runner build --delete-conflicting-outputs`. |
| `DuplicateHandlerException` at startup | Manual `register*Handler` call on top of the generated constructor's registration. | Remove the manual registration — the generated mediator owns it. |
| Compile error in `<file>.chassis.dart` after a refactor | Stale generated file references an old signature. | Re-run with `--delete-conflicting-outputs`. |
| New parameter on `AppMediator(...)` causes a compile error at the call site | `chassis_builder` correctly added a required dependency; the composition root has not been updated. | Construct the new repository in `initializeDependencies()` and pass it to `AppMediator(...)`. See `chassis-bootstrap-app`. |
| Generator runs but no output appears | Annotation typo (`@ChassisHandler` instance instead of `@chassisHandler`), the file is outside `lib/`, or no `@ChassisApp` library / `@chassisModule` class exists in the package. | Check the annotation matches the symbol exported by `package:chassis/chassis.dart` and that a composition root or module declaration exists. |
