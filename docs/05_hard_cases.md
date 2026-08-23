# Hard Cases

Most architectures survive month one. The screens are simple, the lists are short, and every operation is a straightforward fetch-and-render. The problems that break an architecture arrive around month three: the product wants a favorite button that responds instantly, two screens end up watching the same data and the backend bill doubles, the list grows past one page, and someone reaches for "cancellation" to fix a race that cancellation cannot fix. This guide covers those four cases — with the chassis-native recipe for each, and the reasoning behind the boundaries.

This guide assumes you know the dispatch API from [UI Integration](04_ui_integration.md) and the error doctrine from [Error Handling Strategy](error_management.md).

## Optimistic UI

An optimistic update renders the *expected* result of a mutation before the backend confirms it: the star fills on tap, not 400ms later. Chassis has two recipes, and the choice between them is structural, not stylistic:

- **Result-field optimism** — the mutation's result lives in a field that the `run()` itself owns and writes through `onState`. Use the `optimistic:` parameter.
- **Repository-level optimism** — the mutation lands in a *projection* the screen watches (a list fed by a `WatchQuery`, possibly rendered by several screens at once). Apply the write in the repository, on the stream itself.

The criterion in one line: **if the field is owned by the run, use `optimistic:`; if the data is a watched projection, patch the stream in the repository.**

### Result-Field Optimism: the `optimistic:` Parameter

`run()` (and `read()` — the parameter is identical) accepts `optimistic: AsyncData<R>`. At dispatch, that value is emitted verbatim through `onState` *instead of* a loading state — the field takes the expected value immediately. `onSuccess`, `onError`, and the result transition of `onState` fire only for the **real** result, once the backend answers.

```dart
void toggleFavorite() {
  final article = state.article;
  if (article is! AsyncData<Article>) return; // nothing confirmed to toggle
  final toggled =
      article.value.copyWith(isFavorite: !article.value.isFavorite);
  run(
    SetFavoriteCommand(articleId: article.value.id, value: toggled.isFavorite),
    policy: const RunPolicy.droppable(),
    current: article,
    optimistic: AsyncData(toggled),
    onState: (article) => setState(state.copyWith(article: article)),
    onError: (error, stack) => sendEvent(FavoriteFailedEvent(error)),
  );
}
```

