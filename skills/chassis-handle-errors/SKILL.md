---
name: chassis-handle-errors
description: Implement Chassis's error-handling strategy end-to-end — throw exceptions (not Result types), map infrastructure exceptions to domain exceptions in the Repository layer, selectively recover in Handlers, route query errors through `Async<T>.error` and command errors through Events, translate exceptions in the UI with stable error codes, and add a Mediator middleware for crash reporting. Use when adding any try/catch, creating a domain exception class, mapping a `FirebaseException` / `DioException`, deciding between an `errorBuilder` and a snackbar, or wiring crash reporting.
---
# Error Handling in a Chassis Application

## Contents
- [Core Concepts](#core-concepts)
- [The Four Layers of Error Handling](#the-four-layers-of-error-handling)
- [Deciding Where to Catch](#deciding-where-to-catch)
- [Domain Exceptions: Shape and Codes](#domain-exceptions-shape-and-codes)
- [Routing Errors to the UI: State vs Events](#routing-errors-to-the-ui-state-vs-events)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

Chassis handles errors through thrown exceptions, never `Result<T, E>` types. The ViewModel's `run()` and `watch()` methods catch exceptions automatically and route them either into `Async<T>.error` state or into an `onError` callback that can dispatch an event. The framework's job is propagation; the application's job is *deciding where to catch and what shape the exception takes*.

> Exceptions express *unexpected* failures — the happy path broke and someone upstream needs to decide what to do. But many conditions that infrastructure surfaces as errors (a missing document, an empty query result, a cache miss) are part of the *expected* flow. Treating them as errors forces the UI into error states for scenarios that are not, in fact, errors.
> — `docs/error_management.md`

The strategy has four layers, each with a clear responsibility:

1. **Repository** — translate infrastructure exceptions (`FirebaseException`, `DioException`, `SocketException`) into domain exceptions. The Application layer must never see raw infrastructure types.
2. **Handler** — selectively recover from *expected* domain exceptions (a missing cart for a new user → an empty cart). Let *unexpected* failures bubble.
3. **ViewModel** — route query errors through `Async<T>.error` state, command errors through events.
4. **Presentation** — translate the exception type into a localized message, surface a stable error code, optionally show the raw error in debug builds.

A crash-reporting middleware sits at the Mediator level and observes everything that bubbles past handler-level recovery — see the last section.

## The Four Layers of Error Handling

| Layer | Catches | Throws | Goal |
|---|---|---|---|
| Repository | `FirebaseException`, `DioException`, `SocketException`, etc. | Domain exceptions (`PermissionDeniedException`, `NetworkException`, `CartNotFoundException`) | Anti-corruption layer. The Application layer never imports infrastructure error types. |
| Handler | Recoverable domain exceptions | Re-throws or business-specific domain exceptions | Decide what counts as "expected" for *this* business operation. |
| ViewModel | (handled by `run()` / `watch()` automatically) | (does not throw) | Route into `Async<T>.error` (queries) or `sendEvent(<FailedEvent>(error))` (commands). |
| Presentation | (does not catch — receives the error in `errorBuilder` / event handler) | (does not throw) | Translate exception type to localized message; show stable code. |

## Deciding Where to Catch

A handler should catch a domain exception only when it has a *meaningful response*: return a default, try an alternate path, or convert the exception into a more specific one. Catching to rethrow, or catching to log-and-swallow, hides the failure from the crash reporter.

The rule of thumb:

- *Is this a normal business outcome that surfaces as an exception?* (no cart yet for a new user, missing optional document) → catch in the handler, return a sensible default.
- *Is this an unexpected failure?* (network down, permission denied, unknown error) → let it bubble. The ViewModel routes it to `Async.error` or an event; the middleware reports it.

Business rule failures (insufficient inventory, declined payment, expired promo) are also exceptions — typed, with stable codes — and they bubble to the UI through the same pipeline as infrastructure failures, but the UX language is usually different. Infrastructure failures suggest retry; business failures need a specific, terminal explanation.

## Domain Exceptions: Shape and Codes

Domain exceptions serve two audiences: a developer reading a stack trace, and a user reading a translated message and an error code they can quote to support. A well-shaped exception carries a **stable string code**, any **typed fields** the localized message needs, and the **original infrastructure error** when one exists.

> Strings are the right type here. Dart enums cannot be extended outside the package that defines them, which makes a shared `ErrorCode` enum a dead end the moment an app needs a code the enum does not cover.
> — `docs/error_management.md`

Chassis does not ship a base class for domain exceptions. Define them as `implements Exception`, and add an optional project-level `HasErrorCode` interface if multiple layers need to read the code without type checks.

## Routing Errors to the UI: State vs Events

Two channels exist; the right one depends on a single question — *after the error happens, is the current view still useful?*

- **Queries → `Async<T>.error` via `onState`**. A query failure usually means there is nothing meaningful to show on the screen. `AsyncBuilder.errorBuilder` renders a full view error with optional retry.
- **Commands → events via `onError`**. A failed save, payment, or "add to cart" should not replace the form, list, or selection. The screen still has valid content; a snackbar or dialog surfaces the error while state stays intact.

Invert each default in the obvious cases:

- A *command that replaces the view* (checkout submit, account creation) should flow through `onState` like a query — on catastrophic failure a full error view beats a snackbar dropped on a screen the user is leaving.
- A *watch query that hiccups mid-stream* (lost socket, momentary outage) often should keep the last-good snapshot visible via `Async<T>.previous` rather than show an error screen — the soft-error pattern.

## Rules

### Architecture

- **DO** use thrown exceptions, not `Result<T, E>` types. *Chassis catches exceptions natively; `Result` adds boilerplate and breaks the clean `Future<T>` signatures the generated Mediator extensions expect.*
- **DO** map infrastructure exceptions to domain exceptions inside the **Repository implementation**, never in handlers. *Repositories are the anti-corruption layer; the Application layer must not import infrastructure error types.*
- **DO** preserve the original stack trace when wrapping. Use `Error.throwWithStackTrace(mapped, stack)` from inside `on FirebaseException catch (e, stack) { ... }`.
- **DON'T** catch infrastructure errors inside handlers. *That breaks the Dependency Rule and couples the Application layer to a specific provider.*

### Where to catch in handlers

- **DO** catch a recoverable domain exception in the handler when there is a meaningful default — yield an empty cart for `CartNotFoundException`, fall back to a cached value for a transient outage. *Only the handler has enough business context to decide what counts as recoverable.*
- **DO** distinguish business outcomes from unexpected failures *before* deciding to throw. A new user has no cart — that is not an error.
- **DON'T** catch an exception only to rethrow it, or to swallow it silently. *That hides failures from the crash reporter.*
- **DO** model business rule failures as typed domain exceptions with stable codes (`InsufficientInventoryException`, `PaymentDeclinedException`). *Boolean flags and nullable returns hide the failure from the error pipeline.*

### Domain exception shape

- **DO** expose a stable, short string code on every domain exception (`item_not_found`, `insufficient_inventory`, `payment_declined`). *Codes are quoted in support tickets and aggregated in telemetry — treat them as a public API.*
- **DO** carry typed fields the localized message needs (`itemName`, `available`, `requested`). *Pattern matching on the exception type can pull them out without stringly-typed maps.*
- **DO** carry the original infrastructure error when wrapping one (`final Object? originalError`). *The middleware needs it for crash reporting; debug builds can render it.*
- **CONSIDER** defining a project-level `abstract interface class HasErrorCode { String get code; }` to read codes uniformly across UI, logs, and analytics without repeated `is` checks.
- **DON'T** use a Dart `enum` for error codes. *Enums cannot be extended outside the package that defines them, which makes a shared `ErrorCode` a dead end as soon as a feature module needs a new code.*

### Routing in the ViewModel

- **PREFER** routing query errors through `Async<T>` state via `onState`. *`AsyncBuilder.errorBuilder` renders a full error view with retry; loading, data, and error all flow from one source of truth.*
- **PREFER** routing command errors through events via `onError`. *A failed save should not replace the user's form or list.*
- **CONSIDER** inverting these defaults: a command that replaces the view (checkout submit) should flow through `onState`; a watch query whose hiccup should not blow away the screen should rely on `Async<T>.previous` and `AsyncBuilder.maintainState: true`.

### Presentation

- **DO** translate exceptions exclusively in the UI layer. *The Domain layer knows nothing about `BuildContext` or localization packages.*
- **DO** pattern-match on the exception type in the translation extension. *Typed fields flow into the localized message without stringly-typed lookups; the `_` catch-all handles unmapped errors gracefully.*
- **PREFER** displaying both the translated message and the stable error code. *Users cannot read a stack trace, but they can read and quote a short identifier.*
- **CONSIDER** showing the raw exception in `kDebugMode` only — useful in development, never in production.

### Global safety

- **CONSIDER** a `MediatorMiddleware` that catches every exception bubbling through `onRun`, `onRead`, `onWatch`, forwards it to crash reporting with the preserved stack, and **rethrows**. *The middleware is a last line of defence; it observes, never swallows.*

## Workflow

- [ ] **Step 1 — At the Repository implementation**, wrap infrastructure calls in a mapping helper (typically an extension on `Future<T>` / `Stream<T>`). Translate every infrastructure exception to a domain exception. Use `Error.throwWithStackTrace(mapped, stack)` to preserve the original stack.
- [ ] **Step 2 — Define domain exceptions** as `implements Exception`. Carry a stable string `code`, typed fields the UI message will need, and an optional `originalError`. If the project uses a `HasErrorCode` interface, also `implements HasErrorCode`.
- [ ] **Step 3 — In the handler**, decide for each potential exception: *is it a normal business outcome?* If yes, catch and return a sensible default. If no, let it bubble. Document the exceptions `run` / `read` / `watch` may throw in the handler's `///` doc comment.
- [ ] **Step 4 — In the ViewModel**, route query errors through `onState` and command errors through `onError`. Invert if the screen-replacement / soft-error inversion applies.
- [ ] **Step 5 — In the UI**, define a `BuildContext.translateError(Object error)` extension that pattern-matches on exception type. Use it in `errorBuilder` and event handlers. Display the translated message + the stable code.
- [ ] **Step 6 — At the Mediator**, install a `CrashReportingMiddleware` that catches everything in `onRun` / `onRead` / `onWatch`, reports to telemetry with the stack, and rethrows.

## Examples

### Repository: mapping infrastructure exceptions

```dart
extension FirebaseErrorMapper<T> on Future<T> {
  Future<T> mapFirebaseErrors() async {
    try {
      return await this;
    } on FirebaseException catch (e, stack) {
      final mapped = switch (e.code) {
        'permission-denied' => PermissionDeniedException(originalError: e),
        'unavailable' => NetworkException(originalError: e),
        _ => UnknownInfrastructureException(originalError: e),
      };
      Error.throwWithStackTrace(mapped, stack);
    }
  }
}

class FirestoreUserRepository implements IUserRepository {
  @override
  Future<User> getUser(String userId) {
    return firestore
        .collection('users')
        .doc(userId)
        .get()
        .mapFirebaseErrors()
        .then((doc) => doc.toDomain());
  }
}
```

### Domain exception with stable code and typed fields

```dart
abstract interface class HasErrorCode {
  String get code;
}

class InsufficientInventoryException implements Exception, HasErrorCode {
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

  @override
  String get code => 'insufficient_inventory';
}
```

### Handler: selective recovery

```dart
@chassisHandler
class WatchCartQueryHandler implements WatchHandler<WatchCartQuery, ShoppingCart> {
  WatchCartQueryHandler({required ICartRepository cartRepository})
      : _cartRepository = cartRepository;

  final ICartRepository _cartRepository;

  /// Streams the user's cart. Returns an empty cart for new users.
  ///
  /// Throws [PermissionDeniedException] if the caller cannot read this user's cart.
  /// Throws [NetworkException] on unrecoverable network failures.
  @override
  Stream<ShoppingCart> watch(WatchCartQuery query) async* {
    try {
      yield* _cartRepository.watchCart(query.userId);
    } on CartNotFoundException {
      // Expected outcome for a new user — yield empty rather than error.
      yield ShoppingCart.empty(query.userId);
    }
    // PermissionDeniedException, NetworkException — let them bubble.
  }
}
```

### Handler: business rule failure as typed exception

```dart
@chassisHandler
class CreateOrderCommandHandler
    implements CommandHandler<CreateOrderCommand, Order> {
  CreateOrderCommandHandler({
    required IOrderRepository orderRepository,
    required IInventoryService inventoryService,
  })  : _orderRepository = orderRepository,
        _inventoryService = inventoryService;

  final IOrderRepository _orderRepository;
  final IInventoryService _inventoryService;

  /// Throws [InsufficientInventoryException] if any item is out of stock.
  @override
  Future<Order> run(CreateOrderCommand command) async {
    for (final item in command.items) {
      final available = await _inventoryService.available(item.productId);
      if (available < item.quantity) {
        throw InsufficientInventoryException(
          productId: item.productId,
          requested: item.quantity,
          available: available,
        );
      }
    }
    return _orderRepository.create(/* ... */);
  }
}
```

### ViewModel: query through state, command through events

```dart
class CheckoutViewModel extends ViewModel<CheckoutState, CheckoutEvent> {
  CheckoutViewModel(super.mediator) : super(initial: CheckoutState.initial()) {
    // Watch query — error flows into Async.error, AsyncBuilder.errorBuilder renders it.
    watch(
      mediator.watchCart(userId: userId),
      onState: (asyncCart) => setState(state.copyWith(cart: asyncCart)),
    );
  }

  void submit() {
    // Command — keeps state intact, dispatches a one-shot event on failure.
    run(
      mediator.createOrder(/* ... */),
      onData: (order) => sendEvent(OrderConfirmedEvent(order.id)),
      onError: (error) => sendEvent(OrderFailedEvent(error)),
    );
  }
}
```

### UI: translation extension and `errorBuilder`

```dart
extension ErrorTranslation on BuildContext {
  String translateError(Object error) {
    final loc = AppLocalizations.of(this)!;
    return switch (error) {
      InsufficientInventoryException(:final available) =>
        loc.error_inventory(available),
      PermissionDeniedException() => loc.error_permission_denied,
      NetworkException() => loc.error_network,
      _ => loc.error_unknown,
    };
  }
}

// In a screen:
AsyncBuilder<ShoppingCart>(
  state: viewModel.state.cart,
  builder: (_, cart) => CartView(cart: cart),
  errorBuilder: (context, error) {
    final code = error is HasErrorCode ? error.code : 'unknown';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.translateError(error)),
          Text('Error code: $code',
              style: Theme.of(context).textTheme.bodySmall),
          if (kDebugMode) Text('Dev: $error'),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => context.read<CheckoutViewModel>().reload(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  },
);
```

### Crash-reporting middleware

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

  @override
  Future<T> onRead<T>(ReadQuery<T> query, NextRead<ReadQuery<T>, T> next) async {
    try {
      return await next(query);
    } catch (error, stack) {
      _reporter.report(error, stack);
      rethrow;
    }
  }

  @override
  Stream<T> onWatch<T>(WatchQuery<T> query, NextWatch<WatchQuery<T>, T> next) {
    return next(query).handleError((error, stack) {
      _reporter.report(error, stack as StackTrace);
      throw error;
    });
  }
}
```

The middleware never swallows — it observes and rethrows so the ViewModel still transitions to `Async.error` and downstream listeners still receive the failure.

### Anti-pattern: catch-and-swallow

```dart
// ❌ Hides failures from the crash reporter and the user.
@override
Future<User> run(GetUserCommand command) async {
  try {
    return await _repository.getUser(command.id);
  } catch (_) {
    return User.unknown(); // silent failure
  }
}
```

```dart
// ✅ Catch only when there is a meaningful response; let unexpected errors bubble.
@override
Future<User> run(GetUserCommand command) async {
  try {
    return await _repository.getUser(command.id);
  } on UserNotFoundException {
    return User.guest(); // expected business outcome
  }
  // Other exceptions bubble and get reported by the middleware.
}
```

### Anti-pattern: Result type

```dart
// ❌ Forces every handler and ViewModel to unwrap manually; breaks Mediator extensions.
abstract interface class IUserRepository {
  Future<Result<User, Exception>> getUser(String userId);
}
```

```dart
// ✅ Throw exceptions; Chassis catches them.
abstract interface class IUserRepository {
  Future<User> getUser(String userId);
}
```
