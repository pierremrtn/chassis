---
name: chassis-handle-errors
description: Implement Chassis's error-handling strategy end-to-end — throw exceptions (not Result types), map infrastructure exceptions to domain exceptions in the Repository layer, selectively recover in Handlers, cover the error path on every ViewModel dispatch (query errors through `Async<T>` state, command errors through Events carrying the error object), translate errors in the UI with stable codes, and wire the built-in `CrashReportingMiddleware` at the composition root. Use when adding any try/catch, creating a domain exception class, mapping a `FirebaseException` / `DioException`, deciding between an error state and a snackbar, or wiring crash reporting.
---
# Error Handling in a Chassis Application

## Contents
- [Core Concepts](#core-concepts)
- [The Four Layers of Error Handling](#the-four-layers-of-error-handling)
- [Deciding Where to Catch](#deciding-where-to-catch)
- [Domain Exceptions: Shape and Codes](#domain-exceptions-shape-and-codes)
- [Routing Errors to the UI: State vs Events](#routing-errors-to-the-ui-state-vs-events)
- [Observability: Crash Reporting Through Middleware](#observability-crash-reporting-through-middleware)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

Chassis handles errors through thrown exceptions, never `Result<T, E>` types. A ViewModel dispatches message objects with `run()` (a `Command`), `read()` (a `ReadQuery`), and `watch()` (a `WatchQuery`); every dispatch happens inside the framework's try/catch, so any failure — asynchronous, synchronous, even a wiring error — becomes an `Async<T>` error reported through the callbacks instead of a crash at the call site. The framework's job is propagation; the application's job is *deciding where to catch and what shape the error takes*.

> Exceptions express *unexpected* failures — the happy path broke and someone upstream needs to decide what to do. But many conditions that infrastructure surfaces as errors (a missing document, an empty query result, a cache miss) are part of the *expected* flow. Treating them as errors forces the UI into error states for scenarios that are not, in fact, errors.
> — `docs/error_management.md`

The strategy has four layers, each with a clear responsibility:

1. **Repository** — translate infrastructure exceptions (`FirebaseException`, `DioException`, `SocketException`) into domain exceptions. The Application layer must never see raw infrastructure types.
2. **Handler** — selectively recover from *expected* domain exceptions (a missing cart for a new user → an empty cart). Let *unexpected* failures bubble.
3. **ViewModel** — cover the error path on **every** dispatch: query errors flow into `Async<T>` state via `onState`, command errors into events via `onError` — and failure events carry the error *object*, never a string.
4. **Presentation** — translate the error type into a localized message, surface a stable error code, optionally show the raw error in debug builds.

Observability is the middleware chain — chassis has no `BlocObserver`/`ProviderObserver` equivalent, by design. The built-in `LoggingMiddleware` traces every dispatch outcome (including failures with stack traces), and the built-in `CrashReportingMiddleware` reports every failure crossing the mediator — fatal when the failure is a Dart `Error` (a bug), non-fatal otherwise — then lets it propagate. Both are wired once at the composition root — see [Observability](#observability-crash-reporting-through-middleware) and `chassis-bootstrap-app`.

One family of failures is exempt from all of this: the mediator's own `ChassisError` subtypes. `HandlerNotRegisteredError` (dispatch with no handler registered) and `DuplicateHandlerError` (two handlers for one message type, thrown identically in debug and release) are wiring mistakes, not runtime conditions. They extend `Error`, not `Exception` — the type system itself says *never catch*: an `on Exception` clause written for domain failures cannot swallow them, and `CrashReportingMiddleware` classifies them as fatal. Fix the registration (annotate the handler with `@chassisHandler` and re-run `build_runner`; the builder turns a reachable message with no handler into a *build* error, so these rarely survive to runtime). See `chassis-register-handler-with-codegen`.

## The Four Layers of Error Handling

| Layer | Catches | Throws | Goal |
|---|---|---|---|
| Repository | `FirebaseException`, `DioException`, `SocketException`, etc. | Domain exceptions (`PermissionDeniedException`, `NetworkException`, `CartNotFoundException`) | Anti-corruption layer. The Application layer never imports infrastructure error types. |
| Handler | Recoverable domain exceptions | Re-throws or business-specific domain exceptions | Decide what counts as "expected" for *this* business operation. |
| ViewModel | (handled by `run()` / `read()` / `watch()` automatically — any dispatch failure becomes an `AsyncError`) | (does not throw) | Cover the error path: `Async<T>` state via `onState` (queries), events carrying the error object via `onError` (commands). |
| Presentation | (does not catch — receives the error in the `AsyncError` branch or the event listener) | (does not throw) | Translate error type to localized message; show stable code. |

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

- **Queries → `Async<T>` state via `onState`**. A query failure usually means there is nothing meaningful to show on the screen. The widget's `switch` over the sealed `Async<T>` renders the `AsyncError` branch as a full error view with optional retry.
- **Commands → events via `onError`**. A failed save, payment, or "add to cart" should not replace the form, list, or selection. The screen still has valid content; a snackbar or dialog surfaces the error while state stays intact. `onError` receives `(Object error, StackTrace stack)` — put the error *object* in the event, never `error.toString()`.

Whichever channel you pick, **the error path must be covered on every `run`/`read` call**: provide `onState` and/or `onError`. `onSuccess` alone is the invisible-failure anti-pattern — a failed dispatch would report nothing anywhere.

Invert each default in the obvious cases:

- A *command that replaces the view* (checkout submit, account creation) should flow through `onState` like a query — on catastrophic failure a full error view beats a snackbar dropped on a screen the user is leaving.
- A *watch query that hiccups mid-stream* (lost socket, momentary outage) should keep the last-good snapshot visible — the soft-error pattern. The ViewModel's `watch()` produces this automatically: a stream error emits an `AsyncError` carrying the last known data as `previous`. This is exactly the case `AsyncBuilder` (default `maintainState: true`) is reserved for — it keeps rendering the carried value through the hiccup, where a plain `switch` would drop to the error branch. Add an `onError` callback (additive — it never suppresses `onState`) to also notify the user through an event.

## Observability: Crash Reporting Through Middleware

The mediator's middleware chain is chassis's observability channel: every dispatch — from any ViewModel, through any handler — crosses it. Two built-ins cover the standard needs, wired once at the composition root:

- `LoggingMiddleware` — traces every dispatch outcome.
- `CrashReportingMiddleware` — invokes your report callback for every failure, then lets it propagate.

`CrashReportingMiddleware` takes a single function:

```dart
CrashReportingMiddleware(
  (error, stack, {required fatal}) => FirebaseCrashlytics.instance
      .recordError(error, stack, fatal: fatal),
)
```

Classification uses Dart's own `Error`/`Exception` distinction:

- `error is Error` → reported **fatal**: a programming bug (a `TypeError` in a handler, a `ChassisError` wiring mistake).
- anything else → reported **non-fatal**: an expected runtime failure (domain exceptions, `NetworkException`, ...).

The middleware never swallows. Run/read failures are rethrown, so the ViewModel still transitions to `AsyncError`; watch stream errors are reported *and* forwarded to the subscriber, so the soft-error pipeline is untouched. A custom cross-cutting middleware follows the same shape — extend `MediatorMiddleware` (its hooks have pass-through defaults), override `onRun`/`onRead`/`onWatch`, observe, and rethrow. Middlewares never dispatch.

## Rules

### Architecture

- **DO** use thrown exceptions, not `Result<T, E>` types. *`run`/`read`/`watch` catch exceptions natively and report them as `Async` states; `Result` adds unwrapping boilerplate at every layer and breaks the plain `Future<T>` / `Stream<T>` handler signatures.*
- **DO** map infrastructure exceptions to domain exceptions inside the **Repository implementation**, never in handlers. *Repositories are the anti-corruption layer; the Application layer must not import infrastructure error types.*
- **DO** preserve the original stack trace when wrapping. Use `Error.throwWithStackTrace(mapped, stack)` from inside `on FirebaseException catch (e, stack) { ... }`.
- **DON'T** catch infrastructure errors inside handlers. *That breaks the Dependency Rule and couples the Application layer to a specific provider.*
- **DON'T** catch `ChassisError` — or any Dart `Error`. *They extend `Error` precisely so domain-failure `catch` clauses cannot swallow them: a `HandlerNotRegisteredError` or `DuplicateHandlerError` is a wiring bug. Fix the registration instead.*

### Where to catch in handlers

- **DO** catch a recoverable domain exception in the handler when there is a meaningful default — yield an empty cart for `CartNotFoundException`, fall back to a cached value for a transient outage. *Only the handler has enough business context to decide what counts as recoverable.*
- **DO** distinguish business outcomes from unexpected failures *before* deciding to throw. A new user has no cart — that is not an error.
- **DON'T** catch an exception only to rethrow it, or to swallow it silently. *That hides failures from the crash reporter.*
- **DO** model business rule failures as typed domain exceptions with stable codes (`InsufficientInventoryException`, `PaymentDeclinedException`). *Boolean flags and nullable returns hide the failure from the error pipeline.*

### Domain exception shape

- **DO** expose a stable, short string code on every domain exception (`item_not_found`, `insufficient_inventory`, `payment_declined`). *Codes are quoted in support tickets and aggregated in telemetry — treat them as a public API.*
- **DO** carry typed fields the localized message needs (`itemName`, `available`, `requested`). *Pattern matching on the exception type can pull them out without stringly-typed maps.*
- **DO** carry the original infrastructure error when wrapping one (`final Object? originalError`). *The crash report needs it; debug builds can render it.*
- **CONSIDER** defining a project-level `abstract interface class HasErrorCode { String get code; }` to read codes uniformly across UI, logs, and analytics without repeated `is` checks.
- **DON'T** use a Dart `enum` for error codes. *Enums cannot be extended outside the package that defines them, which makes a shared `ErrorCode` a dead end as soon as a feature module needs a new code.*

### Routing in the ViewModel

- **DO** cover the error path on every `run`/`read` call: provide `onState` and/or `onError`. *`onSuccess` alone is the invisible-failure anti-pattern — a failed dispatch reports nothing anywhere (a lint for this is planned).*
- **PREFER** routing query errors through `Async<T>` state via `onState`. *Loading, data, and error all flow from one source of truth, and the UI's `switch` renders a full error view with retry.*
- **PREFER** routing command errors through events via `onError`. *A failed save should not replace the user's form or list.*
- **DO** put the error *object* in failure events (`sendEvent(OrderFailedEvent(error))`), never `error.toString()`. *String-ified errors destroy pattern matching in the listener and in the translation helper.*
- **CONSIDER** inverting these defaults: a command that replaces the view (checkout submit) should flow through `onState`; a watch query whose hiccup should not blow away the screen should rely on `AsyncError.previous` and `AsyncBuilder`'s `maintainState: true`.

### Presentation

- **DO** translate errors exclusively in the UI layer. *The Domain layer knows nothing about `BuildContext` or localization packages.*
- **DO** define the translation helper (`context.translateError(...)` or similar) as a **project-level extension** — it is your code, not chassis API. *Chassis hands the UI the error object; the project owns how it is presented.*
- **DO** pattern-match on the exception type in the translation extension. *Typed fields flow into the localized message without stringly-typed lookups; the `_` catch-all handles unmapped errors gracefully.*
- **PREFER** displaying both the translated message and the stable error code. *Users cannot read a stack trace, but they can read and quote a short identifier.*
- **CONSIDER** showing the raw error in `kDebugMode` only — useful in development, never in production.

### Observability

- **DO** wire `CrashReportingMiddleware` once at the composition root, next to `LoggingMiddleware`. *The middleware chain is chassis's observability channel; every dispatch of the app crosses it, so nothing that bubbles past handler-level recovery goes unreported.*
- **DON'T** swallow failures in a custom middleware — observe, then rethrow (or forward the stream error). *A middleware that swallows turns every downstream `AsyncError` into a silent hang.*

## Workflow

- [ ] **Step 1 — At the Repository implementation**, wrap infrastructure calls in a mapping helper (typically an extension on `Future<T>` / `Stream<T>`). Translate every infrastructure exception to a domain exception. Use `Error.throwWithStackTrace(mapped, stack)` to preserve the original stack.
- [ ] **Step 2 — Define domain exceptions** as `implements Exception`. Carry a stable string `code`, typed fields the UI message will need, and an optional `originalError`. If the project uses a `HasErrorCode` interface, also `implements HasErrorCode`.
- [ ] **Step 3 — In the handler**, decide for each potential exception: *is it a normal business outcome?* If yes, catch and return a sensible default. If no, let it bubble. Document the exceptions `run` / `read` / `watch` may throw in the handler's `///` doc comment.
- [ ] **Step 4 — In the ViewModel**, route query errors through `onState` and command errors through `onError: (error, stack) => sendEvent(<FailedEvent>(error))`. Never leave a `run`/`read` with only `onSuccess`. Invert if the screen-replacement / soft-error inversion applies.
- [ ] **Step 5 — In the UI**, define a project-level `BuildContext.translateError(Object error)` extension that pattern-matches on exception type. Use it in the `AsyncError` branch of the rendering `switch` and in event listeners. Display the translated message + the stable code.
- [ ] **Step 6 — At the composition root**, add `CrashReportingMiddleware((error, stack, {required fatal}) => ...)` next to `LoggingMiddleware` on the `AppMediator` passed to `Chassis.initialize`.

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

class FirestoreUserRepository implements UserRepository {
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

class InsufficientInventoryException({
  required final String productId,
  required final int requested,
  required final int available,
  final Object? originalError,
}) implements Exception, HasErrorCode {
  @override
  String get code => 'insufficient_inventory';
}
```

### Handler: selective recovery

```dart
@chassisHandler
class WatchCartQueryHandler(final CartRepository cartRepository)
    implements WatchHandler<WatchCartQuery, ShoppingCart> {
  /// Streams the user's cart. Returns an empty cart for new users.
  ///
  /// Throws [PermissionDeniedException] if the caller cannot read this user's cart.
  /// Throws [NetworkException] on unrecoverable network failures.
  @override
  Stream<ShoppingCart> watch(WatchCartQuery query) async* {
    try {
      yield* cartRepository.watchCart(query.userId);
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
class CreateOrderCommandHandler({
  required final OrderRepository orderRepository,
  required final InventoryService inventoryService,
}) implements CommandHandler<CreateOrderCommand, Order> {
  /// Throws [InsufficientInventoryException] if any item is out of stock.
  @override
  Future<Order> run(CreateOrderCommand command) async {
    for (final item in command.items) {
      final available = await inventoryService.available(item.productId);
      if (available < item.quantity) {
        throw InsufficientInventoryException(
          productId: item.productId,
          requested: item.quantity,
          available: available,
        );
      }
    }
    return orderRepository.create(/* ... */);
  }
}
```

### ViewModel: query through state, command through events

```dart
sealed class CheckoutEvent {}

final class const OrderConfirmedEvent(final String orderId)
    implements CheckoutEvent;

final class const OrderFailedEvent(
  /// The error object: listeners and the translation helper pattern-match
  /// on its type. A String here would destroy that.
  final Object error,
) implements CheckoutEvent;

class CheckoutViewModel extends ViewModel<CheckoutState, CheckoutEvent> {
  CheckoutViewModel({required this.userId, super.mediator})
      : super(CheckoutState.initial()) {
    watchCart();
  }

  final String userId;

  /// Watch query — a stream error flows into AsyncError state carrying the
  /// last good cart, if any (soft error). Re-calling replaces the
  /// subscription: watches are keyed by query type by default.
  void watchCart() => watch(
        WatchCartQuery(userId: userId),
        current: state.cart,
        onState: (cart) => setState(state.copyWith(cart: cart)),
      );

  /// Command — state stays intact; failure becomes a one-shot event that
  /// carries the error object. The error path is covered by onError.
  void submit() => run(
        SubmitOrderCommand(userId: userId),
        policy: const RunPolicy.droppable(), // double-tap cannot dispatch twice
        onSuccess: (order) => sendEvent(OrderConfirmedEvent(order.id)),
        onError: (error, stack) => sendEvent(OrderFailedEvent(error)),
      );
}
```

### UI: project-level translation helper and error rendering

`translateError` is *your* code — a project-level extension, not chassis API. Chassis delivers the error object; the project decides how to present it.

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

class const CheckoutCartView({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cart = context.select((CheckoutViewModel vm) => vm.state.cart);
    // Simple rendering = inline switch (sealed Async<T> is exhaustive).
    // A screen that must keep the last snapshot through refetches or stream
    // hiccups uses AsyncBuilder (maintainState) instead — see
    // chassis-render-async-state.
    return switch (cart) {
      AsyncData(:final value) => CartView(cart: value),
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError(:final error) => _CartError(error: error),
    };
  }
}

class const _CartError({required final Object error})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final code = switch (error) {
      HasErrorCode(:final code) => code,
      _ => 'unknown',
    };
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
            onPressed: () => context.read<CheckoutViewModel>().watchCart(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
```

### Composition root: logging + crash reporting, wired once

```dart
// lib/main.dart
void main() {
  final crashlytics = FirebaseCrashlytics.instance;

  Chassis.initialize(
    AppMediator(
      orderRepository: FirestoreOrderRepository(FirebaseFirestore.instance),
      cartRepository: FirestoreCartRepository(FirebaseFirestore.instance),
      inventoryService: HttpInventoryService(),
    )
      ..addMiddleware(LoggingMiddleware())
      ..addMiddleware(CrashReportingMiddleware(
        (error, stack, {required fatal}) =>
            crashlytics.recordError(error, stack, fatal: fatal),
      )),
  );

  runApp(const MyApp());
}
```

`AppMediator` is the generated registration constructor (see `chassis-register-handler-with-codegen`). Every ViewModel dispatches its message objects through the mediator installed here, so both middlewares observe every operation of the app. `fatal` is `error is Error` — a `TypeError` in a handler or a `ChassisError` wiring bug reports as fatal; a domain exception reports as non-fatal. The middleware always rethrows: the ViewModel still transitions to `AsyncError`, and watch subscribers still receive the failure.

### Anti-pattern: the invisible failure

```dart
// ❌ onSuccess alone: a failed submit reports NOTHING — no error state,
// no event, the user stares at a button that did nothing.
void submit() => run(
      SubmitOrderCommand(userId: userId),
      onSuccess: (order) => sendEvent(OrderConfirmedEvent(order.id)),
    );
```

```dart
// ✅ Every run/read covers the error path with onState and/or onError.
void submit() => run(
      SubmitOrderCommand(userId: userId),
      onSuccess: (order) => sendEvent(OrderConfirmedEvent(order.id)),
      onError: (error, stack) => sendEvent(OrderFailedEvent(error)),
    );
```

### Anti-pattern: string-ified failure events

```dart
// ❌ error.toString() destroys pattern matching: the listener can no longer
// switch on the type, and translateError falls through to "unknown error".
void submit() => run(
      SubmitOrderCommand(userId: userId),
      onError: (error, stack) => sendEvent(OrderFailedEvent(error.toString())),
    );
```

```dart
// ✅ Carry the object; stringify only at the presentation edge.
void submit() => run(
      SubmitOrderCommand(userId: userId),
      onError: (error, stack) => sendEvent(OrderFailedEvent(error)),
    );
```

### Anti-pattern: catch-and-swallow

```dart
// ❌ Hides failures from the crash reporter and the user.
@override
Future<User> read(GetUserQuery query) async {
  try {
    return await _repository.getUser(query.id);
  } catch (_) {
    return User.unknown(); // silent failure
  }
}
```

```dart
// ✅ Catch only when there is a meaningful response; let unexpected errors bubble.
@override
Future<User> read(GetUserQuery query) async {
  try {
    return await _repository.getUser(query.id);
  } on UserNotFoundException {
    return User.guest(); // expected business outcome
  }
  // Other exceptions bubble and get reported by the middleware.
}
```

### Anti-pattern: Result type

```dart
// ❌ Forces every handler and ViewModel to unwrap manually; run/read/watch
// already report failures as Async states.
abstract interface class UserRepository {
  Future<Result<User, Exception>> getUser(String userId);
}
```

```dart
// ✅ Throw exceptions; Chassis catches them.
abstract interface class UserRepository {
  Future<User> getUser(String userId);
}
```
