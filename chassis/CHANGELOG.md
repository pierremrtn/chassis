# Changelog

## 1.0.0

First stable release.

Requires Dart 3.13+: the library and every documented example use primary
constructors (`class const AsyncData<T>(final T value)`), stable since
Dart 3.13.

### Breaking changes

- `Async<T>`: `AsyncLoading.previous` and `AsyncError.previous` are now typed
  `AsyncData<T>?` instead of `T?`. A non-null `previous` proves a value
  existed, which makes `hasValue`/`valueOrNull` correct for nullable `T`
  (`Async<int?>.data(null).hasValue` is now `true`). Factories changed
  accordingly: `Async.loading({AsyncData<T>? previous})`,
  `Async.error(error, {stackTrace, AsyncData<T>? previous})`.
- `Mediator`: duplicate handler registration now throws
  `DuplicateHandlerError` unconditionally (debug and release behave
  identically). Previously the check only ran in `assert` mode and release
  builds silently overwrote handlers.
- `Mediator.operator+` removed. Composition happens at build time through the
  module system (`@chassisModule` / `@ChassisApp` and `chassis_builder`).
- Dispatching an unregistered command/query now throws
  `HandlerNotRegisteredError` (with an actionable message) instead of a
  bare `Exception`.
- Wiring mistakes are Dart `Error`s, not `Exception`s: the
  `sealed class ChassisError extends Error` family
  (`HandlerNotRegisteredError`, `DuplicateHandlerError`) replaces the
  `ChassisException` family. They are programming errors with no legitimate
  catch site; crash reporting classifies them as fatal, and `on Exception`
  clauses no longer swallow them.
- `MediatorMiddleware` generics simplified: `onRun<R>(Command<R> command,
  NextRun<R> next)` (idem `onRead`/`onWatch`). The chain is always built with
  the abstract message type, so the former `<C extends Command<R>, R>` type
  parameter never carried a concrete type — it promised a specialization
  lever that did not exist.
- `Command`/`Query` implement structural equality: two messages of the same
  type with equal `params` are the same operation (`==`/`hashCode` derived
  from `runtimeType` + `params`). This is the identity contract that caching
  or deduplication middlewares may rely on.
- Registering a handler under an abstract message type
  (`registerQueryHandler<ReadQuery<String>, String>(...)`, typically via an
  upcast handler variable) now throws an `ArgumentError` at registration
  instead of failing at every dispatch with `HandlerNotRegisteredError`.
- `ReadQuery`/`WatchQuery` now `extend` `Query` (previously `implements`).
- Removed `GenerateQueryHandler`/`GenerateCommandHandler` annotations and the
  repository-method generation flow. Handlers are written by hand and wired
  with `@chassisHandler`.
- Removed the unused `rxdart` dependency: the core is now pure Dart with only
  `meta`.

### New

- `CrashReportingMiddleware`: reports every failure crossing the mediator to
  a pluggable crash reporter, then rethrows (never swallows). Dart `Error`s
  are reported as fatal (programming bugs, including chassis wiring errors),
  everything else as non-fatal (expected domain failures). Watch errors are
  reported from the stream and still reach the subscriber.
- `@unhandledMessage` annotation: opts a command/query out of
  `chassis_builder`'s "every reachable message has a handler" build check
  while the handler is being written.
- Bundled LLM skills (`skills/`) and a `dart run chassis:install_skills`
  installer that symlinks them from the resolved package into the project's
  `.claude/skills/` (target directory and `--copy` mode available), so an AI
  coding assistant follows the framework's conventions at the version the
  project pins.
- `LoggingMiddleware`: traces every mediator operation (dispatch, outcome,
  duration, errors with stack traces, optional stream events) through a
  pluggable `ChassisLogSink`. Errors are always rethrown.
- `Command.params` / `Query.params`: overridable parameter maps used by
  `toString` and `LoggingMiddleware`, so traces read
  `CreateUserCommand{name: John}` instead of a bare type name.
- `Async.requireValue`: returns the available value or throws a descriptive
  `StateError`.
- `Async.when` (exhaustive fold over data/loading/error) and `Async.map`
  (value transform preserving state, error, and carried previous data).
- `LoggingMiddleware` preserves the broadcast/single-subscription nature of
  watched streams (per-listener records on broadcast streams; elapsed times
  measured from dispatch).
- `Async` subclasses implement `==`/`hashCode`.
- New annotations `ChassisModule` and `ChassisApp` powering the module system
  (see `chassis_builder`). `@ChassisApp` annotates the library directive of
  the composition root (`@ChassisApp(...) library;`) and names the generated
  mediator class via `mediatorName:` (default `'AppMediator'`).

## 0.0.1+4

- doc: fix some dart doc comments

## 0.0.1+3

- doc: added pubspec topics.

## 0.0.1+2

- doc: README improvements.

## 0.0.1+1

- doc: README improvements.

## 0.0.1

- Initial version.
