---
name: chassis-bootstrap-app
description: Wire the composition root of a Chassis application — declare `lib/mediator.dart` with `@ChassisApp(mediatorName: 'AppMediator')` on the library directive plus the imports that make every handler reachable, run `dart run build_runner build` to generate the registration-only `AppMediator` constructor, then have `main()` construct the repositories and call `Chassis.initialize(AppMediator(...))` — wiring `LoggingMiddleware` and `CrashReportingMiddleware` — before `runApp`. Use when initializing a new Chassis project, adding a module to the app, or onboarding a new repository that the generated `AppMediator` constructor must accept.
---
# Bootstrapping a Chassis Application

## Contents
- [Core Concepts](#core-concepts)
- [The Dependency Tree](#the-dependency-tree)
- [The Composition Root: `lib/mediator.dart`](#the-composition-root-libmediatordart)
- [Installing the Mediator: `Chassis.initialize`](#installing-the-mediator-chassisinitialize)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

A Chassis application is wired bottom-up at startup: repositories construct first (no dependencies), the generated `AppMediator` is constructed from those repositories, and `Chassis.initialize` installs it as the application mediator — once, in `main()`, before `runApp`. ViewModels never hold a mediator reference: they dispatch message objects through `run`/`read`/`watch`, and the installed mediator is resolved lazily at their first dispatch. The widget tree consumes ViewModels through `ViewModelProvider`s whose `create:` callbacks take no wiring — there is nothing to thread through constructors.

The composition root splits into two files with distinct jobs:

- **`lib/mediator.dart`** carries the `@ChassisApp(mediatorName: 'AppMediator')` annotation on its library directive and the imports that make every handler reachable from the generator's import-graph walk. The generator emits the mediator in the adjacent `mediator.chassis.dart`.
- **`lib/main.dart`** constructs the repository implementations, passes them to the generated `AppMediator` constructor, installs the result with `Chassis.initialize`, and calls `runApp`. There is no app-level global mediator variable.

The generated `AppMediator` is a **registration-only constructor**: its single member is a constructor that takes every deduplicated handler dependency as a required named parameter and registers all handlers. It exposes no per-message methods — dispatch always goes through the `run`/`read`/`watch` it inherits from `Mediator`. Adding a handler that depends on a new repository makes the constructor require that repository, a compile error until the composition root provides it — the constructor is the application's dependency manifest. And a concrete Command or Query reachable from the `@ChassisApp` graph with no handler **fails the build**, so "does a handler exist?" is proven before the app ever runs. See `chassis-register-handler-with-codegen` for the handler-side workflow.

No `build.yaml` is needed: `chassis_builder` applies automatically to any package that lists it as a dev dependency (`auto_apply: dependents`).

## The Dependency Tree

```
┌─────────────────────────────────────┐
│ Widget (StatelessWidget / Stateful) │  reads context.select((TViewModel vm) => ...)
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│ ViewModel<State, Event>             │  dispatches message objects via run/read/watch
└──────────────┬──────────────────────┘
               │  (resolved lazily through Chassis.initialize)
┌──────────────▼──────────────────────┐
│ AppMediator (generated)             │  registration-only constructor; middlewares
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│ Repository implementations          │  depend on infrastructure (Firebase, REST)
└─────────────────────────────────────┘
```

Each layer depends only on the layer below, through an interface — and the ViewModel→Mediator edge is not even a code dependency: ViewModels import only message types, and `Chassis.initialize` decides at startup where those messages go. `main()` is the one place this graph actually gets built.

## The Composition Root: `lib/mediator.dart`

The composition root is a dedicated library whose library directive is annotated with `@ChassisApp(...)`. The file has exactly two jobs: carry the annotation, and hold the imports that make every handler reachable. The generator emits the concrete mediator in `mediator.chassis.dart`, next to the annotated file:

```dart
// lib/mediator.dart — the composition root
@ChassisApp(mediatorName: 'AppMediator')
library;

import 'package:chassis/chassis.dart';

// These imports make the handlers reachable from the generator's walk.
import 'package:my_app/features/todos/application/application.dart';

export 'mediator.chassis.dart';
```

Three properties of the generated class matter at the composition root:

1. **The constructor requires every handler dependency** as a required named parameter (deduplicated across handlers). The parameter name is the dependency's type name, decapitalized — `TodoRepository` becomes `todoRepository:`. The constructor body instantiates and registers each handler; there are no other members.
2. **Dispatch goes through the inherited `run` / `read` / `watch`**, so middlewares always apply. `..addMiddleware(LoggingMiddleware())` observes every dispatch of the app.
3. **Handler discovery follows the import graph, within the app's own package.** Only `@chassisHandler` classes reachable from the annotated library are registered; the walk never crosses a package boundary, so handlers in shared packages enter through `@ChassisApp(modules: [AuthModule])` — see `chassis-organize-feature` for the module story. A reachable concrete Command/Query with no handler fails the build (opt out per message with `@unhandledMessage`) — see `chassis-register-handler-with-codegen`.

## Installing the Mediator: `Chassis.initialize`

> `main()` is the only place that sees infrastructure: it constructs the repository implementations, passes them to the generated `AppMediator` constructor — the application's dependency manifest, where a missing dependency is a compile error — and installs the result with `Chassis.initialize`. Every ViewModel resolves that mediator lazily at its first dispatch; if initialization was forgotten, the first dispatch throws an actionable `StateError` naming the fix.
> — `docs/coding_rules.md`

```dart
void main() {
  Chassis.initialize(
    AppMediator(todoRepository: InMemoryTodoRepository())
      ..addMiddleware(LoggingMiddleware()),
  );
  runApp(const TodoApp());
}
```

The pre-1.0 pattern — `late final AppMediator mediator;` initialized at startup and referenced from route builders and ViewModel constructors — is dead. `Chassis.initialize` is the single installation point, and ViewModels resolve it themselves, so a global's only remaining effect is to invite bypasses: presentation code importing `main.dart` (a backward import — presentation never depends on the composition root) and raw `await mediator.run(...)` calls that skip the ViewModel pipeline (`RunPolicy`, `Async` lifecycle, error reporting).

The only other legitimate path from a mediator to a ViewModel is the constructor seam, in tests: every ViewModel declares `{super.mediator}`, production leaves it null, and a test passes a fake (`TodoViewModel(mediator: fakeMediator)`), which always wins over the global. Tests never call `Chassis.initialize` — the global is process-wide state that leaks across test cases.

## Rules

- **DO** declare the composition root in a dedicated `lib/mediator.dart`: `@ChassisApp(mediatorName: 'AppMediator')` on the library directive, the imports that make every handler reachable (a feature barrel keeps this to one line per feature), `modules: [...]` for shared packages, and `export 'mediator.chassis.dart';` so `main.dart` imports one file. *Handler discovery walks the import graph from the annotated library, within the app's own package.*
- **DO** generate the mediator with `dart run build_runner build --delete-conflicting-outputs` after wiring changes. *The generated constructor is only as fresh as the last build.*
- **DO** construct repository implementations in `main()` and install the mediator with `Chassis.initialize(AppMediator(...))` before `runApp`. *The constructor requires every dependency of every reachable handler; the parameter name is the dependency's type name, decapitalized. ViewModels resolve the installed mediator lazily at their first dispatch.*
- **DO** wire observability at the composition root with `..addMiddleware(LoggingMiddleware())` and `..addMiddleware(CrashReportingMiddleware(...))`. *The middleware chain is chassis's observability channel — there is deliberately no `BlocObserver`/`ProviderObserver` equivalent. Every dispatch crosses it; `CrashReportingMiddleware` reports each failure (fatal when it is a Dart `Error`, non-fatal otherwise) then rethrows.* See `chassis-handle-errors`.
- **DO** declare `{super.mediator}` on every ViewModel constructor. *It stays null in production; tests pass a fake through it, which always wins over the global — no global setup, no teardown.*
- **DO** use `ViewModelProvider<TViewModel>(create: (_) => TViewModel(), child: ...)` (or `ViewModelProvider.withEventListener` for event-driven screens) at each route or screen boundary. *The provider owns the ViewModel's lifecycle, and `create` takes no wiring — ViewModels resolve the mediator themselves.*
- **DO** depend on repository **interfaces** (`TodoRepository`, `UserRepository`) in handlers so the generated constructor parameters are interface-typed. *Interfaces let tests substitute mocks and let production swap implementations without touching the composition root structure.*
- **CONSIDER** `WidgetsFlutterBinding.ensureInitialized()` and an async `main()` when infrastructure needs platform channels or awaited setup (opening a database, initializing Firebase) before the mediator constructs.
- **DON'T** write a `build.yaml`. *`chassis_builder` applies automatically to any package that depends on it as a dev dependency; a stale `build.yaml` referencing pre-1.0 builders breaks the build.*
- **DON'T** store the mediator in a global variable. *`Chassis.initialize` already provides the single installation point; a global invites backward imports of `main.dart` and raw dispatch that bypasses the ViewModel pipeline.*
- **DON'T** instantiate handlers manually and call `mediator.registerCommandHandler(...)` alongside the generated `AppMediator`. *The generated constructor already registers every reachable handler; a duplicate registration throws `DuplicateHandlerError` at startup — always, not only in debug builds.*
- **DON'T** call `Chassis.initialize` in tests. *Pass the fake through the ViewModel constructor instead; it always wins over the global. (`Chassis.reset` exists for restoring a clean state, but a suite that needs it usually should have used the constructor seam.)*
- **DON'T** construct the `AppMediator` inside a widget's `build()` or in a `ViewModelProvider.create:` callback. *The mediator is application-scoped, not screen-scoped — building it per route would re-register handlers, re-instantiate repositories that hold caches or stream controllers, and silently break shared state.*

## Workflow

- [ ] **Step 1 — Add dependencies** to `pubspec.yaml`: `chassis: ^1.0.0` and `chassis_flutter: ^1.0.0` (which re-exports `provider`), plus `chassis_builder: ^1.0.0` and `build_runner: ^2.15.0` in `dev_dependencies`. No `build.yaml`.
- [ ] **Step 2 — Define repository interfaces** in `lib/<feature>/domain/<resource>_repository.dart`. Handlers depend on these interface types, so the generated constructor will require them.
- [ ] **Step 3 — Implement the repositories** under `lib/<feature>/infrastructure/<provider>_<resource>_repository.dart`. This is where infrastructure exception mapping lives — see `chassis-handle-errors`.
- [ ] **Step 4 — Author handlers and ViewModels** following `chassis-create-command`, `chassis-create-read-query`, `chassis-create-watch-query`, and `chassis-create-view-model`. Annotate handlers with `@chassisHandler`; give ViewModels `{super.mediator}`.
- [ ] **Step 5 — Declare the composition root.** `lib/mediator.dart` with `@ChassisApp(mediatorName: 'AppMediator')` (plus `modules: [...]` if the app composes shared packages) on the library directive, importing the application layer, exporting `mediator.chassis.dart`.
- [ ] **Step 6 — Generate `AppMediator`** by running `dart run build_runner build --delete-conflicting-outputs`. The output is `mediator.chassis.dart`, next to the annotated file. A reachable message without a handler fails this build — the error lists every orphan and its fixes.
- [ ] **Step 7 — Write `main()`.** Construct each repository, pass them to `AppMediator(...)` as named arguments, cascade `..addMiddleware(LoggingMiddleware())` (plus `CrashReportingMiddleware` — see `chassis-handle-errors`), and hand the result to `Chassis.initialize(...)` before `runApp`.
- [ ] **Step 8 — Compose the root widget tree.** `runApp(MaterialApp(home: ViewModelProvider<TViewModel>(create: (_) => TViewModel(), child: ...)))`. Use `ViewModelProvider.withEventListener` when the screen handles events. See `chassis-consume-view-model` and `chassis-handle-view-model-events`.

## Examples

### `pubspec.yaml`

```yaml
environment:
  sdk: ^3.13.0

dependencies:
  flutter:
    sdk: flutter
  chassis: ^1.0.0
  chassis_flutter: ^1.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  chassis_builder: ^1.0.0
  build_runner: ^2.15.0
```

### Minimal composition root and `main.dart` for a single-screen app

```dart
// lib/mediator.dart
@ChassisApp(mediatorName: 'AppMediator')
library;

import 'package:chassis/chassis.dart';

import 'package:my_app/features/todos/application/application.dart';

export 'mediator.chassis.dart';
```

```dart
// lib/main.dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

import 'package:my_app/mediator.dart';
import 'package:my_app/features/todos/infrastructure/in_memory_todo_repository.dart';
import 'package:my_app/features/todos/presentation/todo_event.dart';
import 'package:my_app/features/todos/presentation/todo_screen.dart';
import 'package:my_app/features/todos/presentation/todo_view_model.dart';

void main() {
  Chassis.initialize(
    AppMediator(todoRepository: InMemoryTodoRepository())
      ..addMiddleware(LoggingMiddleware()),
  );
  runApp(const TodoApp());
}

class const TodoApp({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Todos',
      home: ViewModelProvider.withEventListener<TodoViewModel, TodoEvent>(
        create: (_) => TodoViewModel(),
        onEvent: (context, _, event) {
          if (event case TodoAddedEvent()) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Todo added')),
            );
          }
        },
        child: const TodoScreen(),
      ),
    );
  }
}
```

Note the direction of the imports: presentation files never import `main.dart` or `mediator.dart` — `TodoViewModel` imports only its message types, and `Chassis.initialize` decided where those messages go.

### Larger app with a module, several repositories, and crash reporting

```dart
// lib/mediator.dart
@ChassisApp(modules: [AuthModule], mediatorName: 'AppMediator')
library;

import 'package:auth/auth.dart'; // shared package declaring @chassisModule AuthModule
import 'package:chassis/chassis.dart';

import 'package:my_app/features/features.dart';

export 'mediator.chassis.dart';
```

```dart
// lib/main.dart
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import 'package:my_app/mediator.dart';
import 'package:my_app/features/auth/infrastructure/firebase_auth_repository.dart';
import 'package:my_app/features/orders/infrastructure/firestore_order_repository.dart';
import 'package:my_app/features/users/infrastructure/firestore_user_repository.dart';
import 'package:my_app/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  Chassis.initialize(
    AppMediator(
      authRepository: FirebaseAuthRepository(),
      orderRepository: FirestoreOrderRepository(),
      userRepository: FirestoreUserRepository(),
    )
      ..addMiddleware(LoggingMiddleware())
      ..addMiddleware(CrashReportingMiddleware(
        (error, stack, {required fatal}) => FirebaseCrashlytics.instance
            .recordError(error, stack, fatal: fatal),
      )),
  );

  runApp(const MyApp());
}

class const MyApp({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Shop',
      routerConfig: appRouter,
    );
  }
}
```

The composition root constructs the graph once; nothing downstream ever sees the mediator construction code — routes and widgets provide ViewModels whose dispatches resolve the installed mediator on their own.

### Per-route ViewModel provision

```dart
GoRoute(
  path: '/profile/:userId',
  builder: (context, state) {
    final userId = state.pathParameters['userId']!;
    return ViewModelProvider.withEventListener<UserProfileViewModel, UserProfileEvent>(
      create: (_) => UserProfileViewModel(userId: userId),
      onEvent: (context, _, event) { /* ... */ },
      child: const UserProfileScreen(),
    );
  },
);
```

The route owns the ViewModel's lifecycle: when the user navigates away the provider disposes, which disposes the VM, which cancels its `watch(...)` subscriptions automatically. No mediator is threaded anywhere — `UserProfileViewModel` declares `{super.mediator}` but production leaves it null.

### Anti-pattern: a global mediator variable

```dart
// ❌ Pre-1.0 pattern. The global invites presentation code to import the
// composition root (a backward import) and to dispatch raw mediator calls
// that bypass the ViewModel pipeline (RunPolicy, Async lifecycle, error
// reporting).
late final AppMediator mediator;

void initializeDependencies() {
  mediator = AppMediator(todoRepository: InMemoryTodoRepository());
}

void main() {
  initializeDependencies();
  runApp(const MyApp());
}
```

```dart
// ✅ Install once with Chassis.initialize. ViewModels resolve it lazily at
// their first dispatch; tests bypass it through the constructor seam.
void main() {
  Chassis.initialize(
    AppMediator(todoRepository: InMemoryTodoRepository())
      ..addMiddleware(LoggingMiddleware()),
  );
  runApp(const MyApp());
}
```

### Anti-pattern: manual handler registration

```dart
// ❌ Manual wiring loses the build-time guarantees: the dependency manifest
// drifts silently, and nothing proves every reachable message has a handler.
class ManualMediator extends Mediator {
  ManualMediator(TodoRepository repo) {
    registerQueryHandler(WatchTodosHandler(repository: repo));
    registerCommandHandler(AddTodoHandler(repository: repo));
    registerCommandHandler(ToggleTodoHandler(repository: repo));
  }
}
```

```dart
// ✅ Use the generated AppMediator. Adding a handler with @chassisHandler
// updates the constructor automatically; missing dependencies become compile
// errors at the composition root, and unhandled messages fail the build.
Chassis.initialize(
  AppMediator(todoRepository: todoRepository)
    ..addMiddleware(LoggingMiddleware()),
);
```
