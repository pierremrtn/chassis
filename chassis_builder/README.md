# chassis_builder

Code generation for the [Chassis](https://pub.dev/packages/chassis) framework. This package composes your `@chassisHandler` classes into fully typed mediators: shared packages get a generated interface, the app gets a generated implementation, and a missing handler is a compile error.

## Overview

The generator is driven by three annotations from the `chassis` package:

| Annotation | Placed on | Generates |
|------------|-----------|-----------|
| `@chassisHandler` | A handler class | Nothing by itself — marks the class for discovery |
| `@chassisModule` | A declaration class in a shared package (e.g. `final class AuthModule {}`) | `abstract interface class AuthMediator` — one typed method per handler |
| `@ChassisApp(modules: [...])` | The library directive of the app's composition root | The concrete mediator: `class AppMediator extends Mediator implements AuthMediator { ... }` |

Output is always written to `<file>.chassis.dart`, next to the annotated file.

Key properties of the generated code:

* **Compiler-enforced completeness** - The app mediator `implements` every module interface. If a handler is missing, the generated class fails to implement the interface and the app does not compile.
* **Middlewares always apply** - Every generated method dispatches through `Mediator.run`/`read`/`watch`, never calls a handler directly.
* **No partial output** - Any wiring mistake fails the build with an actionable error (see [Build-time errors](#build-time-errors)). The generator never emits a partial mediator.

## Installation

Add to `pubspec.yaml`:

```yaml
dependencies:
  chassis: ^1.0.0

dev_dependencies:
  chassis_builder: ^1.0.0
  build_runner: ^2.15.0
```

**No `build.yaml` is needed.** The builder applies automatically to every package that depends on `chassis_builder` (`auto_apply: dependents`). Just run:

```bash
dart run build_runner build
```

## Usage

### 1. Annotate handlers

Mark each handler with `@chassisHandler`. The handler must implement one of `CommandHandler`, `ReadHandler`, or `WatchHandler`, and must have an unnamed generative constructor whose parameters are its dependencies — positional or named. Prefer named parameters, especially once a handler has more than one dependency:

```dart
import 'package:chassis/chassis.dart';

final class GetProfileQuery extends ReadQuery<String> {
  GetProfileQuery({required this.userId});

  final String userId;
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

### 2. Declare the composition root

Annotate the library directive of a file in your app with `@ChassisApp`. The generator collects every `@chassisHandler` class reachable from this library's import graph (within the app's own package), plus the handlers of each declared module:

```dart
@ChassisApp(mediatorName: 'AppMediator')
library;

import 'package:chassis/chassis.dart';

import 'main.chassis.dart';
```

`@ChassisApp` accepts two parameters:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `modules` | Module declaration classes (annotated with `@chassisModule`) to compose | `const []` |
| `mediatorName` | Name of the generated mediator class | `'AppMediator'` |

### 3. Run code generation

```bash
# One-time generation
dart run build_runner build

# Watch mode (regenerates on file changes)
dart run build_runner watch

# Clean and rebuild
dart run build_runner build --delete-conflicting-outputs
```

### 4. Generated output

For a file `lib/main.dart`, the generator writes `lib/main.chassis.dart` containing the concrete mediator. Every deduplicated handler dependency becomes a required named constructor parameter; the constructor instantiates and registers all handlers:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND

/// Concrete mediator generated from the `@ChassisApp` library
/// `package:my_app/main.dart`.
///
/// All handlers are registered in the constructor; every method dispatches
/// through the mediator, so middlewares always apply.
class AppMediator extends Mediator implements AuthMediator {
  AppMediator({
    required AuthRepository authRepository,
    required ConfigStore configStore,
  }) {
    registerQueryHandler(GetProfileHandler(repository: authRepository));
    registerCommandHandler(LoginHandler(authRepository));
    registerQueryHandler(GetAppConfigHandler(configStore));
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

### 5. Use in the application

```dart
void main() async {
  final mediator = AppMediator(
    authRepository: HttpAuthRepository(),
    configStore: ConfigStore(),
  )..addMiddleware(LoggingMiddleware());

  // Typed dispatch through the generated methods (middlewares apply).
  await mediator.login('ada', 'secret');
  final profile = await mediator.getProfile(userId: '42');
}
```

## Modules

A module is a shareable package exposing handlers behind a generated interface, consumable by any app without knowing the app's concrete mediator.

### Declaring a module

Annotate a declaration class with `@chassisModule`. The generator emits `abstract interface class <Name>Mediator` (class name minus the trailing `Module`, plus `Mediator`) in `<file>.chassis.dart`, with one typed method per handler reachable from the annotated library's import graph within the module's package.

**Convention: declare the module in the package barrel**, so every handler of the package is reachable:

```dart
// package auth — lib/auth.dart
import 'package:chassis/chassis.dart';

export 'src/handlers.dart';

@chassisModule
final class AuthModule {}
```

This generates `lib/auth.chassis.dart`:

```dart
/// Typed mediator interface of the `AuthModule` module.
abstract interface class AuthMediator {
  Future<String> getProfile({required String userId});
  Future<void> login(String username, String password);
}
```

Shared code (ViewModels, services) depends on `AuthMediator` only:

```dart
import 'package:auth/auth.chassis.dart';

class LoginViewModel {
  LoginViewModel(this._mediator);
  final AuthMediator _mediator;
  // ...
}
```

### Composing modules in an app

```dart
@ChassisApp(modules: [AuthModule], mediatorName: 'AppMediator')
library;

import 'package:auth/auth.dart';
import 'package:chassis/chassis.dart';
```

The generated `AppMediator` implements `AuthMediator` and registers the module's handlers alongside the app's own. If the app fails to provide a handler required by a module interface, the generated class does not satisfy the interface and **the app does not compile** — completeness is guaranteed by the type system, not by runtime checks.

## Method naming

Generated method names derive from the *message* class name — never from the handler, which is an implementation detail: renaming a handler does not change the generated API. Strip a trailing `Query` or `Command`, then decapitalize:

| Message | Generated method |
|---------|------------------|
| `GetProfileQuery` | `getProfile` |
| `LoginCommand` | `login` |
| `CreateUserCommand` | `createUser` |
| `WatchTodosQuery` | `watchTodos` |

Method parameters mirror the message's unnamed constructor: positional stay positional, named stay named, defaults are preserved. Return types are `Future<R>` for commands and read queries, `Stream<R>` for watch queries.

## Handler requirements

For a class annotated with `@chassisHandler`:

* It must implement exactly one of `CommandHandler<C, R>`, `ReadHandler<Q, R>`, or `WatchHandler<Q, R>`.
* It must have an unnamed generative constructor — its parameters, positional or named, are its dependencies, injected via the generated mediator's constructor.
* Its message class (the `Command`/`Query`) must have an unnamed generative constructor — its parameters become the generated method's parameters.
* Neither the handler nor its message class may be generic: mediator dispatch is keyed by the exact runtime type of the message.
* Message constructor parameters and handler dependencies must be class types — function and record types are rejected at build time (wrap them in a class).
* Each command/query type must have exactly one handler across the app and its modules.

## Build-time errors

Wiring mistakes fail the build with an actionable error instead of producing a broken mediator. Each error names the offending element:

| Condition | Error |
|-----------|-------|
| Handler has no unnamed generative constructor | `X is annotated with @chassisHandler but has no unnamed generative constructor.` The generator instantiates handlers by calling their constructor with the dependencies it requires. |
| Annotated class is not a handler | `X is annotated with @chassisHandler but implements none of CommandHandler, ReadHandler, or WatchHandler.` |
| Message has no unnamed generative constructor | `X (handled by Y) has no unnamed generative constructor, so no typed mediator method can be generated for it.` |
| Two handlers for one message type | `Both X and Y handle Z. Each command/query type must have exactly one handler across the app and its modules.` |
| Two messages derive the same method name | `X and Y both derive the method name m from their message. Rename one message class to disambiguate.` |
| Message or handler class is generic | `X (handled by Y) is generic.` Dispatch is keyed by the exact runtime type of the message — declare one concrete message class per operation. |
| Function or record type in a message/dependency | `X has a function type (...), which the generator cannot reference in generated code. Wrap it in a class.` |
| Two modules produce identical method signatures | `X and Y both produce the method m with an identical signature.` The type system would silently satisfy both with one implementation, so chassis refuses the composition — rename one message class to disambiguate. |
| Handler, message, or module class is private | `X ... is private.` The generated file lives elsewhere (it instantiates handlers, constructs messages, and implements module interfaces), so these classes must be public. |
| Default value references a non-`dart:core` declaration | `X.p (handled by Y) has the default value (...), which references Z from ...` The generated mediator repeats default values verbatim with only `dart:core` in scope — remove the default or express it with `dart:core` alone. |
| Module with no reachable handlers | `No @chassisHandler class is reachable from the library declaring X.` A module must be declared in a library that (transitively) imports every handler of the package — typically the package barrel. |
| App with no handlers and no modules | `@ChassisApp on library X found no @chassisHandler class.` Import your handlers (directly or via a barrel) or declare modules. |
| `modules:` lists a non-module class | `@ChassisApp on library X lists Y in modules, which is not a class annotated with @chassisModule.` |
| `@ChassisApp` placed on a class | `@ChassisApp annotates the class X, but it must annotate the library directive.` Remove the class and put the annotation on `library;` at the top of the file. |

### Other issues

**Generated files not updating**

```bash
dart run build_runner build --delete-conflicting-outputs
```

**A handler is missing from the generated mediator**

Handler discovery walks the import graph from the annotated library, restricted to the same package. Make sure the handler's file is (transitively) imported by the `@ChassisApp` library (or the library containing the `@chassisModule` class) — the package barrel is the conventional place to guarantee this.

## Example

See the package's working examples:

* [example](https://github.com/pierremrtn/chassis/blob/main/chassis_builder/example/) - An app composing a module with `@ChassisApp`
* [example_auth](example_auth/) - A shared module package with `@chassisModule`

## Next Steps

* **[Quick Start](https://github.com/pierremrtn/chassis/blob/main/docs/00_quick_start.md)** - See code generation in action
* **[Code Generation](https://github.com/pierremrtn/chassis/blob/main/docs/03_code_generation.md)** - Comprehensive guide to annotations
* **[Business Logic Layer](https://github.com/pierremrtn/chassis/blob/main/docs/02_business_logic.md)** - Commands, Queries, and Handlers
* **[chassis](https://pub.dev/packages/chassis)** - Core package documentation

## License

MIT License - See [LICENSE](https://github.com/pierremrtn/chassis/blob/main/LICENSE) for details.
