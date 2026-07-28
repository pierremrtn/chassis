---
name: chassis-handle-view-model-events
description: Wire one-time UI side effects (snackbars, navigation, dialogs, vibration) emitted by a Chassis ViewModel as sealed Event variants, using `ViewModelProvider.withEvents` at the provision site or `ConsumerMixin` in a descendant widget. Use when adding a `sendEvent(...)` call in a ViewModel and the corresponding listener that turns events into UI side effects. Do NOT model these as nullable state fields (`String? snackbarMessage`) — that is the anti-pattern this skill exists to prevent.
---
# Handling One-Time Events from a ViewModel

## Contents
- [Core Concepts](#core-concepts)
- [State vs Events: The Distinction](#state-vs-events-the-distinction)
- [Two Listener Strategies: `withEvents` vs `ConsumerMixin`](#two-listener-strategies-withevents-vs-consumermixin)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

A Chassis ViewModel exposes two channels: a `state` (observable, persistent) and an `events` stream (one-shot, ephemeral). Events fire once per emission, regardless of widget rebuilds, and feed into UI side effects that should not replay: showing a snackbar, navigating to another screen, popping a dialog, triggering haptic feedback.

Events are produced inside the ViewModel with `sendEvent(<EventVariant>)`. Listeners consume them through one of two strategies:

- **`ViewModelProvider.withEvents<TViewModel, TEvent>`** at the provision site — co-locates the listener with where the ViewModel is created.
- **`ConsumerMixin`** in a descendant `State` — listens to a ViewModel provided by an ancestor.

Both subscribe to the same `events` stream and run cleanup automatically.

## State vs Events: The Distinction

> State represents the data that should be displayed on the screen at any given moment. (...) Events, in contrast, are one-time occurrences. A snackbar notification, a navigation action, or a vibration feedback are ephemeral; they happen once and should not be replayed if the UI rebuilds.
> — `golden_sample.md`

Modeling events as nullable state fields (`String? snackbarMessage`, `String? navigationRoute`) re-introduces every problem the event channel solves. Rebuilds replay the snackbar; manual cleanup is required to clear the field after consumption; the state object accumulates ephemeral fields that have nothing to do with what the UI renders. The compiler cannot help you — there is no exhaustive `switch` on a `String?`. The Event channel exists exactly to avoid this.

The decision is mechanical:

- *Should this still be visible if the screen rebuilds for an unrelated reason?* → State.
- *Does this fire once, trigger a side effect, and then become irrelevant?* → Event.

## Two Listener Strategies: `withEvents` vs `ConsumerMixin`

Both strategies are correct; they apply at different points in the widget tree.

**`ViewModelProvider.withEvents`** is the default. It creates the ViewModel and attaches the listener in one place, eagerly (so events emitted during construction are not missed). The `onEvent` callback receives the provider's own `BuildContext` (which sits *above* the ViewModel in the tree), the ViewModel instance, and the event. `ScaffoldMessenger.of(context)` and `Navigator.of(context)` work from this context; `context.read<TViewModel>()` does not — use the `viewModel` callback argument when you need the VM.

```dart
ViewModelProvider.withEvents<CheckoutViewModel, CheckoutEvent>(
  create: (_) => CheckoutViewModel(mediator),
  onEvent: (context, viewModel, event) { /* ... */ },
  child: const CheckoutScreen(),
);
```

**`ConsumerMixin`** is the right tool when a widget deep in the subtree needs to listen to a ViewModel provided by an ancestor — for example, a sticky footer that reacts to events emitted by a ViewModel above the screen. The mixin attaches in `initState` and disposes the subscription in `dispose`. It throws `StateError` if a listener for the same ViewModel type is registered twice in the same `State`.

```dart
class _CartFooterState extends State<CartFooter> with ConsumerMixin {
  @override
  void initState() {
    super.initState();
    onEvent<CheckoutViewModel, CheckoutEvent>((event) { /* ... */ });
  }
}
```

Use `withEvents` whenever the listener can live at the provision site. Reach for `ConsumerMixin` only when the listener must be separated from the provider by intermediate widgets, or when the listener needs `State` access (controllers, animation tickers, local fields).

## Rules

- **DO** define events as a `sealed class <Feature>Event` with one variant per kind of one-shot occurrence. *Sealed unions enable exhaustive `switch` at the listener and carry payloads via pattern destructuring.*
- **DO** emit events from inside the ViewModel using `sendEvent(<EventVariant>)`.
- **DO** prefer `ViewModelProvider.withEvents<T, E>` for the listener when the provision site is also the right place to handle the side effect. *It co-locates creation and consumption, runs eagerly so construction-time events are not missed, and disposes automatically.*
- **DO** use `ConsumerMixin` when a descendant widget needs to react to an ancestor-provided ViewModel's events, or when the listener needs access to local `State` fields (controllers, focus nodes, scroll positions).
- **DO** pattern-match on the sealed event type with a `switch` and destructure payloads (`case PaymentSuccessEvent(:final orderId): ...`). *The compiler enforces exhaustive handling.*
- **DO** route command failures through events when the screen still has valid content (`onError: (e) => sendEvent(<FailedEvent>(e))`). *A failed save should not blow away the form.* See `chassis-handle-errors`.
- **DON'T** model one-time occurrences as nullable state fields (`String? snackbarMessage`, `String? navigationRoute`, `bool showDialog`). *Rebuilds replay them, manual cleanup is required, the compiler cannot enforce exhaustiveness.*
- **DON'T** call `context.read<TViewModel>()` inside the `withEvents` `onEvent` callback. *The provider's context sits above the VM; use the `viewModel` argument the callback already provides.*
- **DON'T** register two `ConsumerMixin.onEvent<T, E>(...)` calls for the same ViewModel type in the same `State`. *The mixin throws `StateError` — split into a parent/child or merge the handlers.*
- **DON'T** subscribe to `viewModel.events` manually with `listen(...)` and a `StreamSubscription`. *The two listener strategies above own subscription lifecycle; manual subscriptions risk leaks if a widget unmounts before cancellation.*

## Workflow

- [ ] **Step 1 — Decide if the change is an event or state.** If the answer to "should this still be visible after a rebuild?" is no, it is an event.
- [ ] **Step 2 — Add a variant to the sealed event class** with whatever payload the listener will need. See `chassis-create-view-model` for the event class shape.
- [ ] **Step 3 — Emit from the ViewModel.** `sendEvent(<EventVariant>(payload))` from inside `run`'s `onData` / `onError`, or anywhere a one-shot occurrence is observed.
- [ ] **Step 4 — Pick the listener strategy.**
  - Listener at the provision site → `ViewModelProvider.withEvents<TVM, TEvent>` with an `onEvent` callback.
  - Listener inside a descendant widget that does not own the provision → `class _State extends State<...> with ConsumerMixin` and `onEvent<TVM, TEvent>((event) { ... })` in `initState`.
- [ ] **Step 5 — Pattern-match on the sealed event** in the callback. Destructure payloads with `case <Variant>(:final field): ...`.
- [ ] **Step 6 — Drive the side effect** from the matched case: `ScaffoldMessenger.of(context).showSnackBar(...)`, `Navigator.of(context).push(...)`, `showDialog(...)`, `HapticFeedback.lightImpact()`.

## Examples

### `withEvents` at the provision site

```dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

class CheckoutPage extends StatelessWidget {
  const CheckoutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelProvider.withEvents<CheckoutViewModel, CheckoutEvent>(
      create: (_) => CheckoutViewModel(mediator),
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

The `viewModel` callback argument is the right way to call back into the VM — `context.read<CheckoutViewModel>()` would not find the VM since the context sits above it.

### `ConsumerMixin` in a descendant widget

```dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

class CartFooter extends StatefulWidget {
  const CartFooter({super.key});

  @override
  State<CartFooter> createState() => _CartFooterState();
}

class _CartFooterState extends State<CartFooter> with ConsumerMixin {
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
    final viewModel = context.watch<CheckoutViewModel>();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text('Items: ${viewModel.state.cart.valueOrNull?.length ?? 0}'),
    );
  }
}
```

The `CheckoutViewModel` is provided higher up the tree; the footer reads its events without owning the provision.

### Routing a command's success and failure to events

```dart
class CheckoutViewModel extends ViewModel<CheckoutState, CheckoutEvent> {
  CheckoutViewModel(super.mediator) : super(initial: CheckoutState.initial());

  void payAndSubmit() {
    setState(state.copyWith(isProcessingPayment: true));
    run(
      mediator.submitOrder(/* ... */),
      onData: (order) {
        setState(state.copyWith(isProcessingPayment: false));
        sendEvent(PaymentSuccessEvent(order.id));
        sendEvent(NavigateToOrderConfirmationEvent(order.id));
      },
      onError: (error) {
        setState(state.copyWith(isProcessingPayment: false));
        sendEvent(PaymentFailedEvent(error));
      },
    );
  }
}
```

The form state stays intact through both branches; the events drive every UI side effect.

### Anti-pattern: events as state fields

```dart
// ❌ Don't do this — rebuilds replay events, manual cleanup needed.
class BadCheckoutState {
  final String? snackbarMessage;
  final String? navigationRoute;
  final bool showPaymentFailedDialog;
  // ...
}

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
class PaymentSuccessEvent implements CheckoutEvent {
  const PaymentSuccessEvent(this.orderId);
  final String orderId;
}

// In ViewModel:
void onPaymentSuccess(String orderId) {
  sendEvent(PaymentSuccessEvent(orderId));
}

// At provision site:
ViewModelProvider.withEvents<CheckoutViewModel, CheckoutEvent>(
  create: (_) => CheckoutViewModel(mediator),
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
