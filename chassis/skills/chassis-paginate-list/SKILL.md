---
name: chassis-paginate-list
description: Implement a cursor-paginated list with Chassis — infinite scroll, "load more" buttons, page-by-page feeds. The recipe: cursor, accumulated items, and hasMore live in the ViewModel state under one `Async<T>`; page loads dispatch with `RunPolicy.sequential()` so they queue and never interleave; accumulation happens in `onState`; `current:` makes loading-more render as `AsyncLoading(previous:)` so the list stays visible with a spinner row appended; plus refresh (restart from a null cursor) and end-of-list guards. Use when a screen loads a list page by page — infinite scroll, load-more, cursor or offset pagination.
---
# Paginating a List with Chassis

## Contents
- [Core Concepts](#core-concepts)
- [The State Shape](#the-state-shape)
- [The Query and Handler](#the-query-and-handler)
- [loadMore: Sequential, Guarded, Accumulating](#loadmore-sequential-guarded-accumulating)
- [Rendering Loading-More](#rendering-loading-more)
- [Refresh](#refresh)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

Pagination in Chassis is four ingredients, each doing one job:

1. **The cursor lives in the ViewModel state**, next to the accumulated items and a `hasMore` flag — all under one `Async<T>` field.
2. **`RunPolicy.sequential()`** on the page query: runs sharing a key queue and execute one at a time, in call order — page 3 can never land before page 2. The **default key is the query's runtime type**, so every dispatch of the page query (first load, load-more, refresh) shares it — exactly right for `sequential`.
3. **Accumulation happens in `onState`**: the handler returns one page; the callback folds it into the accumulated value, reading *fresh* state (`sequential` captures `current:` and the message at call time, not when the queued run starts).
4. **`current:`** makes loading-more emit `AsyncLoading(previous: <accumulated list>)` — the list stays visible and the UI appends a spinner row instead of blanking (see `chassis-render-async-state`).

As everywhere in Chassis, the ViewModel is message-direct — it dispatches the query object itself (see `chassis-create-view-model`) — and **every dispatch covers the error path** with `onState` or `onError`. Here `onState` receives the error transitions, and the rendering turns them into retry affordances.

## The State Shape

One domain shape serves both roles — the handler fills it with a single page, the ViewModel accumulates into it:

```dart
class const TodoPage({
  /// From the handler: one page of items. In state: all items loaded so far.
  required final List<Todo> items,

  /// Opaque backend cursor for the next page; null when [hasMore] is false.
  required final String? cursor,

  required final bool hasMore,
});
```

The state holds it under a single `Async<TodoPage>`, so loading and error emissions carry the whole accumulated list as `previous` — the anti-blanking behavior falls out of the type:

```dart
class const TodosState({
  /// Accumulated list + pagination bookkeeping. Loading more renders as
  /// AsyncLoading(previous: <everything loaded so far>).
  required final Async<TodoPage> page,
}) {
  TodosState copyWith({Async<TodoPage>? page}) =>
      TodosState(page: page ?? this.page);

  static TodosState initial() => const TodosState(page: Async.loading());
}
```

## The Query and Handler

A plain `ReadQuery` carrying the cursor (see `chassis-create-read-query`); null requests the first page. The cursor belongs in `params` — it defines the operation's identity:

```dart
final class LoadTodosPageQuery({final String? cursor})
    extends ReadQuery<TodoPage> {
  @override
  Map<String, Object?> get params => {'cursor': cursor};
}

@chassisHandler
class LoadTodosPageQueryHandler(final TodoRepository _todoRepository)
    implements ReadHandler<LoadTodosPageQuery, TodoPage> {
  @override
  Future<TodoPage> read(LoadTodosPageQuery query) =>
      _todoRepository.fetchPage(cursor: query.cursor);
}
```

## loadMore: Sequential, Guarded, Accumulating

```dart
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
      page: switch (result) {
        AsyncData(:final value) =>
          AsyncData(_append(state.page.valueOrNull, value)),
        _ => result, // loading/error pass through, carrying the list
      },
    )),
  );
}

TodoPage _append(TodoPage? loaded, TodoPage next) => TodoPage(
      items: [...?loaded?.items, ...next.items],
      cursor: next.cursor,
      hasMore: next.hasMore,
    );
```

Why each guard exists:

- **`page.isLoading`** — the message's cursor is captured when `loadMore()` is *called*, so letting a second call queue while one is in flight would re-fetch the **same page twice** and duplicate its items. One fetch at a time; the sequential queue is the safety net for the dispatches that do overlap (refresh vs. load-more).
- **`!loaded.hasMore`** — the end guard: once the backend reports the end, `loadMore()` is a no-op no matter how often the scroll listener fires.
- **`loaded == null`** — the first page (and its retry after a first-page error) belongs to `refresh()`, which replaces instead of appending.

After a *failed* load-more, `state.page` is `AsyncError(previous: <accumulated>)`: `valueOrNull` still reads the accumulated value, so calling `loadMore()` again retries from the stored cursor.

The merge reads `state.page.valueOrNull` **inside `onState`** — fresh state — rather than trusting the call-time `current:` snapshot, per the `RunPolicy.sequential` contract.

## Rendering Loading-More

`current:` makes the loading emission `AsyncLoading(previous: AsyncData(<accumulated>))`. Match the `previous`-carrying cases before the bare ones (see `chassis-render-async-state`):

```dart
final page = context.select((TodosViewModel vm) => vm.state.page);

return switch (page) {
  AsyncData(:final value) => TodoListView(
      items: value.items,
      showEndOfList: !value.hasMore,
      onEndReached: () => context.read<TodosViewModel>().loadMore(),
    ),
  // Loading more (or refreshing): the list stays put, a spinner row appends.
  AsyncLoading(previous: AsyncData(:final value)) => TodoListView(
      items: value.items,
      showLoadingRow: true,
    ),
  // First page loading.
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
```

## Refresh

Refresh restarts from a null cursor and **replaces** the accumulated list on data. It dispatches under the same default key with the same `sequential` policy, so a refresh fired while a page fetch is in flight *queues behind it* — the refreshed list can never be corrupted by a late page landing after it:

```dart
void refresh() => read(
      LoadTodosPageQuery(cursor: null),
      policy: const RunPolicy.sequential(),
      current: state.page,
      onState: (page) => setState(state.copyWith(page: page)),
    );
```

Call it from the constructor for the first page, from the error panel's retry, and from pull-to-refresh. While it is in flight the state is `AsyncLoading(previous: <accumulated>)`, which also blocks `loadMore()` through its `isLoading` guard — no stale-cursor fetch can slip in behind a refresh. (One cosmetic consequence of the queue: a queued refresh's loading emission carries the list as captured at call time.)

## Rules

- **DO** keep the cursor, the accumulated items, and `hasMore` together in state, under one `Async<T>` field. *Loading and error emissions then carry the whole accumulated list as `previous`, and the anti-blanking rendering falls out of the type.*
- **DO** dispatch every page load with `policy: const RunPolicy.sequential()` under the default key. *The key defaults to the query's runtime type, so first load, load-more, and refresh all share the queue — results execute in call order and never interleave.*
- **DO** accumulate in `onState`, reading fresh state inside the callback. *`sequential` captures `current:` and the message at call time; the merge must read `state.page.valueOrNull` when the result actually lands.*
- **DO** pass `current: state.page` on `loadMore`. *Loading-more then renders as `AsyncLoading(previous:)` — the list stays visible with a spinner row instead of collapsing to a full-screen spinner.*
- **DO** guard `loadMore` against an in-flight fetch (`page.isLoading`) and against the end of the list (`!hasMore`). *The cursor is captured at call time, so a queued duplicate re-fetches the same page; and a scroll listener will happily fire past the last page forever.*
- **DO** restart from a null cursor on refresh, replacing (not appending) on its data. *Same key + `sequential` means a refresh queues behind any in-flight page and lands last, in order.*
- **DO** cover the error path of every dispatch. *`onState` receives the error transitions here; render `AsyncError(previous:)` as the list plus a retry row. If you surface a failure event instead, it carries the error object — `onError: (error, stack) => sendEvent(RefreshFailedEvent(error))`, never `error.toString()` (see `chassis-handle-errors`).*
- **DON'T** use `RunPolicy.restartable()` for page loads. *Pages must accumulate in order; latest-wins would silence the callbacks of an in-flight page and lose its items — and it does not cancel the superseded request anyway (see `docs/05_hard_cases.md`).*
- **DON'T** key pages separately (e.g. `key: cursor`). *Distinct keys mean distinct queues — page fetches would run concurrently and interleave; the shared default key is what makes `sequential` order them.*
- **DON'T** store each page in its own state field or `Async` slot. *The UI renders one list; accumulate into one value and let `previous` carry it through transitions.*
- **DON'T** trust the call-time snapshot for the merge. *`current:` is captured when `read()` is called, not when the queued operation starts — merging into it instead of fresh state drops pages.*

## Workflow

- [ ] **Step 1 — Define the page shape** in the domain: items + cursor + `hasMore`. The handler returns one page's worth; the ViewModel accumulates into the same shape.
- [ ] **Step 2 — Define the query and handler**: `final class Load<X>PageQuery({final String? cursor}) extends ReadQuery<<X>Page>` carrying the nullable cursor (in `params`); the handler forwards it to the repository (see `chassis-create-read-query`, `chassis-register-handler-with-codegen`).
- [ ] **Step 3 — Define the state**: a single `Async<<X>Page>` field, `copyWith`, `initial()` = `Async.loading()`.
- [ ] **Step 4 — Write `refresh()`**: `read(Load<X>PageQuery(cursor: null), policy: const RunPolicy.sequential(), current: state.page, onState: (page) => setState(...))` — replaces on data; call it from the constructor.
- [ ] **Step 5 — Write `loadMore()`**: guard `isLoading`, `valueOrNull == null`, and `!hasMore`; dispatch with the stored cursor, `sequential`, `current:`; merge fresh pages in `onState`, passing loading/error through.
- [ ] **Step 6 — Render** with a `switch` that matches `previous`-carrying cases first: list + spinner row while loading more, list + retry row on a later-page error, full spinner/error only when nothing is loaded yet.
- [ ] **Step 7 — Wire the trigger**: the scroll listener or end-of-list builder calls `context.read<TodosViewModel>().loadMore()` — calling it too often is safe, the guards absorb it.
- [ ] **Step 8 — Test** through the constructor seam (`TodosViewModel(mediator: fakeMediator)`): a fake handler serving fixed pages verifies accumulation, ordering, and the end guard — never `Chassis.initialize` in tests.

## Examples

### The complete ViewModel

```dart
class TodosViewModel extends ViewModel<TodosState, TodosEvent> {
  TodosViewModel({super.mediator}) : super(TodosState.initial()) {
    refresh();
  }

  /// First page, retry, and pull-to-refresh: restart from a null cursor,
  /// REPLACE the accumulated list on data.
  void refresh() => read(
        LoadTodosPageQuery(cursor: null),
        policy: const RunPolicy.sequential(),
        current: state.page,
        onState: (page) => setState(state.copyWith(page: page)),
      );

  /// Next page: APPEND. Guarded against in-flight fetches and the end.
  void loadMore() {
    final page = state.page;
    if (page.isLoading) return;
    final loaded = page.valueOrNull;
    if (loaded == null || !loaded.hasMore) return;
    read(
      LoadTodosPageQuery(cursor: loaded.cursor),
      policy: const RunPolicy.sequential(),
      current: page,
      onState: (result) => setState(state.copyWith(
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

### Variant: silent refresh with a failure event

When pull-to-refresh has its own progress indicator and a failed refresh should keep the list untouched, skip the loading transition and route the failure to a one-time event instead of state:

```dart
final class const TodosRefreshFailedEvent(
  final Object error, // the error object — never error.toString()
) implements TodosEvent;

void refresh() => read(
      LoadTodosPageQuery(cursor: null),
      policy: const RunPolicy.sequential(),
      emitLoading: false, // the list stays untouched while refreshing
      onState: (result) {
        // Only a fresh first page touches the list; the failure has its
        // own channel below — one user-facing signal per outcome.
        if (result case AsyncData()) setState(state.copyWith(page: result));
      },
      onError: (error, stack) => sendEvent(TodosRefreshFailedEvent(error)),
    );
```

One caveat: with `emitLoading: false` the state never becomes loading, so `loadMore()`'s `isLoading` guard does not block during the refresh — if both can be triggered simultaneously on your screen, add an explicit `isRefreshing` flag to state and check it in `loadMore()`.

### Testing accumulation and the end guard

```dart
class FakePagedTodosHandler
    implements ReadHandler<LoadTodosPageQuery, TodoPage> {
  final pages = {
    null: TodoPage(items: [todoA], cursor: 'c1', hasMore: true),
    'c1': TodoPage(items: [todoB], cursor: null, hasMore: false),
  };

  @override
  Future<TodoPage> read(LoadTodosPageQuery query) async =>
      pages[query.cursor]!;
}
```

```dart
test('loadMore accumulates pages and stops at the end', () async {
  final vm = TodosViewModel(
    mediator: Mediator()..registerQueryHandler(FakePagedTodosHandler()),
  );
  await pumpEventQueue(); // constructor refresh loads page 1

  vm.loadMore();
  await pumpEventQueue();

  expect(vm.state.page, isA<AsyncData<TodoPage>>());
  expect(vm.state.page.requireValue.items, [todoA, todoB]);
  expect(vm.state.page.requireValue.hasMore, isFalse);

  vm.loadMore(); // end guard: no dispatch
  await pumpEventQueue();
  expect(vm.state.page.requireValue.items, [todoA, todoB]);
});
```

### Anti-pattern: restartable pagination

```dart
// ❌ Latest-wins loses pages: a second loadMore silences the in-flight
// page's callbacks (its items never merge) — and the superseded request
// still completes on the backend. Pages need a queue, not a race.
read(
  LoadTodosPageQuery(cursor: loaded.cursor),
  policy: const RunPolicy.restartable(),
  current: page,
  onState: (result) => setState(/* ... */),
);
```

```dart
// ✅ Sequential under the shared default key: every page load queues.
read(
  LoadTodosPageQuery(cursor: loaded.cursor),
  policy: const RunPolicy.sequential(),
  current: page,
  onState: (result) => setState(/* ... */),
);
```

For the full walkthrough — including why the default key is exactly right and how refresh interacts with the queue — see `docs/05_hard_cases.md`. Related skills: `chassis-create-view-model` (dispatch contract and testing seam), `chassis-create-read-query` (the message), `chassis-render-async-state` (rendering `previous`-carrying states), `chassis-handle-errors` (error channels), `chassis-optimistic-update` (the other `current:`-driven hard case).
