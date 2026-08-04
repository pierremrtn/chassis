---
name: chassis-consume-view-model
description: Provide a Chassis ViewModel to a widget subtree with `ViewModelProvider`, and read its state from descendants using `context.select((TViewModel vm) => ...)`, `context.watch<TViewModel>()`, `context.read<TViewModel>()`, or `ViewModelProvider.of<TViewModel>(context)`. Use when wiring a screen's ViewModel into the widget tree, when re-providing an existing ViewModel to a new subtree, or when a widget deep in the tree needs to read state from an ancestor-provided ViewModel.
---
# Providing and Consuming a ViewModel

## Contents
- [Core Concepts](#core-concepts)
- [`ViewModelProvider` Variants](#viewmodelprovider-variants)
- [Reading from Descendants: `select`, `watch`, `read`](#reading-from-descendants-select-watch-read)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

`ViewModelProvider<T extends ViewModel<...>>` is a thin wrapper around the `provider` package's `InheritedProvider`. It:

- creates the ViewModel via a `create:` callback (lazily by default — only when first accessed),
- exposes it to descendants by `runtimeType T`,
- calls `viewModel.dispose()` automatically when the provider is removed from the tree,
- attaches a `ChangeNotifier` listener so that descendants subscribed via `context.watch<T>()` rebuild when state changes.

`ViewModelProvider.value(value: existingVm)` re-provides an *existing* instance to a new subtree without taking ownership of disposal. It is the right tool for shared ViewModels across navigation routes or for passing a ViewModel into a widget test.

`ViewModelProvider.withEventListener<T, E>` is the variant that also subscribes to the ViewModel's `events` stream — see `chassis-handle-view-model-events`. It is eager (non-lazy), and the ViewModel additionally buffers events sent before the first subscriber, so events emitted during construction are delivered rather than lost.

## `ViewModelProvider` Variants

| Variant | When to use |
|---|---|
| `ViewModelProvider<T>(create: ...)` | Default. Creates the VM lazily, owns disposal. |
| `ViewModelProvider<T>(create: ..., lazy: false)` | Force eager creation when work runs in the constructor. Use sparingly — eager `create` runs even if no descendant ever reads the VM. |
| `ViewModelProvider<T>.value(value: ...)` | Re-provide an existing VM. Does **not** dispose. Standard tool in widget tests and across navigation. |
| `ViewModelProvider.withEventListener<T, E>(create: ..., onEvent: ...)` | Provide a VM **and** subscribe to its events stream. Eager by construction. See `chassis-handle-view-model-events`. |

## Reading from Descendants: `select`, `watch`, `read`

The `provider` package surfaces these accessors on `BuildContext`:

- **`context.select((T vm) => vm.state.<field>)`** — subscribes the calling widget to **just the selected value**: the widget rebuilds only when that value changes (compared with `==`). This is the preferred way to read state inside `build` — a widget rendering one field is not rebuilt by unrelated state changes. `Async<T>` variants implement `==`, so selecting an `Async<T>` field behaves correctly.
- **`context.watch<T>()`** — subscribes the calling widget to the VM's `ChangeNotifier`. Rebuilds the widget on **every** state change. Reach for it only when a widget genuinely renders most of the state.
- **`context.read<T>()`** — fetches the VM **without** subscribing. Does not trigger rebuilds. Use inside callbacks (`onPressed`, `onChanged`) where you only need to call a method.
- **`ViewModelProvider.of<T>(context, {listen: false})`** — the explicit form. Equivalent to `context.read<T>()` when `listen: false`, and to `context.watch<T>()` when `listen: true`.

The choice matters: calling `context.watch<T>()` or `context.select` from inside a callback subscribes the callback's enclosing widget to rebuilds; calling `context.read<T>()` from inside `build` means rebuilds will not pick up state changes.

## Rules

- **DO** wrap a screen with `ViewModelProvider<TViewModel>(create: (_) => TViewModel(mediator), child: ...)` to give it a ViewModel. *The provider owns creation, exposure, and disposal.*
- **DO** use `ViewModelProvider.withEventListener<T, E>` instead when the screen also handles one-time events. *It combines provision and event listening, runs eagerly so construction-time events are not missed.* See `chassis-handle-view-model-events`.
- **DO** use `ViewModelProvider<T>.value(value: existing)` when re-providing a VM that already exists — across a navigation push, into a sub-route, or in a widget test.
- **DO** read state inside `build` with `context.select((TViewModel vm) => vm.state.<field>)`. *Subscribes the widget to just that field — unrelated state changes don't rebuild it.*
- **DO** read inside callbacks with `context.read<TViewModel>()`. *No subscription, no spurious rebuilds, no surprise.*
- **DO** keep `create:` callbacks free of side effects beyond constructing the VM. *Side effects in `create:` are tied to provider lifecycle, not screen lifecycle, and become hard to reason about.*
- **PREFER** `context.select` over `context.watch<T>()` for rendering. *`watch` rebuilds the widget on every state change; reserve it for widgets that genuinely render most of the state.*
- **PREFER** the `provider` extensions (`context.select` / `context.watch` / `context.read`) over `ViewModelProvider.of<T>(context, listen: ...)`. *Both work; the extensions are more idiomatic.*
- **CONSIDER** `lazy: false` only when the VM's constructor must run before the first descendant reads it (for example, to start a `watch(...)` subscription that must not miss the initial value). The default lazy creation is otherwise correct.
- **DON'T** instantiate a ViewModel directly in a parent widget and pass it down by parameter when more than one descendant needs to read it. *Use `ViewModelProvider`. Manual prop-drilling defeats the dependency injection the provider exists to handle.*
- **DON'T** call `context.read<T>()` from inside `build` and expect the widget to rebuild on state change. *Use `context.select` (or `context.watch<T>()`). `read` does not subscribe.*
- **DON'T** pass an existing VM through the `create:` callback of `ViewModelProvider`. *That handler will dispose it. Use `ViewModelProvider.value(...)` to re-provide without taking ownership.*
- **DON'T** keep a `BuildContext` reference across `await` boundaries before reading providers. *The widget may unmount; `context.mounted` is the safety check.*

## Workflow

- [ ] **Step 1 — Decide where the VM lives.** Screen-level VMs are provided at the screen widget; feature-level VMs (shared by multiple screens) are provided at a route-group ancestor.
- [ ] **Step 2 — Pick the provider variant.**
  - State only → `ViewModelProvider<TVM>(create: ..., child: ...)`.
  - State **and** events → `ViewModelProvider.withEventListener<TVM, TEvent>(create: ..., onEvent: ..., child: ...)`. See `chassis-handle-view-model-events`.
  - Re-providing an existing VM → `ViewModelProvider<TVM>.value(value: existingVm, child: ...)`.
- [ ] **Step 3 — Construct the VM in the `create:` callback** with the Mediator (and any other constructor params from the route — for example, an `id` from route arguments). Avoid side effects.
- [ ] **Step 4 — Read state in descendants** via `context.select((TVM vm) => vm.state.<field>)` inside `build`, paired with `AsyncBuilder` for `Async<T>` fields. See `chassis-render-async-state`.
- [ ] **Step 5 — Read inside callbacks** via `context.read<TVM>().<method>(...)` so the widget hosting the callback does not subscribe.
- [ ] **Step 6 — In tests**, inject a mock VM with `ViewModelProvider<TVM>.value(value: mockVm, child: widgetUnderTest)`. Stub `dispose()` on the mock if `withEventListener` is involved.

## Examples

### Provision + screen-level consumption

```dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

class UserProfileRoute extends StatelessWidget {
  const UserProfileRoute({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    return ViewModelProvider<UserProfileViewModel>(
      create: (_) => UserProfileViewModel(mediator, userId: userId),
      child: const UserProfileScreen(),
    );
  }
}

class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // select — this widget rebuilds only when state.user changes
    final asyncUser = context.select(
      (UserProfileViewModel vm) => vm.state.user,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            // read inside a callback — no subscription
            onPressed: () => context.read<UserProfileViewModel>().toggleEditMode(),
          ),
        ],
      ),
      body: AsyncBuilder<User>(
        state: asyncUser,
        builder: (_, user) => UserProfileBody(user: user),
        errorBuilder: (_, error) => Text('Failed: $error'),
      ),
    );
  }
}
```

### Re-providing an existing VM into a new route

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ViewModelProvider<CheckoutViewModel>.value(
      value: context.read<CheckoutViewModel>(),
      child: const PaymentDetailsScreen(),
    ),
  ),
);
```

`.value` does not take ownership of disposal — the original provider still owns the VM lifecycle.

### `lazy: false` to start work eagerly

```dart
ViewModelProvider<DashboardViewModel>(
  lazy: false, // run constructor side effects (initial watch) immediately
  create: (_) => DashboardViewModel(mediator),
  child: const DashboardScreen(),
);
```

Use this only when the VM's constructor starts a `watch(...)` whose initial loading state should be visible the moment the screen mounts. Otherwise the default lazy creation defers construction until the first provider access (`context.select` / `watch` / `read`), which is usually what you want.

### In a widget test

```dart
testWidgets('renders user name when loaded', (tester) async {
  final mockVm = MockUserProfileViewModel();
  when(() => mockVm.state).thenReturn(
    UserProfileState(
      user: Async.data(User(id: '1', name: 'Alice', email: 'a@x.test')),
      isEditing: false,
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: ViewModelProvider<UserProfileViewModel>.value(
        value: mockVm,
        child: const UserProfileScreen(),
      ),
    ),
  );

  expect(find.text('Alice'), findsOneWidget);
});
```

The `.value` constructor does not call `dispose()` on the mock at teardown — exactly what you want for a test.

### Anti-pattern: prop-drilling

```dart
// ❌ Don't do this — manual prop-drilling defeats the provider abstraction.
class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key, required this.viewModel});
  final UserProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: UserHeader(viewModel: viewModel), // every nested widget must take it
    );
  }
}
```

```dart
// ✅ Provide once at the route boundary, read where needed
ViewModelProvider<UserProfileViewModel>(
  create: (_) => UserProfileViewModel(mediator),
  child: const UserProfileScreen(),
);
```

### Anti-pattern: `context.read` inside `build`

```dart
// ❌ Doesn't rebuild on state change — read does not subscribe.
@override
Widget build(BuildContext context) {
  final viewModel = context.read<UserProfileViewModel>();
  return Text(viewModel.state.user.valueOrNull?.name ?? '...');
}
```

```dart
// ✅ Use select in build, read in callbacks
@override
Widget build(BuildContext context) {
  return AsyncBuilder<User>(
    state: context.select(
      (UserProfileViewModel vm) => vm.state.user,
    ),
    builder: (_, user) => Text(user.name),
  );
}
```
