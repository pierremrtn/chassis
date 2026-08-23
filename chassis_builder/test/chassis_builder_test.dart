import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:chassis_builder/chassis_builder.dart';
import 'package:test/test.dart';

/// Result of running the chassis builder over in-memory sources.
class GenResult {
  GenResult(this.outputs, this.succeeded, this.errors, this.logs);

  /// Generated `.chassis.dart` contents keyed by `<pkg>|lib/...` asset id.
  final Map<String, String> outputs;
  final bool succeeded;
  final String errors;

  /// Build log records as `LEVEL: message` strings.
  final List<String> logs;

  Iterable<String> get warnings => logs.where((l) => l.startsWith('WARNING: '));
}

/// Runs the chassis builder over [sources].
Future<GenResult> generate(
  Map<String, String> sources, {
  String rootPackage = 'app',
}) async {
  final generated = <String, String>{};
  final logs = <String>[];
  // Make real packages (chassis, ...) visible to the test resolver.
  final readerWriter = TestReaderWriter(rootPackage: rootPackage);
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    chassisBuilder(BuilderOptions.empty),
    sources,
    rootPackage: rootPackage,
    readerWriter: readerWriter,
    onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
  );
  // loadIsolateSources also loads real on-disk assets (the example
  // packages, including their generated files): only collect outputs for
  // the in-memory source packages of this test.
  final sourcePackages = sources.keys
      .map((key) => AssetId.parse(key).package)
      .toSet();
  for (final id in result.readerWriter.testing.assets) {
    if (!id.path.endsWith('.chassis.dart')) continue;
    if (!sourcePackages.contains(id.package)) continue;
    // Hidden generated outputs live under .dart_tool/build/generated/<pkg>/;
    // normalize back to '<pkg>|lib/...' keys.
    final path = id.path.replaceFirst(
      RegExp('^\\.dart_tool/build/generated/${id.package}/'),
      '',
    );
    generated['${id.package}|$path'] = result.readerWriter.testing.readString(
      id,
    );
  }
  return GenResult(generated, result.succeeded, result.errors.join('\n'), logs);
}

/// Runs the builder and returns outputs, asserting success.
///
/// With [analyze] (the default), also re-analyzes every generated output
/// against the input sources and fails on any compile error — string
/// expectations alone cannot prove the generated code is valid Dart.
Future<Map<String, String>> generateOutputs(
  Map<String, String> sources, {
  String rootPackage = 'app',
  bool analyze = true,
}) async {
  final result = await generate(sources, rootPackage: rootPackage);
  expect(
    result.succeeded,
    isTrue,
    reason: 'build failed with:\n${result.errors}',
  );
  if (analyze) {
    await expectGeneratedCodeIsValid(
      sources,
      result.outputs,
      rootPackage: rootPackage,
    );
  }
  return result.outputs;
}

/// Resolves [sources] plus generated [outputs] and fails on any diagnostic
/// of severity error inside the generated files.
Future<void> expectGeneratedCodeIsValid(
  Map<String, String> sources,
  Map<String, String> outputs, {
  String rootPackage = 'app',
}) async {
  if (outputs.isEmpty) return;
  await resolveSources(
    {...sources, ...outputs},
    rootPackage: rootPackage,
    // Make the real chassis package readable by the in-memory resolver.
    readAllSourcesFromFilesystem: true,
    (resolver) async {
      for (final entry in outputs.entries) {
        final library = await resolver.libraryFor(AssetId.parse(entry.key));
        final resolved = await library.session.getResolvedLibraryByElement(
          library,
        );
        if (resolved is! ResolvedLibraryResult) {
          fail('could not resolve generated ${entry.key}: $resolved');
        }
        final errors = [
          for (final unit in resolved.units)
            for (final diagnostic in unit.diagnostics)
              if (diagnostic.severity == Severity.error) diagnostic,
        ];
        expect(
          errors,
          isEmpty,
          reason:
              'generated ${entry.key} does not compile:\n'
              '${errors.join('\n')}\n\n${entry.value}',
        );
      }
    },
  );
}

/// Asserts the build failed with an error message matching [matcher].
void expectBuildFailure(GenResult result, Matcher matcher) {
  expect(result.succeeded, isFalse, reason: 'expected the build to fail');
  expect(result.errors, matcher);
}

