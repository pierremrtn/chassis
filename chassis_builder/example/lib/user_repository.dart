import 'package:chassis/chassis.dart';

class UserRepository {
  @generateQueryHandler
  Future<String> getUser(String id) async {
    return 'User $id';
  }

  @generateQueryHandler
  Stream<String> watchUser(String id) async* {
    yield 'User $id';
  }

  @generateCommandHandler
  Future<void> createUser(String name, String email) async {
    print('Creating user $name ($email)');
  }
}
