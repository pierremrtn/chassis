# Error Handling Strategy with Chassis

This document formalizes the error handling strategy within the Chassis framework. It defines how errors flow from the Infrastructure layer up to the UI, ensuring that infrastructure details do not leak into your business logic and that all errors can be safely localized for the user while preserving debug information.

---

## Error Propagation & Architecture

### DO use exceptions rather than Result types for error propagation

Chassis is designed to handle thrown exceptions natively. The ViewModel's `run()`, `read()`, and `watch()` methods catch anything thrown along the dispatch — asynchronously *or* synchronously — and report it as an `AsyncError<T>` through `onState` and `onError`. Returning `Result<T, E>` types creates unnecessary boilerplate and breaks the plain `Future<T>` / `Stream<T>` signatures that handlers declare.

**Bad**

```dart
// Repositories returning Results force Handlers to unwrap them manually
abstract interface class UserRepository {
  Future<Result<User, Exception>> getUser(String userId);
}
```

**Good**

```dart
// Repositories throw exceptions; Chassis catches them automatically
abstract interface class UserRepository {
  Future<User> getUser(String userId);
}
```

### DO map infrastructure exceptions to domain exceptions in the Repository layer

Repositories act as an anti-corruption layer. They must catch infrastructure-specific errors (like `FirebaseException` or `DioException`) and translate them into pure Domain exceptions. This prevents your Application layer from becoming tightly coupled to a specific database or API provider.

**Bad**

```dart
// Handler knows about Firebase (Breaks Dependency Rule)
class GetUserQueryHandler implements ReadHandler<GetUserQuery, User> {
  @override
  Future<User> read(GetUserQuery query) async {
    try {
      return await _repository.getUser(query.userId);
    } on FirebaseException catch (e) {
      throw PermissionDeniedException(e);
    }
  }
}
```

**Good**

```dart
// Repository handles the mapping; Handler remains pure
extension FirebaseErrorMapper<T> on Future<T> {
  Future<T> mapFirebaseErrors() async {
    try {
      return await this;
    } on FirebaseException catch (e, stack) {
      final mapped = switch (e.code) {
        'permission-denied' => PermissionDeniedException(e),
        'unavailable' => NetworkException(e),
        _ => UnknownInfrastructureException(e),
      };
      Error.throwWithStackTrace(mapped, stack);
    }
  }
}

// In your repository implementation
@override
Future<User> getUser(String userId) async {
  return await firestore
      .collection('users')
      .doc(userId)
      .get()
      .mapFirebaseErrors()
      .then((doc) => doc.toDomain());
}
```

### DON'T catch infrastructure errors inside Handlers

The Application layer (Handlers) depends only on Repository interfaces, never on concrete implementations (see [Core Architecture](01_core_architecture.md)). Let the repository handle the mapping, and let the Handler pass the domain exception upward.

### DON'T catch the Mediator's own wiring errors

The Mediator throws `HandlerNotRegisteredError` when a message is dispatched with no registered handler, and `DuplicateHandlerError` when two handlers are registered for the same message type. Both extend the sealed `ChassisError`, which extends `Error` — not `Exception`. The type system itself says it: like `TypeError` or `RangeError`, these describe programming bugs — a wiring mistake to fix, never a runtime condition to recover from. An `on Exception catch` clause written for domain failures will never match them, and `CrashReportingMiddleware` classifies them as **fatal**.

In practice they should rarely survive to runtime at all: chassis_builder turns a concrete message reachable from the `@ChassisApp` graph with no handler into a *build* error (see [Code Generation](03_code_generation.md)). If one does reach you — a manually registered mediator, a message opted out with `@unhandledMessage` — the fix is registration: annotate the handler with `@chassisHandler` and rebuild, or register it on the mediator; don't catch. Note that at the ViewModel call site the dispatch failure still surfaces as an `AsyncError` (the UI never crashes mid-frame), but the middleware has already reported it as fatal — the only correct response is fixing the wiring.

---

## Deciding Where to Catch

Not every error needs to reach the UI. Exceptions express *unexpected* failures — the happy path broke and someone upstream needs to decide what to do. But many conditions that infrastructure surfaces as errors (a missing document, an empty query result, a cache miss) are part of the *expected* flow. Treating them as errors forces the UI into error states for scenarios that are not, in fact, errors.

