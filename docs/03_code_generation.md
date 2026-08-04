# Code Generation

A hand-wired mediator — a class that instantiates every handler, registers it, and exposes one typed method per operation — is pure plumbing: it contains no decisions, only transcription. As an application grows, transcription is where wiring mistakes accumulate: a handler written but never registered, a dependency threaded to the wrong handler, two teams registering handlers for the same message type. That is why the [Quick Start](00_quick_start.md) already lets the generator produce this file; this guide explains everything behind it.

`chassis_builder` generates that plumbing from three annotations: `@chassisHandler` marks a handler for wiring, `@chassisModule` turns a package's handlers into a shareable, typed mediator interface, and `@ChassisApp` composes handlers and modules into the concrete mediator your application uses. The generated mediator is complete by construction — a missing handler is a compile error, and a conflicting one is a build error. This section explains each annotation, the module composition model, and the guarantees the generator enforces.

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

For every library containing a `@chassisModule` or `@ChassisApp` annotation, the generator emits a `<file>.chassis.dart` file next to it: `main.dart` produces `main.chassis.dart`, `example_auth.dart` produces `example_auth.chassis.dart`. Committing these generated files is recommended — reviewers see exactly what code executes, not just the annotations that produce it, and builds carry no generation-time surprises. Never edit them by hand; they are overwritten on the next build.

## Marking Handlers with @chassisHandler

`@chassisHandler` marks a hand-written handler class for wiring. The generator does not write business logic for you — handlers remain ordinary, testable Dart classes as described in [Business Logic](02_business_logic.md). The annotation only tells the generator that this handler participates in a generated mediator.

```dart
import 'package:chassis/chassis.dart';

final class GetProfileQuery extends ReadQuery<String> {
  GetProfileQuery({required this.userId});

  final String userId;

  @override
  Map<String, Object?> get params => {'userId': userId};
}

@chassisHandler
class GetProfileHandler implements ReadHandler<GetProfileQuery, String> {
  GetProfileHandler({required this.repository});

  final AuthRepository repository;

  @override
  Future<String> read(GetProfileQuery query) =>
      repository.profileOf(query.userId);
}
```

An annotated handler must satisfy two structural requirements, both verified at build time:

- It implements one of the handler interfaces: `CommandHandler`, `ReadHandler`, or `WatchHandler`.
- It has an unnamed generative constructor. Its parameters — positional or named — are the handler's dependencies; the generator passes each one back the way it is declared. Prefer named parameters, especially once a handler has more than one dependency: call sites and tests stay readable, and adding a dependency cannot silently reorder the others.

The message class handled by the handler also needs an unnamed generative constructor, because the generator produces a typed mediator method that constructs the message from its parameters. The method's signature mirrors the message constructor exactly — positional stays positional, named stays named, optionals keep their defaults.

The method name is derived mechanically from the *message* class name (never from the handler, which is an implementation detail — renaming a handler does not change the generated API): strip a trailing `Query` or `Command`, then decapitalize. `GetProfileQuery` becomes `getProfile`, `LoginCommand` becomes `login`, `WatchTodosQuery` becomes `watchTodos`. Because naming is mechanical, following the naming conventions from [coding_rules.md](coding_rules.md) yields a predictable, discoverable API for free.

## The App Mediator: @ChassisApp

`@ChassisApp` marks the composition root of an application. Place it on the library directive — the `library;` line at the top of the file — of a library that imports your handlers, directly or through a barrel:

```dart
// lib/main.dart
@ChassisApp(modules: [AuthModule], mediatorName: 'AppMediator')
library;

import 'package:chassis/chassis.dart';
import 'package:example_auth/example_auth.chassis.dart';
import 'package:example_auth/example_auth.dart';

import 'main.chassis.dart';
```

The generator collects every `@chassisHandler` class reachable from the annotated library's import graph (within the app's own package), plus every handler contributed by the listed modules, and emits the concrete mediator in `main.chassis.dart`:

```dart
// main.chassis.dart (generated)
class AppMediator extends Mediator implements AuthMediator {
  AppMediator({
    required AuthRepository authRepository,
    required ConfigStore configStore,
  }) {
    registerQueryHandler(GetProfileHandler(repository: authRepository));
    registerCommandHandler(LoginHandler(repository: authRepository));
    registerQueryHandler(GetAppConfigHandler(store: configStore));
  }

  @override
  Future<String> getProfile({required String userId}) =>
      read(GetProfileQuery(userId: userId));

  @override
  Future<void> login(String username, String password) =>
      run(LoginCommand(username, password));

  Future<String> getAppConfig() => read(GetAppConfigQuery());
}
```

Three properties of this generated class carry the architectural weight:

**The constructor is the dependency manifest.** Every distinct dependency across all handlers appears once as a required named parameter, deduplicated by type. Add a handler that needs a new repository, rebuild, and the constructor gains a parameter — the composition root stops compiling until you provide it. Wiring mistakes surface at compile time, not at runtime.

**Every typed method dispatches through the mediator.** `login(...)` calls `run(LoginCommand(...))`, `getProfile(...)` calls `read(GetProfileQuery(...))`. The typed methods are instance methods of the generated class — not extensions on `Mediator` — and because they route through `run`, `read`, and `watch`, middleware always applies, whether an operation is invoked through its typed method or dispatched as a raw message.

**The class name is yours to choose.** `mediatorName:` names the generated mediator class; it defaults to `'AppMediator'`.

Constructing and using the mediator looks like this:

```dart
void main() async {
  final mediator = AppMediator(
    authRepository: FirebaseAuthRepository(),
    configStore: ConfigStore(),
  )..addMiddleware(LoggingMiddleware());

  await mediator.login('ada', 'secret');
  final profile = await mediator.getProfile(userId: '42');
}
```

