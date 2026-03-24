// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:example/main.dart' as _i1;
import 'package:example/user_repository.dart' as _i2;
import 'package:example/user_repository.handlers.dart' as _i3;
import 'dart:ui' as _i4;
import 'package:chassis/chassis.dart';

class MyMediator extends Mediator {
  MyMediator({
    required _i1.AuthRepo authRepo,
    required _i1.Logger logger,
    required _i2.UserRepository userRepository,
  }) {
    registerCommandHandler(_i1.LoginHandler(authRepo, logger));
    registerQueryHandler(_i1.GetProfileHandler(authRepo));
    registerQueryHandler(_i1.GetAppConfigHandler(authRepo));
    registerQueryHandler(_i3.GetUserQueryHandler(userRepository));
    registerQueryHandler(_i3.WatchUserQueryHandler(userRepository));
    registerCommandHandler(_i3.CreateUserCommandHandler(userRepository));
  }
}

extension MyMediatorExtensions on Mediator {
  Future<void> login(
    String username, {
    _i4.Color test = const _i4.Color(0x000000),
  }) =>
      run(_i1.LoginCommand(
        username,
        test: test,
      ));

  Future<String> getProfile(String userId) => read(_i1.GetProfileQuery(userId));

  Future<String> getAppConfig() => read(_i1.GetAppConfigQuery());

  Future<String> getUser({required String id}) =>
      read(_i3.GetUserQuery(id: id));

  Stream<String> watchUser({required String id}) =>
      watch(_i3.WatchUserQuery(id: id));

  Future<void> createUser({
    required String name,
    required String email,
  }) =>
      run(_i3.CreateUserCommand(
        name: name,
        email: email,
      ));
}
