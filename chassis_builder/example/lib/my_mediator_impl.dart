// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:example/main.dart' as _i1;
import 'package:example/user_repository.dart' as _i2;
import 'package:example/user_repository.handlers.dart' as _i3;
import 'package:chassis/chassis.dart';

class MyMediator extends Mediator {
  MyMediator({
    required _i1.AuthRepo authRepo,
    required _i1.Logger logger,
    required _i2.UserRepository userRepository,
  }) {
    registerCommandHandler(_i1.LoginHandler(authRepo, logger));
    registerQueryHandler(_i1.GetProfileHandler(authRepo));
    registerQueryHandler(_i3.GetUserQueryHandler(userRepository));
    registerQueryHandler(_i3.WatchUserQueryHandler(userRepository));
    registerCommandHandler(_i3.CreateUserCommandHandler(userRepository));
  }
}

extension MyMediatorExtensions on Mediator {
  Future<void> login(_i1.LoginCommand command) => run(command);

  Future<String> getProfile(_i1.GetProfileQuery query) => read(query);

  Future<String> getUserQuery(_i3.GetUserQuery query) => read(query);

  Stream<String> watchUserQuery(_i3.WatchUserQuery query) => watch(query);

  Future<void> createUserCommand(_i3.CreateUserCommand command) => run(command);
}
