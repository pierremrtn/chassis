import 'dart:async';

import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class const TestState({final Async<int> value = const Async.loading()}) {
  TestState copyWith({Async<int>? value}) =>
      TestState(value: value ?? this.value);
}

sealed class TestEvent {}

final class PingEvent implements TestEvent {}

// --- Test messages: they carry the operation to execute, so each test
// controls timing and results while dispatch still goes through a real
// Mediator. ---

final class IntCommand(final Future<int> Function() action)
    extends Command<int>;

final class StringCommand(final Future<String> Function() action)
    extends Command<String>;

final class NullableIntCommand(final Future<int?> Function() action)
    extends Command<int?>;

final class UnregisteredCommand extends Command<int> {}

final class IntReadQuery(final Future<int> Function() action)
    extends ReadQuery<int>;

final class IntWatchQuery(final Stream<int> stream) extends WatchQuery<int>;

final class StringWatchQuery(final Stream<String> stream)
    extends WatchQuery<String>;

/// Its handler throws synchronously (it is not `async*`).
final class ThrowingWatchQuery extends WatchQuery<int> {}

class IntCommandHandler implements CommandHandler<IntCommand, int> {
  @override
  Future<int> run(IntCommand command) => command.action();
}

class StringCommandHandler implements CommandHandler<StringCommand, String> {
  @override
  Future<String> run(StringCommand command) => command.action();
}

class NullableIntCommandHandler
    implements CommandHandler<NullableIntCommand, int?> {
  @override
  Future<int?> run(NullableIntCommand command) => command.action();
}

/// Returns a fixed value, ignoring the command's action — used to tell
/// mediators apart in resolution tests.
class ConstIntCommandHandler(final int value)
    implements CommandHandler<IntCommand, int> {
  @override
  Future<int> run(IntCommand command) async => value;
}

class IntReadHandler implements ReadHandler<IntReadQuery, int> {
  @override
  Future<int> read(IntReadQuery query) => query.action();
}

class IntWatchHandler implements WatchHandler<IntWatchQuery, int> {
  @override
  Stream<int> watch(IntWatchQuery query) => query.stream;
}

class StringWatchHandler implements WatchHandler<StringWatchQuery, String> {
  @override
  Stream<String> watch(StringWatchQuery query) => query.stream;
}

class ThrowingWatchHandler implements WatchHandler<ThrowingWatchQuery, int> {
  @override
  Stream<int> watch(ThrowingWatchQuery query) => throw StateError('sync boom');
}

Mediator buildTestMediator() => Mediator()
  ..registerCommandHandler(IntCommandHandler())
  ..registerCommandHandler(StringCommandHandler())
  ..registerCommandHandler(NullableIntCommandHandler())
  ..registerQueryHandler(IntReadHandler())
  ..registerQueryHandler(IntWatchHandler())
  ..registerQueryHandler(StringWatchHandler())
  ..registerQueryHandler(ThrowingWatchHandler());

class TestViewModel extends ViewModel<TestState, TestEvent> {
  TestViewModel({super.mediator}) : super(const TestState());

  // Expose protected members for testing.
  Future<Async<R>> doRun<R>(
    Command<R> command, {
    Object? key,
    RunPolicy policy = const RunPolicy.concurrent(),
    Async<R>? current,
    AsyncData<R>? optimistic,
    bool emitLoading = true,
    void Function(Async<R> state)? onState,
    void Function(R value)? onSuccess,
    void Function(Object error, StackTrace stack)? onError,
  }) => run(
    command,
    key: key,
    policy: policy,
    current: current,
    optimistic: optimistic,
    emitLoading: emitLoading,
    onState: onState,
    onSuccess: onSuccess,
    onError: onError,
  );