const _handlers = '''
import 'package:chassis/chassis.dart';

class UserRepository {}

final class GetUserQuery({required final String id}) extends ReadQuery<String>;

@chassisHandler
class GetUserHandler(final UserRepository repository)
    implements ReadHandler<GetUserQuery, String> {
  @override
  Future<String> read(GetUserQuery query) async => query.id;
}

final class WatchUserQuery(final String id) extends WatchQuery<String>;

@chassisHandler
class WatchUserHandler(final UserRepository repository)
    implements WatchHandler<WatchUserQuery, String> {
  @override
  Stream<String> watch(WatchUserQuery query) => Stream.value(query.id);
}

final class DeleteUserCommand(final String id) extends Command<void>;

@chassisHandler
class DeleteUserHandler(final UserRepository repository)
    implements CommandHandler<DeleteUserCommand, void> {
  @override
  Future<void> run(DeleteUserCommand command) async {}
}
''';

void main() {
  group('module validation', () {
    test('a module library generates no output', () async {
      final outputs = await generateOutputs({
        'app|lib/handlers.dart': _handlers,
        'app|lib/module.dart': '''
import 'package:chassis/chassis.dart';
import 'handlers.dart';

@chassisModule
final class UserModule {}
''',
      });

      expect(
        outputs,
        isEmpty,
        reason:
            'modules only mark a package for handler discovery — '
            'nothing is generated for them',
      );
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

    test(
      'validates the module package handlers at module build time',
      () async {
        expectBuildFailure(
          await generate({
            'app|lib/module.dart': '''
import 'package:chassis/chassis.dart';

final class PingQuery extends ReadQuery<int> {}

@chassisHandler
class _PingHandler implements ReadHandler<PingQuery, int> {
  _PingHandler();
  @override
  Future<int> read(PingQuery query) async => 1;
}

@chassisModule
final class UserModule {}
''',
          }),
          contains('is private'),
        );
      },
    );
  });

  group('app mediator generation', () {
    test(
      'generates constructor registration only, with deduped dependencies',
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
        // No per-message methods, no module interfaces: dispatch goes through
        // the inherited run/read/watch with the message object.
        expect(mediator, isNot(contains('implements')));
        expect(mediator, isNot(contains('getUser')));
        expect(mediator, isNot(contains('watchUser')));
        expect(mediator, isNot(contains('deleteUser')));
      },
    );

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

      expect(
        outputs['app|lib/app.chassis.dart'],
        contains('class RootMediator extends'),
      );
    });

    test('same-named dependency types from different libraries get distinct '
        'parameters', () async {
      final outputs = await generateOutputs({
        'app|lib/a.dart': '''
import 'package:chassis/chassis.dart';

class Repo {}

final class AQuery extends ReadQuery<int> {}

@chassisHandler
class AHandler(final Repo repo) implements ReadHandler<AQuery, int> {
  @override
  Future<int> read(AQuery query) async => 1;
}
''',
        'app|lib/b.dart': '''
import 'package:chassis/chassis.dart';

class Repo {}

final class BQuery extends ReadQuery<int> {}

@chassisHandler
class BHandler(final Repo repo) implements ReadHandler<BQuery, int> {
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
class ItemsHandler(final List<String> seed)
    implements ReadHandler<ItemsQuery, int> {
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
class PingHandler({
  required final UserRepository repository,
  required final Clock clock,
}) implements ReadHandler<PingQuery, int> {
  @override
  Future<int> read(PingQuery query) async => 1;
}
''',
      });

      final mediator = outputs['app|lib/app.chassis.dart']!;
      expect(mediator, contains('required'));
      expect(
        mediator,
        matches(
          RegExp(
            r'PingHandler\(\s*repository:\s*userRepository,\s*clock:\s*clock,?\s*\)',
          ),
        ),
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
class PingHandler(final UserRepository repository, {required final Clock clock})
    implements ReadHandler<PingQuery, int> {
  @override
  Future<int> read(PingQuery query) async => 1;
}

// Same dependency, positionally: the mediator constructor still declares
// UserRepository once and threads it to both handlers.
@chassisHandler
class PongHandler(final UserRepository repository)
    implements ReadHandler<PongQuery, int> {
  @override
  Future<int> read(PongQuery query) async => 2;
}
''',
      });

      final mediator = outputs['app|lib/app.chassis.dart']!;
      expect(
        mediator,
        matches(
          RegExp(r'PingHandler\(\s*userRepository,\s*clock:\s*clock,?\s*\)'),
        ),
      );
      expect(
        mediator,
        matches(RegExp(r'PongHandler\(\s*userRepository,?\s*\)')),
      );
      expect(
        RegExp('required .*UserRepository userRepository')
            .allMatches(mediator)
            .length,
        1,
        reason: 'the dependency is deduped by type across both forms',
      );
    });

    test(
      'primary-constructor declarations: header-form command and '
      'header-declared handler dependencies register like classic syntax',
      () async {
        final outputs = await generateOutputs({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

class UserRepository {
  Future<void> create(String name, String email) async {}
}

final class CreateUserCommand({
  required final String name,
  required final String email,
}) extends Command<void>;

@chassisHandler
class CreateUserHandler(final UserRepository _repository)
    implements CommandHandler<CreateUserCommand, void> {
  @override
  Future<void> run(CreateUserCommand command) =>
      _repository.create(command.name, command.email);
}
''',
        });

        final mediator = outputs['app|lib/app.chassis.dart']!;
        expect(mediator, contains('class AppMediator extends'));
        // The header-declared dependency surfaces as a required named
        // constructor parameter on the mediator, exactly like a classic
        // `this.`-assigning constructor would.
        expect(
          RegExp('required .*UserRepository userRepository')
              .allMatches(mediator)
              .length,
          1,
        );
        // The handler is registered, its positional declaring parameter
        // passed positionally (the private `_repository` name never leaks
        // into generated code).
        expect(mediator, contains('registerCommandHandler'));
        expect(
          mediator,
          matches(RegExp(r'CreateUserHandler\(\s*userRepository,?\s*\)')),
        );
        expect(mediator, isNot(contains('_repository')));
      },
    );

    test('private message and result types are fine: registration relies on '
        'inference and never denotes them', () async {
      final outputs = await generateOutputs({
        'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

class _Session {
  const _Session();
}

final class _RefreshQuery extends ReadQuery<_Session> {}

@chassisHandler
class RefreshHandler implements ReadHandler<_RefreshQuery, _Session> {
  RefreshHandler();
  @override
  Future<_Session> read(_RefreshQuery query) async => const _Session();
}
''',
      });

      expect(
        outputs['app|lib/app.chassis.dart'],
        contains('registerQueryHandler(_i2.RefreshHandler())'),
      );
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

    test('fails when a handler dependency has a record type', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class PingQuery extends ReadQuery<int> {}

@chassisHandler
class PingHandler(final (String, int) config)
    implements ReadHandler<PingQuery, int> {
  @override
  Future<int> read(PingQuery query) async => config.\$2;
}
''',
        }),
        contains('record type'),
      );
    });

    test('fails when a handler depends on the Mediator', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class RefreshProfileCommand extends Command<void> {}

@chassisHandler
class RefreshProfileHandler(final Mediator mediator)
    implements CommandHandler<RefreshProfileCommand, void> {
  @override
  Future<void> run(RefreshProfileCommand command) async {}
}
''',
        }),
        contains('must not dispatch'),
      );
    });

    test('fails when a handler depends on a Mediator subclass', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

class MyMediator extends Mediator {}

final class PingQuery extends ReadQuery<int> {}

@chassisHandler
class PingHandler(final MyMediator mediator)
    implements ReadHandler<PingQuery, int> {
  @override
  Future<int> read(PingQuery query) async => 1;
}
''',
        }),
        contains('must not dispatch'),
      );
    });

    test('fails when a handler depends on a generated mediator', () async {
      expectBuildFailure(
        await generate({
          // Stands in for a generated mediator: what matters is the
          // `.chassis.dart` library suffix, not how the file was produced.
          'app|lib/auth.chassis.dart': '''
abstract interface class AuthGateway {
  Future<void> login(String username);
}
''',
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';
import 'auth.chassis.dart';

final class PingQuery extends ReadQuery<int> {}

@chassisHandler
class PingHandler(final AuthGateway gateway)
    implements ReadHandler<PingQuery, int> {
  @override
  Future<int> read(PingQuery query) async => 1;
}
''',
        }),
        contains('must not dispatch'),
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

  group('generator holes (C2)', () {
    test('fails when a handler implements two operation interfaces', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class SyncCommand extends Command<void> {}

final class StatusQuery extends ReadQuery<int> {}

@chassisHandler
class DualHandler
    implements CommandHandler<SyncCommand, void>,
        ReadHandler<StatusQuery, int> {
  DualHandler();
  @override
  Future<void> run(SyncCommand command) async {}
  @override
  Future<int> read(StatusQuery query) async => 1;
}
''',
        }),
        allOf(
          contains('CommandHandler and ReadHandler'),
          contains('split it into two handler classes'),
        ),
      );
    });

    test('fails when a handler dependency has a private type', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

class _Config {}

final class PingQuery extends ReadQuery<int> {}

@chassisHandler
class PingHandler(final _Config config)
    implements ReadHandler<PingQuery, int> {
  @override
  Future<int> read(PingQuery query) async => 1;
}
''',
        }),
        allOf(
          contains('private type `_Config`'),
          contains('Make the type public'),
        ),
      );
    });

    test(
      'fails when a private type hides in a dependency type argument',
      () async {
        expectBuildFailure(
          await generate({
            'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

class _Config {}

final class PingQuery extends ReadQuery<int> {}

@chassisHandler
class PingHandler(final List<_Config> configs)
    implements ReadHandler<PingQuery, int> {
  @override
  Future<int> read(PingQuery query) async => configs.length;
}
''',
          }),
          contains('private type `_Config`'),
        );
      },
    );
  });

  group('message-without-handler check (C1)', () {
    test('fails when a reachable concrete message has no handler', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class PingQuery extends ReadQuery<int> {}

final class ExportDataCommand extends Command<void> {}

@chassisHandler
class PingHandler implements ReadHandler<PingQuery, int> {
  PingHandler();
  @override
  Future<int> read(PingQuery query) async => 1;
}
''',
        }),
        allOf(
          contains('No handler is registered'),
          contains('ExportDataCommand'),
          contains('@chassisHandler'),
          contains('@unhandledMessage'),
        ),
      );
    });

    test('lists every orphan message in one error', () async {
      expectBuildFailure(
        await generate({
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class PingQuery extends ReadQuery<int> {}

final class ExportDataCommand extends Command<void> {}

final class WatchExportQuery extends WatchQuery<int> {}

@chassisHandler
class PingHandler implements ReadHandler<PingQuery, int> {
  PingHandler();
  @override
  Future<int> read(PingQuery query) async => 1;
}
''',
        }),
        allOf(contains('ExportDataCommand'), contains('WatchExportQuery')),
      );
    });

    test('@unhandledMessage opts a message out', () async {
      final outputs = await generateOutputs({
        'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

final class PingQuery extends ReadQuery<int> {}

@unhandledMessage // handler comes in the next commit
final class ExportDataCommand extends Command<void> {}

@chassisHandler
class PingHandler implements ReadHandler<PingQuery, int> {
  PingHandler();
  @override
  Future<int> read(PingQuery query) async => 1;
}
''',
      });

      expect(outputs['app|lib/app.chassis.dart'], contains('PingHandler'));
    });

    test('abstract and sealed message base classes are not flagged', () async {
      final outputs = await generateOutputs({
        'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';

abstract base class TodoCommand extends Command<void> {}

sealed class TodoQuery extends ReadQuery<int> {}

final class CountTodosQuery extends TodoQuery {}

final class ClearTodosCommand extends TodoCommand {}

@chassisHandler
class CountTodosHandler implements ReadHandler<CountTodosQuery, int> {
  CountTodosHandler();
  @override
  Future<int> read(CountTodosQuery query) async => 0;
}

@chassisHandler
class ClearTodosHandler implements CommandHandler<ClearTodosCommand, void> {
  ClearTodosHandler();
  @override
  Future<void> run(ClearTodosCommand command) async {}
}
''',
      });

      expect(
        outputs['app|lib/app.chassis.dart'],
        contains('registerCommandHandler'),
      );
    });

    test('fails when a message of a non-module third-party package is '
        'reachable (instead of a runtime HandlerNotRegisteredError)', () async {
      expectBuildFailure(
        await generate({
          'legacy|lib/src/messages.dart': '''
import 'package:chassis/chassis.dart';

final class PurgeCommand extends Command<void> {}
''',
          'legacy|lib/legacy.dart': '''
export 'src/messages.dart';
''',
          'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';
import 'package:legacy/legacy.dart';

final class PingQuery extends ReadQuery<int> {}

@chassisHandler
class PingHandler implements ReadHandler<PingQuery, int> {
  PingHandler();
  @override
  Future<int> read(PingQuery query) async => 1;
}
''',
        }),
        allOf(contains('PurgeCommand'), contains('@chassisModule')),
      );
    });

    test('an app handler can cover a third-party message', () async {
      final result = await generate({
        'legacy|lib/legacy.dart': '''
import 'package:chassis/chassis.dart';

final class PurgeCommand extends Command<void> {}
''',
        'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';
import 'package:legacy/legacy.dart';

@chassisHandler
class AppPurgeHandler implements CommandHandler<PurgeCommand, void> {
  AppPurgeHandler();
  @override
  Future<void> run(PurgeCommand command) async {}
}
''',
      });

      expect(result.succeeded, isTrue, reason: result.errors);
      expect(
        result.outputs['app|lib/app.chassis.dart'],
        contains('AppPurgeHandler'),
      );
    });
  });

  group('out-of-package handler warning (C4)', () {
    test('warns when a reachable handler is not covered by a module', () async {
      final result = await generate({
        'legacy|lib/legacy.dart': '''
import 'package:chassis/chassis.dart';

final class PurgeCommand extends Command<void> {}

@chassisHandler
class PurgeHandler implements CommandHandler<PurgeCommand, void> {
  PurgeHandler();
  @override
  Future<void> run(PurgeCommand command) async {}
}
''',
        'app|lib/app.dart': '''
@ChassisApp()
library;

import 'package:chassis/chassis.dart';
import 'package:legacy/legacy.dart';

// The app provides its own handler for the third-party message, so the
// build succeeds — but the third-party handler is still ignored.
@chassisHandler
class AppPurgeHandler implements CommandHandler<PurgeCommand, void> {
  AppPurgeHandler();
  @override
  Future<void> run(PurgeCommand command) async {}
}
''',
      });

      expect(result.succeeded, isTrue, reason: result.errors);
      expect(
        result.warnings,
        anyElement(
          allOf(
            contains('PurgeHandler'),
            contains('package `legacy`'),
            contains('neither the app package nor a declared module'),
          ),
        ),
      );
    });

    test('does not warn about handlers of a declared module', () async {
      final result = await generate({
        'auth|lib/auth.dart': '''
import 'package:chassis/chassis.dart';

final class LoginCommand extends Command<void> {}

@chassisHandler
class LoginHandler implements CommandHandler<LoginCommand, void> {
  LoginHandler();
  @override
  Future<void> run(LoginCommand command) async {}
}

@chassisModule
final class AuthModule {}
''',
        'app|lib/app.dart': '''
@ChassisApp(modules: [AuthModule])
library;

import 'package:chassis/chassis.dart';
import 'package:auth/auth.dart';
''',
      });

      expect(result.succeeded, isTrue, reason: result.errors);
      expect(result.warnings, isEmpty);
    });
  });

  group('cross-package composition', () {
    const moduleSource = '''
import 'package:chassis/chassis.dart';

abstract interface class AuthRepository {
  Future<void> login(String username);
}

final class LoginCommand(final String username) extends Command<void>;

@chassisHandler
class LoginHandler(final AuthRepository repository)
    implements CommandHandler<LoginCommand, void> {
  @override
  Future<void> run(LoginCommand command) => repository.login(command.username);
}

@chassisModule
final class AuthModule {}
''';

    test('registers module handlers on the app mediator', () async {
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
      expect(mediator, contains('registerCommandHandler'));
      expect(mediator, contains('LoginHandler'));
      expect(mediator, contains('required'));
      expect(mediator, contains('AuthRepository authRepository'));
      // No module interface exists anymore: nothing to implement.
      expect(mediator, isNot(contains('implements')));
      expect(mediator, isNot(contains('AuthMediator')));
      expect(mediator, isNot(contains('.chassis.dart')));
    });

    test('same-named messages in different modules are two distinct '
        'registrations', () async {
      const otherModule = '''
import 'package:chassis/chassis.dart';

final class LoginCommand(final String username, final String password)
    extends Command<void>;

@chassisHandler
class LoginHandler implements CommandHandler<LoginCommand, void> {
  LoginHandler();
  @override
  Future<void> run(LoginCommand command) async {}
}

@chassisModule
final class SsoModule {}
''';

      final outputs = await generateOutputs({
        'auth|lib/auth.dart': moduleSource,
        'sso|lib/sso.dart': otherModule,
        'app|lib/app.dart': '''
@ChassisApp(modules: [AuthModule, SsoModule])
library;

import 'package:chassis/chassis.dart';
import 'package:auth/auth.dart';
import 'package:sso/sso.dart';
''',
      });

      final mediator = outputs['app|lib/app.chassis.dart']!;
      // Registration is keyed by the message type, so two same-named
      // messages from different packages coexist (import prefixes
      // disambiguate) — post-pivot there is no method-name collision.
      expect(RegExp('registerCommandHandler').allMatches(mediator).length, 2);
    });

    test('fails when the app and a module handle the same message', () async {
      expectBuildFailure(
        await generate({
          'auth|lib/auth.dart': moduleSource,
          'app|lib/app.dart': '''
@ChassisApp(modules: [AuthModule])
library;

import 'package:chassis/chassis.dart';
import 'package:auth/auth.dart';

@chassisHandler
class AppLoginHandler implements CommandHandler<LoginCommand, void> {
  AppLoginHandler();
  @override
  Future<void> run(LoginCommand command) async {}
}
''',
        }),
        contains('exactly one handler across'),
      );
    });
  });
}