Handlers are the layer where that decision gets made. A repository cannot know whether "user has no cart yet" means "show the empty state" or "show an error message" — only the handler, with its knowledge of the business operation, can decide. This is why the Handler is the right place to *selectively* catch domain exceptions, convert them into normal values, and keep the flow going.

### DO distinguish business outcomes from unexpected failures

Before throwing, ask whether the condition is part of the operation's normal domain or whether something actually went wrong. A shopping cart that does not exist for a new user is a business outcome — return an empty cart. A network timeout while fetching that cart is an unexpected failure — throw. Mixing the two means the UI renders error screens when it should render empty states, and crash reporters log noise instead of real incidents.

### DO catch recoverable domain exceptions in Handlers

When a handler can meaningfully react to an exception thrown by a repository, catch it there. This keeps recoverable conditions out of `AsyncError` and prevents the UI from showing error screens for normal states. The handler is the only layer that has enough business context to decide what "recoverable" means.

**Bad**

```dart
// Lets a recoverable condition bubble up to the UI
class WatchCartQueryHandler implements WatchHandler<WatchCartQuery, ShoppingCart> {
  final CartRepository cartRepository;

  WatchCartQueryHandler({required this.cartRepository});

  @override
  Stream<ShoppingCart> watch(WatchCartQuery query) {
    // The repository throws CartNotFoundException for new users,
    // and the UI ends up showing an error screen instead of the empty cart.
    return cartRepository.watchCart(query.userId);
  }
}
```

**Good**

```dart
// Converts the expected "no cart yet" outcome into an empty state
class WatchCartQueryHandler implements WatchHandler<WatchCartQuery, ShoppingCart> {
  final CartRepository cartRepository;

  WatchCartQueryHandler({required this.cartRepository});

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

### DON'T catch exceptions you cannot recover from

Catching an exception only to rethrow it — or worse, to swallow it silently — hides failures from the crash reporter and makes bugs much harder to diagnose. Only catch when the handler has a meaningful response: return a default, try an alternate path, or convert one domain exception into a more specific one. Otherwise, let the exception bubble up so Chassis can route it to `AsyncError` and the middleware chain can report it.

### DO model business rule failures as domain exceptions

When a business rule blocks an operation — an order that exceeds inventory, a payment that is declined, a promo code that expired — throw a typed exception with a stable error code. These are failures from the user's perspective and belong in the error channel, not in a nullable return value or a boolean flag. The UI then translates the exception into an actionable message through the normal error pipeline. This is the same principle behind *DO create business-specific error classes for domain failures* in [coding_rules.md](coding_rules.md), seen here from the flow-control angle.

Business rule failures and infrastructure failures share the same mechanism (typed exceptions with stable codes) but serve different UX purposes. Infrastructure failures often suggest retry or offline affordances; business rule failures are terminal for the current operation and usually need a specific, localized explanation. Name both clearly so the Presentation layer can render each appropriately.

---

## Domain Errors & Localization

A domain exception has to serve two audiences simultaneously. The user needs a friendly, localized message they can understand, and — when things go wrong in production — a short identifier they can quote back to customer support. The developer on call needs the underlying infrastructure error and its stack trace. A well-shaped exception carries all three: a stable code, any data the user-facing message needs to interpolate, and the original error when one exists.

Chassis does not ship a base class for domain exceptions, and deliberately so. Each application has its own taxonomy of business failures, and no framework-provided hierarchy can capture that without being either too narrow or in the way. Implement `Exception` directly, shape the fields to the needs of the operation, and use the conventions below to keep the codes stable across releases. Implementing `Exception` (rather than `Error`) also matters for observability: `CrashReportingMiddleware` classifies Dart `Error`s as fatal bugs and everything else as expected, non-fatal domain failures (see below).

### DO use stable string identifiers for error codes

Every domain exception should expose a short, stable string code — `item_not_found`, `insufficient_inventory`, `payment_declined`. These codes serve a production purpose that goes beyond UI translation: they are what users screenshot and send to customer support, what you aggregate in telemetry dashboards, and what on-call engineers grep for in logs. Treat them as a public API of your app and avoid renaming them once they ship.

Strings are the right type here. Dart enums cannot be extended outside the package that defines them, which makes a shared `ErrorCode` enum a dead end the moment an app needs a code the enum does not cover. Strings carry no such limitation, serialize trivially into analytics events and support tickets, and survive refactors without breaking the format your support team already references. The usual objection to strings is that they lose exhaustive pattern matching in the UI switch — but translation is better done by matching on the exception *type*, which keeps exhaustiveness where it matters.

**Bad**

```dart
// Enum codes cannot be extended outside the package they live in,
// and cannot carry the app-specific variants real projects need.
enum ErrorCode {
  itemNotFound,
  insufficientInventory,
}
```

**Good**

```dart
class ItemNotFoundException implements Exception {
  ItemNotFoundException({required this.itemName, this.originalError});

