// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: implementation_imports

// **************************************************************************
// ChassisGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:chassis/chassis.dart' as _i1;
import 'package:example_auth/src/handlers.dart' as _i2;
import 'package:example/main.dart' as _i3;

/// Concrete mediator generated from the `@ChassisApp` library
/// `package:example/main.dart`.
///
/// Registers every reachable handler in its constructor. Dispatch messages
/// through the inherited `run`/`read`/`watch`; middlewares always apply.
class AppMediator extends _i1.Mediator {
  AppMediator({
    required _i2.AuthRepository authRepository,
    required _i3.ConfigStore configStore,
  }) {
    registerQueryHandler(
      _i2.GetProfileQueryHandler(repository: authRepository),
    );
    registerCommandHandler(_i2.LoginCommandHandler(repository: authRepository));
    registerQueryHandler(
      _i2.WatchSessionQueryHandler(repository: authRepository),
    );
    registerQueryHandler(_i3.GetAppConfigQueryHandler(store: configStore));
  }
}
