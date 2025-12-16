// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:example/main.dart' as _i1;
import 'package:chassis/chassis.dart';

class MyMediator extends Mediator {
  MyMediator({
    required _i1.AuthRepo authRepo,
    required _i1.Logger logger,
  }) {
    registerCommandHandler(_i1.LoginHandler(authRepo, logger));
    registerQueryHandler(_i1.GetProfileHandler(authRepo));
  }
}

extension MyMediatorExtensions on Mediator {
  Future<void> login(_i1.LoginCommand command) => run(command);

  Future<String> getProfile(_i1.GetProfileQuery query) => read(query);
}