  final String itemName;
  final Object? originalError;

  String get code => 'item_not_found';
}
```

### DO carry the original infrastructure error when wrapping one

When a repository maps an infrastructure exception into a domain exception, keep a reference to the original error on the domain exception. This lets the middleware forward the underlying failure to crash reporting, and lets debug builds display the raw error to developers without losing the mapped, localizable shape needed by the rest of the pipeline.

**Good**

```dart
class InsufficientInventoryException implements Exception {
  InsufficientInventoryException({
    required this.productId,
    required this.requested,
    required this.available,
    this.originalError,
  });

  final String productId;
  final int requested;
  final int available;
  final Object? originalError;

  String get code => 'insufficient_inventory';
}
```

### CONSIDER defining a project-level interface for coded exceptions

If multiple layers of the application need to read the code of an exception — the UI, logging middleware, analytics — a small project-level interface avoids repeated type checks and keeps the convention discoverable. This is a convention the app owns, not a Chassis type, so it can be extended freely as new exception shapes appear.

**Good**

```dart
/// Project-level convention. Any exception that implements this
/// exposes a stable code readable by the UI, logs, and analytics.
abstract interface class HasErrorCode {
  String get code;
}

class ItemNotFoundException implements Exception, HasErrorCode {
  ItemNotFoundException({required this.itemName, this.originalError});

  final String itemName;
  final Object? originalError;

  @override
  String get code => 'item_not_found';
}
```

---

## Presentation

Chassis exposes three channels a ViewModel can use to surface an error from `run()`, `read()`, or `watch()`: the operation's result can flow into `Async<T>` state via `onState`; the ViewModel can dispatch a one-time event via `sendEvent` from the `onError` callback — invoked with `(Object error, StackTrace stack)`, *after* `onState`, for the error transition; or it can retain the last-good value through the `previous` field carried by `AsyncLoading<T>` and `AsyncError<T>` and flag a soft error. The right channel depends on one question — *after the error happens, is the current view still useful?* The two `PREFER` rules below capture the default answer for queries and commands; both are preferences, not laws, and the app's UX language sometimes demands inverting them. What is *not* negotiable is that some channel handles the error: every dispatch must cover the error path.

### DON'T dispatch with only a success callback

`onSuccess` (and watch's `onData`) are additive conveniences layered on top of `onState` — providing them never suppresses anything, and none of them handles errors. A `run`/`read` whose only callback is `onSuccess` makes failures invisible: the user taps, the operation fails, and nothing happens — no state change, no event, no message. Cover the error path on every dispatch with `onState` (which fires for *every* transition, including `AsyncError`) or `onError`. A future chassis lint will flag `onSuccess`-only dispatches.

**Bad**

```dart
// A failure fires no callback at all: tapping "Add" silently does nothing.
void addToCart(String productId) => run(
      AddToCartCommand(productId: productId),
      onSuccess: (_) => sendEvent(const AddedToCartEvent()),
    );
```

**Good**

```dart
void addToCart(String productId) => run(
      AddToCartCommand(productId: productId),
      onSuccess: (_) => sendEvent(const AddedToCartEvent()),
      onError: (error, stack) => sendEvent(AddToCartFailedEvent(error)),
    );
```

### PREFER routing query errors through Async state

Queries exist to produce the data a screen renders. When a query fails, there is usually nothing meaningful to show without its result, and the natural place for the error is `Async<T>` state — an `AsyncError<T>` in state drives the error branch of the rendering `switch` (or `AsyncBuilder.errorBuilder`), which renders a full view error with optional retry. Flow the error through `onState` so the loading, data, and error rendering all come from the same source of truth.

**Good**

```dart
class UserViewModel extends ViewModel<UserState, UserEvent> {
  UserViewModel({super.mediator}) : super(UserState.initial());

  // onState receives every transition — loading, data, AND error — so the
  // error path is covered by construction.
  void loadUser(String userId) => read(
        GetUserQuery(userId: userId),
        policy: const RunPolicy.restartable(),
        current: state.user,
        onState: (user) => setState(state.copyWith(user: user)),
      );

