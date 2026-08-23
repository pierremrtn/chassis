---
name: chassis-create-read-query
description: Implement a one-time data fetch in a Chassis application as a `ReadQuery` paired with a hand-written `ReadHandler`, registered via `@chassisHandler`. Use when the UI needs the current value of some data once and does not need to react to subsequent changes — for example, an export, a validation check, or a screen-level bootstrap fetch. If the UI should stay synchronized with the data over time, use `chassis-create-watch-query` instead.
---
# Creating a Chassis ReadQuery

## Contents
- [Core Concepts](#core-concepts)
- [When to Use ReadQuery vs WatchQuery](#when-to-use-readquery-vs-watchquery)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

A **ReadQuery** is an immutable message that requests data once. A **ReadHandler** is the stateless class that fulfills that request — it calls a repository and returns a `Future<T>`. The contract enforces Command-Query Separation: a ReadQuery never mutates state; it dispatches through `read()`, not `run()` or `watch()`.

The type system enforces correct routing. The ViewModel's `read<R>(ReadQuery<R> query, ...)` accepts only `ReadQuery` messages — passing one to `watch(...)` is a compile error, which prevents accidental stream subscriptions for one-time operations. Pick `ReadQuery` deliberately — it is the right tool only when the data is consumed once.

Queries expose `Map<String, Object?> get params => const {}` for observability **and identity**. Overriding it makes `toString()` render `GetUserQuery{userId: 42}` and makes `LoggingMiddleware` traces useful instead of a bare type name — and it is also the message's identity: `==` and `hashCode` are derived from the runtime type plus `params`. **Two messages of the same type with equal `params` are the same operation.** Caching and deduplication middlewares (and tooling) rely on this contract — for a query it is exactly the cache key — so a field that affects the operation but is left out of `params` breaks it.

## When to Use ReadQuery vs WatchQuery

> In modern reactive Flutter applications, most data should come from `WatchQuery` streams to keep the UI automatically synchronized with data changes. Reserve `ReadQuery` for cases where you need the current state only once.
> — `docs/coding_rules.md`

ReadQuery fits cleanly in three situations:

1. **Non-interactive operations** — exports, report generation, file production. The output is consumed once and produces a side artifact, not an updating view.
2. **One-time validation checks** — verifying a promo code, checking permissions, confirming availability. The result drives a single decision and does not need to be re-rendered if the underlying data changes.
3. **Pre-render bootstrapping** — work that runs before a screen exists and feeds a configuration the screen then uses statically.

If the data feeds a screen that should reflect later changes (a profile, a list, a counter, a status), use `chassis-create-watch-query` instead.

## Rules

- **DO** declare the message as `final class [Get|Find]<Resource>Query extends ReadQuery<TReturn>`. Use `Get` as the default verb; use `Find` when the result might not exist. Append `By<Criteria>` when querying by a specific parameter (`GetUserByIdQuery`, `FindCustomerByEmailQuery`). *`ReadQuery` is a base class; messages must `extend` it for the Mediator's runtime type lookup.*
- **DO** make the query immutable — declare its fields as `required final` named parameters in the primary-constructor header (`final class GetUserQuery({required final String userId}) extends ReadQuery<User>`). *Queries are data carriers with structural equality; immutability allows safe caching, retry, and parallel dispatch.*
- **DO** override `params` with **every field that affects the operation** (`{'userId': userId}`). *`params` is both the trace (`toString()` and `LoggingMiddleware` render it) and the identity: same type + equal `params` = same operation — the natural cache key. A field left out of `params` makes two different queries compare equal.* **Never include secrets — passwords, tokens, card numbers — in `params`.**
- **DO** keep queries self-contained — every parameter the handler needs lives on the query.
- **DO** declare the handler as `class <QueryName>Handler implements ReadHandler<TQuery, TReturn>` — `implements`, not `extends`. *The naming is mechanical: query name + `Handler` (`GetUserQuery` → `GetUserQueryHandler`). Handlers fulfill a behavioral contract; `implements` forces explicit method signatures.*
- **DO** keep the handler stateless, with a primary constructor — the unnamed generative constructor — whose `final` parameters are its dependencies typed against repository interfaces, and **PREFER named parameters** (`class GetUserQueryHandler({required final UserRepository userRepository}) implements ...`), especially with two or more dependencies. *`chassis_builder` instantiates handlers itself and passes each dependency back the way it is declared; named parameters keep call sites and tests unambiguous.* See `chassis-register-handler-with-codegen`.
- **DO** annotate the handler with `@chassisHandler` so `chassis_builder` registers it in the generated mediator's constructor. *A concrete query reachable from the `@ChassisApp` graph with no handler is a **build error** — dispatching it could only throw at runtime, so the build fails instead. Annotate the message with `@unhandledMessage` to opt out while the handler is being written.*
- **CONSIDER** adding a cache check inside the handler when the underlying repository call is expensive and the data does not change frequently. *ReadHandlers are a natural place to memoize since they have no side effects.*
- **CONSIDER** validating constructor inputs with `assert` for known constraints (non-empty strings, positive ranges).
- **DON'T** put logic on the query class itself. *The query is a DTO; lookup, caching, and transformation live in the handler.*
- **DON'T** use `ReadQuery` for data the UI should keep synchronized over time. *Use `WatchQuery` — see `chassis-create-watch-query`.*
- **DON'T** catch infrastructure exceptions inside the handler. *Repositories map them to domain exceptions; the handler propagates them.* See `chassis-handle-errors`.
- **DON'T** inject the `Mediator` (or the generated mediator) into the handler to reuse another query — the generator rejects it at build time. *The handler composes its result from the repositories it needs; logic shared between handlers lives in an injected service.*
- **DON'T** reference the generated mediator from a ViewModel — dispatch the query object itself with the ViewModel's `read(...)`. *ViewModels never name the generated class: `read` routes the message through the mediator installed by `Chassis.initialize` (or the constructor override, in tests), so middlewares always apply. The generated mediator appears only at the composition root.*

## Workflow

- [ ] **Step 1 — Confirm ReadQuery is the right choice.** If the UI should reflect later changes to the data, switch to `chassis-create-watch-query`.
- [ ] **Step 2 — Name the query.** `Get<Resource>Query`, `Find<Resource>By<Criteria>Query`, etc. The handler name is mechanically `<QueryName>Handler` (`GetUserByIdQuery` → `GetUserByIdQueryHandler`).
- [ ] **Step 3 — Declare the message.** `final class <Name>Query({required final T field, ...}) extends ReadQuery<TReturn>` — the primary-constructor header's `final` named parameters declare the fields. Override `params` with every operation-affecting field (no secrets). A constructor `assert` needs an initializer list, so a query that validates its inputs keeps a classic constructor instead.
- [ ] **Step 4 — Write the handler.** `class <Name>QueryHandler(...) implements ReadHandler<<Name>Query, TReturn>`. Inject repositories as `final` primary-constructor parameters typed against interfaces (prefer named). Implement `Future<TReturn> read(<Name>Query query)`.
- [ ] **Step 5 — Document thrown exceptions** on the handler class with a `///` doc comment listing every domain exception `read()` may throw.
- [ ] **Step 6 — Annotate the handler.** Place `@chassisHandler` on the class.
- [ ] **Step 7 — Co-locate the file.** `application/<feature>/<query_name>_query.dart`, exported from the feature barrel. One query-handler pair per file. See `chassis-organize-feature`.
- [ ] **Step 8 — Regenerate the mediator.** Run `dart run build_runner build --delete-conflicting-outputs`. The build fails if a reachable concrete query has no handler — missing wiring surfaces at build time, not at first dispatch. See `chassis-register-handler-with-codegen`.
- [ ] **Step 9 — Dispatch from a ViewModel** by passing the query object to the ViewModel's `read(...)` in a synchronous, expression-bodied method. Always cover the error path — provide `onState` or `onError`. A refetching read typically wants `policy: const RunPolicy.restartable()` so a newer read supersedes the in-flight one. See `chassis-create-view-model`.

## Examples

### One-time data export

```dart
// application/users/export_user_data_query.dart
import 'package:chassis/chassis.dart';
import '../../domain/users/user_repository.dart';
import '../../domain/users/export_file.dart';
import '../../domain/users/export_format.dart';

final class ExportUserDataQuery({
  required final String userId,
  required final ExportFormat format,
}) extends ReadQuery<ExportFile> {
  @override
  Map<String, Object?> get params =>
      {'userId': userId, 'format': format.name};
}

/// Builds an export of the user's data in the requested format.
///
/// Throws [UserNotFoundException] if the user does not exist.
@chassisHandler
class ExportUserDataQueryHandler({
  required final UserRepository userRepository,
}) implements ReadHandler<ExportUserDataQuery, ExportFile> {
  @override
  Future<ExportFile> read(ExportUserDataQuery query) =>
      userRepository.exportData(query.userId, query.format);
}
```

Both fields appear in `params`: `userId` and `format` each change what the operation produces, so they are both part of the query's identity — leaving `format` out would make a PDF export and a CSV export compare equal.

### Validation check with cache

```dart
// application/promotions/validate_promo_code_query.dart
import 'package:chassis/chassis.dart';
import '../../domain/promotions/promo_repository.dart';
import '../../domain/promotions/promo_code_validation.dart';
import '../../domain/cache/cache_service.dart';

final class ValidatePromoCodeQuery extends ReadQuery<PromoCodeValidation> {
  // The assert needs an initializer list, so this message keeps a classic
  // constructor instead of a primary one.
  ValidatePromoCodeQuery({required this.code, required this.userId})
      : assert(code.length > 0, 'Promo code cannot be empty');

  final String code;
  final String userId;

  @override
  Map<String, Object?> get params => {'code': code, 'userId': userId};
}

@chassisHandler
class ValidatePromoCodeQueryHandler({
  required final PromoRepository promoRepository,
  required final CacheService cacheService,
}) implements ReadHandler<ValidatePromoCodeQuery, PromoCodeValidation> {
  @override
  Future<PromoCodeValidation> read(ValidatePromoCodeQuery query) async {
    final cacheKey = 'promo_${query.code}_${query.userId}';
    final cached = await cacheService.get<PromoCodeValidation>(cacheKey);
    if (cached != null) return cached;

    final validation = await promoRepository.validate(query.code, query.userId);
    await cacheService.set(cacheKey, validation, ttl: const Duration(minutes: 5));
    return validation;
  }
}
```

### Dispatching from a ViewModel

```dart
class ProfileExportViewModel extends ViewModel<ProfileExportState, ProfileExportEvent> {
  ProfileExportViewModel({super.mediator}) : super(ProfileExportState.initial());

  void exportProfile(String userId, ExportFormat format) => read(
        ExportUserDataQuery(userId: userId, format: format),
        current: state.file, // a re-export keeps the previous file visible
        onState: (file) => setState(state.copyWith(file: file)),
        onSuccess: (file) => sendEvent(ExportReadyEvent(file.path)),
      );
}
```

The ViewModel dispatches the query object itself — it holds no mediator field and never names the generated class. `read` routes the message through the mediator installed by `Chassis.initialize(...)` at startup (or the `mediator:` constructor override, the testing seam) and reports the lifecycle as `Async<ExportFile>` states: `onState` fires for **every** transition — loading, data, and error — so the error path is covered; `onSuccess` fires additively after `onState` on success. Passing `current: state.file` makes a re-export carry the previous file through the loading state instead of blanking the UI. The run key defaults to `ExportUserDataQuery`, so concurrent exports interact under the same `RunPolicy`. See `chassis-create-view-model`.

### Anti-pattern: no unnamed generative constructor

```dart
// ❌ Build error: "has no unnamed generative constructor." The generator
// instantiates handlers itself; a factory or named constructor gives it
// nothing to call.
@chassisHandler
class ExportUserDataQueryHandler
    implements ReadHandler<ExportUserDataQuery, ExportFile> {
  ExportUserDataQueryHandler.create({required this.userRepository});
  final UserRepository userRepository;
  // ...
}
```

```dart
// ✅ Primary constructor — unnamed, generative; dependencies as named
// parameters.
@chassisHandler
class ExportUserDataQueryHandler({
  required final UserRepository userRepository,
}) implements ReadHandler<ExportUserDataQuery, ExportFile> {
  // ...
}
```

Write the query and handler by hand, even when the handler is a one-line pass-through. The manual handler leaves room for caching, validation, or composition to grow into.
