import 'dart:async';

import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class TestState {
  const TestState({this.value = const Async.loading()});

  final Async<int> value;

  TestState copyWith({Async<int>? value}) =>
      TestState(value: value ?? this.value);
}

sealed class TestEvent {}

final class PingEvent implements TestEvent {}

class TestViewModel extends ViewModel<TestState, TestEvent> {
  TestViewModel() : super(const TestState());

  // Expose protected members for testing.
  Future<Async<R>> doRun<R>(
    Future<R> Function() operation, {
    Object? key,
    RunPolicy policy = const RunPolicy.concurrent(),
    Async<R>? current,
    bool emitLoading = true,
    void Function(Async<R> state)? onState,
    void Function(R value)? onSuccess,
    void Function(Object error)? onError,
  }) =>
      run(
        operation,
        key: key,
        policy: policy,
        current: current,
        emitLoading: emitLoading,
        onState: onState,
        onSuccess: onSuccess,
        onError: onError,
      );

  WatchHandle doWatch<R>(
    Stream<R> stream, {
    Object? key,
    Async<R>? current,
    bool emitLoading = true,
    void Function(Async<R> state)? onState,
    void Function(R data)? onData,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) =>
      watch(
        stream,
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

void main() {
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

  group('ViewModel.run', () {
    test('onState receives loading then data', () async {
      final vm = TestViewModel();
      final states = <Async<int>>[];

      final result = await vm.doRun(
        () => Future.value(42),
        onState: states.add,
      );

      expect(states, [const Async<int>.loading(), const Async.data(42)]);
      expect(result, const Async.data(42));
    });

    test('onState receives loading then error', () async {
      final vm = TestViewModel();
      final states = <Async<int>>[];

      final result = await vm.doRun(
        () => Future<int>.error(StateError('boom')),
        onState: states.add,
      );

      expect(states.first, const Async<int>.loading());
      expect(states.last, isA<AsyncError<int>>());
      expect(result.hasError, isTrue);
    });

    test('onState AND onSuccess both receive the data', () async {
      final vm = TestViewModel();
      final states = <Async<int>>[];
      int? data;

      await vm.doRun(
        () => Future.value(7),
        onState: states.add,
        onSuccess: (d) => data = d,
      );

      expect(states.last, const Async.data(7));
      expect(data, 7);
    });

    test('onState AND onError both receive the error', () async {
      final vm = TestViewModel();
      final states = <Async<int>>[];
      Object? error;

      await vm.doRun(
        () => Future<int>.error(StateError('boom')),
        onState: states.add,
        onError: (e) => error = e,
      );

      expect(states.last, isA<AsyncError<int>>());
      expect(error, isA<StateError>());
    });

    test('onSuccess alone works and errors are still returned', () async {
      final vm = TestViewModel();
      int? data;

      final ok =
          await vm.doRun(() => Future.value(1), onSuccess: (d) => data = d);
      expect(data, 1);
      expect(ok, const Async.data(1));

      final ko = await vm.doRun(
        () => Future<int>.error(StateError('x')),
        onSuccess: (d) => data = d,
      );
      expect(ko.hasError, isTrue);
      expect(data, 1, reason: 'onSuccess must not fire on error');
    });

    test('a throwing onSuccess does NOT convert success into AsyncError',
        () async {
      final vm = TestViewModel();

      await expectLater(
        vm.doRun(
          () => Future.value(1),
          onSuccess: (_) => throw StateError('callback bug'),
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          'callback bug',
        )),
      );
    });

    test('current propagates previous data into loading and error states',
        () async {
      final vm = TestViewModel();
      final states = <Async<int>>[];

      await vm.doRun(
        () => Future<int>.error(StateError('refresh failed')),
        current: const Async.data(5),
        onState: states.add,
      );

      // Loading keeps showing 5, and so does the soft error.
      expect(states.first.isLoading, isTrue);
      expect(states.first.valueOrNull, 5);
      expect(states.last.hasError, isTrue);
      expect(states.last.valueOrNull, 5);
    });

    test('emitLoading: false skips the loading emission', () async {
      final vm = TestViewModel();
      final states = <Async<int>>[];

      await vm.doRun(() => Future.value(3),
          emitLoading: false, onState: states.add);

      expect(states, [const Async.data(3)]);
    });

    test('callbacks are not invoked after dispose', () async {
      final vm = TestViewModel();
      final completer = Completer<int>();
      final states = <Async<int>>[];

      final future = vm.doRun(() => completer.future, onState: states.add);
      vm.dispose();
      completer.complete(9);
      final result = await future;

      expect(result, const Async.data(9));
      expect(states, [const Async<int>.loading()],
          reason: 'only the pre-dispose loading emission is delivered');
    });
  });

  group('ViewModel.run policies', () {
    test('a non-concurrent policy without a key throws an assertion', () {
      final vm = TestViewModel();
      expect(
        () => vm.doRun(
          () => Future.value(1),
          policy: const RunPolicy.restartable(),
          onSuccess: (_) {},
        ),
        throwsAssertionError,
      );
    });

    test('concurrent (default): overlapping completions interleave', () async {
      final vm = TestViewModel();
      final states = <Async<int>>[];
      final slow = Completer<int>();

      final first = vm.doRun(() => slow.future, onState: states.add);
      await vm.doRun(() => Future.value(2), onState: states.add);
      slow.complete(1);
      await first;

      // The old dispatch writes last: this is the documented unsafe default.
      expect(states.last, const Async.data(1));
    });

    test('restartable: a newer run invalidates in-flight callbacks', () async {
      final vm = TestViewModel();
      final states = <Async<int>>[];
      final slow = Completer<int>();

      final first = vm.doRun(
        () => slow.future,
        key: #load,
        policy: const RunPolicy.restartable(),
        onState: states.add,
      );
      final second = vm.doRun(
        () => Future.value(2),
        key: #load,
        policy: const RunPolicy.restartable(),
        onState: states.add,
      );
      await second;
      slow.complete(1);
      final firstResult = await first;

      expect(states.last, const Async.data(2),
          reason: 'the superseded run must not write after the newer one');
      expect(states.where((s) => s == const Async.data(1)), isEmpty);
      expect(firstResult, const Async.data(1),
          reason: 'the superseded run still returns its own result');
    });

    test('restartable with debounce: bursts coalesce into the latest call',
        () async {
      final vm = TestViewModel();
      final states = <Async<int>>[];
      var dispatches = 0;

      Future<Async<int>> call(int value) => vm.doRun(
            () {
              dispatches++;
              return Future.value(value);
            },
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
      expect(results, everyElement(const Async.data(3)),
          reason: 'coalesced callers resolve with the winning result');
    });

    test('restartable debounce: dispose before the window fires', () async {
      final vm = TestViewModel();
      var dispatched = false;

      final pending = vm.doRun(
        () {
          dispatched = true;
          return Future.value(1);
        },
        key: #search,
        policy:
            const RunPolicy.restartable(debounce: Duration(milliseconds: 50)),
        onSuccess: (_) {},
      );
      vm.dispose();
      final result = await pending;

      expect(dispatched, isFalse);
      expect(result.errorOrNull, isA<StateError>());
    });

    test('droppable: calls made while in flight are dropped', () async {
      final vm = TestViewModel();
      final slow = Completer<int>();
      var droppedDispatched = false;

      final first = vm.doRun(
        () => slow.future,
        key: #submit,
        policy: const RunPolicy.droppable(),
        onSuccess: (_) {},
      );
      final second = vm.doRun(
        () {
          droppedDispatched = true;
          return Future.value(2);
        },
        key: #submit,
        policy: const RunPolicy.droppable(),
        onSuccess: (_) {},
      );
      slow.complete(1);
      final results = await Future.wait([first, second]);

      expect(droppedDispatched, isFalse);
      expect(results, everyElement(const Async.data(1)),
          reason: 'the dropped call resolves with the in-flight result');

      // Once the flight lands, the key is free again.
      final third = await vm.doRun(
        () => Future.value(3),
        key: #submit,
        policy: const RunPolicy.droppable(),
        onSuccess: (_) {},
      );
      expect(third, const Async.data(3));
    });

    test('sequential: runs execute one at a time, in call order', () async {
      final vm = TestViewModel();
      final log = <String>[];
      final gate = Completer<void>();

      final first = vm.doRun(
        () async {
          log.add('start:1');
          await gate.future;
          log.add('end:1');
          return 1;
        },
        key: #queue,
        policy: const RunPolicy.sequential(),
        onSuccess: (_) {},
      );
      final second = vm.doRun(
        () async {
          log.add('start:2');
          return 2;
        },
        key: #queue,
        policy: const RunPolicy.sequential(),
        onSuccess: (_) {},
      );
      await pumpEventQueue();
      expect(log, ['start:1'],
          reason: 'the second run must wait for the first');

      gate.complete();
      await Future.wait([first, second]);
      expect(log, ['start:1', 'end:1', 'start:2']);
    });

    test('keys are independent across policies', () async {
      final vm = TestViewModel();
      final slow = Completer<int>();
      var otherDispatched = false;

      final first = vm.doRun(
        () => slow.future,
        key: #a,
        policy: const RunPolicy.droppable(),
        onSuccess: (_) {},
      );
      await vm.doRun(
        () {
          otherDispatched = true;
          return Future.value(2);
        },
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
    test('onState receives loading, data, and soft errors carrying data',
        () async {
      final vm = TestViewModel();
      final states = <Async<int>>[];
      final controller = StreamController<int>();

      vm.doWatch(controller.stream, onState: states.add);
      controller.add(1);
      controller.addError(StateError('x'));
      controller.add(2);
      await pumpEventQueue();

      expect(states[0], const Async<int>.loading());
      expect(states[1], const Async.data(1));
      expect(states[2].hasError, isTrue);
      expect(states[2].valueOrNull, 1, reason: 'soft error carries last data');
      expect(states[3], const Async.data(2));

      await controller.close();
    });

    test('onData and onError fire in addition to onState', () async {
      final vm = TestViewModel();
      final states = <Async<int>>[];
      final data = <int>[];
      final errors = <Object>[];
      final controller = StreamController<int>();

      vm.doWatch(
        controller.stream,
        onState: states.add,
        onData: data.add,
        onError: errors.add,
      );
      controller.add(1);
      controller.addError(StateError('x'));
      await pumpEventQueue();

      expect(states.length, 3); // loading, data, error
      expect(data, [1]);
      expect(errors.single, isA<StateError>());

      await controller.close();
    });

    test('re-watching with the same key cancels the previous subscription',
        () async {
      final vm = TestViewModel();
      final received = <String>[];
      final first = StreamController<String>();
      final second = StreamController<String>();

      vm.doWatch(first.stream, key: #user, onData: received.add);
      first.add('a');
      await pumpEventQueue();

      vm.doWatch(second.stream, key: #user, onData: received.add);
      first.add('LEAKED');
      second.add('b');
      await pumpEventQueue();

      expect(received, ['a', 'b'],
          reason: 'the replaced subscription must not deliver events');
      expect(first.hasListener, isFalse);

      await first.close();
      await second.close();
    });

    test('watches without key are additive', () async {
      final vm = TestViewModel();
      final received = <String>[];
      final first = StreamController<String>.broadcast();

      vm.doWatch(first.stream, onData: (d) => received.add('1:$d'));
      vm.doWatch(first.stream, onData: (d) => received.add('2:$d'));
      first.add('x');
      await pumpEventQueue();

      expect(received, ['1:x', '2:x']);
      await first.close();
    });

    test('WatchHandle.cancel stops delivery', () async {
      final vm = TestViewModel();
      final received = <int>[];
      final controller = StreamController<int>();

      final handle = vm.doWatch(controller.stream, onData: received.add);
      controller.add(1);
      await pumpEventQueue();
      await handle.cancel();
      controller.add(2);
      await pumpEventQueue();

      expect(received, [1]);
      expect(handle.isCancelled, isTrue);

      await controller.close();
    });

    test('dispose cancels keyed and unkeyed subscriptions', () async {
      final vm = TestViewModel();
      final keyed = StreamController<int>();
      final unkeyed = StreamController<int>();

      vm.doWatch(keyed.stream, key: #k, onData: (_) {});
      vm.doWatch(unkeyed.stream, onData: (_) {});
      vm.dispose();
      await pumpEventQueue();

      expect(keyed.hasListener, isFalse);
      expect(unkeyed.hasListener, isFalse);

      await keyed.close();
      await unkeyed.close();
    });

    test('onDone fires when the stream completes, after the last data',
        () async {
      final vm = TestViewModel();
      final log = <String>[];

      final handle = vm.doWatch(
        Stream.fromIterable([1, 2]),
        onData: (d) => log.add('data:$d'),
        onDone: () => log.add('done'),
      );
      await pumpEventQueue();

      expect(log, ['data:1', 'data:2', 'done']);
      expect(handle.isCancelled, isTrue,
          reason: 'a completed stream releases its handle');
    });

    test('onDone alone satisfies the callback assert', () async {
      final vm = TestViewModel();
      var done = false;

      vm.doWatch(const Stream<int>.empty(), onDone: () => done = true);
      await pumpEventQueue();

      expect(done, isTrue);
    });

    test('onDone does not fire on keyed replacement or manual cancel',
        () async {
      final vm = TestViewModel();
      var doneCalls = 0;
      final first = StreamController<int>();
      final second = StreamController<int>();

      vm.doWatch(first.stream,
          key: #k, onData: (_) {}, onDone: () => doneCalls++);
      vm.doWatch(second.stream,
          key: #k, onData: (_) {}, onDone: () => doneCalls++);

      final handle = vm.doWatch(StreamController<int>().stream,
          onData: (_) {}, onDone: () => doneCalls++);
      await handle.cancel();
      await pumpEventQueue();

      expect(doneCalls, 0,
          reason: 'cancellation is not completion: onDone must not fire');

      await first.close();
      await second.close();
      await pumpEventQueue();
      expect(doneCalls, 1,
          reason: 'only the still-subscribed stream reports completion');
    });

    test('onDone is not invoked after dispose', () async {
      final vm = TestViewModel();
      var done = false;
      final controller = StreamController<int>.broadcast();

      vm.doWatch(controller.stream, onData: (_) {}, onDone: () => done = true);
      vm.dispose();
      await controller.close();
      await pumpEventQueue();

      expect(done, isFalse);
    });

    test('onDone can start a replacement watch under the same key', () async {
      final vm = TestViewModel();
      final received = <int>[];
      final second = StreamController<int>();

      vm.doWatch(
        Stream.fromIterable([1]),
        key: #k,
        onData: received.add,
        onDone: () => vm.doWatch(second.stream, key: #k, onData: received.add),
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
