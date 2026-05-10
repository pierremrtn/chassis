# Error Handling Strategy with Chassis

This document formalizes the error handling strategy within the Chassis framework. It defines how errors flow from the Infrastructure layer up to the UI, ensuring that infrastructure details do not leak into your business logic and that all errors can be safely localized for the user while preserving debug information.

---

## Error Propagation & Architecture

### DO use exceptions rather than Result types for error propagation

Chassis is designed to handle thrown exceptions natively. The ViewModel's `run()` and `watch()` methods automatically catch exceptions and transition state to `AsyncError<T>`, or trigger the `onError` callback. Returning `Result<T, E>` types creates unnecessary boilerplate and breaks the clean `Future<T>` signatures expected by the generated Mediator.

**Bad**

```dart
// Repositories returning Results force Handlers to unwrap them manually
abstract interface class IUserRepository {
  Future<Result<User, Exception>> getUser(String userId);
}
```

**Good**

```dart
// Repositories throw exceptions; Chassis catches them automatically
abstract interface class IUserRepository {
  Future<User> getUser(String userId);
}
```

### DO map infrastructure exceptions to domain exceptions in the Repository layer

Repositories act as an anti-corruption layer. They must catch infrastructure-specific errors (like `FirebaseException` or `DioException`) and translate them into pure Domain exceptions. This prevents your Application layer from becoming tightly coupled to a specific database or API provider.

**Bad**

```dart
// Handler knows about Firebase (Breaks Dependency Rule)
class GetUserHandler implements ReadHandler<GetUserQuery, User> {
  @override
  Future<User> read(GetUserQuery query) async {
    try {
      return await _repository.getUser(query.userId);
    } on FirebaseException catch (e) {
      throw DomainException(ErrorCode.permissionDenied);
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

---

## Deciding Where to Catch

Not every error needs to reach the UI. Exceptions express *unexpected* failures — the happy path broke and someone upstream needs to decide what to do. But many conditions that infrastructure surfaces as errors (a missing document, an empty query result, a cache miss) are part of the *expected* flow. Treating them as errors forces the UI into error states for scenarios that are not, in fact, errors.

Handlers are the layer where that decision gets made. A repository cannot know whether "user has no cart yet" means "show the empty state" or "show an error message" — only the handler, with its knowledge of the business operation, can decide. This is why the Handler is the right place to *selectively* catch domain exceptions, convert them into normal values, and keep the flow going.

### DO distinguish business outcomes from unexpected failures

Before throwing, ask whether the condition is part of the operation's normal domain or whether something actually went wrong. A shopping cart that does not exist for a new user is a business outcome — return an empty cart. A network timeout while fetching that cart is an unexpected failure — throw. Mixing the two means the UI renders error screens when it should render empty states, and crash reporters log noise instead of real incidents.

### DO catch recoverable domain exceptions in Handlers

When a handler can meaningfully react to an exception thrown by a repository or a sub-query, catch it there. This keeps recoverable conditions out of `AsyncError` and prevents the UI from showing error screens for normal states. The handler is the only layer that has enough business context to decide what "recoverable" means.

**Bad**

```dart
// Lets a recoverable condition bubble up to the UI
class WatchCartHandler implements WatchHandler<WatchCartQuery, ShoppingCart> {
  final ICartRepository _cartRepository;

  WatchCartHandler(this._cartRepository);

  @override
  Stream<ShoppingCart> watch(WatchCartQuery query) {
    // The repository throws CartNotFoundException for new users,
    // and the UI ends up showing an error screen instead of the empty cart.
    return _cartRepository.watchCart(query.userId);
  }
}
```

**Good**

```dart
// Converts the expected "no cart yet" outcome into an empty state
class WatchCartHandler implements WatchHandler<WatchCartQuery, ShoppingCart> {
  final ICartRepository _cartRepository;

  WatchCartHandler(this._cartRepository);

