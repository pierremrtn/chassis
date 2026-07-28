import 'package:chassis/chassis.dart';
import 'package:test/test.dart';

// --- Fixtures ---

final class GetGreetingQuery extends ReadQuery<String> {
  GetGreetingQuery(this.name);

  final String name;

  @override
  Map<String, Object?> get params => {'name': name};
}

class GetGreetingHandler implements ReadHandler<GetGreetingQuery, String> {
  @override
  Future<String> read(GetGreetingQuery query) async => 'Hello ${query.name}';
}

final class WatchCounterQuery extends WatchQuery<int> {}

class WatchCounterHandler implements WatchHandler<WatchCounterQuery, int> {
  @override
  Stream<int> watch(WatchCounterQuery query) => Stream.fromIterable([1, 2, 3]);
}

final class IncrementCommand extends Command<int> {
  IncrementCommand(this.by);

  final int by;

  @override
  Map<String, Object?> get params => {'by': by};
}

class IncrementHandler implements CommandHandler<IncrementCommand, int> {
  int total = 0;

  @override
  Future<int> run(IncrementCommand command) async => total += command.by;
}

sealed class UserQuery extends ReadQuery<String> {}

final class UserQueryA extends UserQuery {}

final class UserQueryB extends UserQuery {}

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
      final mediator = Mediator()
        ..registerQueryHandler(GetGreetingHandler());

      expect(await mediator.read(GetGreetingQuery('World')), 'Hello World');
    });

    test('watch dispatches to the registered WatchHandler', () async {
      final mediator = Mediator()..registerQueryHandler(WatchCounterHandler());

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
    test('read throws HandlerNotRegisteredException', () {
      final mediator = Mediator();

      expect(
        () => mediator.read(GetGreetingQuery('x')),
        throwsA(isA<HandlerNotRegisteredException>().having(
          (e) => e.toString(),
          'message',
          allOf(
            contains('GetGreetingQuery'),
            contains('read'),
            contains('registerQueryHandler'),
            contains('@chassisHandler'),
          ),
        )),
      );
    });

    test('watch throws HandlerNotRegisteredException', () {
      final mediator = Mediator();

      expect(
        () => mediator.watch(WatchCounterQuery()),
        throwsA(isA<HandlerNotRegisteredException>()),
      );
    });

    test('run throws HandlerNotRegisteredException', () {
      final mediator = Mediator();

      expect(
        () => mediator.run(IncrementCommand(1)),
        throwsA(isA<HandlerNotRegisteredException>().having(
          (e) => e.toString(),
          'message',
          contains('registerCommandHandler'),
        )),
      );
    });
  });

  group('Mediator duplicate registration', () {
    test('duplicate ReadHandler throws DuplicateHandlerException', () {
      final mediator = Mediator()..registerQueryHandler(GetGreetingHandler());

      expect(
        () => mediator.registerQueryHandler(GetGreetingHandler()),
        throwsA(isA<DuplicateHandlerException>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('GetGreetingQuery'), contains('GetGreetingHandler')),
        )),
      );
    });

    test('duplicate WatchHandler throws DuplicateHandlerException', () {
      final mediator = Mediator()..registerQueryHandler(WatchCounterHandler());

      expect(
        () => mediator.registerQueryHandler(WatchCounterHandler()),
        throwsA(isA<DuplicateHandlerException>()),
      );
    });

    test('duplicate CommandHandler throws DuplicateHandlerException', () {
      final mediator = Mediator()..registerCommandHandler(IncrementHandler());

      expect(
        () => mediator.registerCommandHandler(IncrementHandler()),
        throwsA(isA<DuplicateHandlerException>()),
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

  group('params and toString', () {
    test('command toString includes params', () {
      expect(IncrementCommand(4).toString(), 'IncrementCommand{by: 4}');
    });

    test('query toString includes params', () {
      expect(
        GetGreetingQuery('Ada').toString(),
        'GetGreetingQuery{name: Ada}',
      );
    });

    test('params default to empty', () {
      expect(WatchCounterQuery().params, isEmpty);
      expect(WatchCounterQuery().toString(), 'WatchCounterQuery');
    });
  });
}
