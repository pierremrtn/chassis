import 'dart:async';

import 'package:chassis/chassis.dart';
import 'package:test/test.dart';

class AppSettings {}

class ReadAppSettingsQuery implements Read<AppSettings> {}

class WatchAppSettingsQuery implements Watch<AppSettings> {}

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

sealed class UserQuery implements Read<String> {}

class UserQueryA implements UserQuery {}

class UserQueryB implements UserQuery {}

class UserQueryAHandler extends ReadHandler<UserQueryA, String> {
  UserQueryAHandler()
      : super(
          read: (_) async => "Hello A",
        );
}

class UserQueryBHandler extends ReadHandler<UserQueryB, String> {
  UserQueryBHandler()
      : super(
          read: (_) async => "Hello B",
        );
}

class InlineAppSettingsHandler
    extends ReadHandler<ReadAppSettingsQuery, AppSettings> {
  InlineAppSettingsHandler({required ISomeRepo repo})
      : super(
          read: (_) => repo.test(),
        );
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
