import 'dart:async';

import 'package:chassis/chassis.dart';
import 'package:chassis/testing.dart';
import 'package:test/test.dart';

// --- Fixtures ---

class const Todo(final String title) {
  @override
  bool operator ==(Object other) => other is Todo && other.title == title;

  @override
  int get hashCode => title.hashCode;
}

final class AddTodoCommand(final String title) extends Command<Todo> {
  @override
  Map<String, Object?> get params => {'title': title};
}

final class ClearTodosCommand() extends Command<void>;

final class GetUserQuery(final String userId) extends ReadQuery<String> {
  @override
  Map<String, Object?> get params => {'userId': userId};
}

final class WatchTodosQuery() extends WatchQuery<List<Todo>>;

/// Records the operations it sees, to prove the middleware chain still runs.
class RecordingMiddleware extends MediatorMiddleware {
  final List<String> log = [];

  @override
  Future<R> onRun<R>(
    Command<R> command,
    NextRun<R> next, {
    DispatchContext? context,
  }) {
    log.add('run:$command');
    return next(command);
  }

  @override
  Future<R> onRead<R>(
    ReadQuery<R> query,
    NextRead<R> next, {
    DispatchContext? context,
  }) {
    log.add('read:$query');
    return next(query);
  }

  @override
  Stream<R> onWatch<R>(
    WatchQuery<R> query,
    NextWatch<R> next, {
    DispatchContext? context,
  }) {
    log.add('watch:$query');
    return next(query);
  }
}

