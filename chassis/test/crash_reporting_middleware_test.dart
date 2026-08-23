import 'package:chassis/chassis.dart';
import 'package:test/test.dart';

// --- Fixtures ---

final class OkCommand() extends Command<int>;

class OkHandler implements CommandHandler<OkCommand, int> {
  @override
  Future<int> run(OkCommand command) async => 1;
}

final class DomainFailCommand() extends Command<int>;

class DomainFailHandler implements CommandHandler<DomainFailCommand, int> {
  @override
  Future<int> run(DomainFailCommand command) async =>
      throw const FormatException('bad input');
}

final class BuggyCommand() extends Command<int>;

class BuggyHandler implements CommandHandler<BuggyCommand, int> {
  @override
  Future<int> run(BuggyCommand command) async {
    final Object value = 'not an int';
    return value as int; // TypeError: a programming bug, not a domain failure.
  }
}

final class FailingReadQuery() extends ReadQuery<int>;

class FailingReadHandler implements ReadHandler<FailingReadQuery, int> {
  @override
  Future<int> read(FailingReadQuery query) async =>
      throw const FormatException('read failed');
}

final class ErroringWatchQuery() extends WatchQuery<int>;

class ErroringWatchHandler implements WatchHandler<ErroringWatchQuery, int> {
  @override
  Stream<int> watch(ErroringWatchQuery query) async* {
    yield 1;
    throw const FormatException('stream failed');
  }
}

final class UnregisteredWatchQuery() extends WatchQuery<int>;

class _Report(final Object error, final bool fatal);

void main() {
  late List<_Report> reports;
  late Mediator mediator;

  setUp(() {
    reports = [];
    mediator = Mediator()
      ..registerCommandHandler(OkHandler())
      ..registerCommandHandler(DomainFailHandler())
      ..registerCommandHandler(BuggyHandler())
      ..registerQueryHandler(FailingReadHandler())
      ..registerQueryHandler(ErroringWatchHandler())
      ..addMiddleware(
        CrashReportingMiddleware(
          (error, stack, {required bool fatal}) =>
              reports.add(_Report(error, fatal)),
        ),
      );
  });

  test('a successful operation reports nothing', () async {
    expect(await mediator.run(OkCommand()), 1);
    expect(reports, isEmpty);
  });

  test(
    'an Exception from a command handler is reported non-fatal and rethrown',
    () async {
      await expectLater(
        mediator.run(DomainFailCommand()),
        throwsA(isA<FormatException>()),
      );
      expect(reports, hasLength(1));
      expect(reports.single.error, isA<FormatException>());
      expect(reports.single.fatal, isFalse);
    },
  );

  test(
    'an Error from a command handler is reported fatal and rethrown',
    () async {
      await expectLater(
        mediator.run(BuggyCommand()),
        throwsA(isA<TypeError>()),
      );
      expect(reports, hasLength(1));
      expect(reports.single.error, isA<TypeError>());
      expect(reports.single.fatal, isTrue);
    },
  );

  test('a read failure is reported non-fatal and rethrown', () async {
    await expectLater(
      mediator.read(FailingReadQuery()),
      throwsA(isA<FormatException>()),
    );
    expect(reports, hasLength(1));
    expect(reports.single.fatal, isFalse);
  });

  test(
    'a watch stream error is reported and still reaches the subscriber',
    () async {
      await expectLater(
        mediator.watch(ErroringWatchQuery()),
        emitsInOrder([1, emitsError(isA<FormatException>()), emitsDone]),
      );
      expect(reports, hasLength(1));
      expect(reports.single.error, isA<FormatException>());
      expect(reports.single.fatal, isFalse);
    },
  );

  test('a chassis wiring error is reported fatal and rethrown', () {
    expect(
      () => mediator.watch(UnregisteredWatchQuery()),
      throwsA(isA<HandlerNotRegisteredError>()),
    );
    expect(reports, hasLength(1));
    expect(reports.single.error, isA<HandlerNotRegisteredError>());
    expect(reports.single.fatal, isTrue);
  });
}
