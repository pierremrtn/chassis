// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// Generator: Instance of 'RepositoryGenerator'
// **************************************************************************

import 'package:chassis/chassis.dart';
import 'package:example/user_repository.dart';

class GetUserQuery implements ReadQuery<String> {
  const GetUserQuery({required String this.id});

  final String id;
}

@chassisHandler
class GetUserQueryHandler implements ReadHandler<GetUserQuery, String> {
  GetUserQueryHandler(this._repository);

  final UserRepository _repository;

  @override
  Future<String> read(GetUserQuery query) async {
    return await _repository.getUser(query.id);
  }
}

class WatchUserQuery implements WatchQuery<String> {
  const WatchUserQuery({required String this.id});

  final String id;
}

@chassisHandler
class WatchUserQueryHandler implements WatchHandler<WatchUserQuery, String> {
  WatchUserQueryHandler(this._repository);

  final UserRepository _repository;

  @override
  Stream<String> watch(WatchUserQuery query) {
    return _repository.watchUser(query.id);
  }
}

class CreateUserCommand implements Command<void> {
  const CreateUserCommand({
    required String this.name,
    required String this.email,
  });

  final String name;

  final String email;
}

@chassisHandler
class CreateUserCommandHandler
    implements CommandHandler<CreateUserCommand, void> {
  CreateUserCommandHandler(this._repository);

  final UserRepository _repository;

  @override
  Future<void> run(CreateUserCommand command) async {
    await _repository.createUser(
      command.name,
      command.email,
    );
  }
}
