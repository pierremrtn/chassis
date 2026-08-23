# Code Generation

A hand-wired mediator — a class that instantiates every handler and registers it with its dependencies — is pure plumbing: it contains no decisions, only transcription. As an application grows, transcription is where wiring mistakes accumulate: a handler written but never registered, a dependency threaded to the wrong handler, two teams registering handlers for the same message type. That is why the [Quick Start](00_quick_start.md) already lets the generator produce this file; this guide explains everything behind it.

`chassis_builder` generates exactly one thing: the application's concrete mediator — a class whose *only* member is a constructor that takes every handler dependency as a required named parameter and registers every handler. No per-message methods, no interfaces, nothing else. Three annotations drive it: `@chassisHandler` marks a handler for wiring, `@ChassisApp` marks the composition root the generator walks, and `@chassisModule` extends that walk across package boundaries. Around this single generated class, the builder enforces the framework's flagship guarantee: a reachable message without a handler is a **build error**, not a runtime surprise. This section explains each annotation, the discovery model, and every guarantee the generator enforces.

## Setup

Code generation requires `chassis_builder` and `build_runner` as dev dependencies. No `build.yaml` is needed — the builder applies itself automatically to any package that depends on it.

```yaml
# pubspec.yaml
dependencies:
  chassis: ^1.0.0
  chassis_flutter: ^1.0.0

dev_dependencies:
  chassis_builder: ^1.0.0
  build_runner: ^2.15.0
```

Run the generator with `build_runner`. The build command runs once and exits, suitable for CI. The watch command monitors file changes and regenerates automatically, ideal for development.

```bash
# One-time generation
dart run build_runner build

# Watch mode (auto-regenerates on file changes)
dart run build_runner watch
```

