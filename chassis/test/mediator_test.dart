import 'package:chassis/chassis.dart';
import 'package:test/test.dart';

// --- Fixtures ---

final class GetGreetingQuery(final String name) extends ReadQuery<String> {
  @override
  Map<String, Object?> get params => {'name': name};
}

class GetGreetingHandler implements ReadHandler<GetGreetingQuery, String> {
  @override
  Future<String> read(GetGreetingQuery query) async => 'Hello ${query.name}';
}

final class WatchCounterQuery() extends WatchQuery<int>;

class WatchCounterQueryHandler implements WatchHandler<WatchCounterQuery, int> {
  @override
  Stream<int> watch(WatchCounterQuery query) => Stream.fromIterable([1, 2, 3]);
}

final class IncrementCommand(final int by) extends Command<int> {
  @override
  Map<String, Object?> get params => {'by': by};
}

class IncrementHandler implements CommandHandler<IncrementCommand, int> {
  int total = 0;

  @override
  Future<int> run(IncrementCommand command) async => total += command.by;
}

sealed class UserQuery extends ReadQuery<String> {}

final class UserQueryA() extends UserQuery;

final class UserQueryB() extends UserQuery;

class UserQueryAHandler implements ReadHandler<UserQueryA, String> {
  @override
  Future<String> read(UserQueryA query) async => 'Hello A';
}

class UserQueryBHandler implements ReadHandler<UserQueryB, String> {
  @override
  Future<String> read(UserQueryB query) async => 'Hello B';
}