void main() {
  group('TestMediator stubbing', () {
    test(
      'whenRun routes commands by concrete type and delivers the result',
      () async {
        final mediator = TestMediator()
          ..whenRun<AddTodoCommand, Todo>((cmd) async => Todo(cmd.title));

        expect(await mediator.run(AddTodoCommand('milk')), const Todo('milk'));
      },
    );

    test(
      'whenRead routes queries by concrete type and delivers the result',
      () async {
        final mediator = TestMediator()
          ..whenRead<GetUserQuery, String>((q) async => 'user-${q.userId}');

        expect(await mediator.read(GetUserQuery('42')), 'user-42');
      },
    );

    test(
      'whenWatch routes queries by concrete type and delivers the stream',
      () async {
        final controller = StreamController<List<Todo>>();
        final mediator = TestMediator()
          ..whenWatch<WatchTodosQuery, List<Todo>>((q) => controller.stream);

        final emissions = mediator.watch(WatchTodosQuery()).toList();
        controller
          ..add(const [Todo('a')])
          ..add(const [Todo('a'), Todo('b')]);
        await controller.close();

        expect(await emissions, const [
          [Todo('a')],
          [Todo('a'), Todo('b')],
        ]);
      },
    );

    test('sibling stubs route independently', () async {
      var cleared = false;
      final mediator = TestMediator()
        ..whenRun<AddTodoCommand, Todo>((cmd) async => Todo(cmd.title))
        ..whenRun<ClearTodosCommand, void>((cmd) async => cleared = true);

      await mediator.run(ClearTodosCommand());

      expect(cleared, isTrue);
      expect(await mediator.run(AddTodoCommand('milk')), const Todo('milk'));
    });
  });

  group('TestMediator failure stubbing', () {
    test('a throwing whenRun closure propagates as the dispatch failure', () {
      final mediator = TestMediator()
        ..whenRun<AddTodoCommand, Todo>(
          (cmd) async => throw StateError('todo limit reached'),
        );

      expect(
        mediator.run(AddTodoCommand('milk')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'todo limit reached',
          ),
        ),
      );
    });

    test('a throwing whenRead closure propagates as the dispatch failure', () {
      final mediator = TestMediator()
        ..whenRead<GetUserQuery, String>(
          (q) async => throw StateError('user not found'),
        );

      expect(mediator.read(GetUserQuery('42')), throwsA(isA<StateError>()));
    });

    test('a whenWatch error stream propagates through the subscription', () {
      final mediator = TestMediator()
        ..whenWatch<WatchTodosQuery, List<Todo>>(
          (q) => Stream.error(StateError('connection lost')),
        );

      expect(mediator.watch(WatchTodosQuery()), emitsError(isA<StateError>()));
    });
  });

  group('TestMediator registration guards', () {
    test('a duplicate whenRun stub throws DuplicateHandlerError', () {
      final mediator = TestMediator()
        ..whenRun<AddTodoCommand, Todo>((cmd) async => Todo(cmd.title));

      expect(
        () => mediator.whenRun<AddTodoCommand, Todo>(
          (cmd) async => Todo(cmd.title),
        ),
        throwsA(isA<DuplicateHandlerError>()),
      );
    });

    test('a duplicate whenRead stub throws DuplicateHandlerError', () {
      final mediator = TestMediator()
        ..whenRead<GetUserQuery, String>((q) async => 'a');

      expect(
        () => mediator.whenRead<GetUserQuery, String>((q) async => 'b'),
        throwsA(isA<DuplicateHandlerError>()),
      );
    });

    test('a duplicate whenWatch stub throws DuplicateHandlerError', () {
      final mediator = TestMediator()
        ..whenWatch<WatchTodosQuery, List<Todo>>((q) => const Stream.empty());

      expect(
        () => mediator.whenWatch<WatchTodosQuery, List<Todo>>(
          (q) => const Stream.empty(),
        ),
        throwsA(isA<DuplicateHandlerError>()),
      );
    });

    test('a stub keyed by an abstract message type throws ArgumentError', () {
      final mediator = TestMediator();

      expect(
        () => mediator.whenRun<Command<Todo>, Todo>(
          (cmd) async => const Todo('x'),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => mediator.whenRead<ReadQuery<String>, String>((q) async => 'x'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => mediator.whenWatch<WatchQuery<List<Todo>>, List<Todo>>(
          (q) => const Stream.empty(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'dispatching an unstubbed message throws HandlerNotRegisteredError',
      () {
        final mediator = TestMediator();

        expect(
          () => mediator.run(AddTodoCommand('milk')),
          throwsA(isA<HandlerNotRegisteredError>()),
        );
      },
    );
  });

  group('TestMediator dispatch recording', () {
    test('dispatchedCommands records commands in dispatch order', () async {
      final mediator = TestMediator()
        ..whenRun<AddTodoCommand, Todo>((cmd) async => Todo(cmd.title))
        ..whenRun<ClearTodosCommand, void>((cmd) async {});

      await mediator.run(AddTodoCommand('milk'));
      await mediator.run(ClearTodosCommand());
      await mediator.run(AddTodoCommand('bread'));

      expect(mediator.dispatchedCommands, [
        AddTodoCommand('milk'),
        ClearTodosCommand(),
        AddTodoCommand('bread'),
      ]);
    });

    test(
      'dispatchedQueries records reads and watches in dispatch order',
      () async {
        final mediator = TestMediator()
          ..whenRead<GetUserQuery, String>((q) async => 'user')
          ..whenWatch<WatchTodosQuery, List<Todo>>((q) => const Stream.empty());

        await mediator.read(GetUserQuery('1'));
        await mediator.watch(WatchTodosQuery()).drain<void>();
        await mediator.read(GetUserQuery('2'));

        expect(mediator.dispatchedQueries, [
          GetUserQuery('1'),
          WatchTodosQuery(),
          GetUserQuery('2'),
        ]);
      },
    );

    test('structural equality matches freshly constructed messages', () async {
      final mediator = TestMediator()
        ..whenRun<AddTodoCommand, Todo>((cmd) async => Todo(cmd.title));

      await mediator.run(AddTodoCommand('milk'));

      expect(mediator.dispatchedCommands, contains(AddTodoCommand('milk')));
      expect(
        mediator.dispatchedCommands,
        isNot(contains(AddTodoCommand('bread'))),
      );
    });

    test('a failed dispatch is still recorded', () async {
      final mediator = TestMediator()
        ..whenRun<AddTodoCommand, Todo>((cmd) async => throw StateError('no'));

      try {
        await mediator.run(AddTodoCommand('milk'));
      } on StateError {
        // expected: the stub fails, the dispatch is recorded anyway.
      }

      expect(mediator.dispatchedCommands, [AddTodoCommand('milk')]);
    });
  });

  group('TestMediator middleware chain', () {
    test('middlewares still traverse run, read, and watch', () async {
      final middleware = RecordingMiddleware();
      final mediator = TestMediator()
        ..whenRun<AddTodoCommand, Todo>((cmd) async => Todo(cmd.title))
        ..whenRead<GetUserQuery, String>((q) async => 'user')
        ..whenWatch<WatchTodosQuery, List<Todo>>((q) => const Stream.empty())
        ..addMiddleware(middleware);

      await mediator.run(AddTodoCommand('milk'));
      await mediator.read(GetUserQuery('1'));
      await mediator.watch(WatchTodosQuery()).drain<void>();

      expect(middleware.log, [
        'run:AddTodoCommand{title: milk}',
        'read:GetUserQuery{userId: 1}',
        'watch:WatchTodosQuery',
      ]);
    });
  });
}
