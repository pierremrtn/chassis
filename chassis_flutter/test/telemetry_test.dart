import 'dart:async';

import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// --- Test messages: they carry the operation to execute, so each test
// controls timing and results while dispatch still goes through a real
// Mediator. ---

final class IntCommand(final Future<int> Function() action)
    extends Command<int>;

final class IntReadQuery(final Future<int> Function() action)
    extends ReadQuery<int>;

final class IntWatchQuery(final Stream<int> stream) extends WatchQuery<int>;

/// Its handler throws synchronously (it is not `async*`).
final class ThrowingWatchQuery extends WatchQuery<int> {}

class IntCommandHandler implements CommandHandler<IntCommand, int> {
  @override
  Future<int> run(IntCommand command) => command.action();
}

class IntReadHandler implements ReadHandler<IntReadQuery, int> {
  @override
  Future<int> read(IntReadQuery query) => query.action();
}

class IntWatchHandler implements WatchHandler<IntWatchQuery, int> {
  @override
  Stream<int> watch(IntWatchQuery query) => query.stream;
}

class ThrowingWatchHandler implements WatchHandler<ThrowingWatchQuery, int> {
  @override
  Stream<int> watch(ThrowingWatchQuery query) =>
      throw StateError('sync watch failure');
}

/// Records every hook call as a compact string, ids included, so tests
/// assert exact sequences. Ids are deterministic: each instance restarts
/// at 1.
final class RecordingTelemetry extends ChassisTelemetry {
  final List<String> log = [];

  /// The raw results received, for assertions on payloads (e.g. optimistic
  /// rollback carrying the confirmed value in `previous`).
  final List<Async<Object?>> results = [];

  @override
  void viewModelCreated(ViewModel<Object?, Object?> viewModel) {
    log.add('created ${viewModel.runtimeType}');
  }

  @override
  void viewModelDisposed(ViewModel<Object?, Object?> viewModel) {
    log.add('disposed ${viewModel.runtimeType}');
  }

  @override
  void stateChanged(
    ViewModel<Object?, Object?> viewModel,
    Object? previous,
    Object? next,
  ) {
    log.add('state $previous->$next');
  }

  @override
  void eventSent(
    ViewModel<Object?, Object?> viewModel,
    Object? event, {
    required bool buffered,
  }) {
    log.add('event $event${buffered ? ' buffered' : ''}');
  }

  @override
  int dispatchRequested(
    ViewModel<Object?, Object?> viewModel,
    Object message,
    DispatchKind kind,
    Object key,
    RunPolicy policy, {
    required bool optimistic,
  }) {
    final id = super.dispatchRequested(
      viewModel,
      message,
      kind,
      key,
      policy,
      optimistic: optimistic,
    );
    log.add(
      'requested#$id ${message.runtimeType} '
      '${kind.name}${optimistic ? ' optimistic' : ''}',
    );
    return id;
  }

  @override
  void policyOutcome(
    int dispatchId,
    PolicyDecision decision, {
    int? winnerDispatchId,
  }) {
    log.add(
      'policy#$dispatchId ${decision.name}'
      '${winnerDispatchId == null ? '' : ' winner#$winnerDispatchId'}',
    );
  }

  @override
  void dispatchSent(int dispatchId, Object message) {
    log.add('sent#$dispatchId ${message.runtimeType}');
  }

  @override
  void resultReceived(
    int dispatchId,
    Async<Object?> result,
    RunInvalidation invalidation, {
    required bool wasOptimistic,
  }) {
    results.add(result);
    log.add(
      'result#$dispatchId ${result is AsyncData ? 'data' : 'error'} '
      '${invalidation.name}${wasOptimistic ? ' optimistic' : ''}',
    );
  }

  @override
  int watchStarted(
    ViewModel<Object?, Object?> viewModel,
    Object query,
    Object key, {
    required bool replacedPrevious,
  }) {
    final id = super.watchStarted(
      viewModel,
      query,
      key,
      replacedPrevious: replacedPrevious,
    );
    log.add(
      'watchStarted#$id ${query.runtimeType}'
      '${replacedPrevious ? ' replaced-previous' : ''}',
    );
    return id;
  }

