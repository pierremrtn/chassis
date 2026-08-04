import 'package:chassis/chassis.dart';
import 'package:test/test.dart';

final class PingQuery extends ReadQuery<String> {}

class PingHandler implements ReadHandler<PingQuery, String> {
  @override
  Future<String> read(PingQuery query) async => 'pong';
}

final class TickQuery extends WatchQuery<int> {}

class TickHandler implements WatchHandler<TickQuery, int> {
  @override
  Stream<int> watch(TickQuery query) => Stream.fromIterable([1, 2]);
}

final class NoopCommand extends Command<void> {}

class NoopHandler implements CommandHandler<NoopCommand, void> {
  @override
  Future<void> run(NoopCommand command) async {}
}

final class FailingCommand extends Command<void> {}

class FailingHandler implements CommandHandler<FailingCommand, void> {
  @override
  Future<void> run(FailingCommand command) async {
    throw StateError('handler failure');
  }
}

/// Records the order in which it sees operations, tagged with its own name.
class RecordingMiddleware extends MediatorMiddleware {
  RecordingMiddleware(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  Future<R> onRun<C extends Command<R>, R>(
      C command, NextRun<C, R> next) async {
    log.add('$name:before');
    final result = await next(command);
    log.add('$name:after');
    return result;
  }

  @override
  Future<R> onRead<Q extends ReadQuery<R>, R>(
      Q query, NextRead<Q, R> next) async {
    log.add('$name:before');
    final result = await next(query);
    log.add('$name:after');
    return result;
  }

  @override
  Stream<R> onWatch<Q extends WatchQuery<R>, R>(Q query, NextWatch<Q, R> next) {
    log.add('$name:watch');
    return next(query);
  }
}

void main() {
  group('Middleware chaining', () {
    test('middlewares wrap read in registration order', () async {
      final log = <String>[];
      final mediator = Mediator()
        ..registerQueryHandler(PingHandler())
        ..addMiddleware(RecordingMiddleware('outer', log))
        ..addMiddleware(RecordingMiddleware('inner', log));

      expect(await mediator.read(PingQuery()), 'pong');
      expect(log, [
        'outer:before',
        'inner:before',
        'inner:after',
        'outer:after',
      ]);
    });

    test('middlewares wrap run in registration order', () async {
      final log = <String>[];
      final mediator = Mediator()
        ..registerCommandHandler(NoopHandler())
        ..addMiddleware(RecordingMiddleware('outer', log))
        ..addMiddleware(RecordingMiddleware('inner', log));

      await mediator.run(NoopCommand());
      expect(log, [
        'outer:before',
        'inner:before',
        'inner:after',
        'outer:after',
      ]);
    });

    test('middlewares intercept watch in registration order', () async {
      final log = <String>[];
      final mediator = Mediator()
        ..registerQueryHandler(TickHandler())
        ..addMiddleware(RecordingMiddleware('outer', log))
        ..addMiddleware(RecordingMiddleware('inner', log));

      expect(await mediator.watch(TickQuery()).toList(), [1, 2]);
      expect(log, ['outer:watch', 'inner:watch']);
    });

    test('handler errors propagate through the middleware chain', () async {
      final log = <String>[];
      final mediator = Mediator()
        ..registerCommandHandler(FailingHandler())
        ..addMiddleware(RecordingMiddleware('outer', log));

      await expectLater(
        mediator.run(FailingCommand()),
        throwsA(isA<StateError>()),
      );
      // The middleware saw the dispatch but never the (missing) success.
      expect(log, ['outer:before']);
    });

    test('a middleware can transform the result', () async {
      final mediator = Mediator()
        ..registerQueryHandler(PingHandler())
        ..addMiddleware(_UppercaseMiddleware());

      expect(await mediator.read(PingQuery()), 'PONG');
    });
  });
}

class _UppercaseMiddleware extends MediatorMiddleware {
  @override
  Future<R> onRead<Q extends ReadQuery<R>, R>(
      Q query, NextRead<Q, R> next) async {
    final result = await next(query);
    if (result is String) return result.toUpperCase() as R;
    return result;
  }
}
