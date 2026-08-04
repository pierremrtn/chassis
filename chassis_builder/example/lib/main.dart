/// Composition root: the generator emits `AppMediator` (in
/// `main.chassis.dart`) implementing `AuthMediator` plus the app's own
/// handlers. If a handler is missing, this file no longer compiles.
@ChassisApp(modules: [AuthModule], mediatorName: 'AppMediator')
library;

import 'package:chassis/chassis.dart';
import 'package:example_auth/example_auth.chassis.dart';
import 'package:example_auth/example_auth.dart';

import 'main.chassis.dart';

// --- App-own logic ---

class ConfigStore {
  String get flavor => 'production';
}

final class GetAppConfigQuery extends ReadQuery<String> {}

@chassisHandler
class GetAppConfigHandler implements ReadHandler<GetAppConfigQuery, String> {
  GetAppConfigHandler({required this.store});

  final ConfigStore store;

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
}

void main() async {
  final AppMediator mediator = AppMediator(
    authRepository: FakeAuthRepository(),
    configStore: ConfigStore(),
  )..addMiddleware(LoggingMiddleware());

  // Typed dispatch through the generated methods (middlewares apply).
  await mediator.login('ada', 'secret');
  print(await mediator.getProfile(userId: '42'));
  print(await mediator.getAppConfig());

  // The module interface alone is enough for shared code:
  final AuthMediator auth = mediator;
  await auth.login('grace', 'hopper');
}