  Future<Async<R>> doRead<R>(
    ReadQuery<R> query, {
    Object? key,
    RunPolicy policy = const RunPolicy.concurrent(),
    Async<R>? current,
    AsyncData<R>? optimistic,
    bool emitLoading = true,
    void Function(Async<R> state)? onState,
    void Function(R value)? onSuccess,
    void Function(Object error, StackTrace stack)? onError,
  }) => read(
    query,
    key: key,
    policy: policy,
    current: current,
    optimistic: optimistic,
    emitLoading: emitLoading,
    onState: onState,
    onSuccess: onSuccess,
    onError: onError,
  );

  WatchHandle doWatch<R>(
    WatchQuery<R> query, {
    Object? key,
    Async<R>? current,
    bool emitLoading = true,
    void Function(Async<R> state)? onState,
    void Function(R data)? onData,
    void Function(Object error, StackTrace stack)? onError,
    void Function()? onDone,
  }) => watch(
    query,
    key: key,
    current: current,
    emitLoading: emitLoading,
    onState: onState,
    onData: onData,
    onError: onError,
    onDone: onDone,
  );

  void doSetState(TestState state) => setState(state);

  void doSendEvent(TestEvent event) => sendEvent(event);
}

/// A ViewModel wired to a fresh real mediator via the constructor override —
/// the recommended test setup (no shared global).
TestViewModel vmWith() => TestViewModel(mediator: buildTestMediator());

