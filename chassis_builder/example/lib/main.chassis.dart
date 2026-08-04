// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: implementation_imports

// **************************************************************************
// ChassisGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:chassis/chassis.dart' as _i1;
import 'package:example_auth/example_auth.chassis.dart' as _i2;
import 'package:example_auth/src/handlers.dart' as _i3;
import 'package:example/main.dart' as _i4;

/// Concrete mediator generated from the `@ChassisApp` library
/// `package:example/main.dart`.
///
/// All handlers are registered in the constructor; every method dispatches
/// through the mediator, so middlewares always apply.
class AppMediator extends _i1.Mediator implements _i2.AuthMediator {
  AppMediator({
    required _i3.AuthRepository authRepository,
    required _i4.ConfigStore configStore,
  }) {
    registerQueryHandler(_i3.GetProfileHandler(repository: authRepository));
    registerCommandHandler(_i3.LoginHandler(repository: authRepository));
    registerQueryHandler(_i4.GetAppConfigHandler(store: configStore));
  }

  @override
  Future<String> getProfile({required String userId}) =>
      read(_i3.GetProfileQuery(userId: userId));

  @override
  Future<void> login(
    String username,
    String password,
  ) =>
      run(_i3.LoginCommand(
        username,
        password,
      ));

  Future<String> getAppConfig() => read(_i4.GetAppConfigQuery());
}