  @override
  void watchEmission(int dispatchId, Async<Object?> state) {
    log.add(
      'watchEmission#$dispatchId ${state is AsyncData ? 'data' : 'error'}',
    );
  }

  @override
  void watchEnded(int dispatchId, WatchEndReason reason) {
    log.add('watchEnded#$dispatchId ${reason.name}');
  }
}

/// A hook whose observation methods all throw — proves emissions are
/// guarded.
final class ThrowingTelemetry extends ChassisTelemetry {
  @override
  void stateChanged(
    ViewModel<Object?, Object?> viewModel,
    Object? previous,
    Object? next,
  ) {
    throw StateError('telemetry bug');
  }

  @override
  int dispatchRequested(
    ViewModel<Object?, Object?> viewModel,
    Object message,
    DispatchKind kind,
    Object key,
    RunPolicy policy, {
    required bool optimistic,
  }) {
    throw StateError('telemetry mint bug');
  }
}

/// Records the [DispatchContext] the mediator hands to middlewares.
class ContextSpyMiddleware extends MediatorMiddleware {
  final List<int?> ids = [];

  @override
  Future<R> onRun<R>(
    Command<R> command,
    NextRun<R> next, {
    DispatchContext? context,
  }) {
    ids.add(context?.dispatchId);
    return next(command);
  }

  @override
  Stream<R> onWatch<R>(
    WatchQuery<R> query,
    NextWatch<R> next, {
    DispatchContext? context,
  }) {
    ids.add(context?.dispatchId);
    return next(query);
  }
}

class ProbeViewModel extends ViewModel<int, String> {
  ProbeViewModel() : super(0);

  Future<Async<int>> go(
    Future<int> Function() action, {
    Object? key,
    RunPolicy policy = const RunPolicy.concurrent(),
    Async<int>? current,
    AsyncData<int>? optimistic,
    void Function(Async<int> state)? onState,
  }) => run(
    IntCommand(action),
    key: key,
    policy: policy,
    current: current,
    optimistic: optimistic,
    onState: onState ?? (_) {},
  );

  Future<Async<int>> goRead(Future<int> Function() action) =>
      read(IntReadQuery(action), onState: (_) {});

  WatchHandle look(WatchQuery<int> query, {Object? key}) =>
      watch(query, key: key, onState: (_) {});

  void bump(int value) => setState(value);

  void ping(String event) => sendEvent(event);
}

