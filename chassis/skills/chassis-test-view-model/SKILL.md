---
name: chassis-test-view-model
description: Test a Chassis ViewModel end-to-end by injecting a `TestMediator` (from `package:chassis/testing.dart`) through the constructor's `mediator:` seam — stub the three verbs with closures (`whenRun`/`whenRead`/`whenWatch`; a throwing closure stubs a failure), settle with `pumpEventQueue`, and assert state transitions, emitted events (carrying the error object), and recorded dispatches via structural message equality; never `Chassis.initialize` in tests. Use when adding a `*_view_model_test.dart` file, when a ViewModel gains a new dispatch path, `RunPolicy`, or event that needs coverage, or when replacing hand-rolled fake handler classes or a mocked Mediator.
---
# Testing a Chassis ViewModel

## Contents
- [Core Concepts](#core-concepts)
- [Stubbing the Three Verbs](#stubbing-the-three-verbs)
- [Asserting State Transitions](#asserting-state-transitions)
- [Asserting Events](#asserting-events)
- [Asserting Dispatched Messages](#asserting-dispatched-messages)
- [Testing `RunPolicy` Behavior](#testing-runpolicy-behavior)
- [Testing Watches](#testing-watches)
- [Rules](#rules)
- [Workflow](#workflow)
- [Examples](#examples)

## Core Concepts

A ViewModel dispatches message objects; a ViewModel test controls where they land. The seam is the constructor:

```dart
ViewModel(T initial, {Mediator? mediator});
```

The `mediator:` override always wins over the application mediator installed by `Chassis.initialize`, so a test injects its own dispatch path and never touches the global. **Never call `Chassis.initialize` in a test** — it is process-global state that leaks across test cases; the seam exists precisely so tests never touch it.

`TestMediator` (import `package:chassis/testing.dart` — test files only; it is deliberately not exported from the main library) is a real `Mediator` with two additions:

1. **Closure-based stubs** — `whenRun` / `whenRead` / `whenWatch` register a closure as the handler for one concrete message type, removing the "declare a fake handler class per stub" ceremony.
2. **Dispatch recording** — `dispatchedCommands` and `dispatchedQueries` hold every dispatched message in order, for assertions via structural message equality.

```dart
final mediator = TestMediator()
  ..whenRun<AddTodoCommand, Todo>((cmd) async => Todo(cmd.title))
  ..whenRead<GetUserQuery, User>((q) async => testUser)
  ..whenWatch<WatchTodosQuery, List<Todo>>((q) => controller.stream);

final vm = TodoListViewModel(mediator: mediator);
```

Because `TestMediator` *extends* `Mediator`, everything else is production behavior: dispatch routes by the message's concrete runtime type, middlewares traverse, failures surface to the ViewModel as soft `AsyncError`s, and `RunPolicy` arbitration in the ViewModel is untouched. What you are testing is the ViewModel's real orchestration — only the handlers are stubbed.

These tests run under `flutter_test` (chassis_flutter depends on Flutter foundation) but need no widget tree. This skill covers the ViewModel's orchestration — state transitions, events, policies, dispatches. The business logic behind each message belongs in handler unit tests: see `chassis-write-handler-test`.

## Stubbing the Three Verbs

One `when*` call per concrete message type the ViewModel dispatches:

```dart
final mediator = TestMediator()
  // Command → Future
  ..whenRun<AddTodoCommand, Todo>((cmd) async => Todo(cmd.title))
  // ReadQuery → Future
  ..whenRead<GetTodoStatsQuery, TodoStats>((q) async => testStats)
  // WatchQuery → Stream
  ..whenWatch<WatchTodosQuery, List<Todo>>((q) => controller.stream);
```

**Failure stubbing needs no API — the closure throws**, and the error propagates exactly like a failing production handler (the ViewModel reports it as a soft `AsyncError` through its callbacks):

```dart
mediator.whenRun<AddTodoCommand, Todo>(
  (cmd) async => throw TodoLimitReachedException(),
);
```

**The production registration guards apply unchanged** — `when*` registers through the real `Mediator` registration methods:

- A second stub for the same message type throws `DuplicateHandlerError`. To change behavior mid-test, make the closure itself conditional (a counter, a flag, a `Completer`) — don't re-stub.
- A stub keyed by an abstract message type throws `ArgumentError`. Give inference the concrete type: `whenRun<AddTodoCommand, Todo>(...)` or `whenRun((AddTodoCommand cmd) async => ...)`.

Stub **every** message the ViewModel dispatches, including watches started in its constructor. A missing stub does not crash — it surfaces as a soft `AsyncError` (`HandlerNotRegisteredError`) through the ViewModel's callbacks — which means the failure shows up as a confusing assertion mismatch somewhere else.

## Asserting State Transitions

ViewModel methods are synchronous; the dispatch machinery reports asynchronously. The loading emission is synchronous at dispatch, the result lands after the event queue settles:

```dart
vm.loadStats();
expect(vm.state.stats, isA<AsyncLoading<TodoStats>>()); // immediate

await pumpEventQueue(); // settle the dispatch
expect(vm.state.stats, Async.data(testStats));
```

`Async` values have structural equality, so direct comparison works for scalar payloads; for collections or partial assertions use `isA<...>().having(...)` or the `valueOrNull` / `errorOrNull` accessors.

## Asserting Events

`vm.events` is a broadcast stream, but events emitted *before the first subscription* are buffered and delivered to the first subscriber — so subscribing after acting still works:

```dart
vm.addTodo('milk'); // the stub throws

await expectLater(
  vm.events,
  emits(isA<AddTodoFailedEvent>()
      .having((e) => e.error, 'error', isA<TodoLimitReachedException>())),
);
```

**Assert on the error object**, matching its type (and typed fields with `having`). Failure events carry the error object, never `error.toString()` — if a test finds itself matching a message string, the event type is wrong, not the test.

To assert an exact event sequence (or the *absence* of an event), collect into a list first:

```dart
final events = <TodoListEvent>[];
vm.events.listen(events.add);
// ...act...
await pumpEventQueue();
expect(events, [const TodoAddedEvent()]);
```

## Asserting Dispatched Messages

`TestMediator` records every dispatch — `dispatchedCommands` for `run`, `dispatchedQueries` for `read` and `watch` — in dispatch order, before routing (failed dispatches are recorded too). Messages have structural equality (same type + equal `params`), so assertions compare against freshly constructed instances:

```dart
expect(mediator.dispatchedCommands, contains(AddTodoCommand('milk')));
expect(mediator.dispatchedQueries, [WatchTodosQuery()]); // the constructor watch
```

This is how a test proves *what* the ViewModel asked for — the payload the user's action was translated into — independently of what the stub answered.

## Testing `RunPolicy` Behavior

Policies arbitrate runs *in flight*, so the stub must hold the run open while the test dispatches again. Gate the closure with a `Completer`:

```dart
test('a double-tap dispatches AddTodoCommand once', () async {
  final gate = Completer<Todo>();
  final mediator = TestMediator()
    ..whenWatch<WatchTodosQuery, List<Todo>>((q) => const Stream.empty())
    ..whenRun<AddTodoCommand, Todo>((cmd) => gate.future);
  final vm = TodoListViewModel(mediator: mediator);

  vm.addTodo('milk'); // dispatches; the gate holds it in flight
  vm.addTodo('milk'); // droppable: dropped, never reaches the mediator

  gate.complete(const Todo('milk'));
  await pumpEventQueue();

  expect(mediator.dispatchedCommands, [AddTodoCommand('milk')]); // exactly one
});
```

The dispatch record is the proof: a dropped call never reaches the mediator. The same gating technique verifies `restartable` (complete the first gate *after* a second dispatch and assert the superseded result never landed in state — remember `restartable` cuts callbacks, not the underlying execution) and `sequential` (two gates, assert the second dispatch is recorded only after the first completes). For `restartable(debounce: ...)` windows, drive time with `package:fake_async` — `pumpEventQueue` settles the queue but does not advance timers.

## Testing Watches

Drive a watch with a `StreamController` owned by the test — feed emissions, feed errors, close:

```dart
final controller = StreamController<List<Todo>>();
addTearDown(controller.close);
final mediator = TestMediator()
  ..whenWatch<WatchTodosQuery, List<Todo>>((q) => controller.stream);
final vm = TodoListViewModel(mediator: mediator);

controller.add(const [Todo('milk')]);
await pumpEventQueue();
expect(vm.state.todos.valueOrNull, const [Todo('milk')]);
```

A stream error produces a *soft* `AsyncError` carrying the last emission as `previous` — assert both, since anti-flicker rendering depends on it (see the example below). The watch query itself appears in `dispatchedQueries` once, at subscription — not per emission.

## Rules

- **DO** test a ViewModel through the `mediator:` constructor parameter with a `TestMediator` from `package:chassis/testing.dart`. *The override always wins over the global; the real dispatch semantics — routing, middlewares, soft errors, policy arbitration — stay production-faithful.*
- **DO** create one fresh `TestMediator` per test (in the test body or `setUp`). *There is no reset API by design: shared stubs hit `DuplicateHandlerError` on re-stubbing, and recorded dispatches from a previous case corrupt order assertions.*
- **DO** stub every message the ViewModel dispatches, including watches started in the constructor. *A missing stub is a soft `AsyncError` (`HandlerNotRegisteredError`) in state — no crash, only a failure surfacing in the wrong assertion.*
- **DO** stub failures by throwing from the stub closure. *That is the production failure path: the error crosses the mediator and the ViewModel reports it as a soft `AsyncError` — no dedicated failure API to learn.*
- **DO** settle with `await pumpEventQueue()` between acting and asserting results. *ViewModel methods are synchronous; only the loading emission is observable before the queue settles.*
- **DO** assert failure events on the error object: `having((e) => e.error, 'error', isA<TodoLimitReachedException>())`. *Events carry the error object, never `error.toString()` — a test matching a message string is testing the wrong contract.*
- **DO** assert dispatched messages against freshly constructed instances. *Messages have structural equality — same type + equal `params` — so `contains(AddTodoCommand('milk'))` matches with no argument matchers.*
- **DO** gate stubs with a `Completer` when testing `RunPolicy` behavior. *Policies arbitrate runs in flight; an instantly-resolving stub never produces a collision, and the test passes vacuously.*
- **DO** drive watch tests with a `StreamController` registered with `addTearDown(controller.close)`.
- **DON'T** call `Chassis.initialize` in tests. *It is process-global state that leaks across test cases; the constructor seam exists so tests never touch it.*
- **DON'T** mock the `Mediator` class with a mocking framework. *Stubbing the generic `run<R>`/`read<R>`/`watch<R>` methods fights type inference, and a mock drops the real semantics — registration guards, middleware traversal, soft errors — that `TestMediator` keeps.*
- **DON'T** re-stub a message type to change behavior mid-test. *Registration is production registration: the duplicate throws `DuplicateHandlerError`. Make the closure conditional instead.*
- **DON'T** import `package:chassis/testing.dart` outside test files. *It is test infrastructure — deliberately not exported from `package:chassis/chassis.dart`.*
- **DON'T** test handler business logic through the ViewModel. *Validation, orchestration, and error recovery belong in handler unit tests (`chassis-write-handler-test`); here the handler is a stub by construction.*
- **CONSIDER** asserting the full `dispatchedCommands` list (not only `contains`) when order or count matters — double-tap guards, sequential flows, retry logic.
- **CONSIDER** `package:fake_async` for `restartable(debounce: ...)` windows. *`pumpEventQueue` settles microtasks and events but does not advance timers.*

## Workflow

- [ ] **Step 1 — Place the file** at `test/<feature>/<view_model_name>_test.dart`, mirroring the source path. It runs under `flutter test` (no widget tree needed).
- [ ] **Step 2 — Inventory the messages** the ViewModel dispatches: every `run`/`read`/`watch` call, including watches in the constructor. Each needs a stub.
- [ ] **Step 3 — Build a fresh `TestMediator` per test** and stub each message: `whenRun<C, R>` / `whenRead<Q, R>` / `whenWatch<Q, R>` with explicit type arguments. A small helper returning the baseline mediator keeps tests terse.
- [ ] **Step 4 — Construct the ViewModel** with `MyViewModel(mediator: mediator)`.
- [ ] **Step 5 — Act** by calling the synchronous ViewModel method, then `await pumpEventQueue()`.
- [ ] **Step 6 — Assert**: state via `vm.state` (structural `Async` equality or `isA().having(...)`), events via `expectLater(vm.events, emits(...))` or a collected list, dispatches via `mediator.dispatchedCommands` / `dispatchedQueries`.
- [ ] **Step 7 — Cover the failure path** of every dispatch with a throwing stub: assert the `AsyncError` in state for queries, the failure event (error object) for commands.
- [ ] **Step 8 — Cover the concurrency contract** where the ViewModel declares a `RunPolicy`: gate the stub with a `Completer` and assert the dispatch record.
- [ ] **Step 9 — Run** with `flutter test test/<feature>/`.

## Examples

The ViewModel under test (see `chassis-create-view-model` for its anatomy):

```dart
// presentation/todo_list/todo_list_view_model.dart
class TodoListViewModel extends ViewModel<TodoListState, TodoListEvent> {
  TodoListViewModel({super.mediator}) : super(TodoListState.initial()) {
    watch(
      WatchTodosQuery(),
      current: state.todos,
      onState: (todos) => setState(state.copyWith(todos: todos)),
    );
  }

  void addTodo(String title) => run(
        AddTodoCommand(title),
        policy: const RunPolicy.droppable(),
        onSuccess: (_) => sendEvent(const TodoAddedEvent()),
        onError: (error, stack) => sendEvent(AddTodoFailedEvent(error)),
      );

  void loadStats() => read(
        GetTodoStatsQuery(),
        current: state.stats,
        onState: (stats) => setState(state.copyWith(stats: stats)),
      );
}
```

### Full test file: state, events, dispatches, policy, watch

```dart
// test/todo_list/todo_list_view_model_test.dart
import 'dart:async';

import 'package:chassis/testing.dart';
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/application/todos/todos.dart';
import 'package:my_app/domain/todos/todo.dart';
import 'package:my_app/domain/todos/todo_exceptions.dart';
import 'package:my_app/presentation/todo_list/todo_list_view_model.dart';

/// Baseline: the constructor watch is always dispatched, so every test
/// stubs it. Each test gets a FRESH TestMediator.
TestMediator baseMediator() => TestMediator()
  ..whenWatch<WatchTodosQuery, List<Todo>>((q) => const Stream.empty());

void main() {
  const stats = TodoStats(open: 3, done: 7);

  test('loadStats publishes loading then data into state', () async {
    final mediator = baseMediator()
      ..whenRead<GetTodoStatsQuery, TodoStats>((q) async => stats);
    final vm = TodoListViewModel(mediator: mediator);

    vm.loadStats();
    expect(vm.state.stats, isA<AsyncLoading<TodoStats>>());

    await pumpEventQueue();
    expect(vm.state.stats, const Async.data(stats));
    expect(mediator.dispatchedQueries, contains(GetTodoStatsQuery()));
  });

  test('a failing read surfaces as AsyncError in state', () async {
    final mediator = baseMediator()
      ..whenRead<GetTodoStatsQuery, TodoStats>(
        (q) async => throw StatsUnavailableException(),
      );
    final vm = TodoListViewModel(mediator: mediator);

    vm.loadStats();
    await pumpEventQueue();

    expect(vm.state.stats.errorOrNull, isA<StatsUnavailableException>());
  });

  test('addTodo dispatches the command and emits TodoAddedEvent', () async {
    final mediator = baseMediator()
      ..whenRun<AddTodoCommand, Todo>((cmd) async => Todo(cmd.title));
    final vm = TodoListViewModel(mediator: mediator);
    final events = <TodoListEvent>[];
    vm.events.listen(events.add);

    vm.addTodo('milk');
    await pumpEventQueue();

    // Structural equality: a fresh instance matches the dispatched one.
    expect(mediator.dispatchedCommands, [AddTodoCommand('milk')]);
    expect(events, [const TodoAddedEvent()]);
  });

  test('a failed command emits an event carrying the error object', () async {
    final mediator = baseMediator()
      ..whenRun<AddTodoCommand, Todo>(
        (cmd) async => throw TodoLimitReachedException(),
      );
    final vm = TodoListViewModel(mediator: mediator);

    vm.addTodo('milk');

    // Events sent before the first subscription are buffered for it.
    await expectLater(
      vm.events,
      emits(isA<AddTodoFailedEvent>()
          .having((e) => e.error, 'error', isA<TodoLimitReachedException>())),
    );
  });

  test('a double-tap dispatches AddTodoCommand once (droppable)', () async {
    final gate = Completer<Todo>();
    final mediator = baseMediator()
      ..whenRun<AddTodoCommand, Todo>((cmd) => gate.future);
    final vm = TodoListViewModel(mediator: mediator);
    final events = <TodoListEvent>[];
    vm.events.listen(events.add);

    vm.addTodo('milk'); // dispatches; the gate holds it in flight
    vm.addTodo('milk'); // dropped: resolves with the in-flight result

    gate.complete(const Todo('milk'));
    await pumpEventQueue();

    expect(mediator.dispatchedCommands, [AddTodoCommand('milk')]);
    expect(events, [const TodoAddedEvent()]); // one dispatch, one event
  });

  test('watched todos flow into state; a stream error is soft', () async {
    final controller = StreamController<List<Todo>>();
    addTearDown(controller.close);
    final mediator = TestMediator()
      ..whenWatch<WatchTodosQuery, List<Todo>>((q) => controller.stream);
    final vm = TodoListViewModel(mediator: mediator);

    expect(vm.state.todos, isA<AsyncLoading<List<Todo>>>());

    controller.add(const [Todo('milk')]);
    await pumpEventQueue();
    expect(vm.state.todos.valueOrNull, const [Todo('milk')]);

    controller.addError(ConnectionLostException());
    await pumpEventQueue();
    expect(
      vm.state.todos,
      isA<AsyncError<List<Todo>>>()
          .having((s) => s.error, 'error', isA<ConnectionLostException>())
          // Soft error: the last emission survives for anti-flicker rendering.
          .having((s) => s.previous?.value, 'previous', const [Todo('milk')]),
    );
  });
}
```

No `Chassis.initialize` anywhere: each test owns a fresh, isolated dispatch path, and the record on the `TestMediator` proves exactly what the ViewModel dispatched.

### Anti-pattern: mocking the Mediator class

```dart
// ❌ Fights the generic dispatch methods: `any()` under run<R>/read<R> needs
// per-message fallback values and explicit type juggling, and the mock drops
// the real semantics (registration guards, middleware traversal, soft
// errors) that make the test production-faithful.
class MockMediator extends Mock implements Mediator {}
```

```dart
final mediator = MockMediator();
when(() => mediator.run<Todo>(any())).thenAnswer((_) async => testTodo);
```

```dart
// ✅ TestMediator: one line per stub, inference works, real dispatch.
final mediator = TestMediator()
  ..whenRun<AddTodoCommand, Todo>((cmd) async => Todo(cmd.title));
```

### Anti-pattern: sharing a TestMediator across tests

```dart
// ❌ Shared instance: the second test's re-stub throws
// DuplicateHandlerError, and dispatches recorded by the first test corrupt
// the second's order assertions.
final mediator = TestMediator(); // top-level

// ✅ One fresh TestMediator per test, built in the test body or setUp.
```