void main() {
  group('Mediator dispatch', () {
    test('read dispatches to the registered ReadHandler', () async {
      final mediator = Mediator()..registerQueryHandler(GetGreetingHandler());

      expect(await mediator.read(GetGreetingQuery('World')), 'Hello World');
    });

    test('watch dispatches to the registered WatchHandler', () async {
      final mediator = Mediator()
        ..registerQueryHandler(WatchCounterQueryHandler());

      expect(await mediator.watch(WatchCounterQuery()).toList(), [1, 2, 3]);
    });

    test('run dispatches to the registered CommandHandler', () async {
      final handler = IncrementHandler();
      final mediator = Mediator()..registerCommandHandler(handler);

      expect(await mediator.run(IncrementCommand(2)), 2);
      expect(await mediator.run(IncrementCommand(3)), 5);
      expect(handler.total, 5);
    });

    test('sibling query types dispatch to their own handlers', () async {
      final mediator = Mediator()
        ..registerQueryHandler(UserQueryAHandler())
        ..registerQueryHandler(UserQueryBHandler());

      expect(await mediator.read(UserQueryA()), 'Hello A');
      expect(await mediator.read(UserQueryB()), 'Hello B');
    });
  });

  group('Mediator unregistered handlers', () {
    test('read throws HandlerNotRegisteredError', () {
      final mediator = Mediator();

      expect(
        () => mediator.read(GetGreetingQuery('x')),
        throwsA(
          isA<HandlerNotRegisteredError>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('GetGreetingQuery'),
              contains('read'),
              contains('registerQueryHandler'),
              contains('@chassisHandler'),
            ),
          ),
        ),
      );
    });

    test('watch throws HandlerNotRegisteredError', () {
      final mediator = Mediator();

      expect(
        () => mediator.watch(WatchCounterQuery()),
        throwsA(isA<HandlerNotRegisteredError>()),
      );
    });

    test('run throws HandlerNotRegisteredError', () {
      final mediator = Mediator();

      expect(
        () => mediator.run(IncrementCommand(1)),
        throwsA(
          isA<HandlerNotRegisteredError>().having(
            (e) => e.toString(),
            'message',
            contains('registerCommandHandler'),
          ),
        ),
      );
    });
  });

  group('Mediator duplicate registration', () {
    test('duplicate ReadHandler throws DuplicateHandlerError', () {
      final mediator = Mediator()..registerQueryHandler(GetGreetingHandler());

      expect(
        () => mediator.registerQueryHandler(GetGreetingHandler()),
        throwsA(
          isA<DuplicateHandlerError>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('GetGreetingQuery'), contains('GetGreetingHandler')),
          ),
        ),
      );
    });

    test('duplicate WatchHandler throws DuplicateHandlerError', () {
      final mediator = Mediator()
        ..registerQueryHandler(WatchCounterQueryHandler());

      expect(
        () => mediator.registerQueryHandler(WatchCounterQueryHandler()),
        throwsA(isA<DuplicateHandlerError>()),
      );
    });

    test('duplicate CommandHandler throws DuplicateHandlerError', () {
      final mediator = Mediator()..registerCommandHandler(IncrementHandler());

      expect(
        () => mediator.registerCommandHandler(IncrementHandler()),
        throwsA(isA<DuplicateHandlerError>()),
      );
    });
  });

  group('hasHandlerAvailableFor', () {
    test('reports registered and unregistered types', () {
      final mediator = Mediator()
        ..registerQueryHandler(GetGreetingHandler())
        ..registerCommandHandler(IncrementHandler());

      expect(mediator.hasHandlerAvailableFor<GetGreetingQuery>(), isTrue);
      expect(mediator.hasHandlerAvailableFor<IncrementCommand>(), isTrue);
      expect(mediator.hasHandlerAvailableFor<WatchCounterQuery>(), isFalse);
    });
  });

  group('Mediator abstract registration keys', () {
    test('registering under an abstract query type throws ArgumentError', () {
      final mediator = Mediator();

      expect(
        () => mediator.registerQueryHandler<ReadQuery<String>, String>(
          GetGreetingHandler(),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('concrete'), contains('ReadQuery<String>')),
          ),
        ),
      );
      expect(
        () => mediator.registerQueryHandler<WatchQuery<int>, int>(
          WatchCounterQueryHandler(),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => mediator.registerQueryHandler<Query<String>, String>(
          GetGreetingHandler(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'registering under the abstract Command type throws ArgumentError',
      () {
        final mediator = Mediator();

        expect(
          () => mediator.registerCommandHandler<Command<int>, int>(
            IncrementHandler(),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Command<int>'),
            ),
          ),
        );
      },
    );

    test('an upcast handler variable is rejected at registration', () {
      // The realistic trigger: inference falls back to the variable's static
      // type, so the handler would be keyed by the abstract type and every
      // dispatch would throw HandlerNotRegisteredError.
      final QueryHandler<ReadQuery<String>, String> upcast =
          GetGreetingHandler();
      final mediator = Mediator();

      expect(
        () => mediator.registerQueryHandler(upcast),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('message equality', () {
    test('same type and equal params are the same operation', () {
      expect(IncrementCommand(2), IncrementCommand(2));
      expect(IncrementCommand(2).hashCode, IncrementCommand(2).hashCode);
      expect(GetGreetingQuery('Ada'), GetGreetingQuery('Ada'));
      expect(
        GetGreetingQuery('Ada').hashCode,
        GetGreetingQuery('Ada').hashCode,
      );
    });

    test('different params are different operations', () {
      expect(IncrementCommand(2), isNot(IncrementCommand(3)));
      expect(GetGreetingQuery('Ada'), isNot(GetGreetingQuery('Bob')));
    });

    test('different types with identical params are different operations', () {
      expect(UserQueryA(), isNot(UserQueryB()));
    });

    test('messages without params are equal by type alone', () {
      expect(WatchCounterQuery(), WatchCounterQuery());
      expect(WatchCounterQuery().hashCode, WatchCounterQuery().hashCode);
    });
  });

  group('params and toString', () {
    test('command toString includes params', () {
      expect(IncrementCommand(4).toString(), 'IncrementCommand{by: 4}');
    });

    test('query toString includes params', () {
      expect(GetGreetingQuery('Ada').toString(), 'GetGreetingQuery{name: Ada}');
    });

    test('params default to empty', () {
      expect(WatchCounterQuery().params, isEmpty);
      expect(WatchCounterQuery().toString(), 'WatchCounterQuery');
    });
  });
}
