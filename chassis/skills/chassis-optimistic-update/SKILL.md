---
name: chassis-optimistic-update
description: Make a mutation feel instant — a toggle, favorite, like, mark-as-read, or reorder — by applying the write to the UI before the backend confirms it, with automatic rollback on failure. Two Chassis recipes with a structural criterion between them: result-field optimism via the `optimistic:` parameter of `run`/`read` (on failure, `AsyncError.previous` rolls back to the last confirmed data, never the optimistic value), and repository-level optimism for projections fed by a WatchQuery (patch the cached list, emit immediately, re-emit the rollback on failure). Use when a write should render before the backend confirms — instant toggles, optimistic likes/favorites, drag-reorder, snappy check-off interactions.
---
# Optimistic Updates in Chassis

## Contents
- [Core Concepts](#core-concepts)
- [Recipe A: Result-Field Optimism (`optimistic:`)](#recipe-a-result-field-optimism-optimistic)
- [Recipe B: Repository-Level Optimism (watched projections)](#recipe-b-repository-level-optimism-watched-projections)
- [The Two Repository-Level Traps](#the-two-repository-level-traps)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

An optimistic update renders the *expected* result of a mutation before the backend confirms it. Chassis has two recipes, and choosing between them is structural, not stylistic:

- **Recipe A — result-field optimism**: the mutation's result lives in a field that the `run()` itself owns and writes through `onState`. Use the `optimistic:` parameter of `run`/`read`.
- **Recipe B — repository-level optimism**: the mutation lands in a *projection* the screen watches — a list fed by a `WatchQuery`, possibly rendered by several screens at once. Apply the write in the repository, on the stream itself. (`watch()` has no `optimistic:` parameter, deliberately: the stream's next emission would immediately overwrite it.)

**The criterion in one line: if the field is owned by the run, use `optimistic:` (A); if the data is a watched projection, patch the stream in the repository (B).** If the same entity appears both ways, prefer B — it is the only recipe that keeps every surface consistent.

**The doctrine: a UI that must mark "unconfirmed" is not optimistic — model the status in the domain or use the normal pipeline.** Optimistic UI renders the expected value *as if confirmed*: the field really is `AsyncData`, so the widget needs zero optimism-specific code. If the design calls for a greyed-out message or a "syncing" badge, that pending state is real domain information — put a status field on the entity and let the repository emit it, or use the ordinary loading pipeline.

As everywhere in Chassis (see `chassis-create-view-model`), ViewModels are message-direct — they dispatch the command object itself — and **every dispatch must cover the error path** with `onState` or `onError` (`onError` receives `(Object error, StackTrace stack)`). For optimistic updates this is doubly true: the error transition *is* the rollback.

## Recipe A: Result-Field Optimism (`optimistic:`)

`run()` (and `read()` — the parameter is identical) accepts `optimistic: AsyncData<R>`:

- At dispatch, the optimistic value is emitted **verbatim through `onState`**, *instead of* a loading state. The field takes the expected value immediately.
- `onSuccess`, `onError`, and the result transition of `onState` fire **only for the real result**, once the backend answers.
- **On failure, the emitted `AsyncError.previous` is the last confirmed data** on the key — the latest `AsyncData` actually completed by a run on that `key`, or the data carried by `current:` at dispatch — **never the optimistic value**. Rendering `previous` on error (normal soft-error rendering, see `chassis-render-async-state`) rolls the UI back automatically. The confirmed record is refreshed by every run completing on the key, so the rollback always targets the freshest confirmed truth, not the call-time snapshot.
- `optimistic:` requires `onState` (asserted in debug builds) — the optimistic value is emitted through `onState` only.
- It is typed `AsyncData<R>?`, not `R?`: for a nullable `R`, `optimistic: AsyncData(null)` ("optimistically cleared") stays distinct from omitting the parameter.

Pair the dispatch with `RunPolicy.droppable()` so a double-tap cannot dispatch the mutation twice, and pass `current:` so the rollback target is seeded even before any run has completed on the key.

## Recipe B: Repository-Level Optimism (watched projections)

The command's handler calls the repository as usual (see `chassis-create-command`); the optimism lives in the repository, which owns a local cache of the last snapshot it emitted on the watch stream:

1. **Patch locally and emit**: apply the write to the cached list and emit the patched list immediately on the stream — every watching screen updates now.
2. **Make the backend call.**
3. **On failure, re-emit the rollback list** — as a plain *data* emission, never a stream error — and `rethrow`, so the command's own channel reports the failure.

The ViewModel side carries zero optimism-specific code: the list screen `watch`es the projection, and the toggle dispatches the command with only an `onError` (on success there is nothing to do — the stream already shows the truth).

This recipe composes with the ref-counted shared stream from `docs/05_hard_cases.md` ("Deduplicating Watch Subscriptions"): the optimistic emission travels through the same shared pipe every watcher listens to.

## The Two Repository-Level Traps

**Trap 1 — the server echo.** After the backend confirms, the real upstream feed (Firestore snapshots, server push) emits the confirmed list — usually identical to the one you already emitted optimistically. Either make the source deduplicate (`.distinct()` upstream, with proper `==` on the entity) or tolerate the echo (re-rendering an identical list is harmless). What is *not* harmless is a local patch that differs from the echo — if the server stamps `updatedAt` and your patch does not, the UI visibly flickers from your version to the server's. Keep the patch faithful to what the server will produce.

**Trap 2 — double error signaling.** A failed write surfaces on *two* channels at once: the stream emits the rollback, and the command completes with an error (`onError` fires, the failure event goes out). Pick **one** channel for user-facing feedback — recommended: the **command's failure event**, which carries the error object and fires exactly once, on the screen where the user acted. The stream emission stays a **silent rollback** (plain data, never `addError`).

## Rules

- **DO** use `optimistic: AsyncData(expected)` on `run` when the mutated value lives in a field the run itself owns. *The field takes the expected value at dispatch through `onState`; `onSuccess`/`onError` still report only the real result.*
- **DO** pass `current: state.<field>` alongside `optimistic:`. *It seeds the confirmed record the rollback targets when no run has completed on the key yet.*
- **DO** cover the error path of every optimistic dispatch with `onState` (and usually `onError` for the user-facing event). *The `AsyncError` transition is the rollback — without it the UI keeps rendering a value the backend refused.*
- **DO** pair optimistic mutations with `RunPolicy.droppable()` (default key = the command's class; use a per-entity key like `key: (SetFavoriteCommand, articleId)` for per-item guards). *A double-tap must resolve with the in-flight result, not dispatch twice.*
- **DO** apply optimism in the repository when the mutated data is a projection fed by a `WatchQuery`. *`watch()` has no `optimistic:` parameter — the stream's next emission would overwrite it; patch the cache, emit, then call the backend.*
- **DO** re-emit the rollback as a plain data emission and `rethrow`. *The stream reverts silently; the command's error channel — `onError: (error, stack) => sendEvent(...)` — is the single user-facing failure signal.*
- **DO** carry the error object in failure events (`final Object error`). *`error.toString()` destroys the pattern matching that translation and listener logic rely on — see `chassis-handle-errors`.*
- **DON'T** expect `AsyncError.previous` to hold the optimistic value. *The contract is the opposite: `previous` is the last confirmed data on the key, precisely so rendering it rolls the UI back.*
- **DON'T** patch the optimistic value into state manually before dispatching. *`setState` before `run` bypasses the framework: no confirmed-record seeding, no automatic rollback — the failure leaves your hand-patched value on screen.*
- **DON'T** use `optimistic:` for a value the UI must mark as "unconfirmed". *That is not optimistic UI — it is a real domain status; model it on the entity (the repository emits it as pending) or use the normal loading pipeline.*
- **DON'T** signal one failure on both the stream and the command event. *An error state and a snackbar for the same tap is double feedback; the stream rolls back silently, the command event talks.*
- **DON'T** emit the rollback as a stream error. *A stream error puts every watching screen into an error state; the rollback is data — the confirmed list — and the failure already has its channel.*

## Workflow

- [ ] **Step 1 — Classify the mutation.** Does its result live in a field this ViewModel's `run` writes (→ Recipe A), or in a projection fed by a `WatchQuery`, possibly watched by several screens (→ Recipe B)?
- [ ] **Step 2 — Check the doctrine.** Does the design require marking the value "unconfirmed" (badge, greyed-out row)? Then stop: model the pending status in the domain, or use the normal pipeline — this is not an optimistic update.
- [ ] **Step 3 (A) — Dispatch with `optimistic:`.** Compute the expected value from confirmed state (guard: `if (field is! AsyncData<T>) return;`), then `run(command, policy: const RunPolicy.droppable(), current: field, optimistic: AsyncData(expected), onState: ..., onError: ...)`.
- [ ] **Step 4 (A) — Render the rollback.** Make sure the error branch renders `previous` (match `AsyncError(previous: AsyncData(:final value))` before the bare error case, or use `AsyncBuilder`'s `maintainState`) — see `chassis-render-async-state`.
- [ ] **Step 3 (B) — Patch in the repository.** In the repository method the command handler calls: read the cached snapshot, emit the patched list, `await` the backend call, on failure re-emit the confirmed list and `rethrow`.
- [ ] **Step 4 (B) — Keep the ViewModel plain.** The list `watch`es the projection (`onState` into state); the toggle `run`s the command with `RunPolicy.droppable()` and `onError: (error, stack) => sendEvent(<Failed>(error))` — nothing else.
- [ ] **Step 5 — Handle the echo (B).** Deduplicate upstream (`.distinct()`) or verify the local patch matches what the server will emit.
- [ ] **Step 6 — Test.** Recipe A: a fake handler that throws must produce an `AsyncError` whose `previous` is the pre-toggle data (see `chassis-write-handler-test` for handler fakes). Recipe B: after a failing backend call, the repository stream must have emitted patched-then-confirmed.

## Examples

### Recipe A: optimistic favorite toggle with rollback

```dart
class ArticleViewModel extends ViewModel<ArticleState, ArticleEvent> {
  ArticleViewModel({super.mediator}) : super(ArticleState.initial());

  void toggleFavorite() {
    final article = state.article;
    if (article is! AsyncData<Article>) return; // nothing confirmed to toggle
    final toggled =
        article.value.copyWith(isFavorite: !article.value.isFavorite);
    run(
      SetFavoriteCommand(
        articleId: article.value.id,
        value: toggled.isFavorite,
      ),
      policy: const RunPolicy.droppable(),
      current: article,
      optimistic: AsyncData(toggled),
      onState: (article) => setState(state.copyWith(article: article)),
      onError: (error, stack) => sendEvent(FavoriteFailedEvent(error)),
    );
  }
}

sealed class ArticleEvent {}

final class const FavoriteFailedEvent(
  final Object error, // the error object — never error.toString()
) implements ArticleEvent;
```

The star fills instantly (`onState` receives `AsyncData(toggled)` at dispatch). On failure, `onState` receives `AsyncError(previous: <last confirmed article>)` — rendering `previous` un-fills the star — and `onError` sends the event that explains why.

### Recipe A: rendering that rolls back

```dart
final article = context.select((ArticleViewModel vm) => vm.state.article);

return switch (article) {
  AsyncData(:final value) => ArticleView(article: value),
  AsyncLoading(previous: AsyncData(:final value)) =>
    ArticleView(article: value),
  AsyncLoading() => const Center(child: CircularProgressIndicator()),
  // The rollback: previous is the last CONFIRMED article.
  AsyncError(previous: AsyncData(:final value)) =>
    ArticleView(article: value),
  AsyncError(:final error) => ErrorPanel(error: error),
};
```

### Recipe B: the repository patches the watched stream

```dart
// infrastructure/todos/api_todo_repository.dart
class ApiTodoRepository implements TodoRepository {
  // Last snapshot emitted on the watch stream (shared-stream plumbing in
  // docs/05_hard_cases.md, "Deduplicating Watch Subscriptions").
  List<Todo>? _lastSnapshot;

  void _emit(List<Todo> todos) {
    _lastSnapshot = todos;
    _shared.add(todos);
  }

  @override
  Future<void> setCompleted({
    required String todoId,
    required bool completed,
  }) async {
    final confirmed = _lastSnapshot;
    if (confirmed == null) {
      // No projection in memory to patch: a plain write.
      return _api.setCompleted(todoId: todoId, completed: completed);
    }

    // 1. Patch locally and emit — every watching screen updates now.
    _emit([
      for (final todo in confirmed)
        todo.id == todoId ? todo.copyWith(completed: completed) : todo,
    ]);

    try {
      // 2. The backend call.
      await _api.setCompleted(todoId: todoId, completed: completed);
    } catch (_) {
      // 3. Silent rollback (data, not an error) + rethrow: the command's
      //    channel reports the failure exactly once.
      _emit(confirmed);
      rethrow;
    }
  }
}
```

### Recipe B: the ViewModel stays plain

```dart
class TodosViewModel extends ViewModel<TodosState, TodosEvent> {
  TodosViewModel({super.mediator}) : super(TodosState.initial()) {
    watch(
      WatchTodosQuery(),
      current: state.todos,
      onState: (todos) => setState(state.copyWith(todos: todos)),
    );
  }

  // On success there is nothing to do: the stream already shows the truth.
  void toggleTodo(String todoId, bool completed) => run(
        SetTodoCompletedCommand(todoId: todoId, completed: completed),
        key: (SetTodoCompletedCommand, todoId), // per-todo double-tap guard
        policy: const RunPolicy.droppable(),
        onError: (error, stack) => sendEvent(TodoToggleFailedEvent(error)),
      );
}
```

### Anti-pattern: hand-patched optimism

```dart
// ❌ Bypasses the framework: no confirmed record, no rollback. If the
// command fails, the hand-patched value stays on screen forever.
void toggleFavorite() {
  final toggled = state.article.requireValue.copyWith(isFavorite: true);
  setState(state.copyWith(article: AsyncData(toggled))); // manual patch
  run(
    SetFavoriteCommand(articleId: toggled.id, value: true),
    onSuccess: (_) {}, // and the error path is not even covered
  );
}
```

```dart
// ✅ The framework emits the optimistic value and owns the rollback.
void toggleFavorite() {
  final article = state.article;
  if (article is! AsyncData<Article>) return;
  final toggled = article.value.copyWith(isFavorite: true);
  run(
    SetFavoriteCommand(articleId: toggled.id, value: true),
    policy: const RunPolicy.droppable(),
    current: article,
    optimistic: AsyncData(toggled),
    onState: (article) => setState(state.copyWith(article: article)),
    onError: (error, stack) => sendEvent(FavoriteFailedEvent(error)),
  );
}
```

### Anti-pattern: an "unconfirmed" badge on an optimistic value

```dart
// ❌ The design wants a "syncing" badge on the message — that is not
// optimistic UI, and Async<T> has no "optimistic-pending" case to render.
run(
  SendMessageCommand(text: text),
  optimistic: AsyncData(messages..add(pendingMessage)), // and mutation, too
  onState: (m) => setState(state.copyWith(messages: m)),
);
```

```dart
// ✅ "Pending" is a domain status. The repository appends the message with
// status: MessageStatus.sending, emits it on the watched stream, and emits
// the confirmed (or failed) status when the backend answers.
void send(String text) => run(
      SendMessageCommand(text: text),
      onError: (error, stack) => sendEvent(MessageSendFailedEvent(error)),
    );
```

For the full discussion — criterion, rollback contract, traps, and how this composes with stream deduplication — see `docs/05_hard_cases.md`. Related skills: `chassis-create-view-model` (dispatch contract), `chassis-render-async-state` (rendering `previous`), `chassis-handle-errors` (error channels), `chassis-paginate-list` (another `current:`-driven recipe), `chassis-create-command` and `chassis-create-watch-query` (the messages involved).
