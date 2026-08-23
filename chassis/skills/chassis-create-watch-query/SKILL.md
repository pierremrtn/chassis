---
name: chassis-create-watch-query
description: Implement a reactive data subscription in a Chassis application as a `WatchQuery` paired with a hand-written `WatchHandler`, registered via `@chassisHandler`. Use when the UI needs to stay synchronized with data that can change over time — user profiles, lists, search results, real-time status, collaborative state. This is the default query type for screens that render data; only fall back to `chassis-create-read-query` for one-time fetches.
---
# Creating a Chassis WatchQuery

## Contents
- [Core Concepts](#core-concepts)
- [Why WatchQuery is the Default](#why-watchquery-is-the-default)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

A **WatchQuery** is an immutable message that requests a continuous stream of data. A **WatchHandler** is the stateless class that produces the stream — it calls a repository and returns `Stream<T>`. The contract enforces Command-Query Separation: a WatchQuery never mutates state; it dispatches through `watch()`, never `run()` or `read()`.

The type system enforces correct routing. The ViewModel's `watch<R>(WatchQuery<R> query, ...)` accepts only `WatchQuery` messages — passing one to `read(...)` is a compile error. Pick `WatchQuery` whenever the data is rendered in a view that should stay current.

Queries expose `Map<String, Object?> get params => const {}` for observability **and identity**. Overriding it makes `toString()` render `WatchUserProfileQuery{userId: 42}` and makes `LoggingMiddleware` traces useful instead of a bare type name — and it is also the message's identity: `==` and `hashCode` are derived from the runtime type plus `params`. **Two messages of the same type with equal `params` are the same operation.** Caching and deduplication middlewares (and tooling) rely on this contract, so a field that affects the operation but is left out of `params` breaks it.

## Why WatchQuery is the Default

> In modern reactive Flutter applications, most data should come from `WatchQuery` streams to keep the UI automatically synchronized with data changes.
> — `docs/coding_rules.md`

Reactive Flutter apps want their views to track the data layer without manual refresh logic. A `WatchQuery`-backed `Async<T>` field in state — rendered with an inline `switch` expression on the sealed union (or `AsyncBuilder` when anti-flicker behavior is needed) — keeps the UI in sync as the repository emits new values — pulled from Firestore, a websocket, a local cache, or wherever else the repository ultimately sources its data. The default mental model is:

- *Will this data appear in a view?* → `WatchQuery`.
- *Will the UI need to react when the underlying data changes?* → `WatchQuery`.
- *Is this a one-shot operation that produces an artifact and then ends?* → `ReadQuery`.

The async generator pattern (`async*` and `yield`) inside the handler is a common shape: emit an initial value from a fast source, then merge updates from a slower stream.

## Rules

- **DO** declare the message as `final class Watch<Resource>Query extends WatchQuery<TReturn>`. Use `Watch` as the standard verb (`Observe` is acceptable). Append `By<Criteria>` when querying by a specific parameter (`WatchUserByIdQuery`, `WatchOrderStatusQuery`). *`WatchQuery` is a base class; messages must `extend` it for the Mediator's runtime type lookup.*
- **DO** make the query immutable — declare its fields as `required final` named parameters in the primary-constructor header (`final class WatchUserQuery({required final String userId}) extends WatchQuery<User>`). *Queries are data carriers with structural equality; mutability after construction breaks identity and log/replay safety.*
- **DO** override `params` with **every field that affects the operation** (`{'userId': userId}`). *`params` is both the trace (`toString()` and `LoggingMiddleware` render it) and the identity: same type + equal `params` = same operation. A field left out of `params` makes two different subscriptions compare equal.* **Never include secrets — passwords, tokens, card numbers — in `params`.**
- **DO** keep queries self-contained — every parameter the handler needs lives on the query.
- **DO** declare the handler as `class <QueryName>Handler implements WatchHandler<TQuery, TReturn>` — `implements`, not `extends`. *The naming is mechanical: query name + `Handler` (`WatchUserProfileQuery` → `WatchUserProfileQueryHandler`).*
- **DO** keep the handler stateless, with a primary constructor — the unnamed generative constructor — whose `final` parameters are its dependencies typed against repository interfaces, and **PREFER named parameters** (`class WatchCartQueryHandler({required final CartRepository cartRepository}) implements ...`), especially with two or more dependencies. *`chassis_builder` instantiates handlers itself and passes each dependency back the way it is declared; named parameters keep call sites and tests unambiguous.* See `chassis-register-handler-with-codegen`.
- **DO** annotate the handler with `@chassisHandler` so `chassis_builder` registers it in the generated mediator's constructor. *A concrete query reachable from the `@ChassisApp` graph with no handler is a **build error** — dispatching it could only throw at runtime, so the build fails instead. Annotate the message with `@unhandledMessage` to opt out while the handler is being written.*
- **PREFER** `WatchQuery` over `ReadQuery` for any data displayed in the UI. *The reactive default keeps views synchronized without manual refresh logic.*
- **CONSIDER** the `async*` / `yield*` generator pattern when the stream needs to combine an initial value with subsequent updates, recover from intermediate errors, or transform values.
- **CONSIDER** catching expected, recoverable domain exceptions inside the handler and yielding a sensible default instead — for example, mapping a `CartNotFoundException` to `ShoppingCart.empty()` for a new user. *The handler is the only layer with enough business context to decide what counts as "recoverable".* See `chassis-handle-errors`.
- **DON'T** put logic on the query class itself.
- **DON'T** use `WatchQuery` for one-time operations. *Use `ReadQuery` — see `chassis-create-read-query`.*
- **DON'T** catch infrastructure exceptions inside the handler. *Repositories map them to domain exceptions; the handler propagates them or selectively recovers.* See `chassis-handle-errors`.
- **DON'T** inject the `Mediator` (or the generated mediator) into the handler to reuse another query — the generator rejects it at build time. *The handler composes its stream from the repositories it needs (combine streams there when several sources feed one view); logic shared between handlers lives in an injected service.*
- **DON'T** manually manage the stream subscription in the handler — return the `Stream<T>` and let the ViewModel's `watch()` handle subscription lifecycle and disposal.
- **DON'T** reference the generated mediator from a ViewModel — dispatch the query object itself with the ViewModel's `watch(...)`. *ViewModels never name the generated class: `watch` routes the message through the mediator installed by `Chassis.initialize` (or the constructor override, in tests), so middlewares always apply. The generated mediator appears only at the composition root.*

## Workflow

- [ ] **Step 1 — Confirm WatchQuery is the right choice.** If the data is consumed once and produces an artifact rather than feeding a view, use `chassis-create-read-query`.
- [ ] **Step 2 — Name the query.** `Watch<Resource>Query`, `Watch<Resource>By<Criteria>Query`. The handler name is mechanically `<QueryName>Handler` (`WatchUserProfileQuery` → `WatchUserProfileQueryHandler`).
- [ ] **Step 3 — Declare the message.** `final class <Name>Query({required final T field, ...}) extends WatchQuery<TReturn>` — the primary-constructor header's `final` named parameters declare the fields. Override `params` with every operation-affecting field (no secrets). A constructor `assert` needs an initializer list, so a query that validates its inputs keeps a classic constructor instead.
- [ ] **Step 4 — Write the handler.** `class <Name>QueryHandler(...) implements WatchHandler<<Name>Query, TReturn>`. Inject repositories as `final` primary-constructor parameters typed against interfaces (prefer named). Implement `Stream<TReturn> watch(<Name>Query query)` — return the repository stream directly when no transformation is needed, or use `async*` / `yield*` when composition or recovery is required.
- [ ] **Step 5 — Document thrown exceptions** on the handler class with a `///` doc comment listing every domain exception the stream may surface.
- [ ] **Step 6 — Annotate the handler.** Place `@chassisHandler` on the class.
- [ ] **Step 7 — Co-locate the file.** `application/<feature>/<query_name>_query.dart`, exported from the feature barrel. One query-handler pair per file. See `chassis-organize-feature`.
- [ ] **Step 8 — Regenerate the mediator.** Run `dart run build_runner build --delete-conflicting-outputs`. The build fails if a reachable concrete query has no handler — missing wiring surfaces at build time, not at first dispatch. See `chassis-register-handler-with-codegen`.
- [ ] **Step 9 — Subscribe from a ViewModel** by passing the query object to the ViewModel's `watch(...)` in a synchronous method. Always cover the error path — provide `onState` or `onError`. Watches are keyed by the query's runtime type by default, so re-watching the same query class (with new params) replaces the previous subscription; pass distinct explicit `key:`s only to watch several instances of the same query class concurrently. The framework cancels the subscription automatically when the ViewModel disposes. See `chassis-create-view-model`.

## Examples

### Direct stream pass-through

```dart
// application/users/watch_user_profile_query.dart
import 'package:chassis/chassis.dart';
import '../../domain/users/user_repository.dart';
import '../../domain/users/user_profile.dart';

final class WatchUserProfileQuery({required final String userId})
    extends WatchQuery<UserProfile> {
  @override
  Map<String, Object?> get params => {'userId': userId};
}

/// Streams updates to the user's profile.
///
/// Throws [UserNotFoundException] on the first emission if the user does not exist.
@chassisHandler
class WatchUserProfileQueryHandler({
  required final UserRepository userRepository,
}) implements WatchHandler<WatchUserProfileQuery, UserProfile> {
  @override
  Stream<UserProfile> watch(WatchUserProfileQuery query) =>
      userRepository.watchProfile(query.userId);
}
```

### Composing initial value with live updates (`async*`)

```dart
// application/presence/watch_user_presence_query.dart
import 'package:chassis/chassis.dart';
import '../../domain/presence/realtime_service.dart';
import '../../domain/presence/presence_status.dart';
import '../../domain/users/user_repository.dart';

final class WatchUserPresenceQuery({required final String userId})
    extends WatchQuery<PresenceStatus> {
  @override
  Map<String, Object?> get params => {'userId': userId};
}

@chassisHandler
class WatchUserPresenceQueryHandler({
  required final RealtimeService realtimeService,
  required final UserRepository userRepository,
}) implements WatchHandler<WatchUserPresenceQuery, PresenceStatus> {
  @override
  Stream<PresenceStatus> watch(WatchUserPresenceQuery query) async* {
    yield await userRepository.getPresenceStatus(query.userId);
    yield* realtimeService.watchPresence(query.userId);
  }
}
```

### Recovering from an expected domain exception

```dart
// application/cart/watch_cart_query.dart
import 'package:chassis/chassis.dart';
import '../../domain/cart/cart_repository.dart';
import '../../domain/cart/shopping_cart.dart';
import '../../domain/cart/cart_exceptions.dart';

final class WatchCartQuery({required final String userId})
    extends WatchQuery<ShoppingCart> {
  @override
  Map<String, Object?> get params => {'userId': userId};
}

/// Streams the user's shopping cart, returning an empty cart when none exists yet.
@chassisHandler
class WatchCartQueryHandler({
  required final CartRepository cartRepository,
}) implements WatchHandler<WatchCartQuery, ShoppingCart> {
  @override
  Stream<ShoppingCart> watch(WatchCartQuery query) async* {
    try {
      yield* cartRepository.watchCart(query.userId);
    } on CartNotFoundException {
      yield ShoppingCart.empty(query.userId);
    }
  }
}
```

`CartNotFoundException` is an *expected* domain outcome for a brand-new user — the handler converts it to an empty-state value rather than letting the UI render an error screen. Unexpected failures (network, permission, unknown) still bubble up. See `chassis-handle-errors` for when to catch and when to rethrow.

### Subscribing from a ViewModel

```dart
class UserProfileViewModel extends ViewModel<UserProfileState, UserProfileEvent> {
  UserProfileViewModel({required String userId, super.mediator})
      : super(UserProfileState.initial()) {
    load(userId);
  }

  void load(String userId) => watch(
        // Watches are keyed by the query's runtime type by default:
        // re-calling load with a new id replaces the previous subscription
        // instead of stacking a second one. `current:` carries existing
        // data through the loading state so the screen does not blank.
        WatchUserProfileQuery(userId: userId),
        current: state.profile,
        onState: (profile) => setState(state.copyWith(profile: profile)),
      );
}
```

The ViewModel dispatches the query object itself — it holds no mediator field and never names the generated class. `watch` routes the message through the mediator installed by `Chassis.initialize(...)` at startup (or the `mediator:` constructor override, the testing seam), wraps the stream in `Async<UserProfile>` lifecycle handling, and disposes the subscription with the ViewModel. `onState` fires for **every** transition — loading, data, and error — so the error path is covered (a stream error arrives as a *soft* `AsyncError` carrying the last known data; a handler that throws synchronously reports the same way instead of crashing the call site). Pass distinct explicit `key:`s only when the ViewModel must watch several instances of the same query class concurrently. See `chassis-create-view-model`.

### Anti-pattern: no unnamed generative constructor

```dart
// ❌ Build error: "has no unnamed generative constructor." The generator
// instantiates handlers itself; a factory or named constructor gives it
// nothing to call.
@chassisHandler
class WatchUserProfileQueryHandler
    implements WatchHandler<WatchUserProfileQuery, UserProfile> {
  WatchUserProfileQueryHandler.create({required this.userRepository});
  final UserRepository userRepository;
  // ...
}
```

```dart
// ✅ Primary constructor — unnamed, generative; dependencies as named
// parameters.
@chassisHandler
class WatchUserProfileQueryHandler({
  required final UserRepository userRepository,
}) implements WatchHandler<WatchUserProfileQuery, UserProfile> {
  // ...
}
```

Write the query and handler by hand, even when the handler is a direct stream pass-through. The manual handler leaves room for composition (`async*`, recovery, transformation) to grow into.