  @override
  Stream<ShoppingCart> watch(WatchCartQuery query) async* {
    try {
      yield* _cartRepository.watchCart(query.userId);
    } on CartNotFoundException {
      yield ShoppingCart.empty(query.userId);
    }
  }
}
```

### DON'T catch exceptions you cannot recover from

Catching an exception only to rethrow it — or worse, to swallow it silently — hides failures from the crash reporter and makes bugs much harder to diagnose. Only catch when the handler has a meaningful response: return a default, try an alternate path, or convert one domain exception into a more specific one. Otherwise, let the exception bubble up so Chassis can route it to `AsyncError` and the middleware can report it.

### DO model business rule failures as domain exceptions

When a business rule blocks an operation — an order that exceeds inventory, a payment that is declined, a promo code that expired — throw a typed exception with a stable error code. These are failures from the user's perspective and belong in the error channel, not in a nullable return value or a boolean flag. The UI then translates the exception into an actionable message through the normal error pipeline. This is the same principle behind *DO create business-specific error classes for domain failures* in [coding_rules.md](coding_rules.md), seen here from the flow-control angle.

Business rule failures and infrastructure failures share the same mechanism (typed exceptions with stable codes) but serve different UX purposes. Infrastructure failures often suggest retry or offline affordances; business rule failures are terminal for the current operation and usually need a specific, localized explanation. Name both clearly so the Presentation layer can render each appropriately.

---

## Domain Errors & Localization

A domain exception has to serve two audiences simultaneously. The user needs a friendly, localized message they can understand, and — when things go wrong in production — a short identifier they can quote back to customer support. The developer on call needs the underlying infrastructure error and its stack trace. A well-shaped exception carries all three: a stable code, any data the user-facing message needs to interpolate, and the original error when one exists.

Chassis does not ship a base class for domain exceptions, and deliberately so. Each application has its own taxonomy of business failures, and no framework-provided hierarchy can capture that without being either too narrow or in the way. Implement `Exception` directly, shape the fields to the needs of the operation, and use the conventions below to keep the codes stable across releases.

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

## Presentation & Global Safety

Chassis exposes three channels a ViewModel can use to surface an error from `run()` or `watch()`: the operation's result can flow into `Async<T>` state via `onState`, the ViewModel can dispatch an event via `sendEvent` from an `onError` callback, or it can retain the last-good value on `Async<T>.previous` and flag a soft error. The right channel depends on one question — *after the error happens, is the current view still useful?* The two rules below capture the default answer for queries and commands; both are preferences, not laws, and the app's UX language sometimes demands inverting them.

### PREFER routing query errors through Async state

Queries exist to produce the data a screen renders. When a query fails, there is usually nothing meaningful to show without its result, and the natural place for the error is `Async<T>` state — `AsyncError<T>` drives `AsyncBuilder.errorBuilder`, which renders a full view error with optional retry. Flow the error through `onState` so the loading, data, and error rendering all come from the same source of truth.

**Good**

```dart
void loadUser(String userId) {
  watch(
    mediator.watchUser(userId: userId),
    onState: (asyncUser) => setState(state.copyWith(user: asyncUser)),
  );
}
```

Invert this default when the screen was already displaying valid data and should keep displaying it through the failure — a live dashboard that loses its connection, an autocomplete that fails to refresh. Those cases are covered by the soft-error pattern further down.

### PREFER routing command errors through events

Commands are triggered by user intent on a screen that already has valid content. A failed save, a rejected payment, or a network error on "add to cart" should not replace the view — the user's form, list, or selection is still valid and they need to be able to fix something and retry. Dispatch the error as a one-time event from `onError` so `ViewModelProvider.withEvents` can surface a snackbar, toast, or dialog while the state stays intact.

**Good**

```dart
void save(EditProfileForm form) {
  run(
    mediator.updateProfile(form: form),
    onData: (_) => sendEvent(ProfileSavedEvent()),
    onError: (error) => sendEvent(ProfileSaveFailedEvent(error)),
  );
}
```

Invert this default when the command fundamentally replaces the view — submitting a checkout, completing an onboarding step, creating an account. On success the UI navigates away, and on catastrophic failure a full error view is more informative than a snackbar dropped on a screen the user was already leaving. Those commands should flow their result through `onState` like a query.

### CONSIDER using Async<T>.previous to keep content visible through transient failures

Watch queries that hiccup mid-stream — a lost socket, a momentary Firestore outage — rarely need to blow away the last-good snapshot. `Async<T>` exposes a `previous` field on both `AsyncLoading<T>` and `AsyncError<T>`, and `AsyncBuilder.maintainState` (default `true`) keeps rendering the previous data while the error is active. Combined with the handler-level recovery pattern from *Deciding Where to Catch*, this lets the UI stay useful through transient failures without forcing the user through a full error screen.

### DO translate exceptions in the Presentation layer

The Domain layer knows nothing about `BuildContext` or localization packages. Translating strings must happen exclusively in the UI layer. Pattern match on the exception type so that typed fields — like the missing item's name or the available stock — can flow directly into the localized message without going through a stringly-typed map.

**Good**

```dart
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

When rendering errors using `AsyncBuilder.errorBuilder`, show the translated message alongside the stable error code. Users cannot read a stack trace, but they can read a short identifier off their screen and repeat it to customer support, which turns an opaque failure into an actionable ticket. The raw exception should only appear in debug builds, where it helps the developer on the other end.

**Good**

```dart
AsyncBuilder<User>(
  state: viewModel.state.user,
  errorBuilder: (context, error) {
    final code = error is HasErrorCode ? error.code : 'unknown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.translateError(error)),
        Text(
          'Error code: $code',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (kDebugMode) Text('Dev: $error'),
      ],
    );
  },
)
```

### CONSIDER using a global Mediator middleware for crash reporting

If a repository author forgets to map an infrastructure error, or an unexpected crash occurs, it should not go unnoticed. Implement a middleware to catch all unhandled exceptions at the Mediator level, forward them to your telemetry service (like Crashlytics) with the preserved stack trace, and then rethrow so the ViewModel still transitions to `AsyncError<T>`.

**Good**

```dart
class CrashReportingMiddleware implements MediatorMiddleware {
  CrashReportingMiddleware(this._reporter);

  final ICrashReporter _reporter;

  @override
  Future<T> onRun<T>(Command<T> command, NextRun<Command<T>, T> next) async {
    try {
      return await next(command);
    } catch (error, stack) {
      _reporter.report(error, stack);
      rethrow;
    }
  }

  // Mirror the same try/catch/rethrow shape for onRead and onWatch
  // so read queries and watch streams are covered as well.
}
```

The middleware is the last line of defence: it should never swallow errors, only observe them. Apply the same pattern to `onRead` and `onWatch` so every message type flows through crash reporting.