Typing `mediator.` in the IDE lists every operation the application supports, with full parameter types. The generated mediator is the discoverable, type-safe catalog of your application's capabilities.

## Modules: Sharing Features Across Apps

Larger organizations split features into packages: an `auth` package, a `billing` package, each with its own commands, queries, and handlers, reused by several applications. The module system makes such a package a first-class unit of composition with a typed contract.

### Declaring a module with @chassisModule

A module is declared by annotating a class in the shared package, conventionally in the package barrel so that every handler is reachable from its imports:

```dart
// package example_auth — lib/example_auth.dart
import 'package:chassis/chassis.dart';

export 'src/handlers.dart';

@chassisModule
final class AuthModule {}
```

The generator emits `example_auth.chassis.dart` next to it, containing an abstract interface named after the module — the class name minus a trailing `Module`, plus `Mediator` — with one typed method per handler reachable from the library's import graph within the package:

```dart
// example_auth.chassis.dart (generated)
abstract interface class AuthMediator {
  Future<String> getProfile({required String userId});
  Future<void> login(String username, String password);
}
```

The module package ships this interface; consumers import it with:

```dart
import 'package:example_auth/example_auth.chassis.dart';
```

Note what the module does *not* contain: registration code or a concrete mediator. A module declares operations; the application that composes it decides how they are wired and which repository implementations back them. The module's handlers depend on repository interfaces (like `AuthRepository` above), and the app supplies the implementations through the generated constructor.

One consequence is part of the module contract: the app's generated mediator instantiates the module's handlers directly, importing the libraries that declare them — including libraries under the module's `lib/src/`. Handler classes must therefore be public, and the files declaring them must remain importable: moving or renaming them inside `src/` is a breaking change for composing apps (it invalidates their generated code until they re-run `build_runner`), even though no hand-written code references those files.

### Composing modules and enforcing completeness

An application adopts a module by listing it in `@ChassisApp(modules: [...])`. The generated mediator then `implements` the module's interface, and this is where completeness becomes compiler-enforced: if a handler of the module were missing, the generated class would fail to implement `AuthMediator`, and the project would not compile. There is no runtime discovery step to forget and no registration list to keep in sync.

Modules also compose with the app's own handlers. In the example above, `GetAppConfigHandler` belongs to the app package and appears in the same generated mediator alongside the module's operations, without belonging to any module interface.

### Sharing ViewModels against the module interface

Because the interface is a plain Dart type, shared packages can build on it — including Flutter presentation code. A module can export ViewModels written against its own mediator interface, without knowing anything about the applications that will host them:

```dart
// In the auth package — depends only on the module's generated interface.
class LoginViewModel extends ViewModel<LoginState, LoginEvent> {
  LoginViewModel(this._auth) : super(LoginState.initial());

  final AuthMediator _auth;

  void login(String username, String password) {
    run(
      () => _auth.login(username, password),
      onSuccess: (_) => sendEvent(const LoginSucceededEvent()),
      onError: (error) => sendEvent(LoginFailedEvent(error)),
    );
  }
}
```

The application's generated mediator implements `AuthMediator`, so the app passes it straight to the ViewModel:

```dart
ViewModelProvider(
  create: (_) => LoginViewModel(mediator),
  child: const LoginScreen(),
);
```

This is the module composition story end to end: the shared package owns messages, handlers, the generated interface, and optionally ViewModels; the application owns the repository implementations and the single generated mediator that binds everything together.

## Build-Time Guarantees

The generator treats every wiring ambiguity as a build failure with an actionable message — it never emits a partial mediator. The build fails when:

- A `@chassisHandler` class has no unnamed generative constructor.
- A `@chassisHandler` class implements none of `CommandHandler`, `ReadHandler`, or `WatchHandler`.
- Two handlers — across the app and all its modules — handle the same command or query type. Each message type must have exactly one handler.
- Two handlers — across the app and all its modules — derive typed methods with the same name, or produce methods with identical signatures. Either would emit invalid or silently-merged Dart, so the generator refuses the composition and asks you to rename one message class.
- A handler, message, or module class is private (`_Foo`) — the generated file lives elsewhere and could not reference it.
- A message constructor parameter has a default value that references anything outside `dart:core` — the generated method repeats the default verbatim, with only `dart:core` in scope.
- A `@chassisModule` class has no reachable `@chassisHandler` — usually a sign the module was not declared in the package barrel.
- `@ChassisApp(modules: [...])` lists a class that is not annotated with `@chassisModule`.
- `@ChassisApp` is placed on a class instead of the library directive.

These checks complement the compile-time completeness guarantee (a missing module handler makes the generated class fail to implement the module interface) and the Mediator's own runtime protections for manually wired handlers: registering two handlers for one type throws `DuplicateHandlerException`, and dispatching a message with no handler throws `HandlerNotRegisteredException` — see [Error Management](error_management.md).

If the generator seems to produce nothing, check that the annotation is spelled exactly (`@chassisHandler`, `@chassisModule`, `@ChassisApp`) and that the handlers are reachable from the annotated library's imports within the same package.

## Summary

Code generation removes the transcription layer between your handlers and your mediator. `@chassisHandler` marks hand-written handlers, `@chassisModule` turns a package's handlers into a typed, shareable mediator interface, and `@ChassisApp` composes modules and app handlers into one concrete mediator whose constructor is the dependency manifest of the application. Typed methods are instance methods of the generated class, always dispatch through the mediator so middleware applies, and follow a mechanical naming rule that keeps the API predictable. Completeness is enforced by the compiler, and conflicts are rejected at build time with actionable errors.

With the wiring automated, the next section focuses on connecting this architecture to Flutter's widget tree through ViewModels and reactive widgets in [UI Integration](04_ui_integration.md).
