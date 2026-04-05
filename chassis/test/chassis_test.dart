import 'dart:async';

import 'package:chassis/chassis.dart';
import 'package:test/test.dart';

class AppSettings {}

final class ReadAppSettingsQuery extends ReadQuery<AppSettings> {}

final class WatchAppSettingsQuery extends WatchQuery<AppSettings> {}

// A handler that ONLY implements IQueryHandler
class ReadAppSettingsQueryHandler
    implements ReadHandler<ReadAppSettingsQuery, AppSettings> {
  ReadAppSettingsQueryHandler(this.repo);

  final ISomeRepo repo;

  @override
  Future<AppSettings> read(ReadAppSettingsQuery query) {
    return repo.test();
  }
}

abstract interface class ISomeRepo {
  Future<AppSettings> test();
  Stream<AppSettings> get stream;
}

class MockRepo implements ISomeRepo {
  Stream<AppSettings> _gen() async* {
    yield AppSettings();
  }

  @override
  Stream<AppSettings> get stream => _gen();

  @override
  Future<AppSettings> test() async {
    return AppSettings();
  }
}

sealed class UserQuery extends ReadQuery<String> {}

final class UserQueryA extends UserQuery {}

final class UserQueryB extends UserQuery {}

class UserQueryAHandler implements ReadHandler<UserQueryA, String> {
  @override
  Future<String> read(UserQueryA query) async => "Hello A";
}

class UserQueryBHandler implements ReadHandler<UserQueryB, String> {
  @override
  Future<String> read(UserQueryB query) async => "Hello B";
}

class InlineAppSettingsHandler
    implements ReadHandler<ReadAppSettingsQuery, AppSettings> {
  InlineAppSettingsHandler({required this.repo});

  final ISomeRepo repo;

  @override
  Future<AppSettings> read(ReadAppSettingsQuery query) {
    return repo.test();
  }
}

void main() {
  group('Mediator tests', () {
    test("Registering handler", () async {
      final repo = MockRepo();
      final mediator = Mediator()
        ..registerQueryHandler(InlineAppSettingsHandler(repo: repo));

      final AppSettings readtSettings =
          await mediator.read(ReadAppSettingsQuery());
    });

    test("Registering multiple handlers", () async {
      final repo = MockRepo();
      final mediator = Mediator()
        ..registerQueryHandler(InlineAppSettingsHandler(repo: repo))
        ..registerQueryHandler(UserQueryAHandler());

      final readtSettings = await mediator.read(ReadAppSettingsQuery());
      final user = await mediator.read(UserQueryA());

      expect(user, "Hello A");
    });

    test("Registering multiple handlers with polymorphism", () async {
      final repo = MockRepo();
      final mediator = Mediator()
        ..registerQueryHandler(InlineAppSettingsHandler(repo: repo))
        ..registerQueryHandler(UserQueryAHandler())
        ..registerQueryHandler(UserQueryBHandler());

      final readtSettings = await mediator.read(ReadAppSettingsQuery());
      final usera = await mediator.read(UserQueryA());
      final userb = await mediator.read(UserQueryB());

      expect(usera, "Hello A");
      expect(userb, "Hello B");
    });
  });
}