void main() {
  late Mediator mediator;
  late RecordingTelemetry telemetry;

  setUp(() {
    mediator = Mediator()
      ..registerCommandHandler(IntCommandHandler())
      ..registerQueryHandler(IntReadHandler())
      ..registerQueryHandler(IntWatchHandler())
      ..registerQueryHandler(ThrowingWatchHandler());
    telemetry = RecordingTelemetry();
    Chassis.initialize(mediator, telemetry: telemetry);
  });

  tearDown(Chassis.reset);

  /// A ProbeViewModel with the construction noise already cleared.
  ProbeViewModel probe() {
    final vm = ProbeViewModel();
    telemetry.log.clear();
    return vm;
  }

  group('ViewModel lifecycle', () {
    test('creation and disposal are reported in order', () {
      final vm = ProbeViewModel();
      expect(telemetry.log, ['created ProbeViewModel']);
      vm.dispose();
      expect(telemetry.log, [
        'created ProbeViewModel',
        'disposed ProbeViewModel',
      ]);
    });

    test(
      'active watches end with reason disposed, before viewModelDisposed',
      () {
        final vm = probe();
        final controller = StreamController<int>.broadcast();
        vm.look(IntWatchQuery(controller.stream));
        telemetry.log.clear();

        vm.dispose();
        expect(telemetry.log, [
          'watchEnded#1 disposed',
          'disposed ProbeViewModel',
        ]);
      },
    );
  });

  group('State and events', () {
    test('setState reports previous and next', () {
      final vm = probe();
      vm.bump(1);
      vm.bump(2);
      expect(telemetry.log, ['state 0->1', 'state 1->2']);
    });

    test('events report buffered before the first listener, direct after', () {
      final vm = probe();
      vm.ping('early');
      vm.events.listen((_) {});
      vm.ping('late');
      expect(telemetry.log, ['event early buffered', 'event late']);
    });
  });

  group('run / read', () {
    test('concurrent success: requested → immediate → sent → result', () async {
      final vm = probe();
      await vm.go(() async => 1);
      expect(telemetry.log, [
        'requested#1 IntCommand command',
        'policy#1 immediate',
        'sent#1 IntCommand',
        'result#1 data none',
      ]);
    });

    test('failure reports an error result', () async {
      final vm = probe();
      await vm.go(() async => throw StateError('boom'));
      expect(telemetry.log.last, 'result#1 error none');
    });

    test('read reports kind read', () async {
      final vm = probe();
      await vm.goRead(() async => 1);
      expect(telemetry.log, [
        'requested#1 IntReadQuery read',
        'policy#1 immediate',
        'sent#1 IntReadQuery',
        'result#1 data none',
      ]);
    });

    test('restartable: the superseded run still reports its result', () async {
      final vm = probe();
      final gate = Completer<int>();
      final first = vm.go(
        () => gate.future,
        policy: const RunPolicy.restartable(),
      );
      final second = vm.go(
        () async => 2,
        policy: const RunPolicy.restartable(),
      );
      await second;
      gate.complete(1);
      await first;

      expect(telemetry.log, [
        'requested#1 IntCommand command',
        'policy#1 immediate',
        'sent#1 IntCommand',
        'requested#2 IntCommand command',
        'policy#2 immediate',
        'sent#2 IntCommand',
        'result#2 data none',
        'result#1 data superseded',
      ]);
    });

    test('restartable debounce: N debounced, a single dispatchSent', () async {
      final vm = probe();
      const policy = RunPolicy.restartable(
        debounce: Duration(milliseconds: 20),
      );
      final futures = [
        vm.go(() async => 1, policy: policy),
        vm.go(() async => 2, policy: policy),
        vm.go(() async => 3, policy: policy),
      ];
      await Future.wait(futures);

      expect(telemetry.log.where((e) => e.startsWith('policy')), [
        'policy#1 debounced',
        'policy#2 debounced',
        'policy#3 debounced',
      ]);
      expect(telemetry.log.where((e) => e.startsWith('sent')), [
        'sent#3 IntCommand',
      ]);
      expect(telemetry.log.where((e) => e.startsWith('result')), [
        'result#3 data none',
      ]);
    });

    test('droppable: the dropped call names the winner', () async {
      final vm = probe();
      final gate = Completer<int>();
      final first = vm.go(
        () => gate.future,
        policy: const RunPolicy.droppable(),
      );
      final second = vm.go(
        () async => 99,
        policy: const RunPolicy.droppable(),
      );
      gate.complete(1);
      await Future.wait([first, second]);

      expect(telemetry.log, [
        'requested#1 IntCommand command',
        'policy#1 immediate',
        'sent#1 IntCommand',
        'requested#2 IntCommand command',
        'policy#2 dropped winner#1',
        'result#1 data none',
      ]);
    });

    test('sequential: the second call is queued', () async {
      final vm = probe();
      final gate = Completer<int>();
      final first = vm.go(
        () => gate.future,
        policy: const RunPolicy.sequential(),
      );
      final second = vm.go(
        () async => 2,
        policy: const RunPolicy.sequential(),
      );
      gate.complete(1);
      await Future.wait([first, second]);

      expect(telemetry.log.where((e) => e.startsWith('policy')), [
        'policy#1 immediate',
        'policy#2 queued',
      ]);
    });

    test('optimistic success is flagged on requested and result', () async {
      final vm = probe();
      await vm.go(() async => 5, optimistic: const AsyncData(3));
      expect(telemetry.log, [
        'requested#1 IntCommand command optimistic',
        'policy#1 immediate',
        'sent#1 IntCommand',
        'result#1 data none optimistic',
      ]);
    });

    test('optimistic failure: the result carries the rollback value', () async {
      final vm = probe();
      await vm.go(
        () async => throw StateError('rejected'),
        current: const AsyncData(1),
        optimistic: const AsyncData(3),
      );
      expect(telemetry.log.last, 'result#1 error none optimistic');
      final result = telemetry.results.single;
      result as AsyncError<Object?>;
      expect(result.previous, const AsyncData<Object?>(1));
    });
  });

  group('watch', () {
    test('emissions and completion', () async {
      final vm = probe();
      final controller = StreamController<int>.broadcast();
      vm.look(IntWatchQuery(controller.stream));

      controller.add(1);
      await pumpEventQueue();
      controller.addError(StateError('soft'));
      await pumpEventQueue();
      await controller.close();
      await pumpEventQueue();

      expect(telemetry.log, [
        'watchStarted#1 IntWatchQuery',
        'watchEmission#1 data',
        'watchEmission#1 error',
        'watchEnded#1 done',
      ]);
    });

    test(
      're-watching the same key replaces: ended(replaced) then started',
      () async {
        final vm = probe();
        final a = StreamController<int>.broadcast();
        final b = StreamController<int>.broadcast();
        vm.look(IntWatchQuery(a.stream));
        vm.look(IntWatchQuery(b.stream));

        expect(telemetry.log, [
          'watchStarted#1 IntWatchQuery',
          'watchEnded#1 replaced',
          'watchStarted#2 IntWatchQuery replaced-previous',
        ]);
        vm.dispose();
      },
    );

    test('external cancel reports cancelled', () async {
      final vm = probe();
      final controller = StreamController<int>.broadcast();
      final handle = vm.look(IntWatchQuery(controller.stream));
      await handle.cancel();
      expect(telemetry.log, [
        'watchStarted#1 IntWatchQuery',
        'watchEnded#1 cancelled',
      ]);
    });

    test('synchronous materialization failure reports failedToStart', () {
      final vm = probe();
      final handle = vm.look(ThrowingWatchQuery());
      expect(handle.isCancelled, isTrue);
      expect(telemetry.log, [
        'watchStarted#1 ThrowingWatchQuery',
        'watchEnded#1 failedToStart',
      ]);
    });
  });

  group('Guarding', () {
    test('a throwing hook is reported and never reaches the app', () async {
      Chassis.initialize(mediator, telemetry: ThrowingTelemetry());
      final reported = <FlutterErrorDetails>[];
      final previousHandler = FlutterError.onError;
      FlutterError.onError = reported.add;
      try {
        final vm = ProbeViewModel();
        vm.bump(7);
        expect(vm.state, 7);
        // A throwing mint disables telemetry for the dispatch, nothing else.
        final result = await vm.go(() async => 1);
        expect(result, const AsyncData<int>(1));
      } finally {
        FlutterError.onError = previousHandler;
      }
      expect(reported, hasLength(2)); // stateChanged + dispatchRequested
      expect(reported.first.library, 'chassis_flutter');
    });
  });

  group('DispatchContext', () {
    test(
      'the middleware receives the id minted by dispatchRequested',
      () async {
        final spy = ContextSpyMiddleware();
        mediator.addMiddleware(spy);
        final vm = probe();

        await vm.go(() async => 1);
        final controller = StreamController<int>.broadcast();
        vm.look(IntWatchQuery(controller.stream));

        expect(spy.ids, [1, 2]);
        expect(telemetry.log, contains('requested#1 IntCommand command'));
        expect(telemetry.log, contains('watchStarted#2 IntWatchQuery'));
        vm.dispose();
      },
    );

    test('context is null when telemetry is inactive', () async {
      final spy = ContextSpyMiddleware();
      mediator.addMiddleware(spy);
      Chassis.initialize(mediator); // no telemetry
      final vm = ProbeViewModel();

      await vm.go(() async => 1);
      expect(spy.ids, [null]);
    });
  });
}
