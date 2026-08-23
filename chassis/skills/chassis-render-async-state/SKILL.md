---
name: chassis-render-async-state
description: Render an `Async<T>` value in the widget tree — by default with an inline `switch` expression (the sealed `AsyncData` / `AsyncLoading` / `AsyncError` union gives compiler-checked exhaustiveness), reaching for Chassis's `AsyncBuilder` when you need `maintainState` anti-flicker behavior (keep showing the previous value during a refetch or soft error). Use when displaying any data wrapped in `Async<T>` (a watch query result, a one-time fetch result, a derived state field); the failure modes this prevents are manual `isLoading` flag chains and forgotten error branches.
---
# Rendering Async State

## Contents
- [Core Concepts](#core-concepts)
- [The Default: an Inline `switch` Expression](#the-default-an-inline-switch-expression)
- [`AsyncBuilder` for Anti-Flicker](#asyncbuilder-for-anti-flicker)
- [Builder Resolution Rules](#builder-resolution-rules)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

`Async<T>` is the sealed union that models the lifecycle of an asynchronous value: `AsyncData<T>(value)`, `AsyncLoading<T>({previous})`, or `AsyncError<T>(error, {stackTrace, previous})`. Both `AsyncLoading` and `AsyncError` can carry `previous` — typed `AsyncData<T>?`, not a bare `T?` — which enables the UI to keep displaying valid data while a refetch is in flight or while a transient error is active. Carrying the whole `AsyncData` makes "a value existed" provable even when `T` is nullable and the value itself is `null`: `Async<int?>.data(null).hasValue` is `true`, and the data branch renders it.

There are two rendering tools, and the doctrine picks between them:

- **An inline `switch` expression** — the default for simple rendering. The union is sealed, so the compiler enforces that every branch (including the error) is handled.
- **`AsyncBuilder<T>`** — reserved for **anti-flicker behavior** (`maintainState`: keep rendering the carried `previous` data during a refetch or soft error) or for reusable loading/error scaffolding.

## The Default: an Inline `switch` Expression

```dart
final asyncTodos = context.select((TodoViewModel vm) => vm.state.todos);
return switch (asyncTodos) {
  AsyncLoading() => const Center(child: CircularProgressIndicator()),
  AsyncError(:final error) => Center(child: Text(context.translateError(error))),
  AsyncData(value: final todos) when todos.isEmpty =>
    const Center(child: Text('No todos yet. Add one above.')),
  AsyncData(value: final todos) => TodoList(todos: todos),
};
```

Why this is the default:

- **Exhaustiveness is compiler-checked.** `Async<T>` is sealed: delete the `AsyncError` case and the file stops compiling. A forgotten error branch cannot ship.
- **Destructuring in place.** `:final error` and `value: final todos` bind exactly what the branch needs — no `valueOrNull`, no force-unwrap.
- **Guarded cases handle empty states** (`when todos.isEmpty`) without a fourth state class.
- **Less indirection** than three builder callbacks for what is one expression.

Note that a bare `AsyncLoading()` pattern also matches a loading state that *carries* previous data — the switch deliberately ignores `previous` and shows the spinner. That is correct when the screen has no refetch, and exactly what you don't want during pull-to-refresh: that is `AsyncBuilder`'s job. (`context.translateError` is a project-level helper, not framework API — see `chassis-handle-errors`.)

## `AsyncBuilder` for Anti-Flicker

`AsyncBuilder<T>` turns an `Async<T>` into a `Widget` with `previous`-carrying resolution built in. It takes:

- `state: Async<T>` — the current value.
- `builder: (BuildContext, T) → Widget` — required. Renders when data is available.
- `loadingBuilder: (BuildContext) → Widget` — optional. Default: `Center(child: CircularProgressIndicator())`.
- `errorBuilder: (BuildContext, Object) → Widget` — optional. Default: a red `ErrorWidget` naming the missing `errorBuilder` in debug builds, `SizedBox.shrink()` in release builds.
- `maintainState: bool` — default `true`. Controls whether the previous value should be shown during loading / error refresh.

> AsyncBuilder is a StatelessWidget that renders different UI based on Async<T> state, eliminating manual state checking in build methods.
> — `docs/04_ui_integration.md`

The `builder` callback receives the unwrapped `T` — no defensive `Async` checks are needed inside it (for a nullable `T`, a legitimate `null` value does reach `builder`).

The default `maintainState: true` keeps stale data visible while new data is loading: the user does not see a flash of spinner during pull-to-refresh or pagination — they see their data, and it updates when the new value arrives. The visual flow:

- **Initial load** (`AsyncLoading()`, no previous): `loadingBuilder` runs → spinner.
- **First success** (`AsyncData(user)`): `builder` runs → user profile.
- **Refetch** (`AsyncLoading(previous: AsyncData(user))`): `builder` continues with the previous user. No flicker. The ViewModel produces this shape by passing `current:` to `run` / `read` / `watch` — see `chassis-create-view-model`.
- **Refetch completes** (`AsyncData(newUser)`): `builder` updates smoothly.
- **Refetch error** (`AsyncError(e, previous: AsyncData(user))`): `builder` continues with the previous user. The error is silent in the UI — handle it through events if the user should be notified. See `chassis-handle-view-model-events` and `chassis-handle-errors`.

Set `maintainState: false` only when you explicitly want the loading or error UI to replace stale data — though at that point a plain `switch` usually expresses the same thing more directly.

## Builder Resolution Rules

The widget pattern-matches on the sealed union in this exact order:

1. **`AsyncData<T>(:value)`** → `builder(context, value)`.
2. **`AsyncLoading<T>(previous: AsyncData(:value))` when `maintainState`** → `builder(context, value)`. Anti-flicker: the carried data keeps rendering during a refetch.
3. **`AsyncError<T>(previous: AsyncData(:value))` when `maintainState`** → `builder(context, value)`. The soft-error case: a mid-stream failure keeps the last snapshot visible.
4. **`AsyncLoading<T>()`** → `loadingBuilder` (or the default centered `CircularProgressIndicator`).
5. **`AsyncError<T>(:error)`** → `errorBuilder(context, error)` (or the default: `ErrorWidget` in debug, `SizedBox.shrink()` in release).

Because the match is on `AsyncData` — not on a null check — the data branch also runs for `AsyncData<T?>(null)`: a nullable `T` with a legitimate `null` value reaches `builder`, which must handle it.

## Rules

- **DO** wrap any asynchronous datum in state with `Async<T>`. *The sealed union forces exhaustive handling of loading and error at the render site.*
- **DO** render simple cases with an inline `switch` expression on the `Async<T>`. *Sealed means the compiler refuses a missing branch — the error case cannot be forgotten — with destructuring in place and no indirection through builder callbacks.*
- **DO** reach for `AsyncBuilder` when the UI must keep showing the previous value during a refetch or soft error, or when loading/error scaffolding is reused across screens. *Its `maintainState` resolution implements the `previous`-carrying anti-flicker behavior that a plain `switch` deliberately ignores.*
- **DO** provide a custom `errorBuilder` for any user-facing screen. *The default is loud in debug (a red `ErrorWidget`, so a missing branch cannot ship unnoticed) but renders nothing (`SizedBox.shrink()`) in release — acceptable for non-critical secondary widgets, never for the primary content of a screen.*
- **DO** translate domain exceptions in the error branch and display the translated message alongside a stable error code. See `chassis-handle-errors`.
- **DO** handle empty data (empty list, no results) inside the data branch — a guarded `switch` case (`AsyncData(value: final l) when l.isEmpty`) or a conditional in the `builder` body. *Emptiness is data, not a fourth lifecycle state.*
- **PREFER** the default `maintainState: true` for lists, profiles, dashboards, and any screen where seeing the previous value during refresh is helpful — and make the ViewModel pass `current:` so loading/error emissions actually carry the previous data.
- **CONSIDER** a plain `switch` (or `maintainState: false`) when stale data is worse than no data — payment confirmation, security state, anything where correctness trumps continuity.
- **CONSIDER** providing a branded `loadingBuilder` rather than the default `CircularProgressIndicator` — typically a `Skeleton`, a `Shimmer`, or a layout-preserving placeholder so the screen does not jump when the data arrives.
- **DON'T** branch on flags (`isLoading`, `hasError`, `hasValue` chains) in `build()`. *Flag chains silently miss a case; the `switch` on the sealed union is checked by the compiler.*
- **DON'T** force-unwrap with `state.valueOrNull!` — and never treat `valueOrNull == null` as "no data" when `T` is nullable. *Use pattern matching, or `requireValue` where the value is guaranteed to exist (it throws a descriptive `StateError` otherwise); `hasValue` is the null-safe presence check.*
- **DON'T** collapse an error into a default with `valueOrNull ?? fallback`. *The same characters also spell "I forgot the error case" — the reader cannot tell a decision from an accident, and on primary content the screen renders failures as data. When degrading on error IS the design (optional content, error surfaced through another channel), say so through the explicit channel: an error branch (or `errorBuilder`) that returns the default (`// deliberate`). A business-case fallback ("document absent → empty value") belongs at the data layer, decided once in the repository — by the time a value is an `AsyncError`, it is not data anymore.*
- **DON'T** model loading or error UI with nullable fields in state (`String? errorMessage`, `bool isLoading`). *That re-introduces every bug `Async<T>` was built to prevent.* See `chassis-create-view-model`.

## Workflow

- [ ] **Step 1 — Confirm the data is in `Async<T>`.** If the ViewModel exposes raw `T?` or `bool isLoading + T? data + Object? error`, refactor it to `Async<T>` first. See `chassis-create-view-model`.
- [ ] **Step 2 — Pick the tool.** Default: an inline `switch` expression on the value read with `context.select`. Use `AsyncBuilder` when the screen refetches and the previous value must stay visible (anti-flicker) — and make the ViewModel pass `current:` to `run` / `read` / `watch` so the loading/error emissions carry it.
- [ ] **Step 3 — Write the data branch.** Render the success layout. Handle empty-list / no-results with a guarded case (`when list.isEmpty`) or inside the `builder` body.
- [ ] **Step 4 — Cover the error branch.** Translate the exception, surface a stable error code, add a retry affordance if the operation is retriable. Never collapse it into a fallback silently.
- [ ] **Step 5 — Write the loading branch** (or `loadingBuilder`). Match the layout of the data branch when possible (skeleton, shimmer) to avoid a layout jump on first paint.
- [ ] **Step 6 — For `AsyncBuilder`, decide on `maintainState`.** Keep the default unless stale data is incorrect for this screen.

## Examples

### Simple screen: the inline `switch` default

```dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

class const UserProfileScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // select — rebuilds only when state.user changes
    final asyncUser = context.select(
      (UserProfileViewModel vm) => vm.state.user,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('User Profile')),
      body: switch (asyncUser) {
        AsyncLoading() => const _ProfileSkeleton(),
        AsyncError(:final error) => _ProfileErrorView(
            error: error,
            // read inside a callback — no subscription
            onRetry: () => context.read<UserProfileViewModel>().reload(),
          ),
        AsyncData(value: final user) => UserProfileBody(user: user),
      },
    );
  }
}
```

Every branch is compiler-enforced: remove the `AsyncError` case and this stops compiling.

### Empty state as a guarded case

```dart
final asyncTodos = context.select((TodoViewModel vm) => vm.state.todos);
return switch (asyncTodos) {
  AsyncLoading() => const Center(child: CircularProgressIndicator()),
  AsyncError(:final error) => Center(child: Text('Failed to load todos: $error')),
  AsyncData(value: final todos) when todos.isEmpty =>
    const Center(child: Text('No todos yet. Add one above.')),
  AsyncData(value: final todos) => ListView.builder(
      itemCount: todos.length,
      itemBuilder: (_, i) => TodoTile(todo: todos[i]),
    ),
};
```

Emptiness is data — a guarded case, not a fourth lifecycle state.

### Anti-flicker on pull-to-refresh: `AsyncBuilder`

`maintainState: true` (the default) keeps the previous list visible during a refetch — the case `AsyncBuilder` is reserved for.

```dart
AsyncBuilder<List<Order>>(
  state: context.select((OrdersViewModel vm) => vm.state.orders),
  // maintainState: true, // default — keeps previous data visible during refresh
  builder: (context, orders) => RefreshIndicator(
    onRefresh: context.read<OrdersViewModel>().refresh,
    child: ListView.builder(
      itemCount: orders.length,
      itemBuilder: (_, i) => OrderTile(order: orders[i]),
    ),
  ),
  loadingBuilder: (_) => const _OrdersSkeleton(),
  errorBuilder: (_, error) => _OrdersErrorView(error: error),
);
```

While the refresh is in flight the state is `AsyncLoading(previous: AsyncData(orders))` — the builder continues with the carried data and the list does not flash empty. The ViewModel produces this shape by passing `current: state.orders` to `read`/`watch` (see `chassis-create-view-model`). A plain `switch` would drop to the spinner here — that is exactly the difference between the two tools.

### Stale data is misleading: back to the `switch`

```dart
// Never show a stale payment status: the plain switch renders exactly the
// current state, carrying nothing over.
final asyncStatus = context.select(
  (CheckoutViewModel vm) => vm.state.paymentStatus,
);
return switch (asyncStatus) {
  AsyncLoading() => const PaymentStatusBadge.loading(),
  // deliberate degradation: the failure is surfaced through an event
  AsyncError() => const PaymentStatusBadge.unknown(),
  AsyncData(value: final status) => PaymentStatusBadge(status: status),
};
```

(Inside an existing `AsyncBuilder`, `maintainState: false` achieves the same non-carrying behavior.)

### Errors with translated message and stable code

The error branch receives the raw `Object`. Translate it inside, and surface the stable code so the user can quote it to support. See `chassis-handle-errors`.

```dart
AsyncBuilder<User>(
  state: context.select((UserProfileViewModel vm) => vm.state.user),
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

### Anti-pattern: flag-check chains

```dart
// ❌ Don't do this. Nothing checks that all cases are covered, and the
// force-unwrap crashes the day the chain misses one.
@override
Widget build(BuildContext context) {
  final user = context.watch<UserProfileViewModel>().state.user;
  if (user.isLoading) return const CircularProgressIndicator();
  if (user.hasError) return Text('Error: ${user.errorOrNull}');
  return UserCard(user: user.valueOrNull!);
}
```

```dart
// ✅ An exhaustive switch on the sealed union
@override
Widget build(BuildContext context) {
  final asyncUser = context.select(
    (UserProfileViewModel vm) => vm.state.user,
  );
  return switch (asyncUser) {
    AsyncLoading() => const CircularProgressIndicator(),
    AsyncError(:final error) => Text('Error: $error'),
    AsyncData(value: final user) => UserCard(user: user),
  };
}
```
