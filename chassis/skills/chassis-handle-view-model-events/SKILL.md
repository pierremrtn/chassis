---
name: chassis-handle-view-model-events
description: Wire one-time UI side effects (snackbars, navigation, dialogs, vibration) emitted by a Chassis ViewModel as sealed Event variants, using `ViewModelProvider.withEventListener` at the provision site, the `EventListener` widget in a descendant subtree, or `EventListenerMixin` in a descendant `State`. Use when adding a `sendEvent(...)` call in a ViewModel and the corresponding listener that turns events into UI side effects. Do NOT model these as nullable state fields (`String? snackbarMessage`) — that is the anti-pattern this skill exists to prevent.
---
# Handling One-Time Events from a ViewModel

## Contents
- [Core Concepts](#core-concepts)
- [State vs Events: The Distinction](#state-vs-events-the-distinction)
- [Three Listener Strategies](#three-listener-strategies)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

A Chassis ViewModel exposes two channels: a `state` (observable, persistent) and an `events` stream (one-shot, ephemeral). Events fire once per emission, regardless of widget rebuilds, and feed into UI side effects that should not replay: showing a snackbar, navigating to another screen, popping a dialog, triggering haptic feedback.

Events are produced inside the ViewModel with `sendEvent(<EventVariant>)` — typically from the `onSuccess`/`onError` callbacks of a `run`/`read` dispatch (see `chassis-create-view-model`). **Failure events carry the error object** (`final Object error`), never `error.toString()`: a string-ified error destroys pattern matching, and the listener can no longer branch on the error type to translate it. Listeners consume events through one of three strategies:

- **`ViewModelProvider.withEventListener<TViewModel, TEvent>`** at the provision site — co-locates the listener with where the ViewModel is created. The practical default.
- **`EventListener<TViewModel, TEvent>`** — a widget wrapping a descendant subtree; the event-side counterpart of `AsyncBuilder`.
- **`EventListenerMixin`** in a descendant `State` — for widgets that are already stateful and would rather not wrap their tree.

All three subscribe to the same `events` stream and run cleanup automatically.

The stream has deliberate buffering semantics: events sent with `sendEvent(...)` **before the first subscriber** are buffered (bounded) and delivered to that first subscriber, so events emitted during ViewModel construction are not lost. After the first subscription, regular broadcast semantics apply — events emitted while nobody listens are dropped.

## State vs Events: The Distinction

> State represents the data that should be displayed on the screen at any given moment. (...) Events, in contrast, are one-time occurrences. A snackbar notification, a navigation action, or a vibration feedback are ephemeral; they happen once and should not be replayed if the UI rebuilds.
> — `golden_sample.md`

Modeling events as nullable state fields (`String? snackbarMessage`, `String? navigationRoute`) re-introduces every problem the event channel solves. Rebuilds replay the snackbar; manual cleanup is required to clear the field after consumption; the state object accumulates ephemeral fields that have nothing to do with what the UI renders. The compiler cannot help you — there is no exhaustive `switch` on a `String?`. The Event channel exists exactly to avoid this.

The decision is mechanical:

- *Should this still be visible if the screen rebuilds for an unrelated reason?* → State.
- *Does this fire once, trigger a side effect, and then become irrelevant?* → Event.

## Three Listener Strategies

All three strategies are correct; they apply at different points in the widget tree.

**`ViewModelProvider.withEventListener`** is the practical default. It creates the ViewModel and attaches the listener in one place, eagerly — combined with the pre-subscription buffer, events emitted during construction reach the listener. The `onEvent` callback receives the provider's own `BuildContext` (which sits *above* the ViewModel in the tree), the ViewModel instance, and the event. `ScaffoldMessenger.of(context)` and `Navigator.of(context)` work from this context; `context.read<TViewModel>()` does not — use the `viewModel` callback argument when you need the VM.

```dart
ViewModelProvider.withEventListener<CheckoutViewModel, CheckoutEvent>(
  create: (_) => CheckoutViewModel(),
  onEvent: (context, viewModel, event) { /* ... */ },
  child: const CheckoutScreen(),
);
```

**`EventListener`** is the declarative option for a descendant: a widget that wraps a subtree and invokes its callback for each event of the ViewModel provided above — the event-side counterpart of `AsyncBuilder`. Its callback context sits *below* the provider, so `context.read<TViewModel>()` works there. It resubscribes automatically if the provider swaps the ViewModel instance.

```dart
EventListener<CheckoutViewModel, CheckoutEvent>(
  onEvent: (context, event) { /* ... */ },
  child: const CartFooter(),
);
```

**`EventListenerMixin`** serves widgets that are already `StatefulWidget`s and would rather not wrap their tree — for example, a listener that needs `State` access (controllers, animation tickers, local fields). The mixin attaches in `initState` and disposes the subscription in `dispose`. It throws `StateError` if a listener for the same ViewModel type is registered twice in the same `State`.

```dart
class _CartFooterState extends State<CartFooter> with EventListenerMixin {
  @override
  void initState() {
    super.initState();
    onEvent<CheckoutViewModel, CheckoutEvent>((event) { /* ... */ });
  }
}
```

Use `withEventListener` whenever the listener can live at the provision site. Reach for `EventListener` when the listener must be separated from the provider by intermediate widgets, and for `EventListenerMixin` when that listener additionally needs `State` access.

## Rules

- **DO** define events as a `sealed class <Feature>Event` with one variant per kind of one-shot occurrence. *Sealed unions enable exhaustive `switch` at the listener and carry payloads via pattern destructuring.*
- **DO** emit events from inside the ViewModel using `sendEvent(<EventVariant>)`.
- **DO** carry the error object in failure event variants (`class const PaymentFailedEvent(final Object error) implements CheckoutEvent;`). *The listener pattern-matches on the error type to pick the dialog, translation, or retry affordance; `error.toString()` destroys that.*
- **DO** prefer `ViewModelProvider.withEventListener<T, E>` for the listener when the provision site is also the right place to handle the side effect. *It co-locates creation and consumption, runs eagerly so construction-time events are not missed, and disposes automatically.*
- **DO** use the `EventListener` widget when a descendant subtree needs to react to an ancestor-provided ViewModel's events, and `EventListenerMixin` when that listener additionally needs access to local `State` fields (controllers, focus nodes, scroll positions).
- **DO** pattern-match on the sealed event type with a `switch` and destructure payloads (`case PaymentSuccessEvent(:final orderId): ...`). *The compiler enforces exhaustive handling.*
- **DO** route command failures through events when the screen still has valid content (`onError: (error, stack) => sendEvent(<FailedEvent>(error))`). *A failed save should not blow away the form.* See `chassis-handle-errors`.
- **DON'T** model one-time occurrences as nullable state fields (`String? snackbarMessage`, `String? navigationRoute`, `bool showDialog`). *Rebuilds replay them, manual cleanup is required, the compiler cannot enforce exhaustiveness.*
- **DON'T** call `context.read<TViewModel>()` inside the `withEventListener` `onEvent` callback. *The provider's context sits above the VM; use the `viewModel` argument the callback already provides.*
- **DON'T** register two `EventListenerMixin.onEvent<T, E>(...)` calls for the same ViewModel type in the same `State`. *The mixin throws `StateError` — split into a parent/child or merge the handlers.*
- **DON'T** subscribe to `viewModel.events` manually with `listen(...)` and a `StreamSubscription`. *The three listener strategies above own subscription lifecycle; manual subscriptions risk leaks if a widget unmounts before cancellation.*

## Workflow

- [ ] **Step 1 — Decide if the change is an event or state.** If the answer to "should this still be visible after a rebuild?" is no, it is an event.
- [ ] **Step 2 — Add a variant to the sealed event class** with whatever payload the listener will need — the error object itself for failure variants. See `chassis-create-view-model` for the event class shape.
- [ ] **Step 3 — Emit from the ViewModel.** `sendEvent(<EventVariant>(payload))` from inside a dispatch's `onSuccess` / `onError`, or anywhere a one-shot occurrence is observed.
- [ ] **Step 4 — Pick the listener strategy.**
  - Listener at the provision site → `ViewModelProvider.withEventListener<TVM, TEvent>` with an `onEvent` callback.
  - Listener wrapping a descendant subtree → `EventListener<TVM, TEvent>(onEvent: ..., child: ...)`.
  - Listener inside a descendant `State` that needs local fields → `class _State extends State<...> with EventListenerMixin` and `onEvent<TVM, TEvent>((event) { ... })` in `initState`.
- [ ] **Step 5 — Pattern-match on the sealed event** in the callback. Destructure payloads with `case <Variant>(:final field): ...`.
- [ ] **Step 6 — Drive the side effect** from the matched case: `ScaffoldMessenger.of(context).showSnackBar(...)`, `Navigator.of(context).push(...)`, `showDialog(...)`, `HapticFeedback.lightImpact()`.

## Examples

### `withEventListener` at the provision site

```dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

class const CheckoutPage({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ViewModelProvider.withEventListener<CheckoutViewModel, CheckoutEvent>(
      create: (_) => CheckoutViewModel(),
      onEvent: (context, viewModel, event) {
        switch (event) {
          case PaymentSuccessEvent(:final orderId):
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Payment successful — order #$orderId')),
            );
          case PaymentFailedEvent(:final error):
            showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Payment failed'),
                // translateError is a project-level helper extension that
                // pattern-matches on the error object — see chassis-handle-errors.
                content: Text(context.translateError(error)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          case NavigateToOrderConfirmationEvent(:final orderId):
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => OrderConfirmationScreen(orderId: orderId),
              ),
            );
        }
      },
      child: const CheckoutScreen(),
    );
  }
}
```

The `viewModel` callback argument is the right way to call back into the VM — `context.read<CheckoutViewModel>()` would not find the VM since the context sits above it. Translating the error here only works because `PaymentFailedEvent` carries the error *object*.

### `EventListener` around a descendant subtree

```dart
EventListener<CheckoutViewModel, CheckoutEvent>(
  onEvent: (context, event) {
    if (event case PaymentSuccessEvent(:final orderId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order #$orderId confirmed')),
      );
    }
  },
  child: const CartFooter(),
);
```

The listener wraps only the subtree that cares about the events; its callback context sits *below* the provider, so `context.read<CheckoutViewModel>()` works here.

### `EventListenerMixin` in a descendant widget

```dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class const CartFooter({super.key}) extends StatefulWidget {
  @override
  State<CartFooter> createState() => _CartFooterState();
}

class _CartFooterState extends State<CartFooter> with EventListenerMixin {
  @override
  void initState() {
    super.initState();
    onEvent<CheckoutViewModel, CheckoutEvent>((event) {
      if (event is PaymentSuccessEvent) {
        HapticFeedback.lightImpact();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncCart = context.select(
      (CheckoutViewModel vm) => vm.state.cart,
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: switch (asyncCart) {
        AsyncData(value: final cart) => Text('Items: ${cart.length}'),
        AsyncLoading() => const Text('…'),
        AsyncError() => const Text('Cart unavailable'),
      },
    );
  }
}
```

The `CheckoutViewModel` is provided higher up the tree; the footer reads its events without owning the provision.

### Routing a command's success and failure to events

```dart
class CheckoutViewModel extends ViewModel<CheckoutState, CheckoutEvent> {
  CheckoutViewModel({super.mediator}) : super(CheckoutState.initial());

  void payAndSubmit() => run(
        SubmitOrderCommand(cartId: state.cartId),
        policy: const RunPolicy.droppable(), // a double-tap cannot submit twice
        onState: (submission) =>
            setState(state.copyWith(submission: submission)),
        onSuccess: (order) {
          sendEvent(PaymentSuccessEvent(order.id));
          sendEvent(NavigateToOrderConfirmationEvent(order.id));
        },
        onError: (error, stack) => sendEvent(PaymentFailedEvent(error)),
      );
}
```

The method is synchronous and expression-bodied — the command message goes straight to `run`. `onState` tracks the submission lifecycle in state (button spinner via `state.submission.isLoading`), while the events drive every UI side effect; the form state stays intact through both branches. See `chassis-create-view-model`.

### Anti-pattern: events as state fields

```dart
// ❌ Don't do this — rebuilds replay events, manual cleanup needed.
class BadCheckoutState({
  final String? snackbarMessage,
  final String? navigationRoute,
  final bool showPaymentFailedDialog = false,
  // ...
});
```

```dart
// In ViewModel:
void onPaymentSuccess() {
  setState(state.copyWith(snackbarMessage: 'Payment successful'));
}

// In widget:
final message = state.snackbarMessage;
if (message != null) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    viewModel.setState(state.copyWith(snackbarMessage: null)); // manual cleanup
  });
}
```

```dart
// ✅ Use the event channel
sealed class CheckoutEvent {}

class const PaymentSuccessEvent(final String orderId) implements CheckoutEvent;
```

```dart
// In ViewModel:
void onPaymentSuccess(String orderId) => sendEvent(PaymentSuccessEvent(orderId));

// At provision site:
ViewModelProvider.withEventListener<CheckoutViewModel, CheckoutEvent>(
  create: (_) => CheckoutViewModel(),
  onEvent: (context, _, event) {
    if (event case PaymentSuccessEvent(:final orderId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment successful — order #$orderId')),
      );
    }
  },
  child: const CheckoutScreen(),
);
```
