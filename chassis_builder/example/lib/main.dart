import 'package:chassis/chassis.dart';
import 'my_mediator.chassis.dart';

// Use strict dependency injection
class AuthRepo {}

class Logger {}

void main() async {
  final authRepo = AuthRepo();
  final logger = Logger();

  // Instantiate the generated concrete class
  final mediator = $MyMediator(
    authRepo: authRepo,
    logger: logger,
  );

  await mediator.login(LoginCommand('test_user'));
  final profile = await mediator.getProfile(GetProfileQuery('user_id'));
  print('Profile: $profile');
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

class LoginCommand extends Command<void> {
  final String username;
  LoginCommand(this.username);
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

class GetProfileQuery extends ReadQuery<String> {
  final String userId;
  GetProfileQuery(this.userId);
}
