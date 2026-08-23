import 'package:chassis/chassis.dart';

/// Repository interface the app must provide to the module's handlers.
abstract interface class AuthRepository {
  Future<void> login(String username, String password);
  Future<String> profileOf(String userId);
  Stream<bool> sessionActive();
}

final class LoginCommand(final String username, final String password)
    extends Command<void> {
  @override
  Map<String, Object?> get params => {'username': username};
}

@chassisHandler
class LoginCommandHandler({required final AuthRepository repository})
    implements CommandHandler<LoginCommand, void> {
  @override
  Future<void> run(LoginCommand command) =>
      repository.login(command.username, command.password);
}

final class GetProfileQuery({required final String userId})
    extends ReadQuery<String> {
  @override
  Map<String, Object?> get params => {'userId': userId};
}

@chassisHandler
class GetProfileQueryHandler({required final AuthRepository repository})
    implements ReadHandler<GetProfileQuery, String> {
  @override
  Future<String> read(GetProfileQuery query) =>
      repository.profileOf(query.userId);
}

final class WatchSessionQuery extends WatchQuery<bool> {}

@chassisHandler
class WatchSessionQueryHandler({required final AuthRepository repository})
    implements WatchHandler<WatchSessionQuery, bool> {
  @override
  Stream<bool> watch(WatchSessionQuery query) => repository.sessionActive();
}
