import 'package:chassis/chassis.dart';
import 'package:example/user_repository.dart';
import 'my_mediator_impl.dart';
import 'dart:ui';

// Use strict dependency injection
class AuthRepo {}

class Logger {}

void main() async {
  final authRepo = AuthRepo();
  final logger = Logger();
  final userRepository = UserRepository();

  // Instantiate the generated concrete class
  final mediator = MyMediator(
    authRepo: authRepo,
    logger: logger,
    userRepository: userRepository,
  );

  await mediator.login('test_user');
  final profile = await mediator.getProfile('user_id');
  print('Profile: $profile');

  final config = await mediator.getAppConfig();
  print('Config: $config');
}

@chassisHandler
class LoginHandler implements CommandHandler<LoginCommand, void> {
  final AuthRepo authRepo;
  final Logger logger;

  LoginHandler(this.authRepo, this.logger);

  @override
  Future<void> run(LoginCommand command) async {
    print('Login ${command.username}');
  }
}

final class LoginCommand extends Command<void> {
  final String username;
  final Color test;
  LoginCommand(this.username, {this.test = const Color(0x000000)});
}

@chassisHandler
class GetProfileHandler implements ReadHandler<GetProfileQuery, String> {
  final AuthRepo authRepo;

  GetProfileHandler(this.authRepo);

  @override
  Future<String> read(GetProfileQuery query) async {
    return 'User Profile';
  }
}

final class GetProfileQuery extends ReadQuery<String> {
  final String userId;
  GetProfileQuery(this.userId);
}

final class GetAppConfigQuery extends ReadQuery<String> {
  GetAppConfigQuery();
}

@chassisHandler
class GetAppConfigHandler implements ReadHandler<GetAppConfigQuery, String> {
  final AuthRepo authRepo;

  GetAppConfigHandler(this.authRepo);

  @override
  Future<String> read(GetAppConfigQuery query) async {
    return 'App Config';
  }
}
