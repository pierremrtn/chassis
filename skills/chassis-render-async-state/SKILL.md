---
name: chassis-render-async-state
description: Render an `Async<T>` value in the widget tree using Chassis's `AsyncBuilder`, with builder / loadingBuilder / errorBuilder and anti-flicker behavior via `maintainState`. Use when displaying any data wrapped in `Async<T>` (a watch query result, a one-time fetch result, a derived state field) — the alternative would be a manual `if (loading) ... else if (error) ...` chain in `build()`, which is exactly what this widget exists to replace.
---
# Rendering Async State with AsyncBuilder

## Contents
- [Core Concepts](#core-concepts)
- [Builder Resolution Rules](#builder-resolution-rules)
- [Anti-Flicker with `maintainState`](#anti-flicker-with-maintainstate)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

`Async<T>` is the sealed union that models the lifecycle of an asynchronous value: `AsyncLoading<T>`, `AsyncData<T>`, or `AsyncError<T>`. Both `AsyncLoading` and `AsyncError` can carry a `previous` value, which enables the UI to keep displaying valid data while a refetch is in flight or while a transient error is active.

`AsyncBuilder<T>` is the widget that turns an `Async<T>` into a `Widget`. It takes:

- `state: Async<T>` — the current value.
- `builder: (BuildContext, T) → Widget` — required. Renders when data is available.
- `loadingBuilder: (BuildContext) → Widget` — optional. Default: `Center(child: CircularProgressIndicator())`.
- `errorBuilder: (BuildContext, Object) → Widget` — optional. Default: `SizedBox.shrink()`.
- `maintainState: bool` — default `true`. Controls whether the previous value should be shown during loading / error refresh.

> AsyncBuilder is a StatelessWidget that renders different UI based on Async<T> state, eliminating manual state checking in build methods.
> — `docs/04_ui_integration.md`

The `builder` callback receives the unwrapped `T`, never `null`. No defensive null checks are needed inside it.

## Builder Resolution Rules

The widget resolves which builder to call in this exact order:

1. **`state.hasValue && maintainState`** → `builder(context, state.valueOrNull!)`. This is the anti-flicker case: even if the state is `AsyncLoading(previous: data)` or `AsyncError(previous: data)`, the data builder runs.
2. **`state.isLoading`** → `loadingBuilder` (or default spinner).
3. **`state.hasError`** → `errorBuilder` (or empty box).
4. **Fallback** → `SizedBox.shrink()`.

Set `maintainState: false` only when you explicitly want the loading or error UI to replace stale data — for example, on a screen where stale data would be misleading (a payment status, a security indicator).

## Anti-Flicker with `maintainState`

The default `maintainState: true` keeps stale data visible while new data is loading. The user does not see a flash of spinner during pull-to-refresh or pagination — they see their data, and it updates when the new value arrives. This is the right default for most lists, profiles, and dashboards.

The visual flow with `maintainState: true`:

- **Initial load** (`Async.loading()`, no previous): `loadingBuilder` runs → spinner.
- **First success** (`Async.data(user)`): `builder` runs → user profile.
- **Refetch** (`Async.loading(previous: user)`): `builder` continues with previous user. No flicker.
- **Refetch completes** (`Async.data(newUser)`): `builder` updates smoothly.
- **Refetch error** (`Async.error(e, previous: user)`): `builder` continues with previous user. The error is silent in the UI — handle it through events if the user should be notified. See `chassis-handle-view-model-events` and `chassis-handle-errors`.

## Rules

- **DO** wrap any asynchronous data in state with `Async<T>` and render it through `AsyncBuilder<T>`. *The sealed union forces exhaustive handling and the widget eliminates manual `if (loading) ... else ...` chains in `build()`.*
- **DO** keep the `builder` focused on rendering data. Pull conditional layout (empty list, no results) inside the `builder` body, since `builder` only runs when data is present.
- **DO** provide a custom `errorBuilder` for any user-facing screen. *The default is `SizedBox.shrink()`, which silently hides errors — acceptable for non-critical secondary widgets, never for the primary content of a screen.*
- **DO** translate domain exceptions in the `errorBuilder` and display the translated message alongside a stable error code. See `chassis-handle-errors`.
- **PREFER** the default `maintainState: true` for lists, profiles, dashboards, and any screen where seeing the previous value during refresh is helpful.
- **CONSIDER** `maintainState: false` when stale data is worse than no data — payment confirmation, security state, anything where correctness trumps continuity.
- **CONSIDER** providing a branded `loadingBuilder` rather than the default `CircularProgressIndicator` — typically a `Skeleton`, a `Shimmer`, or a layout-preserving placeholder so the screen does not jump when the data arrives.
- **DON'T** unwrap `Async<T>` manually with `if (state.user.hasValue) ... else if (...) ...` in `build()`. *That is exactly the boilerplate `AsyncBuilder` exists to remove. The single exception is when the conditional drives layout outside the data area — even then, prefer composition over manual unwrapping.*
- **DON'T** call `state.valueOrNull!` outside the `builder` callback. *The whole point of the sealed union is that the value is only safely accessible in `AsyncData`.*
- **DON'T** model loading or error UI with nullable fields in state (`String? errorMessage`, `bool isLoading`). *That re-introduces every bug `Async<T>` was built to prevent.* See `chassis-create-view-model`.

## Workflow

- [ ] **Step 1 — Confirm the data is in `Async<T>`.** If the ViewModel exposes raw `T?` or `bool isLoading + T? data + Object? error`, refactor it to `Async<T>` first. See `chassis-create-view-model`.
- [ ] **Step 2 — Pick the right host.** A screen-level fetch usually has a single top-level `AsyncBuilder` wrapping the whole content; a derived secondary widget (a sidebar count, a preview pane) has its own local `AsyncBuilder`.
- [ ] **Step 3 — Write the `builder`** assuming `data` is present. Render the success layout. Handle empty-list / no-results cases inside the body.
- [ ] **Step 4 — Provide `loadingBuilder`** unless the default spinner is intentional. Match the layout of the data builder when possible (skeleton, shimmer) to avoid a layout jump on first paint.
- [ ] **Step 5 — Provide `errorBuilder`** for user-facing screens. Translate the exception and surface a stable error code. Add a retry affordance if the operation is retriable.
- [ ] **Step 6 — Decide on `maintainState`.** Keep the default unless stale data is incorrect for this screen.

## Examples

### Standard screen with all three builders

```dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<UserProfileViewModel>();

    return Scaffold(
      appBar: AppBar(title: const Text('User Profile')),
      body: AsyncBuilder<User>(
        state: viewModel.state.user,
        builder: (context, user) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundImage: NetworkImage(user.avatarUrl),
              ),
              const SizedBox(height: 16),
              Text(user.name, style: Theme.of(context).textTheme.headlineMedium),
              Text(user.email),
            ],
          ),
        ),
        loadingBuilder: (context) => const _ProfileSkeleton(),
        errorBuilder: (context, error) => _ProfileErrorView(
          error: error,
          onRetry: () => viewModel.reload(),
        ),
      ),
    );
  }
}
```

### Empty-state inside the builder

The `builder` only runs once data is available, so empty-state branching belongs inside its body — not as a separate state.

```dart
AsyncBuilder<List<Todo>>(
  state: viewModel.state.todos,
  builder: (context, todos) {
    if (todos.isEmpty) {
      return const Center(child: Text('No todos yet. Add one above.'));
    }
    return ListView.builder(
      itemCount: todos.length,
      itemBuilder: (_, i) => TodoTile(todo: todos[i]),
    );
  },
  loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
  errorBuilder: (_, error) => Center(child: Text('Failed to load todos: $error')),
);
```

### Anti-flicker on pull-to-refresh

`maintainState: true` (the default) keeps the previous list visible during a refetch.

```dart
AsyncBuilder<List<Order>>(
  state: viewModel.state.orders,
  // maintainState: true, // default — keeps previous data visible during refresh
  builder: (context, orders) => RefreshIndicator(
    onRefresh: viewModel.refresh,
    child: ListView.builder(
      itemCount: orders.length,
      itemBuilder: (_, i) => OrderTile(order: orders[i]),
    ),
  ),
);
```

While the refresh is in flight the state is `AsyncLoading(previous: orders)` — the builder continues with `previous` and the list does not flash empty.

### Disabling `maintainState` when stale data is misleading

```dart
AsyncBuilder<PaymentStatus>(
  state: viewModel.state.paymentStatus,
  maintainState: false, // never show stale payment status
  builder: (context, status) => PaymentStatusBadge(status: status),
  loadingBuilder: (_) => const PaymentStatusBadge.loading(),
  errorBuilder: (_, error) => const PaymentStatusBadge.unknown(),
);
```

### Errors with translated message and stable code

The `errorBuilder` receives the raw `Object`. Translate it inside, and surface the stable code so the user can quote it to support. See `chassis-handle-errors`.

```dart
AsyncBuilder<User>(
  state: viewModel.state.user,
  builder: (context, user) => UserCard(user: user),
  errorBuilder: (context, error) {
    final code = error is HasErrorCode ? error.code : 'unknown';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.translateError(error)),
          const SizedBox(height: 4),
          Text(
            'Error code: $code',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (kDebugMode) Text('Dev: $error'),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => context.read<UserProfileViewModel>().reload(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  },
);
```

### Anti-pattern: manual unwrapping

```dart
// ❌ Don't do this. AsyncBuilder exists exactly to replace this chain.
@override
Widget build(BuildContext context) {
  final user = context.watch<UserProfileViewModel>().state.user;
  if (user.isLoading) return const CircularProgressIndicator();
  if (user.hasError) return Text('Error: ${user.errorOrNull}');
  return UserCard(user: user.valueOrNull!);
}
```

```dart
// ✅ Use AsyncBuilder
@override
Widget build(BuildContext context) {
  final viewModel = context.watch<UserProfileViewModel>();
  return AsyncBuilder<User>(
    state: viewModel.state.user,
    builder: (_, user) => UserCard(user: user),
    errorBuilder: (_, error) => Text('Error: $error'),
  );
}
```
