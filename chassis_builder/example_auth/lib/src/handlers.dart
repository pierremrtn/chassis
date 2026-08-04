import 'package:chassis/chassis.dart';

/// Repository interface the app must provide to the module's handlers.
abstract interface class AuthRepository {
  Future<void> login(String username, String password);
  Future<String> profileOf(String userId);
}

final class LoginCommand extends Command<void> {
  LoginCommand(this.username, this.password);

  final String username;
  final String password;

  @override
  Map<String, Object?> get params => {'username': username};
}

@chassisHandler
class LoginHandler implements CommandHandler<LoginCommand, void> {
  LoginHandler({required this.repository});

  final AuthRepository repository;

  @override
  Future<void> run(LoginCommand command) =>
      repository.login(command.username, command.password);
}

final class GetProfileQuery extends ReadQuery<String> {
  GetProfileQuery({required this.userId});

  final String userId;

  @override
  Map<String, Object?> get params => {'userId': userId};
}

@chassisHandler
class GetProfileHandler implements ReadHandler<GetProfileQuery, String> {
  GetProfileHandler({required this.repository});

  final AuthRepository repository;

  @override
  Future<String> read(GetProfileQuery query) =>
      repository.profileOf(query.userId);
}
