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

A **ReadQuery** is an immutable message that requests data once. A **ReadHandler** is the stateless class that fulfills that request — it calls a repository and returns a `Future<T>`. The contract enforces Command-Query Separation: a ReadQuery never mutates state; the Mediator routes it through `read()`, not `run()` or `watch()`.

The type system enforces correct routing. Attempting to dispatch a `ReadQuery` through `mediator.watch(...)` is a compile error, which prevents accidental stream subscriptions for one-time operations. Pick `ReadQuery` deliberately — it is the right tool only when the data is consumed once.

Queries also expose `Map<String, Object?> get params => const {}` for observability. Overriding it makes `toString()` render `GetUserQuery{userId: 42}` and makes `LoggingMiddleware` traces useful instead of a bare type name.

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
- **DO** make the query immutable with `final` fields and a named-parameter constructor (unnamed, generative — the generated typed method rebuilds the message from its own parameters). *Queries are data carriers; immutability allows safe caching, retry, and parallel dispatch.*
- **DO** override `params` to expose the query's fields for logging (`{'userId': userId}`). *`toString()` and `LoggingMiddleware` render it.* **Never include secrets — passwords, tokens, card numbers — in `params`.**
- **DO** keep queries self-contained — every parameter the handler needs lives on the query.
- **DO** declare the handler as `class <QueryName>Handler implements ReadHandler<TQuery, TReturn>` — `implements`, not `extends`. *Handlers fulfill a behavioral contract; `implements` forces explicit method signatures.*
- **DO** keep the handler stateless, with an unnamed generative constructor whose parameters are its dependencies typed against repository interfaces, and **PREFER named parameters** (`GetUserQueryHandler({required this.userRepository})`), especially with two or more dependencies. *`chassis_builder` instantiates handlers itself and passes each dependency back the way it is declared; named parameters keep call sites and tests unambiguous.* See `chassis-register-handler-with-codegen`.
- **DO** annotate the handler with `@chassisHandler` so `chassis_builder` registers it. *Without the annotation the handler exists but the Mediator cannot find it.*
- **CONSIDER** adding a cache check inside the handler when the underlying repository call is expensive and the data does not change frequently. *ReadHandlers are a natural place to memoize since they have no side effects.*
- **CONSIDER** validating constructor inputs with `assert` for known constraints (non-empty strings, positive ranges).
- **DON'T** put logic on the query class itself. *The query is a DTO; lookup, caching, and transformation live in the handler.*
- **DON'T** use `ReadQuery` for data the UI should keep synchronized over time. *Use `WatchQuery` — see `chassis-create-watch-query`.*
- **DON'T** catch infrastructure exceptions inside the handler. *Repositories map them to domain exceptions; the handler propagates them.* See `chassis-handle-errors`.
- **DON'T** dispatch raw query instances from ViewModels — use the typed method on the generated mediator (`mediator.getUserById(...)`). *The typed method is compile-checked and discoverable; both routes dispatch through `read`, so middlewares apply either way.*

## Workflow

- [ ] **Step 1 — Confirm ReadQuery is the right choice.** If the UI should reflect later changes to the data, switch to `chassis-create-watch-query`.
- [ ] **Step 2 — Name the query.** `Get<Resource>Query`, `Find<Resource>By<Criteria>Query`, etc. The handler name is mechanically `<QueryName>Handler`, and the generated method name is the query name minus `Query`, decapitalized (`GetUserByIdQuery` → `getUserById`).
- [ ] **Step 3 — Declare the message.** `final class <Name>Query extends ReadQuery<TReturn>` with `final` fields and a named-parameter constructor. Override `params` with the loggable fields (no secrets).
- [ ] **Step 4 — Write the handler.** `class <Name>QueryHandler implements ReadHandler<<Name>Query, TReturn>`. Inject repositories as constructor parameters typed against interfaces (prefer named). Implement `Future<TReturn> read(<Name>Query query)`.
- [ ] **Step 5 — Document thrown exceptions** on the handler class with a `///` doc comment listing every domain exception `read()` may throw.
- [ ] **Step 6 — Annotate the handler.** Place `@chassisHandler` on the class.
- [ ] **Step 7 — Co-locate the file.** `application/<feature>/<query_name>_query.dart`, exported from the feature barrel. One query-handler pair per file. See `chassis-organize-feature`.
- [ ] **Step 8 — Regenerate the mediator.** Run `dart run build_runner build --delete-conflicting-outputs`. See `chassis-register-handler-with-codegen`.
- [ ] **Step 9 — Dispatch from a ViewModel** through the generated typed method (`mediator.getUserById(userId: ...)`), wrapped by the ViewModel's `run()`. See `chassis-create-view-model`.