  // Same shape for a live query. Re-calling watchUser with a new id
  // replaces the previous subscription: watches are keyed by query type
  // by default, and stream errors arrive through onState as soft errors.
  void watchUser(String userId) => watch(
        WatchUserQuery(userId: userId),
        current: state.user,
        onState: (user) => setState(state.copyWith(user: user)),
      );
}
```

Invert this default when the screen was already displaying valid data and should keep displaying it through the failure — a live dashboard that loses its connection, an autocomplete that fails to refresh. Those cases are covered by the soft-error pattern further down.

### PREFER routing command errors through events

Commands are triggered by user intent on a screen that already has valid content. A failed save, a rejected payment, or a network error on "add to cart" should not replace the view — the user's form, list, or selection is still valid and they need to be able to fix something and retry. Dispatch the error as a one-time event from `onError` so `ViewModelProvider.withEventListener` can surface a snackbar, toast, or dialog while the state stays intact.

**Good**

```dart
void save(EditProfileForm form) => run(
      UpdateProfileCommand(form: form),
      onSuccess: (_) => sendEvent(const ProfileSavedEvent()),
      onError: (error, stack) => sendEvent(ProfileSaveFailedEvent(error)),
    );
```

The failure event carries the error *object*, never `error.toString()` — a stringified error destroys the pattern matching that translation (and any other listener logic) relies on:

**Bad**

```dart
// Stringly-typed event: the listener can only display the raw string.
final class ProfileSaveFailedEvent {
  const ProfileSaveFailedEvent(this.message);
  final String message;
}
```

**Good**

```dart
// The event carries the error object; the event listener translates it
// at display time (context.translateError(event.error)).
final class ProfileSaveFailedEvent {
  const ProfileSaveFailedEvent(this.error);
  final Object error;
}
```

Invert this default when the command fundamentally replaces the view — submitting a checkout, completing an onboarding step, creating an account. On success the UI navigates away, and on catastrophic failure a full error view is more informative than a snackbar dropped on a screen the user was already leaving. Those commands should flow their result through `onState` like a query.

### CONSIDER using Async<T>.previous to keep content visible through transient failures

Watch queries that hiccup mid-stream — a lost socket, a momentary Firestore outage — rarely need to blow away the last-good snapshot. `watch` reports stream errors as *soft* errors: the `AsyncError<T>` it emits carries the last known data in `previous`. When rendering with an inline `switch`, match `AsyncError(previous: AsyncData(:final value))` before the bare error case to keep the content on screen; `AsyncBuilder` exists for exactly this behavior (`maintainState`, default `true`, keeps rendering the previous data while the error is active). Combined with the handler-level recovery pattern from *Deciding Where to Catch*, this lets the UI stay useful through transient failures without forcing the user through a full error screen.

### DO translate exceptions in the Presentation layer

The Domain layer knows nothing about `BuildContext` or localization packages. Translating strings must happen exclusively in the UI layer. Pattern match on the exception type so that typed fields — like the missing item's name or the available stock — can flow directly into the localized message without going through a stringly-typed map. `context.translateError` is a helper *your project* defines and owns; Chassis ships no translation API.

**Good**

```dart
/// Project-level helper — not a Chassis API.
extension ErrorTranslation on BuildContext {
  String translateError(Object error) {
    final loc = AppLocalizations.of(this)!;

    return switch (error) {
      ItemNotFoundException(:final itemName) => loc.error_item_not_found(itemName),
      InsufficientInventoryException(:final available) => loc.error_inventory(available),
      PermissionDeniedException() => loc.error_permission_denied,
      NetworkException() => loc.error_network,
      _ => loc.error_unknown,
    };
  }
}
```

Pattern matching gives the switch access to the typed fields of each exception for free, and the `_` catch-all ensures unmapped errors fall back to a generic message rather than breaking the UI. If the app's exception hierarchy lives under a sealed class, the switch can be made exhaustive and the catch-all dropped — but that is an optimization, not a requirement.

### PREFER displaying both the translated message and the error code to users

When rendering the error branch, show the translated message alongside the stable error code. Users cannot read a stack trace, but they can read a short identifier off their screen and repeat it to customer support, which turns an opaque failure into an actionable ticket. The raw exception should only appear in debug builds, where it helps the developer on the other end.

**Good**

```dart
Widget build(BuildContext context) {
  final user = context.select((UserViewModel vm) => vm.state.user);

  return switch (user) {
    AsyncData(:final value) => UserProfileView(user: value),
    AsyncLoading() => const Center(child: CircularProgressIndicator()),
    AsyncError(:final error) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.translateError(error)),
          Text(
            'Error code: ${error is HasErrorCode ? error.code : 'unknown'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (kDebugMode) Text('Dev: $error'),
        ],
      ),
  };
}
```

---

## Observability: the Middleware Chain Is the Observer

Coming from other state-management frameworks, you might look for the equivalent of a `BlocObserver` or a `ProviderObserver`. Chassis has none — by design. Every operation in a Chassis app crosses the mediator as a typed message, so the middleware chain *is* the observability channel: a middleware sees the message itself and its declared `params`, covers commands, reads, and watch streams alike, and is wired exactly once, at the composition root. There is no per-ViewModel, per-screen, or per-handler instrumentation to keep in sync.

The complete wiring lives in `main()`, on the mediator passed to `Chassis.initialize`:

```dart
void main() {
  Chassis.initialize(AppMediator(
    userRepository: FirebaseUserRepository(),
    cartRepository: FirestoreCartRepository(),
  )
    ..addMiddleware(LoggingMiddleware())
    ..addMiddleware(CrashReportingMiddleware(
      (error, stack, {required fatal}) => FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: fatal),
    )));
  runApp(const MyApp());
}
```

### DO wire `CrashReportingMiddleware` so no failure goes unnoticed

If a repository author forgets to map an infrastructure error, or an unexpected crash occurs, it should not go unnoticed. Chassis ships `CrashReportingMiddleware` for exactly this: it reports every failure crossing the mediator to your telemetry callback with the preserved stack trace, then lets it propagate — reporting never swallows failures, so the ViewModel still transitions to `AsyncError<T>`.

Failures are classified with Dart's own distinction, passed to your callback as `fatal`:

- A Dart `Error` — a `TypeError` in a handler, a `ChassisError` wiring mistake — is a **programming bug** and is reported as **fatal**.
- Anything else — `Exception`s, your domain failures — is an **expected runtime failure** and is reported as **non-fatal**.

This split is what keeps crash dashboards honest: real bugs page someone, while `payment_declined` shows up as telemetry, not as a crash. It is also why domain failures must implement `Exception`, never extend `Error`.

Watch queries are covered end to end: each error flowing through the watched stream is reported *and* forwarded to the subscriber — the ViewModel still receives its soft `AsyncError`. A handler that throws synchronously at subscription (including a wiring error) is reported, then rethrown into the normal dispatch protection.

### CONSIDER wiring `LoggingMiddleware` to trace every operation

Chassis ships a `LoggingMiddleware` that records every dispatch — command, read, and watch — with its outcome, duration, and errors including stack traces. Each record renders the message's `params`, so a failing trace reads `UpdateProfileCommand{userId: u1} failed after 230ms: NetworkException` instead of a bare type name. Errors are always rethrown; logging never swallows failures. Route records to your own logger or breadcrumb trail by providing a custom `ChassisLogSink`.

**Good**

```dart
// Development: also trace dispatch starts and stream emissions.
Chassis.initialize(
  AppMediator(userRepository: FirebaseUserRepository())
    ..addMiddleware(LoggingMiddleware(logStart: true, logStreamEvents: true)),
);
```

Remember that `params` flows into these traces — override it on your messages for observability, and never include secrets in it.

### CONSIDER writing custom middlewares for other telemetry channels

Analytics, performance tracing, or breadcrumbs follow the same shape: extend `MediatorMiddleware` and override the hooks you need — `onRun` for commands, `onRead` for read queries, `onWatch` for watch streams. Hooks you don't override keep their pass-through defaults. Middlewares observe, enrich, or block the message on its way to the handler; they never dispatch messages themselves — a multi-step flow belongs in a single handler composing several repositories.

**Good**

```dart
class AnalyticsMiddleware extends MediatorMiddleware {
  AnalyticsMiddleware(this._analytics);

  final AnalyticsService _analytics;

  @override
  Future<R> onRun<R>(Command<R> command, NextRun<R> next) async {
    final result = await next(command);
    _analytics.track('command_${command.runtimeType}', command.params);
    return result;
  }
}
```

Like the built-in middlewares, a custom one must never swallow errors: observe, then rethrow (or simply don't catch). The last line of defence only works if every failure keeps propagating.
