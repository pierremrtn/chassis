import 'package:chassis/chassis.dart';
import 'package:chassis_flutter/chassis_flutter.dart';

// Domain

abstract class IUserRepo {
  UserData get user;
  Stream<UserData> get stream;
}

class UserData {}

class UserQuery implements ReadAndWatch<UserData> {}

class UserQueryHandler extends ReadAndWatchHandler<UserQuery, UserData> {
  UserQueryHandler({required IUserRepo repo})
      : super(
          read: (query) async => repo.user,
          watch: (query) => repo.stream,
        );
}

// UI
class MyViewModel extends ViewModel<int> {
  MyViewModel({
    required UserQueryHandler userHandler,
  }) : super(0) {
    userQuery = readHandle(userHandler);
  }

  late final FutureHandle<UserQuery, UserData> userQuery;
}

// Widget tree

final p = Provider(
  create: (context) => MyViewModel(
    userHandler: Mediator().handler(),
  ),
);
