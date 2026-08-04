# Changelog

## 1.0.0

First stable release.

### Breaking changes

- `Async<T>`: `AsyncLoading.previous` and `AsyncError.previous` are now typed
  `AsyncData<T>?` instead of `T?`. A non-null `previous` proves a value
  existed, which makes `hasValue`/`valueOrNull` correct for nullable `T`
  (`Async<int?>.data(null).hasValue` is now `true`). Factories changed
  accordingly: `Async.loading({AsyncData<T>? previous})`,
  `Async.error(error, {stackTrace, AsyncData<T>? previous})`.
- `Mediator`: duplicate handler registration now throws
  `DuplicateHandlerException` unconditionally (debug and release behave
  identically). Previously the check only ran in `assert` mode and release
  builds silently overwrote handlers.
- `Mediator.operator+` removed. Composition happens at build time through the
  module system (`@chassisModule` / `@ChassisApp` and `chassis_builder`).
- Dispatching an unregistered command/query now throws
  `HandlerNotRegisteredException` (with an actionable message) instead of a
  bare `Exception`.
- `ReadQuery`/`WatchQuery` now `extend` `Query` (previously `implements`).
- Removed `GenerateQueryHandler`/`GenerateCommandHandler` annotations and the
  repository-method generation flow. Handlers are written by hand and wired
  with `@chassisHandler`.
- Removed the unused `rxdart` dependency: the core is now pure Dart with only
  `meta`.

### New

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