## Examples

### One-time data export

```dart
// application/users/export_user_data_query.dart
import 'package:chassis/chassis.dart';
import '../../domain/users/user_repository.dart';
import '../../domain/users/export_file.dart';
import '../../domain/users/export_format.dart';

final class ExportUserDataQuery extends ReadQuery<ExportFile> {
  ExportUserDataQuery({required this.userId, required this.format});

  final String userId;
  final ExportFormat format;

  @override
  Map<String, Object?> get params =>
      {'userId': userId, 'format': format.name};
}

/// Builds an export of the user's data in the requested format.
///
/// Throws [UserNotFoundException] if the user does not exist.
@chassisHandler
class ExportUserDataQueryHandler
    implements ReadHandler<ExportUserDataQuery, ExportFile> {
  ExportUserDataQueryHandler({required this.userRepository});

  final UserRepository userRepository;

  @override
  Future<ExportFile> read(ExportUserDataQuery query) =>
      userRepository.exportData(query.userId, query.format);
}
```

### Validation check with cache

```dart
// application/promotions/validate_promo_code_query.dart
import 'package:chassis/chassis.dart';
import '../../domain/promotions/promo_repository.dart';
import '../../domain/promotions/promo_code_validation.dart';
import '../../domain/cache/cache_service.dart';

final class ValidatePromoCodeQuery extends ReadQuery<PromoCodeValidation> {
  ValidatePromoCodeQuery({required this.code, required this.userId})
      : assert(code.length > 0, 'Promo code cannot be empty');

  final String code;
  final String userId;

  @override
  Map<String, Object?> get params => {'code': code, 'userId': userId};
}

@chassisHandler
class ValidatePromoCodeQueryHandler
    implements ReadHandler<ValidatePromoCodeQuery, PromoCodeValidation> {
  ValidatePromoCodeQueryHandler({
    required this.promoRepository,
    required this.cacheService,
  });

  final PromoRepository promoRepository;
  final CacheService cacheService;

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
  ProfileExportViewModel(this._mediator) : super(ProfileExportState.initial());

  final AppMediator _mediator;

  void exportProfile(String userId, ExportFormat format) {
    run(
      () => _mediator.exportUserData(userId: userId, format: format),
      current: state.file,
      onState: (asyncFile) => setState(state.copyWith(file: asyncFile)),
      onSuccess: (file) => sendEvent(ExportReadyEvent(file.path)),
    );
  }
}
```

The generated typed method `_mediator.exportUserData(...)` returns `Future<ExportFile>`. The ViewModel's `run()` (not the Mediator's) wraps it with `Async<T>` lifecycle handling — `onState` fires for every transition and `onSuccess` fires additively on success. Passing `current: state.file` makes a re-export carry the previous file through the loading state instead of blanking the UI. See `chassis-create-view-model`.

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
// ✅ Unnamed constructor; dependencies as named parameters.
@chassisHandler
class ExportUserDataQueryHandler
    implements ReadHandler<ExportUserDataQuery, ExportFile> {
  ExportUserDataQueryHandler({required this.userRepository});
  final UserRepository userRepository;
  // ...
}
```

Write the query and handler by hand, even when the handler is a one-line pass-through. The manual handler leaves room for caching, validation, or composition to grow into.