void main() {
  setUp(Chassis.reset);
  tearDown(Chassis.reset);

  group('ViewModel.setState', () {
    test('updates state and notifies listeners', () {
      final vm = TestViewModel();
      var notified = 0;
      vm.addListener(() => notified++);

      vm.doSetState(const TestState(value: Async.data(1)));

      expect(vm.state.value, const Async.data(1));
      expect(notified, 1);
    });
  });

  group('Mediator resolution', () {
    test('dispatch without initialize nor override throws an actionable '
        'StateError', () {
      final vm = TestViewModel();

      expect(
        () => vm.doRun(IntCommand(() async => 1), onSuccess: (_) {}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Chassis.initialize'),
              contains('runApp'),
              contains('mediator: fakeMediator'),
            ),
          ),
        ),
      );
    });

    test(
      'the global mediator installed by Chassis.initialize is used',
      () async {
        Chassis.initialize(
          Mediator()..registerCommandHandler(ConstIntCommandHandler(1)),
        );
        final vm = TestViewModel();

        final result = await vm.doRun(
          IntCommand(() async => 0),
          onSuccess: (_) {},
        );

        expect(result, const Async.data(1));
      },
    );

    test('the constructor override wins over the global', () async {
      Chassis.initialize(
        Mediator()..registerCommandHandler(ConstIntCommandHandler(1)),
      );
      final vm = TestViewModel(
        mediator: Mediator()..registerCommandHandler(ConstIntCommandHandler(2)),
      );

      final result = await vm.doRun(
        IntCommand(() async => 0),
        onSuccess: (_) {},
      );

      expect(result, const Async.data(2));
    });

    test('a missing handler surfaces as a soft AsyncError', () async {
      final vm = vmWith();

      final result = await vm.doRun(UnregisteredCommand(), onError: (_, __) {});

      expect(result.errorOrNull, isA<HandlerNotRegisteredError>());
    });
  });

  group('ViewModel.run', () {
    test('onState receives loading then data', () async {
      final vm = vmWith();
      final states = <Async<int>>[];

      final result = await vm.doRun(
        IntCommand(() => Future.value(42)),
        onState: states.add,
      );

      expect(states, [const Async<int>.loading(), const Async.data(42)]);
      expect(result, const Async.data(42));
    });

    test('onState receives loading then error', () async {
      final vm = vmWith();
      final states = <Async<int>>[];

      final result = await vm.doRun(
        IntCommand(() => Future<int>.error(StateError('boom'))),
        onState: states.add,
      );

      expect(states.first, const Async<int>.loading());
      expect(states.last, isA<AsyncError<int>>());
      expect(result.hasError, isTrue);
    });

    test('onState AND onSuccess both receive the data', () async {
      final vm = vmWith();
      final states = <Async<int>>[];
      int? data;

      await vm.doRun(
        IntCommand(() => Future.value(7)),
        onState: states.add,
        onSuccess: (d) => data = d,
      );

      expect(states.last, const Async.data(7));
      expect(data, 7);
    });

    test('onState AND onError both receive the error', () async {
      final vm = vmWith();
      final states = <Async<int>>[];
      Object? error;

      await vm.doRun(
        IntCommand(() => Future<int>.error(StateError('boom'))),
        onState: states.add,
        onError: (e, s) => error = e,
      );

      expect(states.last, isA<AsyncError<int>>());
      expect(error, isA<StateError>());
    });

    test('onError receives the failure stack trace', () async {
      final vm = vmWith();
      StackTrace? stack;

      await vm.doRun(
        IntCommand(() async => throw StateError('boom')),
        onError: (e, s) => stack = s,
      );

      expect(stack, isNotNull);
      expect(stack.toString(), isNotEmpty);
    });

    test('onSuccess alone works and errors are still returned', () async {
      final vm = vmWith();
      int? data;

      final ok = await vm.doRun(
        IntCommand(() => Future.value(1)),
        onSuccess: (d) => data = d,
      );
      expect(data, 1);
      expect(ok, const Async.data(1));

      final ko = await vm.doRun(
        IntCommand(() => Future<int>.error(StateError('x'))),
        onSuccess: (d) => data = d,
      );
      expect(ko.hasError, isTrue);
      expect(data, 1, reason: 'onSuccess must not fire on error');
    });

    test(
      'a throwing onSuccess does NOT convert success into AsyncError',
      () async {
        final vm = vmWith();

        await expectLater(
          vm.doRun(
            IntCommand(() => Future.value(1)),
            onSuccess: (_) => throw StateError('callback bug'),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'callback bug',
            ),
          ),
        );
      },
    );

    test(
      'current propagates previous data into loading and error states',
      () async {
        final vm = vmWith();
        final states = <Async<int>>[];

        await vm.doRun(
          IntCommand(() => Future<int>.error(StateError('refresh failed'))),
          current: const Async.data(5),
          onState: states.add,
        );

        // Loading keeps showing 5, and so does the soft error.
        expect(states.first.isLoading, isTrue);
        expect(states.first.valueOrNull, 5);
        expect(states.last.hasError, isTrue);
        expect(states.last.valueOrNull, 5);
      },
    );

    test('emitLoading: false skips the loading emission', () async {
      final vm = vmWith();
      final states = <Async<int>>[];

      await vm.doRun(
        IntCommand(() => Future.value(3)),
        emitLoading: false,
        onState: states.add,
      );

      expect(states, [const Async.data(3)]);
    });

    test('callbacks are not invoked after dispose', () async {
      final vm = vmWith();
      final completer = Completer<int>();
      final states = <Async<int>>[];

      final future = vm.doRun(
        IntCommand(() => completer.future),
        onState: states.add,
      );
      vm.dispose();
      completer.complete(9);
      final result = await future;

      expect(result, const Async.data(9));
      expect(states, [
        const Async<int>.loading(),
      ], reason: 'only the pre-dispose loading emission is delivered');
    });

    test(
      'sharing a key across incompatible result types asserts in debug',
      () async {
        final vm = vmWith();

        await vm.doRun(
          IntCommand(() => Future.value(1)),
          key: #shared,
          onSuccess: (_) {},
        );

        expect(
          () => vm.doRun(
            StringCommand(() => Future.value('x')),
            key: #shared,
            onSuccess: (_) {},
          ),
          throwsA(
            isA<AssertionError>().having(
              (e) => e.message.toString(),
              'message',
              allOf(contains('shared'), contains('int'), contains('String')),
            ),
          ),
        );
      },
    );
  });

  group('ViewModel.read', () {
    test('dispatches a ReadQuery with the same lifecycle as run', () async {
      final vm = vmWith();
      final states = <Async<int>>[];

      final result = await vm.doRead(
        IntReadQuery(() => Future.value(5)),
        onState: states.add,
      );

      expect(states, [const Async<int>.loading(), const Async.data(5)]);
      expect(result, const Async.data(5));
    });

    test('a restartable refetch is keyed by query type by default', () async {
      final vm = vmWith();
      final states = <Async<int>>[];
      final slow = Completer<int>();

      final first = vm.doRead(
        IntReadQuery(() => slow.future),
        policy: const RunPolicy.restartable(),
        onState: states.add,
      );
      final second = vm.doRead(
        IntReadQuery(() => Future.value(2)),
        policy: const RunPolicy.restartable(),
        onState: states.add,
      );
      await second;
      slow.complete(1);
      await first;

      expect(states.last, const Async.data(2));
      expect(
        states.where((s) => s == const Async.data(1)),
        isEmpty,
        reason: 'the superseded refetch must not report',
      );
    });
  });

  group('ViewModel.run optimistic', () {
    test('emits the optimistic data at dispatch instead of loading', () async {
      final vm = vmWith();
      final states = <Async<int>>[];

      final result = await vm.doRun(
        IntCommand(() => Future.value(42)),
        current: const Async.data(1),
        optimistic: const AsyncData(41),
        onState: states.add,
      );

      expect(states, [const AsyncData(41), const AsyncData(42)]);
      expect(result, const Async.data(42));
    });

    test('is emitted even with emitLoading: false', () async {
      final vm = vmWith();
      final states = <Async<int>>[];

      await vm.doRun(
        IntCommand(() => Future.value(42)),
        optimistic: const AsyncData(41),
        emitLoading: false,
        onState: states.add,
      );

      expect(states, [const AsyncData(41), const AsyncData(42)]);
    });

    test('onSuccess fires only for the real result', () async {
      final vm = vmWith();
      final successes = <int>[];

      await vm.doRun(
        IntCommand(() => Future.value(42)),
        optimistic: const AsyncData(41),
        onState: (_) {},
        onSuccess: successes.add,
      );

      expect(successes, [42]);
    });

    test('failure rolls back to the data carried by current', () async {
      final vm = vmWith();
      final states = <Async<int>>[];

      final result = await vm.doRun(
        IntCommand(() => Future<int>.error(StateError('boom'))),
        current: const Async.data(1),
        optimistic: const AsyncData(41),
        onState: states.add,
      );

      expect(states.first, const AsyncData(41));
      expect(
        states.last,
        isA<AsyncError<int>>().having(
          (e) => e.previous,
          'previous',
          const AsyncData(1),
        ),
        reason: 'previous is the confirmed value, never the optimistic one',
      );
      expect(result, states.last);
    });

    test('failure with no prior data reports a bare error', () async {
      final vm = vmWith();
      final states = <Async<int>>[];

      await vm.doRun(
        IntCommand(() => Future<int>.error(StateError('boom'))),
        optimistic: const AsyncData(41),
        onState: states.add,
      );

      expect(
        states.last,
        isA<AsyncError<int>>().having((e) => e.previous, 'previous', isNull),
      );
    });

    test('failure restores an intermediate confirmed completion, '
        'not the call-time snapshot', () async {
      final vm = vmWith();
      final gate = Completer<int>();

      // Optimistic run in flight; its call-time snapshot carries 1.
      final failing = vm.doRun(
        IntCommand(() => gate.future),
        key: #k,
        current: const Async.data(1),
        optimistic: const AsyncData(41),
        onState: (_) {},
      );

      // Another run on the same key completes with confirmed data meanwhile.
      await vm.doRun(
        IntCommand(() => Future.value(2)),
        key: #k,
        current: const Async.data(41),
        onState: (_) {},
      );

      gate.completeError(StateError('boom'));
      final result = await failing;

      expect(
        result,
        isA<AsyncError<int>>().having(
          (e) => e.previous,
          'previous',
          const AsyncData(2),
        ),
        reason: 'rollback targets the freshest confirmed truth on the key',
      );
    });

    test('AsyncData(null) is a real optimistic value for nullable T', () async {
      final vm = vmWith();
      final states = <Async<int?>>[];

      await vm.doRun<int?>(
        NullableIntCommand(() => Future.value(7)),
        current: const Async<int?>.data(3),
        optimistic: const AsyncData<int?>(null),
        onState: states.add,
      );

      expect(states.first, const AsyncData<int?>(null));
      expect(
        states.first.hasValue,
        isTrue,
        reason: 'null was produced optimistically — it counts as data',
      );
      expect(states.last, const AsyncData<int?>(7));
    });

    test('optimistic without onState throws an assertion', () {
      final vm = vmWith();
      expect(
        () => vm.doRun(
          IntCommand(() => Future.value(1)),
          optimistic: const AsyncData(0),
          onSuccess: (_) {},
        ),
        throwsAssertionError,
      );
    });
  });

  group('ViewModel.run policies', () {
    test('concurrent (default): overlapping completions interleave', () async {
      final vm = vmWith();
      final states = <Async<int>>[];
      final slow = Completer<int>();

      final first = vm.doRun(
        IntCommand(() => slow.future),
        onState: states.add,
      );
      await vm.doRun(IntCommand(() => Future.value(2)), onState: states.add);
      slow.complete(1);
      await first;

      // The old dispatch writes last: this is the documented unsafe default.
      expect(states.last, const Async.data(1));
    });

    test('policies apply per message type without an explicit key', () async {
      final vm = vmWith();
      final states = <Async<int>>[];
      final slow = Completer<int>();

      final first = vm.doRun(
        IntCommand(() => slow.future),
        policy: const RunPolicy.restartable(),
        onState: states.add,
      );
      final second = vm.doRun(
        IntCommand(() => Future.value(2)),
        policy: const RunPolicy.restartable(),
        onState: states.add,
      );
      await second;
      slow.complete(1);
      await first;

      expect(
        states.last,
        const Async.data(2),
        reason:
            'two dispatches of the same command class share the '
            'default key (their runtime type)',
      );
      expect(states.where((s) => s == const Async.data(1)), isEmpty);
    });

    test('restartable: a newer run invalidates in-flight callbacks', () async {
      final vm = vmWith();
      final states = <Async<int>>[];
      final slow = Completer<int>();

      final first = vm.doRun(
        IntCommand(() => slow.future),
        key: #load,
        policy: const RunPolicy.restartable(),
        onState: states.add,
      );
      final second = vm.doRun(
        IntCommand(() => Future.value(2)),
        key: #load,
        policy: const RunPolicy.restartable(),
        onState: states.add,
      );
      await second;
      slow.complete(1);
      final firstResult = await first;

      expect(
        states.last,
        const Async.data(2),
        reason: 'the superseded run must not write after the newer one',
      );
      expect(states.where((s) => s == const Async.data(1)), isEmpty);
      expect(
        firstResult,
        const Async.data(1),
        reason: 'the superseded run still returns its own result',
      );
    });

    test(
      'restartable with debounce: bursts coalesce into the latest call',
      () async {
        final vm = vmWith();
        final states = <Async<int>>[];
        var dispatches = 0;

        Future<Async<int>> call(int value) => vm.doRun(
          IntCommand(() {
            dispatches++;
            return Future.value(value);
          }),
          key: #search,
          policy: const RunPolicy.restartable(
            debounce: Duration(milliseconds: 20),
          ),
          onState: states.add,
        );

        final futures = [call(1), call(2), call(3)];
        final results = await Future.wait(futures);

        expect(dispatches, 1, reason: 'only the latest call dispatches');
        expect(states, [const Async<int>.loading(), const Async.data(3)]);
        expect(
          results,
          everyElement(const Async.data(3)),
          reason: 'coalesced callers resolve with the winning result',
        );
      },
    );

    test('restartable debounce: dispose before the window fires', () async {
      final vm = vmWith();
      var dispatched = false;

      final pending = vm.doRun(
        IntCommand(() {
          dispatched = true;
          return Future.value(1);
        }),
        key: #search,
        policy: const RunPolicy.restartable(
          debounce: Duration(milliseconds: 50),
        ),
        onSuccess: (_) {},
      );
      vm.dispose();
      final result = await pending;

      expect(dispatched, isFalse);
      expect(result.errorOrNull, isA<StateError>());
    });

    test('droppable: calls made while in flight are dropped', () async {
      final vm = vmWith();
      final slow = Completer<int>();
      var droppedDispatched = false;

      final first = vm.doRun(
        IntCommand(() => slow.future),
        key: #submit,
        policy: const RunPolicy.droppable(),
        onSuccess: (_) {},
      );
      final second = vm.doRun(
        IntCommand(() {
          droppedDispatched = true;
          return Future.value(2);
        }),
        key: #submit,
        policy: const RunPolicy.droppable(),
        onSuccess: (_) {},
      );
      slow.complete(1);
      final results = await Future.wait([first, second]);

      expect(droppedDispatched, isFalse);
      expect(
        results,
        everyElement(const Async.data(1)),
        reason: 'the dropped call resolves with the in-flight result',
      );

      // Once the flight lands, the key is free again.
      final third = await vm.doRun(
        IntCommand(() => Future.value(3)),
        key: #submit,
        policy: const RunPolicy.droppable(),
        onSuccess: (_) {},
      );
      expect(third, const Async.data(3));
    });

    test('sequential: runs execute one at a time, in call order', () async {
      final vm = vmWith();
      final log = <String>[];
      final gate = Completer<void>();

      final first = vm.doRun(
        IntCommand(() async {
          log.add('start:1');
          await gate.future;
          log.add('end:1');
          return 1;
        }),
        key: #queue,
        policy: const RunPolicy.sequential(),
        onSuccess: (_) {},
      );
      final second = vm.doRun(
        IntCommand(() async {
          log.add('start:2');
          return 2;
        }),
        key: #queue,
        policy: const RunPolicy.sequential(),
        onSuccess: (_) {},
      );
      await pumpEventQueue();
      expect(log, [
        'start:1',
      ], reason: 'the second run must wait for the first');

      gate.complete();
      await Future.wait([first, second]);
      expect(log, ['start:1', 'end:1', 'start:2']);
    });

    test('keys are independent across policies', () async {
      final vm = vmWith();
      final slow = Completer<int>();
      var otherDispatched = false;

      final first = vm.doRun(
        IntCommand(() => slow.future),
        key: #a,
        policy: const RunPolicy.droppable(),
        onSuccess: (_) {},
      );
      await vm.doRun(
        IntCommand(() {
          otherDispatched = true;
          return Future.value(2);
        }),
        key: #b,
        policy: const RunPolicy.droppable(),
        onSuccess: (_) {},
      );

      expect(otherDispatched, isTrue);
      slow.complete(1);
      await first;
    });
  });

  group('ViewModel.watch', () {
    test(
      'onState receives loading, data, and soft errors carrying data',
      () async {
        final vm = vmWith();
        final states = <Async<int>>[];
        final controller = StreamController<int>();

        vm.doWatch(IntWatchQuery(controller.stream), onState: states.add);
        controller.add(1);
        controller.addError(StateError('x'));
        controller.add(2);
        await pumpEventQueue();

        expect(states[0], const Async<int>.loading());
        expect(states[1], const Async.data(1));
        expect(states[2].hasError, isTrue);
        expect(
          states[2].valueOrNull,
          1,
          reason: 'soft error carries last data',
        );
        expect(states[3], const Async.data(2));

        await controller.close();
      },
    );

    test('onData and onError fire in addition to onState', () async {
      final vm = vmWith();
      final states = <Async<int>>[];
      final data = <int>[];
      final errors = <Object>[];
      final stacks = <StackTrace>[];
      final controller = StreamController<int>();

      vm.doWatch(
        IntWatchQuery(controller.stream),
        onState: states.add,
        onData: data.add,
        onError: (e, s) {
          errors.add(e);
          stacks.add(s);
        },
      );
      controller.add(1);
      controller.addError(StateError('x'));
      await pumpEventQueue();

      expect(states.length, 3); // loading, data, error
      expect(data, [1]);
      expect(errors.single, isA<StateError>());
      expect(stacks, hasLength(1));

      await controller.close();
    });

    test(
      'a handler throwing synchronously reports an AsyncError, not a crash',
      () async {
        final vm = vmWith();
        final states = <Async<int>>[];
        Object? error;

        final handle = vm.doWatch(
          ThrowingWatchQuery(),
          current: const Async.data(9),
          onState: states.add,
          onError: (e, s) => error = e,
        );

        expect(states.first.isLoading, isTrue);
        expect(states.last, isA<AsyncError<int>>());
        expect(
          states.last.valueOrNull,
          9,
          reason: 'the synchronous failure is a soft error like any other',
        );
        expect(error, isA<StateError>());
        expect(handle.isCancelled, isTrue);
      },
    );

    test(
      're-watching the same query type replaces the previous subscription',
      () async {
        final vm = vmWith();
        final received = <String>[];
        final first = StreamController<String>();
        final second = StreamController<String>();

        vm.doWatch(StringWatchQuery(first.stream), onData: received.add);
        first.add('a');
        await pumpEventQueue();

        vm.doWatch(StringWatchQuery(second.stream), onData: received.add);
        first.add('LEAKED');
        second.add('b');
        await pumpEventQueue();

        expect(
          received,
          ['a', 'b'],
          reason:
              'watches are keyed by query type by default: the replaced '
              'subscription must not deliver events',
        );
        expect(first.hasListener, isFalse);

        await first.close();
        await second.close();
      },
    );

    test(
      'explicit distinct keys make watches of the same query additive',
      () async {
        final vm = vmWith();
        final received = <String>[];
        final source = StreamController<String>.broadcast();

        vm.doWatch(
          StringWatchQuery(source.stream),
          key: #one,
          onData: (d) => received.add('1:$d'),
        );
        vm.doWatch(
          StringWatchQuery(source.stream),
          key: #two,
          onData: (d) => received.add('2:$d'),
        );
        source.add('x');
        await pumpEventQueue();

        expect(received, ['1:x', '2:x']);
        await source.close();
      },
    );

    test('WatchHandle.cancel stops delivery', () async {
      final vm = vmWith();
      final received = <int>[];
      final controller = StreamController<int>();

      final handle = vm.doWatch(
        IntWatchQuery(controller.stream),
        onData: received.add,
      );
      controller.add(1);
      await pumpEventQueue();
      await handle.cancel();
      controller.add(2);
      await pumpEventQueue();

      expect(received, [1]);
      expect(handle.isCancelled, isTrue);

      await controller.close();
    });

    test('dispose cancels all subscriptions', () async {
      final vm = vmWith();
      final keyed = StreamController<int>();
      final defaultKeyed = StreamController<String>();

      vm.doWatch(IntWatchQuery(keyed.stream), key: #k, onData: (_) {});
      vm.doWatch(StringWatchQuery(defaultKeyed.stream), onData: (_) {});
      vm.dispose();
      await pumpEventQueue();

      expect(keyed.hasListener, isFalse);
      expect(defaultKeyed.hasListener, isFalse);

      await keyed.close();
      await defaultKeyed.close();
    });

    test(
      'onDone fires when the stream completes, after the last data',
      () async {
        final vm = vmWith();
        final log = <String>[];

        final handle = vm.doWatch(
          IntWatchQuery(Stream.fromIterable([1, 2])),
          onData: (d) => log.add('data:$d'),
          onDone: () => log.add('done'),
        );
        await pumpEventQueue();

        expect(log, ['data:1', 'data:2', 'done']);
        expect(
          handle.isCancelled,
          isTrue,
          reason: 'a completed stream releases its handle',
        );
      },
    );

    test('onDone alone satisfies the callback assert', () async {
      final vm = vmWith();
      var done = false;

      vm.doWatch(
        IntWatchQuery(const Stream<int>.empty()),
        onDone: () => done = true,
      );
      await pumpEventQueue();

      expect(done, isTrue);
    });

    test(
      'onDone does not fire on keyed replacement or manual cancel',
      () async {
        final vm = vmWith();
        var doneCalls = 0;
        final first = StreamController<int>();
        final second = StreamController<int>();

        vm.doWatch(
          IntWatchQuery(first.stream),
          key: #k,
          onData: (_) {},
          onDone: () => doneCalls++,
        );
        vm.doWatch(
          IntWatchQuery(second.stream),
          key: #k,
          onData: (_) {},
          onDone: () => doneCalls++,
        );

        final handle = vm.doWatch(
          IntWatchQuery(StreamController<int>().stream),
          key: #other,
          onData: (_) {},
          onDone: () => doneCalls++,
        );
        await handle.cancel();
        await pumpEventQueue();

        expect(
          doneCalls,
          0,
          reason: 'cancellation is not completion: onDone must not fire',
        );

        await first.close();
        await second.close();
        await pumpEventQueue();
        expect(
          doneCalls,
          1,
          reason: 'only the still-subscribed stream reports completion',
        );
      },
    );

    test('onDone is not invoked after dispose', () async {
      final vm = vmWith();
      var done = false;
      final controller = StreamController<int>.broadcast();

      vm.doWatch(
        IntWatchQuery(controller.stream),
        onData: (_) {},
        onDone: () => done = true,
      );
      vm.dispose();
      await controller.close();
      await pumpEventQueue();

      expect(done, isFalse);
    });

    test('onDone can start a replacement watch under the same key', () async {
      final vm = vmWith();
      final received = <int>[];
      final second = StreamController<int>();

      vm.doWatch(
        IntWatchQuery(Stream.fromIterable([1])),
        key: #k,
        onData: received.add,
        onDone: () => vm.doWatch(
          IntWatchQuery(second.stream),
          key: #k,
          onData: received.add,
        ),
      );
      await pumpEventQueue();
      second.add(2);
      await pumpEventQueue();

      expect(received, [1, 2]);
      await second.close();
    });
  });

  group('ViewModel.events', () {
    test('events emitted before the first subscription are buffered', () async {
      final vm = TestViewModel();
      vm.doSendEvent(PingEvent());
      vm.doSendEvent(PingEvent());

      final received = <TestEvent>[];
      vm.events.listen(received.add);
      await pumpEventQueue();

      expect(received.length, 2);
    });

    test('events flow normally after the first subscription', () async {
      final vm = TestViewModel();
      final received = <TestEvent>[];
      vm.events.listen(received.add);
      await pumpEventQueue();

      vm.doSendEvent(PingEvent());
      await pumpEventQueue();

      expect(received.length, 1);
    });

    test('dispose closes the events stream', () async {
      final vm = TestViewModel();
      var done = false;
      vm.events.listen((_) {}, onDone: () => done = true);
      await pumpEventQueue();

      vm.dispose();
      await pumpEventQueue();

      expect(done, isTrue);
    });

    test('sendEvent after dispose is a no-op', () {
      final vm = TestViewModel();
      vm.dispose();
      expect(() => vm.doSendEvent(PingEvent()), returnsNormally);
    });
  });
}
