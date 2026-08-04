import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:chassis_builder/chassis_builder.dart';
import 'package:test/test.dart';

/// Result of running the chassis builder over in-memory sources.
class GenResult {
  GenResult(this.outputs, this.succeeded, this.errors);

  /// Generated `.chassis.dart` contents keyed by `<pkg>|lib/...` asset id.
  final Map<String, String> outputs;
  final bool succeeded;
  final String errors;
}

/// Runs the chassis builder over [sources].
Future<GenResult> generate(
  Map<String, String> sources, {
  String rootPackage = 'app',
}) async {
  final generated = <String, String>{};
  // Make real packages (chassis, ...) visible to the test resolver.
  final readerWriter = TestReaderWriter(rootPackage: rootPackage);
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    chassisBuilder(BuilderOptions.empty),
    sources,
    rootPackage: rootPackage,
    readerWriter: readerWriter,
  );
  for (final id in result.readerWriter.testing.assets) {
    if (!id.path.endsWith('.chassis.dart')) continue;
    // Hidden generated outputs live under .dart_tool/build/generated/<pkg>/;
    // normalize back to '<pkg>|lib/...' keys.
    final path = id.path.replaceFirst(
      RegExp('^\\.dart_tool/build/generated/${id.package}/'),
      '',
    );
    generated['${id.package}|$path'] =
        result.readerWriter.testing.readString(id);
  }
  return GenResult(generated, result.succeeded, result.errors.join('\n'));
}

/// Runs the builder and returns outputs, asserting success.
Future<Map<String, String>> generateOutputs(
  Map<String, String> sources, {
  String rootPackage = 'app',
}) async {
  final result = await generate(sources, rootPackage: rootPackage);
  expect(result.succeeded, isTrue,
      reason: 'build failed with:\n${result.errors}');
  return result.outputs;
}

/// Asserts the build failed with an error message matching [matcher].
void expectBuildFailure(GenResult result, Matcher matcher) {
  expect(result.succeeded, isFalse, reason: 'expected the build to fail');
  expect(result.errors, matcher);
}

const _handlers = '''
import 'package:chassis/chassis.dart';

class UserRepository {}

final class GetUserQuery extends ReadQuery<String> {
  GetUserQuery({required this.id});
  final String id;
}

@chassisHandler
class GetUserHandler implements ReadHandler<GetUserQuery, String> {
  GetUserHandler(this.repository);
  final UserRepository repository;

  @override
  Future<String> read(GetUserQuery query) async => query.id;
}

final class WatchUserQuery extends WatchQuery<String> {
  WatchUserQuery(this.id);
  final String id;
}

@chassisHandler
class WatchUserHandler implements WatchHandler<WatchUserQuery, String> {
  WatchUserHandler(this.repository);
  final UserRepository repository;

  @override
  Stream<String> watch(WatchUserQuery query) => Stream.value(query.id);
}

final class DeleteUserCommand extends Command<void> {
  DeleteUserCommand(this.id);
  final String id;
}

@chassisHandler
class DeleteUserHandler implements CommandHandler<DeleteUserCommand, void> {
  DeleteUserHandler(this.repository);
  final UserRepository repository;

  @override
  Future<void> run(DeleteUserCommand command) async {}
}
''';

