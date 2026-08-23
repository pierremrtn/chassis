/// Round-trip test of the *generated* mediator: real dispatch through
/// `run`/`read`/`watch` with fake infrastructure, and a middleware
/// traversed for every operation. This executes `main.chassis.dart` as
/// produced by chassis_builder — if the generator emits invalid or
/// incomplete registration code, this test fails.
library;

import 'package:chassis/chassis.dart';
import 'package:example/main.chassis.dart';
import 'package:example/main.dart';
import 'package:example_auth/example_auth.dart';
import 'package:test/test.dart';

/// Records every operation seen by the middleware chain.
class RecordingMiddleware extends MediatorMiddleware {
  final seen = <String>[];

  @override
  Future<R> onRun<R>(
    Command<R> command,
    NextRun<R> next, {
    DispatchContext? context,
  }) {
    seen.add('run:$command');
    return next(command);
  }

  @override
  Future<R> onRead<R>(
    ReadQuery<R> query,
    NextRead<R> next, {
    DispatchContext? context,
  }) {
    seen.add('read:$query');
    return next(query);
  }

  @override
  Stream<R> onWatch<R>(
    WatchQuery<R> query,
    NextWatch<R> next, {
    DispatchContext? context,
  }) {
    seen.add('watch:$query');
    return next(query);
  }
}

void main() {
  test(
    'generated mediator dispatches run/read/watch through middlewares',
    () async {
      final middleware = RecordingMiddleware();
      final mediator = AppMediator(
        authRepository: FakeAuthRepository(),
        configStore: ConfigStore(),
      )..addMiddleware(middleware);

      // Module handlers (command, read, watch) and the app's own handler are
      // all registered by the generated constructor.
      await mediator.run(LoginCommand('ada', 'secret'));
      expect(
        await mediator.read(GetProfileQuery(userId: '42')),
        'profile of 42',
      );
      expect(await mediator.read(GetAppConfigQuery()), 'production');
      expect(await mediator.watch(WatchSessionQuery()).first, isTrue);

      expect(middleware.seen, [
        'run:LoginCommand{username: ada}',
        'read:GetProfileQuery{userId: 42}',
        'read:GetAppConfigQuery',
        'watch:WatchSessionQuery',
      ]);
    },
  );

  test(
    'dispatching an unregistered message throws HandlerNotRegisteredError',
    () {
      final mediator = AppMediator(
        authRepository: FakeAuthRepository(),
        configStore: ConfigStore(),
      );

      expect(
        () => mediator.read(_UnregisteredQuery()),
        throwsA(isA<HandlerNotRegisteredError>()),
      );
    },
  );
}

// Never registered: private to this test, invisible to the generator's
// import-graph walk from the @ChassisApp library.
final class _UnregisteredQuery extends ReadQuery<int> {}
