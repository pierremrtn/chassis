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
    required this.userQuery,
  }) : super(0) {
    autoDispose(userQuery);
  }

  final ReadAndWatchHandle<UserQuery, UserData> userQuery;
}

// Widget tree

// final p = Provider(
//   create: (context) => MyViewModel(
//     userQuery: mediator.readWatchHandle(),
//   ),
// );