The star flips the instant the user taps: `onState` receives `AsyncData(toggled)` at dispatch and the widget renders it as plain data — zero optimism-specific rendering code. `RunPolicy.droppable()` (under the default key, the command's class) makes a double-tap resolve with the in-flight result instead of dispatching twice.

**The rollback contract.** On failure, the emitted `AsyncError.previous` is the last **confirmed** data on the key — the latest `AsyncData` actually completed by a run on that key, or the data carried by `current:` at dispatch — **never the optimistic value**. Rendering `previous` on error (the normal soft-error rendering) therefore rolls the UI back automatically: the star un-fills, and the `onError` event tells the user why. The confirmed record is kept per `key` and refreshed by every completing run, so even if another mutation lands while the optimistic one is in flight, the rollback targets the freshest confirmed truth, not the call-time snapshot.

Three boundaries to respect:

- `optimistic:` requires `onState` (asserted in debug builds) — the optimistic value is emitted through `onState` only.
- `optimistic:` is typed `AsyncData<R>?`, not `R?`: for a nullable `R`, `optimistic: AsyncData(null)` ("optimistically cleared") stays distinct from omitting the parameter.
- The doctrine: **a UI that must mark "unconfirmed" is not optimistic — model the status in the domain or use the normal pipeline.** Optimistic UI renders the expected value *as if confirmed*; that is the whole point of the honest `AsyncData` encoding. If the design calls for a greyed-out message or a "syncing" badge, that pending state is real domain information — put a status field on the entity and let the repository emit it, or fall back to the ordinary loading pipeline.

### Repository-Level Optimism: Patch the Watched Stream

`watch()` has no `optimistic:` parameter, deliberately: the stream's next emission would immediately overwrite any value injected at the ViewModel. When the mutated data is a watched projection — a todo list fed by `WatchTodosQuery`, rendered by the list screen and maybe a badge in the app bar — optimism belongs where the stream is produced: the repository.

The recipe: the command's handler calls the repository; the repository applies the write to its local cache and **emits the patched list immediately** on the stream every watcher receives; then it makes the backend call; on failure it re-emits the rollback list and rethrows.

```dart
// infrastructure/todos/api_todo_repository.dart
class ApiTodoRepository implements TodoRepository {
  // The repository owns a local projection: the last snapshot it emitted on
  // the watch stream.
  List<Todo>? _lastSnapshot;

  void _emit(List<Todo> todos) {
    _lastSnapshot = todos;
    // The stream every watcher receives — the sharing plumbing behind it
    // is the subject of the next section.
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

    // 1. Apply the write locally and emit: every watching screen updates now.
    _emit([
      for (final todo in confirmed)
        todo.id == todoId ? todo.copyWith(completed: completed) : todo,
    ]);

    try {
      // 2. Make the backend call.
      await _api.setCompleted(todoId: todoId, completed: completed);
    } catch (_) {
      // 3. On failure, re-emit the rollback list — a plain data emission,
      //    not an error — and let the command's channel report the failure.
      _emit(confirmed);
      rethrow;
    }
  }
}
```

The ViewModel side carries **zero optimism-specific code** — that is the payoff. The list screen watches the projection; the toggle dispatches the command and only handles the outcome:

```dart
// The list is a watched projection: patched emissions arrive like any other.
void watchTodos() => watch(
      WatchTodosQuery(),
      current: state.todos,
      onState: (todos) => setState(state.copyWith(todos: todos)),
    );

// The command's own channel carries only the outcome. On success there is
// nothing to do — the stream already shows the truth.
void toggleTodo(String todoId, bool completed) => run(
      SetTodoCompletedCommand(todoId: todoId, completed: completed),
      key: (SetTodoCompletedCommand, todoId), // per-todo double-tap guard
      policy: const RunPolicy.droppable(),
      onError: (error, stack) => sendEvent(TodoToggleFailedEvent(error)),
    );
```

Every screen watching the projection updates and rolls back in lockstep, because there is exactly one source of truth being patched. Two traps come with this power:

**Trap 1 — the server echo.** After the backend confirms the write, the real upstream feed (a Firestore snapshot listener, a server push) emits the confirmed list — which is byte-for-byte the list you already emitted optimistically. Either make the source deduplicate (`.distinct()` on the upstream with proper `==` on the entity) or simply tolerate the echo: re-rendering an identical list is harmless. What is *not* harmless is a local patch that differs from the echo — if the server stamps `updatedAt` and your patch does not, the UI visibly flickers from your version to the server's. Keep the local patch faithful to what the server will produce, or accept the reconciliation as visible.

**Trap 2 — double error signaling.** A failed write surfaces on *two* channels at once: the stream emits the rollback, and the command completes with an error (`onError` fires, the failure event goes out). If both channels produce user-facing feedback, the user gets an error state *and* a snackbar for one failure. Pick **one** channel for the user: the recommendation is the **command's failure event** (it carries the error object and fires exactly once, on the screen where the user acted), while the stream emission stays a **silent rollback** — which is why the recipe re-emits the rollback as plain *data*, never as a stream error.

### Choosing Between the Two

| | Result-field optimism | Repository-level optimism |
|---|---|---|
| The data is | a field the `run()` owns and writes | a projection fed by a `WatchQuery` |
| Who sees it | this ViewModel's state | every watcher of the stream |
| Optimism lives in | the dispatch (`optimistic:`) | the repository (patch + emit) |
| Rollback | `AsyncError.previous` = last confirmed data | re-emit the confirmed list |
| User-facing failure | `onError` → failure event | the command's failure event (stream rolls back silently) |

If the same entity appears both as a run-owned field on a detail screen and inside a watched list, prefer the repository-level recipe — it is the only one that keeps every surface consistent.

## Deduplicating Watch Subscriptions

Two screens watching the same query must not pay for two backend subscriptions. And by default, they will: **each `ViewModel.watch` is its own subscription to the handler's stream**. The mediator routes every `WatchTodosQuery` dispatch to the handler, the handler returns a fresh stream, and if the repository opens a backend feed per stream, two screens means two Firestore listeners, two sockets, twice the bill. The mediator does not share streams between dispatches — deduplication is **infrastructure's job, not the mediator's**: only the data source knows what is safe to share, for how long, and what a late subscriber should see first.

The recipe lives in the repository: a **ref-counted broadcast stream** around a single upstream subscription, replaying the last value to late subscribers so a screen opened second doesn't stare at a spinner until the next backend push.

```dart
// infrastructure/todos/api_todo_repository.dart
class ApiTodoRepository implements TodoRepository {
  ApiTodoRepository(this._api);

  final TodoApi _api;

  StreamController<List<Todo>>? _shared;
  StreamSubscription<List<Todo>>? _upstream;
  List<Todo>? _lastSnapshot;

  @override
  Stream<List<Todo>> watchTodos() {
    final shared = _shared ??= StreamController<List<Todo>>.broadcast(
      onListen: _connect, // 0 → 1 watchers: open the backend feed
      onCancel: _disconnect, // last watcher left: close it
    );
    // Each caller gets its own view: the last snapshot replayed immediately,
    // then the shared broadcast. Stream.multi runs this callback per
    // listener, synchronously at subscription — no gap in which an
    // emission could slip by unobserved.
    return Stream.multi((subscriber) {
      final last = _lastSnapshot;
      if (last != null) subscriber.add(last);
      subscriber.addStream(shared.stream);
    });
  }

  void _connect() {
    // The upstream is already mapped to domain types and domain errors —
    // the anti-corruption work described in the error handling guide.
    _upstream = _api.watchTodos().listen(
      (todos) {
        _lastSnapshot = todos;
        _shared!.add(todos);
      },
      onError: _shared!.addError,
    );
  }

  Future<void> _disconnect() async {
    _lastSnapshot = null;
    await _upstream?.cancel();
    _upstream = null;
  }
}
```

The moving parts, and why each exists:

- **`StreamController.broadcast(onListen:, onCancel:)`** is the ref-counter: `onListen` fires when the watcher count goes from zero to one (open the backend feed), `onCancel` when it drops back to zero (close it). A broadcast controller accepts new listeners after that, so the next `watch()` transparently reconnects.
- **`_lastSnapshot` + `Stream.multi`** handle the late subscriber: a broadcast stream does not replay, so the second screen would otherwise render nothing until the backend pushes again. The `Stream.multi` callback runs per listener and delivers the cached snapshot first, then follows the shared feed.
- The whole thing composes with both recipes above: `_emit` from the repository-level optimism recipe is exactly `_lastSnapshot = todos; _shared!.add(todos);` — the optimistic patch reaches every watcher through the same shared pipe, and a screen opened mid-flight receives the patched snapshot on arrival.

Teams already using [rxdart](https://pub.dev/packages/rxdart) can replace the hand-rolled version with `stream.shareReplay(maxSize: 1)` — the same semantics in one call. Chassis itself has no rxdart dependency and does not require one; the recipe above is plain `dart:async`.

Downstream of the repository nothing changes: the handler still returns `_todoRepository.watchTodos()`, and each ViewModel still calls `watch(WatchTodosQuery(), ...)` — its subscription is now one listener on the shared broadcast instead of one backend feed. When the last ViewModel disposes (or replaces its watch under the same key), the ref-count reaches zero and the backend subscription actually closes.

## Paginated Lists

Pagination in chassis is four ingredients, each doing one job:

1. **The cursor lives in the ViewModel state**, next to the accumulated items and a `hasMore` flag — all under one `Async<T>` field.
2. **`RunPolicy.sequential()`** on the page query: page loads queue per key and never interleave, so page 3 can never land before page 2.
3. **Accumulation happens in `onState`**: the handler returns one page; the callback folds it into the accumulated value, reading fresh state.
4. **`current:`** makes loading-more render as `AsyncLoading(previous: <accumulated list>)` — the list stays visible and the UI appends a spinner row instead of blanking.

The worked example, bottom-up. One domain shape serves both roles — the handler fills it with a single page, the ViewModel accumulates into it:

```dart
// domain/todos/todo_page.dart
class TodoPage {
  const TodoPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });

  /// From the handler: one page of items. In state: all items loaded so far.
  final List<Todo> items;

  /// Opaque backend cursor for the next page; null when [hasMore] is false.
  final String? cursor;

  final bool hasMore;
}
```

```dart
// application/todos/load_todos_page_query.dart
final class LoadTodosPageQuery extends ReadQuery<TodoPage> {
  LoadTodosPageQuery({this.cursor});

  /// Null requests the first page.
  final String? cursor;

  @override
  Map<String, Object?> get params => {'cursor': cursor};
}

@chassisHandler
class LoadTodosPageQueryHandler
    implements ReadHandler<LoadTodosPageQuery, TodoPage> {
  LoadTodosPageQueryHandler(this._todoRepository);

  final TodoRepository _todoRepository;

  @override
  Future<TodoPage> read(LoadTodosPageQuery query) =>
      _todoRepository.fetchPage(cursor: query.cursor);
}
```

The state holds the accumulated page under a single `Async<TodoPage>` — so the loading and error emissions carry the whole accumulated list as `previous`, for free:

```dart
// presentation/todos/todos_state.dart
class TodosState {
  const TodosState({required this.page});

  /// The accumulated list plus its pagination bookkeeping. Loading more is
  /// AsyncLoading(previous: <everything loaded so far>).
  final Async<TodoPage> page;

  TodosState copyWith({Async<TodoPage>? page}) =>
      TodosState(page: page ?? this.page);

  static TodosState initial() => const TodosState(page: Async.loading());
}
```

```dart
// presentation/todos/todos_view_model.dart
class TodosViewModel extends ViewModel<TodosState, TodosEvent> {
  TodosViewModel({super.mediator}) : super(TodosState.initial()) {
    refresh();
  }

  /// Loads the first page — and reloads from scratch on pull-to-refresh or
  /// retry. The result REPLACES the accumulated list; current: keeps it
  /// visible (as previous) while the refresh is in flight.
  void refresh() => read(
        LoadTodosPageQuery(cursor: null),
        policy: const RunPolicy.sequential(),
        current: state.page,
        onState: (page) => setState(state.copyWith(page: page)),
      );

  /// Loads the next page and APPENDS it. The shared default key +
  /// sequential keep it ordered with refresh(); the guards stop duplicate
  /// and past-the-end fetches.
  void loadMore() {
    final page = state.page;
    if (page.isLoading) return; // one page fetch at a time
    final loaded = page.valueOrNull; // survives a soft error on a later page
    if (loaded == null || !loaded.hasMore) return; // nothing yet / end reached
    read(
      LoadTodosPageQuery(cursor: loaded.cursor),
      policy: const RunPolicy.sequential(),
      current: page,
      onState: (result) => setState(state.copyWith(
        // Fold the fresh page into the accumulated value, reading fresh
        // state; loading and error transitions pass through unchanged
        // (they already carry the accumulated list as previous).
        page: switch (result) {
          AsyncData(:final value) =>
            AsyncData(_append(state.page.valueOrNull, value)),
          _ => result,
        },
      )),
    );
  }

  TodoPage _append(TodoPage? loaded, TodoPage next) => TodoPage(
        items: [...?loaded?.items, ...next.items],
        cursor: next.cursor,
        hasMore: next.hasMore,
      );
}

sealed class TodosEvent {}
```

The details that make this correct, not just plausible:

- **The default key is exactly right.** Every dispatch of `LoadTodosPageQuery` — first load, load-more, refresh — shares the key (the query's runtime type), so `sequential` serializes *all* of them: a refresh dispatched while page 2 is in flight queues behind it and then replaces the list, instead of interleaving with it.
- **The guards.** `page.isLoading` stops a second load-more while one is in flight — necessary because the message's cursor is captured when `loadMore()` is *called*, so a queued duplicate would re-fetch the same page. The `hasMore` check stops loading past the end; `loaded == null` leaves the first-load path (and its retry) to `refresh()`. After a failed load-more, `state.page` is `AsyncError(previous: <accumulated>)` — `valueOrNull` still reads the accumulated value, so calling `loadMore()` again retries from the stored cursor.
- **Accumulation reads fresh state.** `sequential` captures `current:` at call time, not when the queued operation starts (see [RunPolicy](04_ui_integration.md#concurrency-key-and-runpolicy)) — which is why the merge reads `state.page.valueOrNull` *inside* `onState` rather than trusting a captured snapshot. The only call-time capture left is cosmetic: a queued refresh's loading emission carries the list as of the call.
- **The error path is covered** on both methods: `onState` receives the error transitions, and the rendering below turns them into a retry affordance.

The rendering falls out of the `previous`-carrying states — loading more is a spinner row appended to a fully visible list:

```dart
class TodosScreen extends StatelessWidget {
  const TodosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final page = context.select((TodosViewModel vm) => vm.state.page);

    return switch (page) {
      AsyncData(:final value) => TodoListView(
          items: value.items,
          showEndOfList: !value.hasMore,
          onEndReached: () => context.read<TodosViewModel>().loadMore(),
        ),
      // Loading more (or refreshing): the accumulated list stays on screen,
      // with a spinner row appended.
      AsyncLoading(previous: AsyncData(:final value)) => TodoListView(
          items: value.items,
          showLoadingRow: true,
        ),
      // First page loading: nothing to show yet.
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      // A later page failed: keep the list, offer a retry row.
      AsyncError(previous: AsyncData(:final value)) => TodoListView(
          items: value.items,
          showRetryRow: true,
          onRetry: () => context.read<TodosViewModel>().loadMore(),
        ),
      // The first page failed: full error view with retry.
      AsyncError(:final error) => ErrorPanel(
          error: error,
          onRetry: () => context.read<TodosViewModel>().refresh(),
        ),
    };
  }
}
```

`TodoListView` and `ErrorPanel` are ordinary project widgets — the pattern is in the `switch`, which orders the `previous`-carrying cases before the bare ones.

## `restartable` Does Not Cancel Execution

**`RunPolicy.restartable` cuts callbacks, not execution.** When a new run supersedes an in-flight one on the same key, the superseded operation *keeps running to completion*: its network call finishes, its database write commits, its side effects land. The only thing that stops is reporting — the superseded run's `onState`/`onSuccess`/`onError` are never invoked, because its transitions no longer describe the current intent.

This asymmetry dictates where each policy belongs:

- **`restartable` is for reads.** A superseded `GetUserQuery` that completes anyway wasted some bandwidth and produced a result nobody renders — *waste, not incorrectness*. Search-as-you-type, refetches, filter changes: all safe, all better with `restartable`.
- **Mutations use `droppable` or `sequential` — never supplant a write.** A `restartable` on `SubmitOrderCommand` does not abort the first submission when the user taps again; it silences its callbacks while *both* POSTs hit the server. The user sees one confirmation and gets two orders. `droppable` (the first wins, later taps resolve with the in-flight result) or `sequential` (all execute, in order) are the honest concurrency semantics for writes.

```dart
// ❌ Both submissions execute; only the second one reports.
void submitOrder() => run(
      SubmitOrderCommand(cart: state.cart),
      policy: const RunPolicy.restartable(),
      onSuccess: (_) => sendEvent(const OrderSubmittedEvent()),
      onError: (error, stack) => sendEvent(OrderFailedEvent(error)),
    );

// ✅ A double-tap cannot dispatch twice.
void submitOrder() => run(
      SubmitOrderCommand(cart: state.cart),
      policy: const RunPolicy.droppable(),
      onSuccess: (_) => sendEvent(const OrderSubmittedEvent()),
      onError: (error, stack) => sendEvent(OrderFailedEvent(error)),
    );
```

### Why Chassis Has No Cancellation API

True cancellation was evaluated for chassis and rejected — deliberately, not as an oversight. Three reasons:

1. **Cancellation is cooperative, end-to-end.** Dart futures cannot be killed from outside; cancelling real work means threading a cancellation token through every layer that does the work. The token would appear in every repository interface, every API client, every handler — a framework parameter infecting every port signature in the architecture, paid for by all the operations that will never be cancelled.
2. **A client-side abort does not abort the server.** By the time the user "cancels", the request has usually left the device. Closing the socket does not un-send it: the server processes the write anyway. Client-side cancellation of a mutation is theater.
3. **For commands, the outcome becomes unknowable.** A cancelled write is neither confirmed nor rolled back — did it land? The application can no longer say. The correct tools for "the user changed their mind mid-write" are domain-level: **idempotency keys** (retrying or superseding a submission is safe because the server deduplicates) and **compensation** (a follow-up command that undoes the first). These are architecture concerns, designed per operation — not a framework API that pretends a boolean flag can make a distributed write un-happen.

What chassis gives you covers the legitimate needs, without the false promise:

- **`restartable(debounce: ...)`** avoids *starting* work at all — the only fully safe form of "cancellation" is the dispatch that never happened.
- **`restartable`** discards stale *results* — the right fix for superseded reads.
- **`watch` has real, native cancellation** — the one place it is actually possible. A keyed replacement (re-watching the same query class) or `WatchHandle.cancel()` cancels the upstream `StreamSubscription`, and that cancellation genuinely propagates: an `async*` handler is torn down, and a ref-counted repository stream (see [Deduplicating Watch Subscriptions](#deduplicating-watch-subscriptions)) closes the backend feed when the last watcher leaves.

## Summary

Optimistic UI has two shapes: `optimistic:` for a field the run owns (with `AsyncError.previous` guaranteeing rollback to the last *confirmed* data), and repository-level patching for watched projections (rollback re-emitted as silent data, the failure reported once, through the command's event). Watch deduplication is infrastructure's job — a ref-counted broadcast stream with last-value replay in the repository, since every `ViewModel.watch` is its own subscription to the handler's stream. Pagination is a cursor in state, `RunPolicy.sequential` on a shared key, accumulation in `onState`, and `current:` so loading-more keeps the list on screen. And `restartable` cuts callbacks, not execution: reads can be superseded, writes must be dropped or queued, and the absence of a cancellation API is a decision — idempotency and compensation solve what a token only pretends to.
