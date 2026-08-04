import 'package:chassis/chassis.dart';
import 'package:test/test.dart';

final class GetUserQuery extends ReadQuery<String> {
  GetUserQuery(this.id);

  final String id;

  @override
  Map<String, Object?> get params => {'id': id};
}

class GetUserHandler implements ReadHandler<GetUserQuery, String> {
  @override
  Future<String> read(GetUserQuery query) async => 'user-${query.id}';
}

final class FailingQuery extends ReadQuery<String> {}

class FailingQueryHandler implements ReadHandler<FailingQuery, String> {
  @override
  Future<String> read(FailingQuery query) async {
    throw StateError('boom');
  }
}

final class TickQuery extends WatchQuery<int> {}

class TickHandler implements WatchHandler<TickQuery, int> {
  @override
  Stream<int> watch(TickQuery query) => Stream.fromIterable([1, 2]);
}

final class BroadcastTickQuery extends WatchQuery<int> {}

class BroadcastTickHandler implements WatchHandler<BroadcastTickQuery, int> {
  @override
  Stream<int> watch(BroadcastTickQuery query) =>
      Stream.fromIterable([1, 2]).asBroadcastStream();
}

final class FailingTickQuery extends WatchQuery<int> {}

class FailingTickHandler implements WatchHandler<FailingTickQuery, int> {
  @override
  Stream<int> watch(FailingTickQuery query) async* {
    yield 1;
    throw StateError('stream boom');
  }
}

final class SaveCommand extends Command<void> {
  SaveCommand(this.name);

  final String name;

  @override
  Map<String, Object?> get params => {'name': name};
}

class SaveHandler implements CommandHandler<SaveCommand, void> {
  @override
  Future<void> run(SaveCommand command) async {}
}

class FakeSink implements ChassisLogSink {
  final List<ChassisLogRecord> records = [];

  @override
  void write(ChassisLogRecord record) => records.add(record);

  List<ChassisLogEvent> get events => [for (final r in records) r.event];
}

void main() {
  group('LoggingMiddleware', () {
    test('logs read success with duration and params', () async {
      final sink = FakeSink();
      final mediator = Mediator()
        ..registerQueryHandler(GetUserHandler())
        ..addMiddleware(LoggingMiddleware(sink: sink));

      await mediator.read(GetUserQuery('42'));

      expect(sink.events, [ChassisLogEvent.success]);
      final record = sink.records.single;
      expect(record.kind, ChassisLogKind.read);
      expect(record.params, {'id': '42'});
      expect(record.elapsed, isNotNull);
      expect(record.toString(), contains('GetUserQuery{id: 42}'));
      expect(record.toString(), contains('succeeded'));
    });

    test('logStart emits a start record first', () async {
      final sink = FakeSink();
      final mediator = Mediator()
        ..registerQueryHandler(GetUserHandler())
        ..addMiddleware(LoggingMiddleware(sink: sink, logStart: true));

      await mediator.read(GetUserQuery('42'));

      expect(sink.events, [ChassisLogEvent.start, ChassisLogEvent.success]);
    });

    test('logs run success', () async {
      final sink = FakeSink();
      final mediator = Mediator()
        ..registerCommandHandler(SaveHandler())
        ..addMiddleware(LoggingMiddleware(sink: sink));

      await mediator.run(SaveCommand('doc'));

      final record = sink.records.single;
      expect(record.kind, ChassisLogKind.run);
      expect(record.params, {'name': 'doc'});
    });

    test('logs error with stack trace and rethrows', () async {
      final sink = FakeSink();
      final mediator = Mediator()
        ..registerQueryHandler(FailingQueryHandler())
        ..addMiddleware(LoggingMiddleware(sink: sink));

      await expectLater(
        mediator.read(FailingQuery()),
        throwsA(isA<StateError>()),
      );

      final record = sink.records.single;
      expect(record.event, ChassisLogEvent.error);
      expect(record.error, isA<StateError>());
      expect(record.stackTrace, isNotNull);
      expect(record.toString(), contains('failed'));
    });

    test('logs missing handler as error and rethrows', () async {
      final sink = FakeSink();
      final mediator = Mediator()..addMiddleware(LoggingMiddleware(sink: sink));

      await expectLater(
        mediator.read(GetUserQuery('42')),
        throwsA(isA<HandlerNotRegisteredException>()),
      );

      expect(sink.records.single.event, ChassisLogEvent.error);
    });

    test('watch logs completion, without per-event records by default',
        () async {
      final sink = FakeSink();
      final mediator = Mediator()
        ..registerQueryHandler(TickHandler())
        ..addMiddleware(LoggingMiddleware(sink: sink));

      expect(await mediator.watch(TickQuery()).toList(), [1, 2]);
      expect(sink.events, [ChassisLogEvent.streamDone]);
    });

    test('watch logs stream events when logStreamEvents is true', () async {
      final sink = FakeSink();
      final mediator = Mediator()
        ..registerQueryHandler(TickHandler())
        ..addMiddleware(LoggingMiddleware(sink: sink, logStreamEvents: true));

      await mediator.watch(TickQuery()).toList();
      expect(sink.events, [
        ChassisLogEvent.streamEvent,
        ChassisLogEvent.streamEvent,
        ChassisLogEvent.streamDone,
      ]);
    });

    test('watch logs stream errors and rethrows them to the listener',
        () async {
      final sink = FakeSink();
      final mediator = Mediator()
        ..registerQueryHandler(FailingTickHandler())
        ..addMiddleware(LoggingMiddleware(sink: sink));

      await expectLater(
        mediator.watch(FailingTickQuery()).toList(),
        throwsA(isA<StateError>()),
      );

      // The error is logged; the listener (toList) cancels on error, so no
      // done record follows.
      expect(sink.events.first, ChassisLogEvent.error);
    });

    test('watch preserves the broadcast nature of the source stream', () async {
      final sink = FakeSink();
      final mediator = Mediator()
        ..registerQueryHandler(BroadcastTickHandler())
        ..addMiddleware(LoggingMiddleware(sink: sink));

      final broadcast = mediator.watch(BroadcastTickQuery());
      expect(broadcast.isBroadcast, isTrue);

      final single = Mediator()
        ..registerQueryHandler(TickHandler())
        ..addMiddleware(LoggingMiddleware(sink: sink));
      expect(single.watch(TickQuery()).isBroadcast, isFalse);
    });
  });
}
