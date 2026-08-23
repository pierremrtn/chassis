# What a Feature Costs

Chassis requires more files per feature than Bloc or Riverpod. This is not an accident to be explained away — it is the trade the framework makes, and you should see the price before you pay it. This page counts the artifacts honestly for one representative feature, compares the same feature on the other two stacks, and then explains what the extra artifacts buy: standardization, a build-time wiring guarantee, test seams, and centralized observability.

The framing question is the same one the [README](https://github.com/pierremrtn/chassis#how-is-this-different-from-bloc-or-riverpod) asks: **where does business logic live?** Each stack gives a different answer, and each answer has a different price tag.

## The yardstick: a "favorites" feature

A screen that shows the user's favorite items and keeps itself up to date, with a heart button on each row that toggles the favorite on or off. A failed toggle shows a snackbar. Two operations: *watch the favorites* and *toggle a favorite*.

All three stacks share the same data foundation, because all three recommend it — a repository is the common ground of [Flutter's official app architecture guidance](https://docs.flutter.dev/app-architecture), Bloc's tutorials, and Riverpod's examples alike:

- `favorite.dart` — the entity
- `favorites_repository.dart` — the repository interface
- `remote_favorites_repository.dart` — the implementation

Those three files cost the same everywhere. The comparison below is about everything on top of them.

## The same feature, three ways

### Bloc

Bloc is opinionated about *presentation*: events in, states out, over an observable stream. Its official answer to the framing question is that business logic lives **inside blocs** — the bloc *is* the business logic component. For favorites:

| Artifact | Contents | Rough size |
|---|---|---|
| `favorites_event.dart` | `FavoritesSubscriptionRequested`, `FavoriteToggled` | ~15 lines |
| `favorites_state.dart` | status enum + list + `copyWith` + `props` | ~40 lines |
| `favorites_bloc.dart` | `on<...>` registrations + the two handlers' logic | ~50 lines |
| `favorites_screen.dart` | `BlocProvider` + `BlocBuilder` + `BlocListener` | ~120 lines |

Four files (the event/state files are conventionally `part`s of the bloc's library), roughly **105 lines** of logic and state plus the screen. No code generation, no build step. Wiring is a `BlocProvider` in the widget tree; a `RepositoryProvider` above it supplies the repository.

The cost Bloc *doesn't* charge in files, it charges in **conflation**: `FavoritesBloc` holds both the use case ("toggle a favorite") and the UI state machine (the status enum, the list, the error field, the event-to-state choreography). That is by design and it works — but when a second screen needs to toggle favorites, the use case is embedded in a class that also owns another screen's state. In practice teams either duplicate the logic in a second bloc, extract it into the repository (moving business rules into the data layer), or have blocs listen to each other. The logic has a home; the home just has two jobs.

### Riverpod

Riverpod is a reactive **dependency graph**, deliberately unopinionated about layers: any provider can depend on any other, and where business logic lives is left to the team. That is a design choice, not a flaw — it is also why Riverpod has the lowest floor of the three:

| Artifact | Contents | Rough size |
|---|---|---|
| `favorites_providers.dart` | a `StreamProvider` for the list, a repository provider, toggle logic | ~25 lines |
| `favorites_screen.dart` | `ConsumerWidget` + `ref.watch`/`ref.read` | ~110 lines |

Two files, roughly **25 lines** of logic and state plus the screen. The minimal version is genuinely minimal: the list is a five-line `StreamProvider`, and the toggle can be a single `ref.read(favoritesRepositoryProvider).toggle(id)` in the button callback. With `riverpod_generator` there is a `build_runner` step too, but it is optional.

The flexibility is the point — and it is also the cost. Nothing in the tool distinguishes a use case from a piece of UI state from a data source; a toggle called directly from a widget callback, a toggle inside an `AsyncNotifier`, and a toggle routed through a service class are all equally idiomatic. Whatever layering the team wants, code review has to enforce, because the framework won't.

### Chassis

Chassis implements [Flutter's recommended app architecture](https://docs.flutter.dev/app-architecture) — MVVM, commands, repositories — and gives business logic a layer of its own. Each operation is a typed message with a handler; the ViewModel dispatches messages and holds UI state, nothing else. For favorites:

| Artifact | Contents | Rough size |
|---|---|---|
| `application/watch_favorites_query.dart` | `WatchFavoritesQuery` + its handler | ~20 lines |
| `application/toggle_favorite_command.dart` | `ToggleFavoriteCommand` + its handler | ~25 lines |
| `presentation/favorites_view_model.dart` | state + events + ViewModel | ~55 lines |
| `presentation/favorites_screen.dart` | `ViewModelProvider` + `context.select` + `switch` | ~120 lines |
| `lib/mediator.dart` | one new `import` making the handlers reachable | +1 line |
| — | `dart run build_runner build` | required |

Four new files plus a one-line touch to the composition root and a build step, roughly **100 lines** of logic and state plus the screen. Here is what the two operation files actually look like — a message and its handler, co-located:

```dart
// application/toggle_favorite_command.dart
final class ToggleFavoriteCommand extends Command<void> {
  ToggleFavoriteCommand({required this.itemId});

  final String itemId;

  @override
  Map<String, Object?> get params => {'itemId': itemId};
}

@chassisHandler
class ToggleFavoriteCommandHandler
    implements CommandHandler<ToggleFavoriteCommand, void> {
  ToggleFavoriteCommandHandler(this._repository);

  final FavoritesRepository _repository;

  @override
  Future<void> run(ToggleFavoriteCommand command) =>
      _repository.toggle(command.itemId);
}
```

And the ViewModel that dispatches them:

```dart
class FavoritesViewModel extends ViewModel<FavoritesState, FavoritesEvent> {
  FavoritesViewModel({super.mediator}) : super(FavoritesState.initial()) {
    watch(
      WatchFavoritesQuery(),
      onState: (favorites) => setState(state.copyWith(favorites: favorites)),
    );
  }

  void toggleFavorite(String itemId) => run(
        ToggleFavoriteCommand(itemId: itemId),
        onError: (error, stack) => sendEvent(ToggleFavoriteFailedEvent(error)),
      );
}
```

A fair objection at this point: `ToggleFavoriteCommandHandler.run` is one line. The handler earns its file when the operation grows — validation, a second repository, a business rule — but for a trivial delegation it *is* ceremony, and Chassis charges it anyway, because the framework's guarantees (below) only hold if every operation goes through the same pipeline.

## The count

| | Bloc | Riverpod | Chassis |
|---|---|---|---|
| Shared data layer (entity, repository interface, implementation) | 3 files | 3 files | 3 files |
| Logic + state artifacts | 3 files (bloc, events, states) | 1 file (providers) | 3 files (2 message+handler, 1 VM/state/events) |
| Screen | 1 file | 1 file | 1 file |
| Composition root touched | widget tree (`BlocProvider`) | widget tree (`ProviderScope`) | `mediator.dart` (+1 import) and generated file |
| Build step | none | optional (`riverpod_generator`) | **required** (`build_runner`) |
| Logic + state lines (approx.) | ~105 | ~25 | ~100 |
| **Total files** | **7** | **5** | **7** written, 1 edited, 1 generated |

Chassis is the most expensive column: nine artifacts in motion (seven written, one edited, one generated) against Bloc's seven and Riverpod's five, a mandatory code generation step, and line counts comparable to Bloc's. Riverpod's floor is far below both.

For a whole-app data point rather than estimates: the [`examples/todo`](https://github.com/pierremrtn/chassis/tree/main/examples/todo) app in this repository — three operations (watch, add, toggle), all four layers, composition root, and UI — is **390 lines total**, of which 26 are generated and 142 are the screen. The marginal cost of one Chassis operation in that codebase is about 20 lines of message + handler plus a 3–5 line ViewModel method.

Two mitigations, stated plainly rather than as excuses. First, the boilerplate is *mechanical*: every operation has the same shape, which is exactly what code generation tools and LLMs are good at — Chassis ships [AI skills](https://github.com/pierremrtn/chassis#built-for-the-ai-era) that produce these files, and a human reviewing them checks a known shape rather than reading novel structure. Second, the cost is front-loaded and flat: operation #40 costs the same 20 lines as operation #4, in the same places.

## The refactoring radius

File counts measure the day you write the feature. The radius of a change measures every day after.

### Adding an operation ("clear all favorites")

- **Bloc** — a new event class, a new `on<FavoritesCleared>` registration and handler inside `FavoritesBloc`, a dispatch in the UI. The bloc file grows; nothing outside it changes.
- **Riverpod** — a new method on a notifier, or a new provider. Smallest radius of the three.
- **Chassis** — one new file (`clear_favorites_command.dart` with message + handler), one ViewModel method, rerun `build_runner`. Existing logic files are never edited — the new operation is purely additive. If the new handler needs a dependency the app doesn't have yet, the generated `AppMediator` constructor gains a required named parameter and `main.dart` **stops compiling** until the dependency is provided: the wiring gap is a compile error, not a runtime discovery.

### Renaming an operation

All three stacks are compiler-checked here; the difference is how much the rename touches.

- **Bloc** — rename the event class; the `on<...>` registration and every `add(...)` site follow via IDE rename.
- **Riverpod** — rename the provider or method; with `riverpod_generator`, the generated symbol renames with it.
- **Chassis** — rename the message class and, by [naming convention](coding_rules.md#naming-conventions), its handler (`ToggleFavoriteCommand` → `MarkFavoriteCommand`, `ToggleFavoriteCommandHandler` → `MarkFavoriteCommandHandler`); dispatch sites follow via IDE rename; rerun `build_runner`. Two class renames instead of one — but nothing else, because everything the framework derives (registration, the build-time check) keys off the message type, never off names in configuration. A missed site anywhere is a compile or build error.

### Splitting a feature into its own package

- **Bloc** — move the files, re-point imports, move the `BlocProvider`. Straightforward; nothing verifies the result beyond imports resolving.
- **Riverpod** — providers are package-agnostic; move the files and re-point imports. Same: the compiler checks references, nothing checks layering.
- **Chassis** — move the feature's four layers into the package, add a `@chassisModule` class, declare it in `@ChassisApp(modules: [FavoritesModule])`. The generator's import-graph walk deliberately never crosses package boundaries on its own, so this declaration is mandatory — and if you forget it, the build fails listing every orphaned message and the fix, and warns about the handlers it found in an undeclared package. The move is more ceremonial than on the other stacks, and the wiring proof survives it. See [Code Generation](03_code_generation.md#modules-cross-package-handler-discovery).

## What the extra artifacts buy

If the accounting above were the whole story, Chassis would simply be the worst deal on the table. The artifacts are the mechanism for four properties the other stacks leave to discipline.

### Every feature has the same shape

A Chassis feature is always a message, a handler, a ViewModel method — in that order, in those folders. There is one correct way to add an operation, so any developer (or coding agent) opening any feature finds the same structure, diffs are small and predictable, and code review checks a known shape. Bloc standardizes the presentation side of this; Riverpod deliberately standardizes none of it. Chassis standardizes the path from gesture to repository — with one honest caveat: **the repository layer itself is covered by conventions, not by framework API**. Chassis tells you where repositories go and how handlers consume them ([Coding Rules](coding_rules.md#repository)); it does not generate or verify them.

### Missing handler = build error

Because operations are declared as message types, the "does every operation have an implementation?" question has a static answer, and the builder checks it: a concrete `Command` or `ReadQuery` or `WatchQuery` reachable from the app graph with no handler **fails the build**, at the message's declaration site, before the app ever runs. Bloc has no equivalent question to check (an event and its handler live in the same class), and Riverpod resolves the graph at runtime. This guarantee is what the mandatory `build_runner` step purchases. See [Code Generation](03_code_generation.md#missing-handlers-fail-the-build).

### The test seams are part of the shape

The artifacts are also the places where tests attach:

- **Handlers** are plain Dart classes taking repository interfaces — a handler test is a unit test with fakes, no Flutter, no framework.
- **ViewModels** take an optional `Mediator` in their constructor (`FavoritesViewModel(mediator: fakeMediator)`) — the fake wins over the global installed by `Chassis.initialize`, so no test touches global state. Messages have structural equality (same type + equal `params`), so stubs match dispatched messages without argument matchers.

On the other stacks these seams exist too — a bloc takes its repository, a provider can be overridden in `ProviderScope` — but the *cut line* differs: Chassis lets you test the use case with no UI state machine attached, and the UI state machine with no use case attached. See [Coding Rules — Testing](coding_rules.md#testing).

### One interception point for observability

Every operation of every feature crosses the mediator, so cross-cutting concerns are written once: `LoggingMiddleware` traces every dispatch with its `params`, outcome, and duration; `CrashReportingMiddleware` reports every failure — classified fatal (an `Error`, i.e. a bug) or non-fatal (an expected domain failure) — and rethrows. There is deliberately no `BlocObserver`/`ProviderObserver` equivalent: the middleware chain *is* the observability channel, and a caching, auditing, or retry policy added there covers the favorites feature and the forty features after it without touching any of them. See [Core Architecture — Middleware](01_core_architecture.md#middleware).

## When the cost is not worth it

The table doesn't lie in the other direction either. For a prototype, a small app, or a solo project with a handful of screens, Chassis's fixed costs — four layers, a build step, three files per feature — buy guarantees you may never collect on, and Riverpod or Bloc will get you to a working product with meaningfully less ceremony. Chassis's costs amortize with team size, codebase lifetime, and reliance on AI agents: the more people (or models) write features, the more it is worth paying per-feature ceremony to make every feature identical and machine-checked.
