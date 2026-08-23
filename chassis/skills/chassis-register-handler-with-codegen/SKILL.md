---
name: chassis-register-handler-with-codegen
description: Register a hand-written Chassis handler in the generated mediator by annotating it with `@chassisHandler` and running `dart run build_runner build --delete-conflicting-outputs`. Use after authoring or modifying any handler — the mediator's registration constructor must be regenerated for the new handler to be wired into the dependency graph. Also use when a chassis_builder build fails: this skill covers the missing-handler build check (a reachable message without a handler fails the build; `@unhandledMessage` opts out), the `@chassisModule` cross-package discovery, and every build-time error and warning the generator can raise.
---
# Registering a Handler via `@chassisHandler` and `build_runner`

## Contents
- [Core Concepts](#core-concepts)
- [What the Generator Produces](#what-the-generator-produces)
- [The Handler Contract](#the-handler-contract)
- [The Missing-Handler Build Check](#the-missing-handler-build-check)
- [Cross-Package Discovery: `@chassisModule`](#cross-package-discovery-chassismodule)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)
- [Build-Time Errors](#build-time-errors)
- [Troubleshooting](#troubleshooting)

## Core Concepts

`chassis_builder` is a `build_runner` package driven by four annotations:

- `@chassisHandler` marks a handler class for registration.
- `@ChassisApp(modules: [...])` on the app's composition-root library directive produces the concrete mediator (`AppMediator` by default; override with `mediatorName:`) in `<file>.chassis.dart` — see `chassis-bootstrap-app`.
- `@chassisModule` on a class in a shared package's barrel makes that package's handlers discoverable from an app. It generates **nothing** — its only role is cross-package discovery.
- `@unhandledMessage` on a Command/Query opts that message out of the missing-handler build check while its handler is being written.

Discovery walks the import graph: a handler is registered when it is reachable, through imports or exports, from the library carrying `@ChassisApp` (for app-own handlers) or `@chassisModule` (for module handlers), within that library's own package. The walk **never crosses a package boundary** — a handler in another package is invisible to `@ChassisApp` even if the app imports that package's barrel; it enters the app mediator only through a `@chassisModule` declared in its own package and listed in `modules: [...]`. No `build.yaml` is needed — the builder applies automatically to any package that lists `chassis_builder` as a dev dependency.

Completeness is build-enforced. A concrete Command/Query reachable from the `@ChassisApp` graph with no handler is a **build error** — chassis fails the build instead of letting the dispatch throw `HandlerNotRegisteredError` at runtime. Since ViewModels dispatch message objects directly, this proof cannot live at the call site; the builder proves it once for the whole graph, at the declaration site. Wiring mistakes the generator itself can detect fail the build with an actionable error; the generator never emits a partial mediator.

Without the annotation, a handler exists but no mediator knows about it — and its message fails the build as unhandled. Without re-running `build_runner`, the generated mediator is stale and dispatch throws `HandlerNotRegisteredError` at runtime.

## What the Generator Produces

The generated file contains exactly one class: a mediator whose **only member is its constructor**. For each `@chassisHandler` reachable from the `@ChassisApp` graph, the generator:

- adds the handler's constructor dependencies to the mediator constructor as required **named** parameters, deduplicated across all handlers by resolved type, named after the dependency's type, decapitalized (`OrderRepository` → `orderRepository:`),
- instantiates and registers the handler in the constructor body, passing each dependency back the way the handler declares it.

```dart
// Hand-written handler:
@chassisHandler
class CreateOrderHandler({
  required final OrderRepository orderRepository,
}) implements CommandHandler<CreateOrderCommand, Order> {
  // ...
}

// Generated (in <composition-root-file>.chassis.dart) — the whole class:
class AppMediator extends Mediator {
  AppMediator({
    required OrderRepository orderRepository,
  }) {
    registerCommandHandler(
      CreateOrderHandler(orderRepository: orderRepository),
    );
    // ... every other reachable handler
  }
}
```

No per-message methods, no module interfaces — nothing else is generated. Dispatch goes through the `run`/`read`/`watch` the class inherits from `Mediator`, so middlewares (logging, crash reporting) always apply. Message and result types are never denoted in the generated code (registration relies on inference), so private message and result types are fine — only handler classes and their constructor dependency types must be public.

## The Handler Contract

The generator instantiates handlers itself, so the handler class has a mechanical shape:

- a **public class** with an **unnamed generative constructor** — a primary constructor satisfies this (no factory, no named constructor),
- implementing **exactly one** operation interface — `CommandHandler`, `ReadHandler`, or `WatchHandler` — with no type parameters on the handler class,
- each constructor parameter — positional or named, declared `final` in the primary-constructor header so it becomes a field — is a dependency the generated mediator constructor will require and pass through, the way it is declared. **Prefer named parameters**, especially with two or more dependencies: registration sites and tests stay unambiguous,
- every dependency type must be **public** (including nested type arguments) and must not be a function or record type — the generated mediator declares it as a constructor parameter in another library,
- never a `Mediator`-typed dependency: handlers must not dispatch. A multi-step flow is one handler composing several repositories; logic shared between handlers moves into an injected service.

```dart
@chassisHandler
class GetProfileQueryHandler({
  required final AuthRepository repository, // primary constructor — unnamed, generative
}) implements ReadHandler<GetProfileQuery, String> {
  @override
  Future<String> read(GetProfileQuery query) =>
      repository.profileOf(query.userId);
}
```

The message class has no constructor requirements — the generated code never references it.

## The Missing-Handler Build Check

> A concrete Command or Query reachable from the `@ChassisApp` import graph with no `@chassisHandler` handler is a **build error** — chassis fails the build instead of letting the dispatch throw `HandlerNotRegisteredError` at runtime.
> — `docs/coding_rules.md`

"Reachable" means everything the app code can name: the app package's own imports and exports, plus the export closure of directly imported foreign libraries. The build fails with **one** error listing every orphan message, its URI, and the three fixes:

1. annotate its handler with `@chassisHandler` and rerun `build_runner`;
2. if the message lives in another package, declare that package's `@chassisModule` class in `@ChassisApp(modules: [...])`;
3. opt out with `@unhandledMessage` while the handler is being written.

```dart
@unhandledMessage // handler lands in the next commit
final class ExportReportCommand({required final String reportId})
    extends Command<void>;
```

The annotation is a visible, greppable TODO rather than a silent gap — remove it when the handler lands.

## Cross-Package Discovery: `@chassisModule`

A shared package (an auth flow, a billing engine) exposes its handlers by declaring a module class in its barrel — the library that (transitively) imports every handler of the package:

```dart
// package auth — lib/auth.dart
@chassisModule
final class AuthModule {}
```

The app lists it in `@ChassisApp(modules: [AuthModule])`, which makes the generator walk the module library's import graph *in the module's package* and register those handlers on the app mediator, with their dependencies folded into the same constructor. The module class generates no output of its own; module libraries are still validated at their own build time (handler shape, one handler per message), so mistakes fail early in the module's package. A reachable `@chassisHandler` living in a package that is neither the app's nor a declared module's triggers a build **warning** naming the handler and the `modules: [...]` fix — it will not be registered. See `chassis-organize-feature` for module layout.

## Rules

- **DO** annotate every hand-written handler with `@chassisHandler`. *Without it the handler is not registered — and its message fails the build as unhandled.*
- **DO** give the handler a primary constructor — the unnamed generative constructor — whose `final` parameters are its dependencies, typed against public repository / service interfaces, and **PREFER named parameters** (`class FooHandler({required final BarRepository barRepository}) implements ...`), especially with two or more dependencies. *The generator passes each dependency back the way it is declared; named parameters keep registration sites and tests unambiguous, and adding a dependency cannot silently swap two same-typed arguments.*
- **DO** keep the handler reachable from the `@ChassisApp` (or `@chassisModule`) library through imports — a feature barrel is the standard way. *Discovery walks the import graph within the package; an unreachable handler is absent from the generated mediator, and its message — if still reachable — fails the build as unhandled.*
- **DO** declare a `@chassisModule` class in the barrel of every handler-bearing package, and list it in `@ChassisApp(modules: [...])`. *The import-graph walk never crosses a package boundary; without the module, out-of-package handlers are never registered (the generator warns).*
- **DO** run `dart run build_runner build --delete-conflicting-outputs` after adding, removing, or modifying any handler. *Stale generated code routes through old versions of the handler, or fails to compile against new constructor signatures.*
- **PREFER** `dart run build_runner watch --delete-conflicting-outputs` during active development. *Re-runs the generator on every save, eliminating the wait-and-rerun loop.*
- **CONSIDER** committing the generated `.chassis.dart` files to source control. *Reviewers see the actual code that runs, not only the annotations that produce it.*
- **CONSIDER** `@unhandledMessage` on a message whose handler is not written yet. *The build check refuses reachable messages without handlers; the annotation is an explicit, greppable opt-out — remove it when the handler lands.*
- **DON'T** write a `build.yaml`. *The builder applies automatically to dependents of `chassis_builder`; pre-1.0 builder configuration no longer resolves.*
- **DON'T** edit generated files directly. *Edits are overwritten on the next build. Change the handler or the annotation site instead.*
- **DON'T** inject the `Mediator` (or the generated mediator class) into a handler. *Handlers never dispatch — the generator fails the build. Model the flow as one command whose handler composes the repositories it needs.*
- **DON'T** mix manual `mediator.registerCommandHandler(...)` calls with the generated mediator. *The constructor already registered every reachable handler; a duplicate registration throws `DuplicateHandlerError` — always, not only in debug builds.*
- **DON'T** ignore generator errors. *Each one names the exact element and contract violation — see [Build-Time Errors](#build-time-errors). The build never emits a partial mediator, so the error is the only way forward.*

## Workflow

- [ ] **Step 1 — Add `chassis_builder: ^1.0.0` and `build_runner: ^2.15.0`** to `dev_dependencies` in `pubspec.yaml`. They are already present in any Chassis-bootstrapped project; check before adding. No `build.yaml`.
- [ ] **Step 2 — Author or modify the handler** following `chassis-create-command`, `chassis-create-read-query`, or `chassis-create-watch-query`. Place `@chassisHandler` on the class; give it a primary constructor whose `final` parameters are its dependencies (prefer named).
- [ ] **Step 3 — Make the handler reachable.** Export it from the feature barrel (or import it) so the `@ChassisApp` / `@chassisModule` library reaches it through the import graph.
- [ ] **Step 4 — Run the generator.**
  - One-shot: `dart run build_runner build --delete-conflicting-outputs`.
  - Watch mode: `dart run build_runner watch --delete-conflicting-outputs`.
- [ ] **Step 5 — Read the output.** A generator error names the offending element and the violated contract — fix at the source, not in generated files. See [Build-Time Errors](#build-time-errors).
- [ ] **Step 6 — Update `main()`** if the mediator constructor gained a new parameter (because the new handler depends on a new repository): construct the repository and pass it to `AppMediator(...)` inside `Chassis.initialize`. See `chassis-bootstrap-app`.
- [ ] **Step 7 — Dispatch the message from a ViewModel**: `run(CreateOrderCommand(...))` — the message object itself, through the ViewModel's `run`/`read`/`watch`. See `chassis-create-view-model`.

## Examples

### `pubspec.yaml`

```yaml
environment:
  sdk: ^3.13.0

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
import 'package:app/orders/domain/order.dart';
import 'package:app/orders/domain/order_repository.dart';

final class CreateOrderCommand({
  required final String userId,
  required final List<OrderItem> items,
}) extends Command<Order> {
  @override
  Map<String, Object?> get params => {'userId': userId, 'items': items.length};
}

@chassisHandler
class CreateOrderHandler({
  required final OrderRepository orderRepository,
}) implements CommandHandler<CreateOrderCommand, Order> {
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
// ✅ Primary constructor — unnamed, generative; dependencies as named
// parameters.
@chassisHandler
class CreateOrderHandler({
  required final OrderRepository orderRepository,
}) implements CommandHandler<CreateOrderCommand, Order> {
  // ...
}
```

### Anti-pattern: a reachable message with no handler

```dart
// ❌ Build error: the message is reachable from the @ChassisApp graph but
// nothing handles it — dispatching it could only throw at runtime.
final class ExportReportCommand({required final String reportId})
    extends Command<void>;
```

```dart
// ✅ Either write and annotate the handler...
@chassisHandler
class ExportReportHandler
    implements CommandHandler<ExportReportCommand, void> { /* ... */ }

// ✅ ...or opt out explicitly while it is being written.
@unhandledMessage // handler lands in the next commit
final class ExportReportCommand({required final String reportId})
    extends Command<void>;
```

### Anti-pattern: editing generated files

Generated `.chassis.dart` files are overwritten on every build. If something looks wrong in the output, the fix is upstream — usually in the handler's constructor or the annotation site. Editing the generated file is throwaway work.

## Build-Time Errors

The generator fails the build — never emitting a partial mediator — with one of these errors. Each one names the exact element and contract violation:

| Error message (abridged) | Meaning | Fix |
|---|---|---|
| `No handler is registered for these messages, which are reachable from the @ChassisApp library <uri>: - <Message> (<uri>) ...` | The missing-handler check: a concrete Command/Query the app code can name has no handler. One error lists every orphan. | Annotate a handler with `@chassisHandler` and rerun `build_runner`; if the message lives in another package, declare its `@chassisModule` in `modules: [...]`; or opt out with `@unhandledMessage`. |
| `Both <HandlerA> (<uri>) and <HandlerB> (<uri>) handle <MessageType>` | Two handlers (across app + modules) claim the same command/query type. | Delete one, or split the message into two types. |
| `<Handler> implements both CommandHandler and ReadHandler` | One handler class handles exactly one operation. | Split it into two handler classes. |
| `<Handler> ... has no unnamed generative constructor` | The generator instantiates handlers itself and found no constructor it can call. | Add an unnamed generative constructor (no factory). |
| `<Handler> is annotated with @chassisHandler but is private` | The generated mediator instantiates handlers from another file. | Make the handler class public. |
| `<Handler> ... implements none of CommandHandler, ReadHandler, or WatchHandler` | `@chassisHandler` sits on a class that is not a handler. | Implement the matching handler interface, or remove the annotation. |
| `<Handler> is generic` | The generator instantiates handlers concretely. | Remove the type parameters. |
| `<Handler>'s constructor parameter ... would let the handler dispatch through the mediator` | A handler declares the `Mediator` (or a generated mediator class) as a dependency — handlers must not dispatch. | Model the flow as one command whose handler composes the repositories it needs; extract shared logic into an injected service. |
| `<Handler>'s constructor parameter ... has the private type ...` | The generated mediator declares this dependency as a constructor parameter in another library, where a private type (including nested type arguments) cannot be referenced. | Make the type public or wrap it in a public class. |
| `<Handler>'s constructor parameter ... has a function type / record type` | The generator cannot reference function or record types in generated code. | Wrap it in a class. |
| `<Message> (handled by <Handler>) is generic` | Mediator dispatch is keyed by the exact runtime type of the message, which type arguments would make ambiguous. | Declare one concrete message class per operation. |
| `No @chassisHandler class is reachable from the library declaring <Module>` | The `@chassisModule` library does not import any handler. Raised at the module's own build, and again at the app's if the module is listed. | Declare the module in the package barrel (or make the barrel export the handlers). |
| `@ChassisApp on library <uri> found no @chassisHandler class` | Nothing reachable in the app package and no modules declared. | Import the handlers (directly or via a barrel) or declare modules. |
| `@ChassisApp on library <uri> lists <X> in modules, which is not a class annotated with @chassisModule` | `modules:` contains a non-module type. | List only `@chassisModule`-annotated declaration classes. |
| `@ChassisApp annotates the class <X>, but it must annotate the library directive` | `@ChassisApp` sits on a class (pre-1.0 form). | Remove the class and put the annotation on `library;` at the top of the file. |

One diagnostic is a **warning**, not an error:

| Warning message (abridged) | Meaning | Fix |
|---|---|---|
| `<Handler> (<uri>) is annotated with @chassisHandler but belongs to package <X>, which is neither the app package nor a declared module — it will NOT be registered on <AppMediator>` | The walk found a foreign handler it is not allowed to register (discovery never crosses package boundaries on its own). | Add that package's `@chassisModule` class to `@ChassisApp(modules: [...])`. |

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Build fails listing unhandled messages | A reachable Command/Query has no `@chassisHandler` handler — new message without its handler, handler not annotated, or handler unreachable from the graph. | Write/annotate the handler and export it from the barrel; declare the owning package's module; or `@unhandledMessage` for work in progress. |
| `HandlerNotRegisteredError` at runtime | Stale generated mediator — the generator was not re-run after wiring changes. (The missing-handler check turns most of these into build errors.) | Run `dart run build_runner build --delete-conflicting-outputs`. |
| `DuplicateHandlerError` at startup | Manual `register*Handler` call on top of the generated constructor's registration. | Remove the manual registration — the generated mediator owns it. |
| Compile error in `<file>.chassis.dart` after a refactor | Stale generated file references an old signature. | Re-run with `--delete-conflicting-outputs`. |
| New parameter on `AppMediator(...)` causes a compile error in `main()` | `chassis_builder` correctly added a required dependency; the composition root has not been updated. | Construct the new repository and pass it to `AppMediator(...)` inside `Chassis.initialize`. See `chassis-bootstrap-app`. |
| Warning: handler `will NOT be registered` | The handler lives in a package that is neither the app's nor a declared module's. | Declare `@chassisModule` in that package's barrel and list it in `@ChassisApp(modules: [...])`. |
| Generator runs but no output appears | Annotation typo (`@ChassisHandler` instance instead of `@chassisHandler`), the file is outside `lib/`, or no `@ChassisApp` library exists in the package. | Check the annotation matches the symbol exported by `package:chassis/chassis.dart` and that a composition root exists. |
