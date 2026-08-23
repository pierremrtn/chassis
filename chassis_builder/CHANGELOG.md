# Changelog

## 1.0.0

First stable release — the generator behind Chassis's message-direct
architecture.

Requires Dart 3.13+: handlers and messages written with primary constructors
(stable since Dart 3.13) are fully supported by the generator, and all
examples use them.

### Generated output

- `@ChassisApp(modules: [...], mediatorName: 'AppMediator')` on the
  composition root's *library directive* (`@ChassisApp(...) library;`)
  generates `<file>.chassis.dart` containing exactly one class: the app
  mediator, extending `Mediator`, with a registration-only constructor.
  Handler dependencies are collected across all handlers, deduplicated, and
  become required named constructor parameters. No per-message methods are
  generated: dispatch goes through the inherited `run`/`read`/`watch`, so
  middlewares always apply and ViewModels depend only on message types.
  Placing `@ChassisApp` on a class fails the build with a migration message.
- `@chassisModule` generates no output. Its single role is cross-package
  handler discovery: the import-graph walk is scoped to each root library's
  own package, so handlers living in a shared package are found only when
  that package's module class is listed in `@ChassisApp(modules: [...])`.
  Module libraries are still validated at their own build time (handler
  shape, one handler per message), so wiring mistakes fail early in the
  module's package.
- Handler constructors may declare their dependencies as positional or named
  parameters; the generator passes each dependency back the way it is
  declared. Named parameters are the recommended style for handlers with
  more than one dependency.
- Message and result types are never denoted in generated code (registration
  relies on inference), so private message and result types are fine.
- Robust identifier generation: dependency parameter names are derived from
  resolved elements (generic and nullable types produce valid names;
  same-named types from different packages get distinct parameters).

### Build-time checks

- **A missing handler is a build error at the declaration site.** Every
  concrete `Command`/`ReadQuery`/`WatchQuery` reachable from the
  `@ChassisApp` library's graph must have a handler, or the build fails with
  one error listing every orphan message, its URI, and the fixes: annotate a
  handler with `@chassisHandler` (and rerun `build_runner`), declare the
  module that provides it, or opt out with `@unhandledMessage` while the
  handler is being written.
- Two handlers for the same message type fail the build — each command/query
  has exactly one handler.
- A handler class implementing two operation interfaces (e.g.
  `CommandHandler` + `ReadHandler`) fails the build: split it into two
  handler classes.
- A handler whose constructor depends on the `Mediator` (or on anything
  generated) fails the build — handlers never dispatch; a multi-step flow is
  one handler composing several repositories or services.
- Private or generic handler classes, generic message classes, handlers
  without an unnamed generative constructor, and function, record, or
  private types in handler constructors (including nested type arguments)
  are rejected with actionable `InvalidGenerationSourceError`s. The
  generator never emits a partial mediator.
- An out-of-package `@chassisHandler` not covered by a declared module logs
  a warning naming the handler, its package, and the
  `@ChassisApp(modules: [...])` fix.

### Compatibility

- Requires `analyzer >=12 <15`, `build ^4`, `source_gen ^4`.
