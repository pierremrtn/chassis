// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:example/my_mediator.dart' as _i1;
import 'package:example/main.dart' as _i2;
import 'package:chassis/chassis.dart';

class $MyMediator extends _i1.MyMediator {
  $MyMediator({
    required _i2.AuthRepo authRepo,
    required _i2.Logger logger,
  }) {
    registerCommandHandler(_i2.LoginHandler(authRepo, logger));
    registerQueryHandler(_i2.GetProfileHandler(authRepo));
  }
}

extension MyMediatorExtensions on Mediator {
  Future<void> login(_i2.LoginCommand command) => run(command);

  Future<String> getProfile(_i2.GetProfileQuery query) => read(query);
}
