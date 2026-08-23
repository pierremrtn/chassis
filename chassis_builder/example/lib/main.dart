/// Composition root: the generator emits `AppMediator` (in
/// `main.chassis.dart`), which extends `Mediator` and registers every
/// handler of the `AuthModule` package plus the app's own handlers in its
/// constructor. A reachable message without a handler fails the build.
@ChassisApp(modules: [AuthModule], mediatorName: 'AppMediator')
library;

import 'package:chassis/chassis.dart';
import 'package:example_auth/example_auth.dart';

import 'main.chassis.dart';

// --- App-own logic ---

class ConfigStore {
  String get flavor => 'production';
}

final class GetAppConfigQuery extends ReadQuery<String> {}

@chassisHandler
class GetAppConfigQueryHandler({required final ConfigStore store})
    implements ReadHandler<GetAppConfigQuery, String> {
  @override
  Future<String> read(GetAppConfigQuery query) async => store.flavor;
}

// --- Infrastructure ---

class FakeAuthRepository implements AuthRepository {
  @override
  Future<void> login(String username, String password) async {
    print('logged in as $username');
  }

  @override
  Future<String> profileOf(String userId) async => 'profile of $userId';

  @override
  Stream<bool> sessionActive() => Stream.value(true);
}

void main() async {
  final AppMediator mediator = AppMediator(
    authRepository: FakeAuthRepository(),
    configStore: ConfigStore(),
  )..addMiddleware(LoggingMiddleware());

  // Message-direct dispatch through the mediator (middlewares apply).
  await mediator.run(LoginCommand('ada', 'secret'));
  print(await mediator.read(GetProfileQuery(userId: '42')));
  print(await mediator.read(GetAppConfigQuery()));
  print(await mediator.watch(WatchSessionQuery()).first);
}
