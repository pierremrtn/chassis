# Chassis 1.0.0 — API reference brief (for doc/skill alignment)

Authoritative source: the code. Read these files when in doubt:
- `chassis/lib/src/async.dart`, `chassis/lib/src/mediator/*.dart`, `chassis/lib/src/annotations.dart`
- `chassis_flutter/lib/src/view_model/view_model.dart`, `view_model_provider.dart`, `widgets/async_builder.dart`
- `chassis_builder/lib/src/generator.dart`
- Working end-to-end example: `chassis_builder/example` (app) + `chassis_builder/example_auth` (module)
- Flutter example: `chassis_flutter/example/example.dart`

## Removed (must not appear anywhere in docs/skills)

- `@generateQueryHandler`, `@generateCommandHandler`, `GenerateQueryHandler`,
  `GenerateCommandHandler`, `RepositoryGenerator`, `repository_builder`,
  `.handlers.dart` outputs, the "90/10 principle" framing.
- `Mediator.operator+` (mediator merging). Composition is at build time now.
- `@chassisMediator` / `ChassisMediator` annotation.
- Builder options `mediator_name` / `output_name`; the `$lib$` →
  `app_mediator.dart` output model; generated `extension on Mediator`
  (typed methods are now instance methods of the generated class).
- build.yaml configuration for consumers: none needed anymore
  (`auto_apply: dependents`). Consumers just depend on `chassis_builder` as a
  dev dependency and run `dart run build_runner build`.

## Codegen model (new)

- `@chassisHandler` on a handler class → picked up by generation. Handler must
  have an unnamed generative constructor with positional dependencies only.
- `@chassisModule` on a declaration class (e.g. `final class AuthModule {}`)
  in a shared package → generates `<file>.chassis.dart` next to it, with
  `abstract interface class AuthMediator` (name = class name minus trailing
  `Module`, plus `Mediator`) containing one typed method per handler
  reachable from that library's import graph (within the same package).
  Convention: declare the module in the package barrel so every handler is
  reachable.
- `@ChassisApp(modules: [AuthModule], name: 'AppMediator')` on a class in the
  app → generates `<file>.chassis.dart` with the concrete mediator:
  `class AppMediator extends Mediator implements AuthMediator { ... }`.
  - Constructor takes every deduplicated handler dependency as a required
    named parameter, instantiates handlers, and registers them.
  - Every generated method dispatches through `run`/`read`/`watch`, so
    middlewares ALWAYS apply.
  - Missing handler ⇒ the generated class fails to implement the interface ⇒
    compile error. Completeness is compiler-enforced.
  - Build-time errors (never a partial mediator): handler without unnamed
    constructor, handler not implementing a handler interface, two handlers
    for one message type, two modules producing identical method signatures,
    module with no reachable handler, `modules:` listing a non-module class.
- Generated method names: handler class name minus trailing `Handler`, then
  minus trailing `Query`/`Command`, decapitalized. `GetProfileHandler` →
  `getProfile`.
- Import of a module's generated interface: `import 'package:auth/auth.chassis.dart';`

## Core (chassis)

- `Command<R>` and `Query<T>` (sealed; `ReadQuery<T>`/`WatchQuery<T>` extend
  it) expose `Map<String, Object?> get params => const {}` — override to make
  logs useful; `toString()` renders `TypeName{key: value}`. Never put secrets
  in params.
- `Mediator`: `registerQueryHandler`/`registerCommandHandler` throw
  `DuplicateHandlerException` on duplicates (always, not just debug).
  `read`/`watch`/`run` throw `HandlerNotRegisteredException` with actionable
  messages. Both extend `sealed class ChassisException`.
- `LoggingMiddleware({ChassisLogSink sink = const PrintLogSink(), bool
  logStart = false, bool logStreamEvents = false})` — records
  `ChassisLogRecord` (event: start|success|error|streamEvent|streamDone,
  kind: run|read|watch, request, params, elapsed, error, stackTrace). Wire:
  `mediator.addMiddleware(LoggingMiddleware())`.
- `Async<T>` sealed: `AsyncData<T>(value)`, `AsyncLoading<T>({AsyncData<T>?
  previous})`, `AsyncError<T>(error, {stackTrace, AsyncData<T>? previous})`.
  - `previous` is an `AsyncData<T>?` — proves a value existed even when the
    value is `null` (nullable T is fully supported).
  - `hasValue`, `valueOrNull`, `requireValue`, `isLoading`, `hasError`,
    `errorOrNull`; transitions `toLoading()`, `toData(v)`, `toError(e, s)`
    carry data; `==`/`hashCode` implemented.
  - Prefer exhaustive pattern matching over flag checks in examples.

## chassis_flutter

- `ViewModel<T, E>(mediator, {required T initial})`.
- Callback contract of `run`/`watch` (IMPORTANT, documented on the class):
  - `onState` (if provided) fires for EVERY transition (loading/data/error).
  - `onData`/`onError` are ADDITIVE, fired after `onState`. No suppression.
  - Callbacks run outside the internal try/catch: a throwing callback
    propagates; it is never converted into an `AsyncError`.
  - At least one callback is required (assert).
- `run<R>(Future<R> future, {Async<R>? current, bool emitLoading = true,
  onState, onData, onError}) → Future<Async<R>>`. `current` makes loading and
  error emissions carry the existing data (anti-flicker). Callbacks are not
  invoked after dispose.
- `watch<R>(Stream<R> stream, {Object? key, Async<R>? current, bool
  emitLoading = true, onState, onData, onError}) → WatchHandle`. A new watch
  with the same `key` cancels and replaces the previous subscription
  (canonical: `key: #user` when re-watching with new arguments). Without a
  key, subscriptions are additive until dispose. `WatchHandle.cancel()`.
  Stream errors emit a soft error carrying the last data.
- Events: `sendEvent` buffers (bounded) until the FIRST subscriber of
  `events`, then broadcast semantics. `ViewModelProvider.withEvents` receives
  construction-time events. `dispose()` closes the stream.
- `ViewModelProvider(create:)` / `.value(...)` / `.withEvents<T, E>(create:,
  onEvent:)` / `ViewModelProvider.of<T>(context)` — unchanged surface.
- `ConsumerMixin.onEvent<VM, E>(handler)` — unchanged.
- `AsyncBuilder<T>(state:, builder:, loadingBuilder:, errorBuilder:,
  maintainState: true)` — data branch renders for `AsyncData(null)` with
  nullable T; `maintainState` keeps carried data visible while
  loading/erroring.
- `SafeChangeNotifier`/`SafeNotifierMixin` exported.

## Packaging

- Versions: all packages `1.0.0`. License: MIT everywhere.
- Consumers install: `chassis: ^1.0.0`, `chassis_flutter: ^1.0.0`,
  dev: `chassis_builder: ^1.0.0`, `build_runner: ^2.15.0`. No build.yaml.
- The repo docs folder is `docs/` (never `documentation/`).