For the library carrying the `@ChassisApp` annotation, the generator emits a `<file>.chassis.dart` file next to it: `mediator.dart` produces `mediator.chassis.dart`. (`@chassisModule` produces no output — see [Modules](#modules-cross-package-handler-discovery).) Committing the generated file is recommended — reviewers see exactly what code executes, not just the annotations that produce it, and builds carry no generation-time surprises. Never edit it by hand; it is overwritten on the next build.

## Marking Handlers with @chassisHandler

`@chassisHandler` marks a hand-written handler class for wiring. The generator does not write business logic for you — handlers remain ordinary, testable Dart classes as described in [Business Logic](02_business_logic.md). The annotation only tells the generator that this handler must be registered in the generated mediator's constructor.

```dart
import 'package:chassis/chassis.dart';

final class GetProfileQuery extends ReadQuery<String> {
  GetProfileQuery({required this.userId});

  final String userId;

  @override
  Map<String, Object?> get params => {'userId': userId};
}

@chassisHandler
class GetProfileQueryHandler implements ReadHandler<GetProfileQuery, String> {
  GetProfileQueryHandler({required this.repository});

  final AuthRepository repository;

  @override
  Future<String> read(GetProfileQuery query) =>
      repository.profileOf(query.userId);
}
```

An annotated handler must satisfy a few structural requirements, all verified at build time:

- It is public and non-generic — the generated mediator instantiates it from another file.
- It implements exactly **one** of the handler interfaces: `CommandHandler`, `ReadHandler`, or `WatchHandler`. One handler class handles one operation; a class implementing two interfaces is a build error asking you to split it.
- It has an unnamed generative constructor. Its parameters — positional or named — are the handler's dependencies; the generator passes each one back the way it is declared. Prefer named parameters, especially once a handler has more than one dependency: call sites and tests stay readable, and adding a dependency cannot silently reorder the others.
- Its dependencies are types the generated file can reference: public classes — not private types, not function or record types (wrap those in a class), and never the `Mediator` or anything generated, because [handlers do not dispatch](coding_rules.md#dont-dispatch-commands-or-queries-from-handlers-or-middleware).

The message class must be one concrete, `final` class per operation, and non-generic — mediator dispatch is keyed by the message's exact runtime type, which type arguments would make ambiguous. Message and result types are never spelled out in generated code (registration relies entirely on type inference), so private message and result types are fine.

Nothing in the generated API derives from the handler's name: generated identity comes from the *message*, and renaming a handler changes nothing outside its own file. The `<MessageName>Handler` convention (`CreateUserCommand` → `CreateUserCommandHandler`) is for humans, enforced by [coding_rules.md](coding_rules.md#do-name-handlers-after-their-full-message-name-plus-handler), not by the generator.

## The App Mediator: @ChassisApp

`@ChassisApp` marks the composition root of an application. Place it on the library directive — the `library;` line at the top of the file — of a dedicated `lib/mediator.dart` whose two jobs are carrying the annotation and holding the imports that make every handler reachable:

```dart
// lib/mediator.dart — the composition root
@ChassisApp(modules: [AuthModule], mediatorName: 'AppMediator')
library;

import 'package:chassis/chassis.dart';

// The auth feature lives in its own package: its handlers are contributed
// by the AuthModule declaration above, not by this import.
import 'package:auth/auth.dart';

// These imports make the app's own handlers reachable from the walk.
import 'package:app/config/application/application.dart';

export 'mediator.chassis.dart';
```

Discovery is an import-graph walk. Starting from the annotated library, the generator traverses every library of the app's *own package* through its imports and exports, collecting each `@chassisHandler` class it finds. Directly imported foreign libraries are scanned through their export closure only — their public API, which is everything the app's code can name — and that scan collects *messages* (for the completeness check below), never handlers: **the walk never registers handlers across a package boundary**. Handlers living in another package are contributed exclusively by listing that package's module class in `modules:` (see [Modules](#modules-cross-package-handler-discovery)); a single-package application needs no modules at all.

From the collected handlers, the generator emits the concrete mediator in `mediator.chassis.dart` — one class, containing nothing but a registration constructor:

```dart
// mediator.chassis.dart (generated)
import 'package:chassis/chassis.dart' as _i1;
import 'package:auth/src/handlers.dart' as _i2;
import 'package:app/config/application/application.dart' as _i3;

/// Concrete mediator generated from the `@ChassisApp` library
/// `package:app/mediator.dart`.
///
/// Registers every reachable handler in its constructor. Dispatch messages
/// through the inherited `run`/`read`/`watch`; middlewares always apply.
class AppMediator extends _i1.Mediator {
  AppMediator({
    required _i2.AuthRepository authRepository,
    required _i3.ConfigStore configStore,
  }) {
    registerQueryHandler(
        _i2.GetProfileQueryHandler(repository: authRepository));
    registerCommandHandler(_i2.LoginCommandHandler(repository: authRepository));
    registerQueryHandler(
        _i2.WatchSessionQueryHandler(repository: authRepository));
    registerQueryHandler(_i3.GetAppConfigQueryHandler(store: configStore));
  }
}
```

Three properties of this generated class carry the architectural weight:

**The constructor is the dependency manifest.** Every distinct dependency across all handlers appears once as a required named parameter, deduplicated by resolved type — here four handlers share two dependencies. Add a handler that needs a new repository, rebuild, and the constructor gains a parameter: the composition root stops compiling until you provide it. Wiring mistakes surface at compile time, not at runtime.

**Registration is the entire generated API.** The class exposes no per-message methods and implements no interfaces. Dispatch goes through the `run`, `read`, and `watch` the class inherits from `Mediator` — so middleware always applies — and in application code even those calls are rare: ViewModels dispatch message objects through their own `run`/`read`/`watch`, without ever referencing `AppMediator` as a type (see [UI Integration](04_ui_integration.md)).

**The class name is yours to choose.** `mediatorName:` names the generated mediator class; it defaults to `'AppMediator'`.

The composition root comes together in `main()`: construct the infrastructure implementations, hand them to the generated constructor, and install the result with `Chassis.initialize` before `runApp`:

```dart
// lib/main.dart
import 'package:app/mediator.dart';

void main() {
  Chassis.initialize(AppMediator(
    authRepository: FirebaseAuthRepository(),
    configStore: ConfigStore(),
  )..addMiddleware(LoggingMiddleware()));
  runApp(const MyApp());
}
```

This is the only place in the application that names `AppMediator`. Everywhere else, the application's capabilities are its catalog of Command and Query classes — which the next guarantee keeps honest.

## Missing Handlers Fail the Build

Because ViewModels dispatch message objects directly, "does a handler exist for this message?" cannot be proven at any call site. So the builder proves it once, for the whole graph, at the declaration site: **every concrete `Command`, `ReadQuery`, or `WatchQuery` reachable from the `@ChassisApp` library — the app package's own import/export graph plus the export closure of directly imported foreign libraries, i.e. everything the app's code can name — must have a handler, or the build fails.** Without this check, dispatching an orphan message could only throw `HandlerNotRegisteredError` at runtime; chassis refuses to build it instead. This is the framework's flagship guarantee: *missing handler = build error*, moved from the call site to the declaration site.

The failure is a single error listing **every** orphan message with its declaring URI — one rebuild shows the full extent of the gap, not one message per rebuild — and names the three fixes:

- Annotate the intended handler with `@chassisHandler` and rerun `build_runner`.
- If the message lives in another package, declare that package's `@chassisModule` class in `@ChassisApp(modules: [...])`.
- If the handler genuinely does not exist yet, opt the message out with `@unhandledMessage`.

`@unhandledMessage` is the explicit escape hatch for work in progress — a visible, greppable TODO rather than a silent gap:

```dart
@unhandledMessage // handler lands in the next commit
final class ExportReportCommand extends Command<void> {
  ExportReportCommand({required this.reportId});

  final String reportId;
}
```

An opted-out message compiles, and dispatching it surfaces as an `AsyncError` at the ViewModel (carrying the `HandlerNotRegisteredError`) — see [Error Management](error_management.md) for how that failure is classified and reported.

## Modules: Cross-Package Handler Discovery

Larger organizations split features into packages: an `auth` package, a `billing` package, each with its own commands, queries, and handlers, reused by several applications. The generator's import-graph walk never crosses package boundaries on its own — that is what modules are for, and it is *all* they are for: **a module is a cross-package handler discovery marker, nothing more**.

A module is declared by annotating a class in the shared package, conventionally in the package barrel so that every handler is reachable from its imports and exports:

```dart
// package auth — lib/auth.dart
import 'package:chassis/chassis.dart';

export 'src/handlers.dart';

@chassisModule
final class AuthModule {}
```

`@chassisModule` generates no output file. Its single role: when an application lists the class in `@ChassisApp(modules: [AuthModule])`, the app-side generator resolves it and walks the import graph of the library that declares it, scoped to the module's package, registering every `@chassisHandler` it finds on the app's mediator. Module libraries are still validated at their own build time — handler shape, one handler per message, at least one reachable handler — so wiring mistakes fail early, in the module's package, not in every app that composes it.

There is no generated module interface, because none is needed: the module's *message types are its contract*. A shared package exports its commands and queries; presentation code in any package — including ViewModels shipped by the module itself — dispatches those messages directly and depends on nothing else. The application's side of the contract is the repository interfaces the module's handlers depend on: the app supplies the implementations through the generated constructor (`authRepository:` in the example above), which is how one `auth` package runs against Firebase in one app and a REST backend in another.

One consequence of registration-by-instantiation is part of the module contract: the app's generated mediator instantiates the module's handlers directly, importing the libraries that declare them — including libraries under the module's `lib/src/` (the generated file carries an `ignore_for_file: implementation_imports` for this reason). Handler classes must therefore be public, and the files declaring them must remain importable: moving or renaming them inside `src/` is a breaking change for composing apps (it invalidates their generated code until they re-run `build_runner`), even though no hand-written code references those files.

Finally, the generator guards the boundary it enforces: if the walk encounters an `@chassisHandler` class in a package that is neither the app's nor a declared module's, it emits a **warning** naming the handler, its package, and the fix — add that package's `@chassisModule` class to `@ChassisApp(modules: [...])` — because that handler will *not* be registered. (If the foreign package's messages are reachable, the missing-handler build error catches the gap as well; the warning diagnoses it precisely.)

## Build-Time Guarantees

The generator treats every wiring ambiguity as a build failure with an actionable message — it never emits a partial mediator. The build fails when:

- A concrete message reachable from the app graph has no handler and no `@unhandledMessage` opt-out — the flagship check, [detailed above](#missing-handlers-fail-the-build).
- Two handlers — across the app and all its modules — handle the same command or query type. Each message type must have exactly one handler; the error names both handler classes.
- A `@chassisHandler` class implements two operation interfaces (e.g. `CommandHandler` *and* `ReadHandler`). One handler class handles exactly one operation — split it into two handler classes.
- A `@chassisHandler` class implements none of `CommandHandler`, `ReadHandler`, or `WatchHandler`.
- A `@chassisHandler` class has no unnamed generative constructor, is private, or is generic — the generator instantiates handlers concretely, from another file.
- A handler constructor parameter has a private type, including nested in type arguments (`List<_Config>`): the generated mediator declares that dependency as a constructor parameter in another library, where a private type cannot be referenced. Make the type public or wrap it in a public class.
- A handler constructor parameter has a function or record type, which generated code cannot reliably reference. Wrap it in a class.
- A handler constructor parameter is typed as the `Mediator`, a subclass, or anything from a generated `.chassis.dart` library. Handlers must not dispatch commands or queries — model the flow as one command whose handler composes the repositories it needs, and share logic between handlers through an injected service. See the [coding rules](coding_rules.md#dont-dispatch-commands-or-queries-from-handlers-or-middleware).
- A handled message class is generic — dispatch is keyed by the message's exact runtime type, which type arguments would make ambiguous. Declare one concrete message class per operation.
- A `@chassisModule` library has no reachable `@chassisHandler` — usually a sign the module class was not declared in the package barrel.
- `@ChassisApp(modules: [...])` lists a class that is not annotated with `@chassisModule`.
- `@ChassisApp` is placed on a class instead of the library directive.
- `@ChassisApp` finds no handler at all — nothing reachable in the app package and no modules declared.

One diagnostic is a warning rather than an error: a reachable `@chassisHandler` in a package that is neither the app's nor a declared module's (see [Modules](#modules-cross-package-handler-discovery)).

These build-time checks are the front line; the `Mediator` itself keeps equivalent runtime protections for manually wired handlers: registering two handlers for one type throws `DuplicateHandlerError`, and dispatching a message with no handler throws `HandlerNotRegisteredError`. Both extend the sealed `ChassisError` — Dart `Error`s, not `Exception`s: wiring bugs to fix, never conditions to catch — see [Error Management](error_management.md).

If the generator seems to produce nothing, check that the annotation is spelled exactly (`@chassisHandler`, `@chassisModule`, `@ChassisApp`), that `@ChassisApp` sits on the library directive, and that the handlers are reachable from the annotated library's imports within the same package.

## Summary

Code generation removes the transcription layer between your handlers and your mediator. `@chassisHandler` marks hand-written handlers; `@ChassisApp` on `lib/mediator.dart` walks the app's import graph and emits one class — a registration-only mediator whose constructor is the dependency manifest of the application, deduplicated across handlers; `@chassisModule` extends the walk across package boundaries and generates nothing. There are no per-message methods and no generated interfaces: message types are the contract, dispatch goes through the inherited `run`/`read`/`watch`, and middleware always applies. Above all, the builder proves at the declaration site that every reachable message has a handler — wiring mistakes are build errors with actionable messages, never runtime surprises.

With the wiring automated, the next section focuses on connecting this architecture to Flutter's widget tree through ViewModels and reactive widgets in [UI Integration](04_ui_integration.md).
