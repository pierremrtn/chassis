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

A **WatchQuery** is an immutable message that requests a continuous stream of data. A **WatchHandler** is the stateless class that produces the stream — it calls a repository and returns `Stream<T>`. The contract enforces Command-Query Separation: a WatchQuery never mutates state; the Mediator routes it through `watch()`, never `run()` or `read()`.

The type system enforces correct routing. Attempting to dispatch a `WatchQuery` through `mediator.read(...)` is a compile error. Pick `WatchQuery` whenever the data is rendered in a view that should stay current.

Queries also expose `Map<String, Object?> get params => const {}` for observability. Overriding it makes `toString()` render `WatchUserProfileQuery{userId: 42}` and makes `LoggingMiddleware` traces useful instead of a bare type name.

## Why WatchQuery is the Default

> In modern reactive Flutter applications, most data should come from `WatchQuery` streams to keep the UI automatically synchronized with data changes.
> — `docs/coding_rules.md`

Reactive Flutter apps want their views to track the data layer without manual refresh logic. A `WatchQuery`-backed `Async<T>` plugged into an `AsyncBuilder` keeps the UI in sync as the repository emits new values — pulled from Firestore, a websocket, a local cache, or wherever else the repository ultimately sources its data. The default mental model is:

- *Will this data appear in a view?* → `WatchQuery`.
- *Will the UI need to react when the underlying data changes?* → `WatchQuery`.
- *Is this a one-shot operation that produces an artifact and then ends?* → `ReadQuery`.

The async generator pattern (`async*` and `yield`) inside the handler is a common shape: emit an initial value from a fast source, then merge updates from a slower stream.

## Rules

- **DO** declare the message as `final class Watch<Resource>Query extends WatchQuery<TReturn>`. Use `Watch` as the standard verb (`Observe` is acceptable). Append `By<Criteria>` when querying by a specific parameter (`WatchUserByIdQuery`, `WatchOrderStatusQuery`). *`WatchQuery` is a base class; messages must `extend` it for the Mediator's runtime type lookup.*
- **DO** make the query immutable with `final` fields and a named-parameter constructor (unnamed, generative — the generated typed method rebuilds the message from its own parameters).
- **DO** override `params` to expose the query's fields for logging (`{'userId': userId}`). *`toString()` and `LoggingMiddleware` render it.* **Never include secrets — passwords, tokens, card numbers — in `params`.**
- **DO** keep queries self-contained — every parameter the handler needs lives on the query.
- **DO** declare the handler as `class <QueryName>Handler implements WatchHandler<TQuery, TReturn>` — `implements`, not `extends`.
- **DO** keep the handler stateless, with an unnamed generative constructor whose parameters are its dependencies typed against repository interfaces, and **PREFER named parameters** (`WatchCartQueryHandler({required this.cartRepository})`), especially with two or more dependencies. *`chassis_builder` instantiates handlers itself and passes each dependency back the way it is declared; named parameters keep call sites and tests unambiguous.* See `chassis-register-handler-with-codegen`.
- **DO** annotate the handler with `@chassisHandler` so `chassis_builder` registers it.
- **PREFER** `WatchQuery` over `ReadQuery` for any data displayed in the UI. *The reactive default keeps views synchronized without manual refresh logic.*
- **CONSIDER** the `async*` / `yield*` generator pattern when the stream needs to combine an initial value with subsequent updates, recover from intermediate errors, or transform values.
- **CONSIDER** catching expected, recoverable domain exceptions inside the handler and yielding a sensible default instead — for example, mapping a `CartNotFoundException` to `ShoppingCart.empty()` for a new user. *The handler is the only layer with enough business context to decide what counts as "recoverable".* See `chassis-handle-errors`.
- **DON'T** put logic on the query class itself.
- **DON'T** use `WatchQuery` for one-time operations. *Use `ReadQuery` — see `chassis-create-read-query`.*
- **DON'T** catch infrastructure exceptions inside the handler. *Repositories map them to domain exceptions; the handler propagates them or selectively recovers.* See `chassis-handle-errors`.
- **DON'T** manually manage the stream subscription in the handler — return the `Stream<T>` and let the ViewModel's `watch()` handle subscription lifecycle and disposal.
- **DON'T** dispatch raw query instances from ViewModels — use the typed method on the generated mediator (`mediator.watchUserProfile(userId: ...)`). *The typed method is compile-checked and discoverable; both routes dispatch through `watch`, so middlewares apply either way.*

## Workflow