void main() {
  group('module interface generation', () {
    test('generates one typed method per handler', () async {
      final outputs = await generateOutputs({
        'app|lib/handlers.dart': _handlers,
        'app|lib/module.dart': '''
import 'package:chassis/chassis.dart';
import 'handlers.dart';

@chassisModule
final class UserModule {}
''',
      });

      final interface = outputs['app|lib/module.chassis.dart']!;
      expect(interface, contains('abstract interface class UserMediator'));
      expect(
          interface, contains('Future<String> getUser({required String id})'));
      expect(interface, contains('Stream<String> watchUser(String id)'));
      expect(interface, contains('Future<void> deleteUser(String id)'));
    });

    test('module class not ending in Module gets Mediator suffix', () async {
      final outputs = await generateOutputs({
        'app|lib/handlers.dart': _handlers,
        'app|lib/module.dart': '''
import 'package:chassis/chassis.dart';
import 'handlers.dart';

@chassisModule
final class Accounts {}
''',
      });

      expect(outputs['app|lib/module.chassis.dart'],
          contains('abstract interface class AccountsMediator'));
    });

    test('fails loudly when no handler is reachable', () async {
      expectBuildFailure(
        await generate({
          'app|lib/module.dart': '''
import 'package:chassis/chassis.dart';

@chassisModule
final class EmptyModule {}
''',
        }),
        contains('No @chassisHandler class is reachable'),
      );
    });
  });

  group('app mediator generation', () {
    test('generates registration, typed methods, and deduped dependencies',
        () async {
      final outputs = await generateOutputs({
        'app|lib/handlers.dart': _handlers,
        'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';
import 'handlers.dart';
''',
      });

      final mediator = outputs['app|lib/app.chassis.dart']!;
      expect(mediator, contains('class AppMediator extends'));
      // Three handlers share one UserRepository → a single constructor param.
      expect(
        RegExp('required .*UserRepository userRepository')
            .allMatches(mediator)
            .length,
        1,
      );
      expect(mediator, contains('registerQueryHandler'));
      expect(mediator, contains('registerCommandHandler'));
      // Methods dispatch through the mediator, never the handler directly.
      expect(mediator, matches(RegExp(r'=>\s*read\(')));
      expect(mediator, matches(RegExp(r'=>\s*run\(')));
      expect(mediator, matches(RegExp(r'=>\s*watch\(')));
    });

    test('custom mediator name', () async {
      final outputs = await generateOutputs({
        'app|lib/handlers.dart': _handlers,
        'app|lib/app.dart': '''
@ChassisApp(mediatorName: 'RootMediator')
library;

import 'package:chassis/chassis.dart';
import 'handlers.dart';
''',
      });

      expect(outputs['app|lib/app.chassis.dart'],
          contains('class RootMediator extends'));
    });

    test(
        'same-named dependency types from different libraries get distinct '
        'parameters', () async {
      final outputs = await generateOutputs({
        'app|lib/a.dart': '''
import 'package:chassis/chassis.dart';

class Repo {}

final class AQuery extends ReadQuery<int> {}

@chassisHandler
class AHandler implements ReadHandler<AQuery, int> {
  AHandler(this.repo);
  final Repo repo;
  @override
  Future<int> read(AQuery query) async => 1;
}
''',
        'app|lib/b.dart': '''
import 'package:chassis/chassis.dart';

class Repo {}

final class BQuery extends ReadQuery<int> {}

@chassisHandler
class BHandler implements ReadHandler<BQuery, int> {
  BHandler(this.repo);
  final Repo repo;
  @override
  Future<int> read(BQuery query) async => 2;
}
''',
        'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';
import 'a.dart';
import 'b.dart';
''',
      });

      final mediator = outputs['app|lib/app.chassis.dart']!;
      expect(mediator, contains('Repo repo,'));
      expect(mediator, contains('Repo repo2'));
    });

    test('generic dependency types produce valid parameter names', () async {
      final outputs = await generateOutputs({
        'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class ItemsQuery extends ReadQuery<int> {}

@chassisHandler
class ItemsHandler implements ReadHandler<ItemsQuery, int> {
  ItemsHandler(this.seed);
  final List<String> seed;
  @override
  Future<int> read(ItemsQuery query) async => seed.length;
}
''',
      });

      final mediator = outputs['app|lib/app.chassis.dart']!;
      expect(mediator, contains('required List<String> list'));
    });

    test('named constructor dependencies are passed by name', () async {
      final outputs = await generateOutputs({
        'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

class UserRepository {}

class Clock {}

final class PingQuery extends ReadQuery<int> {}

@chassisHandler
class PingHandler implements ReadHandler<PingQuery, int> {
  PingHandler({required this.repository, required this.clock});
  final UserRepository repository;
  final Clock clock;
  @override
  Future<int> read(PingQuery query) async => 1;
}
''',
      });

      final mediator = outputs['app|lib/app.chassis.dart']!;
      expect(mediator, contains('required'));
      expect(
        mediator,
        matches(RegExp(
            r'PingHandler\(\s*repository:\s*userRepository,\s*clock:\s*clock,?\s*\)')),
      );
    });

    test('mixed positional and named dependencies keep their form', () async {
      final outputs = await generateOutputs({
        'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

class UserRepository {}

class Clock {}

final class PingQuery extends ReadQuery<int> {}

final class PongQuery extends ReadQuery<int> {}

@chassisHandler
class PingHandler implements ReadHandler<PingQuery, int> {
  PingHandler(this.repository, {required this.clock});
  final UserRepository repository;
  final Clock clock;
  @override
  Future<int> read(PingQuery query) async => 1;
}

// Same dependency, positionally: the mediator constructor still declares
// UserRepository once and threads it to both handlers.
@chassisHandler
class PongHandler implements ReadHandler<PongQuery, int> {
  PongHandler(this.repository);
  final UserRepository repository;
  @override
  Future<int> read(PongQuery query) async => 2;
}
''',
      });

      final mediator = outputs['app|lib/app.chassis.dart']!;
      expect(
        mediator,
        matches(
            RegExp(r'PingHandler\(\s*userRepository,\s*clock:\s*clock,?\s*\)')),
      );
      expect(
          mediator, matches(RegExp(r'PongHandler\(\s*userRepository,?\s*\)')));
      expect(
        RegExp('required .*UserRepository userRepository')
            .allMatches(mediator)
            .length,
        1,
        reason: 'the dependency is deduped by type across both forms',
      );
    });

    test('method names derive from the message, not the handler', () async {
      final outputs = await generateOutputs({
        'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class HandlerFactoryQuery extends ReadQuery<int> {}

// Deliberately named nothing like the message: the generated method must
// still be derived from HandlerFactoryQuery.
@chassisHandler
class LegacyLookupImpl implements ReadHandler<HandlerFactoryQuery, int> {
  LegacyLookupImpl();
  @override
  Future<int> read(HandlerFactoryQuery query) async => 1;
}
''',
      });

      expect(outputs['app|lib/app.chassis.dart'],
          contains('Future<int> handlerFactory()'));
    });

    test('fails when a message class is generic', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class FetchQuery<T> extends ReadQuery<T> {}

@chassisHandler
class FetchStringHandler implements ReadHandler<FetchQuery<String>, String> {
  FetchStringHandler();
  @override
  Future<String> read(FetchQuery<String> query) async => '';
}
''',
        }),
        contains('is generic'),
      );
    });

    test('fails when a message parameter has a function type', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class TransformQuery extends ReadQuery<int> {
  TransformQuery(this.transform);
  final int Function(int) transform;
}

@chassisHandler
class TransformHandler implements ReadHandler<TransformQuery, int> {
  TransformHandler();
  @override
  Future<int> read(TransformQuery query) async => query.transform(1);
}
''',
        }),
        contains('function type'),
      );
    });

    test('fails when a handler dependency has a record type', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class PingQuery extends ReadQuery<int> {}

@chassisHandler
class PingHandler implements ReadHandler<PingQuery, int> {
  PingHandler(this.config);
  final (String, int) config;
  @override
  Future<int> read(PingQuery query) async => config.\$2;
}
''',
        }),
        contains('record type'),
      );
    });

    test('fails when a handler has no unnamed constructor', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class PingQuery extends ReadQuery<int> {}

@chassisHandler
class PingHandler implements ReadHandler<PingQuery, int> {
  PingHandler.create();
  @override
  Future<int> read(PingQuery query) async => 1;
}
''',
        }),
        contains('no unnamed generative constructor'),
      );
    });

    test('fails when a handler implements no handler interface', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

@chassisHandler
class NotAHandler {
  NotAHandler();
}
''',
        }),
        contains('implements none of CommandHandler, ReadHandler'),
      );
    });

    test('fails when two handlers handle the same message type', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class PingQuery extends ReadQuery<int> {}

@chassisHandler
class FirstPingHandler implements ReadHandler<PingQuery, int> {
  FirstPingHandler();
  @override
  Future<int> read(PingQuery query) async => 1;
}

@chassisHandler
class SecondPingHandler implements ReadHandler<PingQuery, int> {
  SecondPingHandler();
  @override
  Future<int> read(PingQuery query) async => 2;
}
''',
        }),
        contains('exactly one handler'),
      );
    });

    test('fails when modules list a non-module class', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp(modules: [NotAModule])
library;

import 'package:chassis/chassis.dart';

final class NotAModule {}
''',
        }),
        contains('not a class annotated with @chassisModule'),
      );
    });

    test('fails when no handler and no module is declared', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';
''',
        }),
        contains('found no @chassisHandler class'),
      );
    });

    test('fails when a handler class is private', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class PingQuery extends ReadQuery<int> {}

@chassisHandler
class _PingHandler implements ReadHandler<PingQuery, int> {
  _PingHandler();
  @override
  Future<int> read(PingQuery query) async => 1;
}
''',
        }),
        contains('is private'),
      );
    });

    test('fails when a message class is private', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class _PingQuery extends ReadQuery<int> {}

@chassisHandler
class PingHandler implements ReadHandler<_PingQuery, int> {
  PingHandler();
  @override
  Future<int> read(_PingQuery query) async => 1;
}
''',
        }),
        contains('is private'),
      );
    });

    test('fails when a module class is private', () async {
      expectBuildFailure(
        await generate({
          'app|lib/handlers.dart': _handlers,
          'app|lib/module.dart': '''
import 'package:chassis/chassis.dart';
import 'handlers.dart';

@chassisModule
final class _UserModule {}
''',
        }),
        contains('is private'),
      );
    });

    test('dart:core default values are repeated in the generated method',
        () async {
      final outputs = await generateOutputs({
        'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class SearchQuery extends ReadQuery<int> {
  SearchQuery({this.limit = 20, this.debounce = const Duration(milliseconds: 300)});
  final int limit;
  final Duration debounce;
}

@chassisHandler
class SearchHandler implements ReadHandler<SearchQuery, int> {
  SearchHandler();
  @override
  Future<int> read(SearchQuery query) async => query.limit;
}
''',
      });

      final mediator = outputs['app|lib/app.chassis.dart']!;
      expect(mediator, contains('int limit = 20'));
      expect(mediator,
          contains('Duration debounce = const Duration(milliseconds: 300)'));
    });

    test('fails when a default value references a non-dart:core declaration',
        () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

enum SortOrder { ascending, descending }

final class ListQuery extends ReadQuery<int> {
  ListQuery({this.order = SortOrder.ascending});
  final SortOrder order;
}

@chassisHandler
class ListHandler implements ReadHandler<ListQuery, int> {
  ListHandler();
  @override
  Future<int> read(ListQuery query) async => 1;
}
''',
        }),
        contains('default value'),
      );
    });

    test('fails when @ChassisApp annotates a class', () async {
      expectBuildFailure(
        await generate({
          'app|lib/handlers.dart': _handlers,
          'app|lib/app.dart': '''
import 'package:chassis/chassis.dart';
import 'handlers.dart';

@ChassisApp()
final class App {}
''',
        }),
        contains('must annotate the library directive'),
      );
    });
  });

  group('cross-package composition', () {
    const moduleSource = '''
import 'package:chassis/chassis.dart';

abstract interface class AuthRepository {
  Future<void> login(String username);
}

final class LoginCommand extends Command<void> {
  LoginCommand(this.username);
  final String username;
}

@chassisHandler
class LoginHandler implements CommandHandler<LoginCommand, void> {
  LoginHandler(this.repository);
  final AuthRepository repository;
  @override
  Future<void> run(LoginCommand command) => repository.login(command.username);
}

@chassisModule
final class AuthModule {}
''';

    test(
        'app mediator implements the module interface and registers its '
        'handlers', () async {
      final outputs = await generateOutputs({
        'auth|lib/auth.dart': moduleSource,
        'app|lib/app.dart': '''
@ChassisApp(modules: [AuthModule])
library;

import 'package:chassis/chassis.dart';
import 'package:auth/auth.dart';
''',
      });

      final mediator = outputs['app|lib/app.chassis.dart']!;
      expect(mediator, contains('implements'));
      expect(mediator, contains('AuthMediator'));
      expect(mediator, contains('auth.chassis.dart'));
      expect(mediator, contains('registerCommandHandler'));
      expect(mediator, contains('@override'));
      expect(mediator, contains('login(String username)'));
    });

    test('fails when two modules produce identical method signatures',
        () async {
      const otherModule = '''
import 'package:chassis/chassis.dart';

final class LoginCommand extends Command<void> {
  LoginCommand(this.username);
  final String username;
}

@chassisHandler
class LoginHandler implements CommandHandler<LoginCommand, void> {
  LoginHandler();
  @override
  Future<void> run(LoginCommand command) async {}
}

@chassisModule
final class SsoModule {}
''';

      expectBuildFailure(
        await generate({
          'auth|lib/auth.dart': moduleSource,
          'sso|lib/sso.dart': otherModule,
          'app|lib/app.dart': '''
@ChassisApp(modules: [AuthModule, SsoModule])
library;

import 'package:chassis/chassis.dart';
import 'package:auth/auth.dart';
import 'package:sso/sso.dart';
''',
        }),
        contains('identical signature'),
      );
    });

    test(
        'fails when two modules derive the same method name with different '
        'signatures', () async {
      // Same derived name `login`, different parameters: without the
      // cross-owner name check this would emit two `login` methods — invalid
      // Dart in the generated file.
      const otherModule = '''
import 'package:chassis/chassis.dart';

final class LoginCommand extends Command<void> {
  LoginCommand(this.username, this.password);
  final String username;
  final String password;
}

@chassisHandler
class LoginHandler implements CommandHandler<LoginCommand, void> {
  LoginHandler();
  @override
  Future<void> run(LoginCommand command) async {}
}

@chassisModule
final class SsoModule {}
''';

      expectBuildFailure(
        await generate({
          'auth|lib/auth.dart': moduleSource,
          'sso|lib/sso.dart': otherModule,
          'app|lib/app.dart': '''
@ChassisApp(modules: [AuthModule, SsoModule])
library;

import 'package:chassis/chassis.dart';
import 'package:auth/auth.dart';
import 'package:sso/sso.dart';
''',
        }),
        contains('both derive the method name'),
      );
    });
  });
}
