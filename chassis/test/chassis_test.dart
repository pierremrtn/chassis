import 'dart:async';

import 'package:chassis/chassis.dart';
import 'package:test/test.dart';

class AppSettings {}

class AppSettingsQuery implements ReadAndWatch<AppSettings> {}

// A handler that ONLY implements IQueryHandler
class AppSettingsHandler
    implements
        ReadHandler<AppSettingsQuery, AppSettings>,
        WatchHandler<AppSettingsQuery, AppSettings> {
  AppSettingsHandler(this.repo);

  final ISomeRepo repo;

  @override
  Future<AppSettings> read(AppSettingsQuery query) {
    return repo.test();
  }

  @override
  Stream<AppSettings> watch(AppSettingsQuery query) {
    return repo.stream;
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
    extends ReadAndWatchHandler<AppSettingsQuery, AppSettings> {
  InlineAppSettingsHandler({required ISomeRepo repo})
      : super(
          read: (_) => repo.test(),
          watch: (_) => repo.stream,
        );
}

void main() {
  group('Mediator tests', () {
    test("Registering handler", () async {
      final repo = MockRepo();
      final mediator = Mediator()
        ..registerQuery(InlineAppSettingsHandler(repo: repo));

      final AppSettings readtSettings = await mediator.read(AppSettingsQuery());
      final watchSettings = await mediator.watch(AppSettingsQuery()).first;
    });

    test("Registering multiple handlers", () async {
      final repo = MockRepo();
      final mediator = Mediator()
        ..registerQuery(InlineAppSettingsHandler(repo: repo))
        ..registerQuery(UserQueryAHandler());

      final readtSettings = await mediator.read(AppSettingsQuery());
      final user = await mediator.read(UserQueryA());

      expect(user, "Hello A");
    });

    test("Registering multiple handlers with polymorphism", () async {
      final repo = MockRepo();
      final mediator = Mediator()
        ..registerQuery(InlineAppSettingsHandler(repo: repo))
        ..registerQuery(UserQueryAHandler())
        ..registerQuery(UserQueryBHandler());

      final readtSettings = await mediator.read(AppSettingsQuery());
      final usera = await mediator.read(UserQueryA());
      final userb = await mediator.read(UserQueryB());

      expect(usera, "Hello A");
      expect(userb, "Hello B");
    });
  });
}