- [ ] **Step 1 — Confirm WatchQuery is the right choice.** If the data is consumed once and produces an artifact rather than feeding a view, use `chassis-create-read-query`.
- [ ] **Step 2 — Name the query.** `Watch<Resource>Query`, `Watch<Resource>By<Criteria>Query`. The handler name is mechanically `<QueryName>Handler`, and the generated method name is the query name minus `Query`, decapitalized (`WatchUserProfileQuery` → `watchUserProfile`).
- [ ] **Step 3 — Declare the message.** `final class <Name>Query extends WatchQuery<TReturn>` with `final` fields and a named-parameter constructor. Override `params` with the loggable fields (no secrets).
- [ ] **Step 4 — Write the handler.** `class <Name>QueryHandler implements WatchHandler<<Name>Query, TReturn>`. Inject repositories as constructor parameters typed against interfaces (prefer named). Implement `Stream<TReturn> watch(<Name>Query query)` — return the repository stream directly when no transformation is needed, or use `async*` / `yield*` when composition or recovery is required.
- [ ] **Step 5 — Document thrown exceptions** on the handler class with a `///` doc comment listing every domain exception the stream may surface.
- [ ] **Step 6 — Annotate the handler.** Place `@chassisHandler` on the class.
- [ ] **Step 7 — Co-locate the file.** `application/<feature>/<query_name>_query.dart`, exported from the feature barrel. One query-handler pair per file. See `chassis-organize-feature`.
- [ ] **Step 8 — Regenerate the mediator.** Run `dart run build_runner build --delete-conflicting-outputs`. See `chassis-register-handler-with-codegen`.
- [ ] **Step 9 — Subscribe from a ViewModel** through the generated typed method (`mediator.watchUserProfile(userId: ...)`), wrapped by the ViewModel's `watch()`. Pass `key:` when the subscription can be restarted with new arguments. The framework cancels the subscription automatically when the ViewModel disposes. See `chassis-create-view-model`.

## Examples

### Direct stream pass-through

```dart
// application/users/watch_user_profile_query.dart
import 'package:chassis/chassis.dart';
import '../../domain/users/user_repository.dart';
import '../../domain/users/user_profile.dart';

final class WatchUserProfileQuery extends WatchQuery<UserProfile> {
  WatchUserProfileQuery({required this.userId});

  final String userId;

  @override
  Map<String, Object?> get params => {'userId': userId};
}

/// Streams updates to the user's profile.
///
/// Throws [UserNotFoundException] on the first emission if the user does not exist.
@chassisHandler
class WatchUserProfileQueryHandler
    implements WatchHandler<WatchUserProfileQuery, UserProfile> {
  WatchUserProfileQueryHandler({required this.userRepository});

  final UserRepository userRepository;

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

final class WatchUserPresenceQuery extends WatchQuery<PresenceStatus> {
  WatchUserPresenceQuery({required this.userId});

  final String userId;

  @override
  Map<String, Object?> get params => {'userId': userId};
}

@chassisHandler
class WatchUserPresenceQueryHandler
    implements WatchHandler<WatchUserPresenceQuery, PresenceStatus> {
  WatchUserPresenceQueryHandler({
    required this.realtimeService,
    required this.userRepository,
  });

  final RealtimeService realtimeService;
  final UserRepository userRepository;

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

final class WatchCartQuery extends WatchQuery<ShoppingCart> {
  WatchCartQuery({required this.userId});

  final String userId;

  @override
  Map<String, Object?> get params => {'userId': userId};
}

/// Streams the user's shopping cart, returning an empty cart when none exists yet.
@chassisHandler
class WatchCartQueryHandler
    implements WatchHandler<WatchCartQuery, ShoppingCart> {
  WatchCartQueryHandler({required this.cartRepository});

  final CartRepository cartRepository;

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
  UserProfileViewModel(this._mediator, {required String userId})
      : super(UserProfileState.initial()) {
    load(userId);
  }

  final AppMediator _mediator;

  void load(String userId) {
    // Re-calling load with a new id replaces the previous subscription
    // thanks to the key; `current:` carries existing data through the
    // loading state so the screen does not blank.
    watch(
      _mediator.watchUserProfile(userId: userId),
      key: #profile,
      current: state.profile,
      onState: (asyncProfile) =>
          setState(state.copyWith(profile: asyncProfile)),
    );
  }
}
```

`_mediator.watchUserProfile(...)` is the typed instance method generated from the `@chassisHandler`-annotated handler. It returns `Stream<UserProfile>`, which the ViewModel's `watch()` (not the Mediator's) wraps with `Async<T>` lifecycle handling and automatic disposal. See `chassis-create-view-model`.

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
// ✅ Unnamed constructor; dependencies as named parameters.
@chassisHandler
class WatchUserProfileQueryHandler
    implements WatchHandler<WatchUserProfileQuery, UserProfile> {
  WatchUserProfileQueryHandler({required this.userRepository});
  final UserRepository userRepository;
  // ...
}
```

Write the query and handler by hand, even when the handler is a direct stream pass-through. The manual handler leaves room for composition (`async*`, recovery, transformation) to grow into.
