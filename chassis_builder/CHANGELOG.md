# Changelog

## 1.0.0

First stable release — full generator rewrite around the module system.

### Breaking changes

- Removed the `RepositoryGenerator` and the
  `@generateQueryHandler`/`@generateCommandHandler` annotations. Handlers are
  written by hand and marked with `@chassisHandler`.
- Removed the `$lib$`-wide `app_mediator.dart` generation and its
  `mediator_name`/`output_name` options, along with the generated
  `extension on Mediator`. Generation is now anchored on the annotated
  elements — the `@ChassisApp` library directive and `@chassisModule`
  classes — and emits `<file>.chassis.dart`.
- Requires `analyzer >=12`, `build ^4`, `source_gen ^4`.

### New

- Handler constructors may declare their dependencies as positional or named
  parameters; the generator passes each dependency back the way it is
  declared. Named parameters are the recommended style for handlers with
  more than one dependency.
- **Module system.** `@chassisModule` on a class (e.g. `AuthModule`) in a
  shared package generates an `abstract interface class AuthMediator` with
  one typed method per `@chassisHandler` reachable from that library within
  the package. Shared ViewModels can depend on the interface without knowing
  the app.
- `@ChassisApp(modules: [AuthModule, ...])` on the composition root's library
  directive generates the app's concrete mediator (named by `mediatorName:`,
  default `'AppMediator'`): it `implements` every module interface (a missing
  handler is a compile error), registers all handlers in its constructor with
  deduplicated dependencies, and every generated method dispatches through
  `run`/`read`/`watch` so middlewares always apply. Cross-package handler
  discovery follows the import graph. Placing `@ChassisApp` on a class fails
  the build with a migration message.
- Conflict detection at build time: two handlers for the same message type,
  or two modules producing identical method signatures, fail the build with
  an explicit error.
- The generator fails loudly with actionable `InvalidGenerationSourceError`s
  (missing unnamed constructor, class not implementing a handler interface,
  module without reachable handlers, ...). It never emits a partial mediator.
- Method names derive from the *message* class name (`CreateUserCommand` →
  `createUser`), never from the handler: renaming a handler (an
  implementation detail) does not change the generated API.
- Generic message/handler classes, and function or record types in message
  constructors and handler dependencies, are rejected at build time with an
  explanation — mediator dispatch is keyed by the exact runtime type of the
  message, and the generator never emits code it cannot reference reliably.
- Robust identifier generation: dependency parameter names are derived from
  resolved elements (generic and nullable types produce valid names;
  same-named types from different packages get distinct parameters).
