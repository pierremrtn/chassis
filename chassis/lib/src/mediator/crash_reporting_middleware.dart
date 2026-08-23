import 'dart:async';

import 'command.dart';
import 'dispatch_context.dart';
import 'middleware.dart';
import 'query.dart';

/// Middleware that reports every failure crossing the mediator to a crash
/// reporter, then lets it propagate — reporting never swallows failures.
///
/// The middleware chain is chassis's observability channel (there is no
/// `Observer` hook): it sees the typed message and its params, and is wired
/// once at the composition root.
///
/// Failures are classified with Dart's own distinction:
/// - [Error] — a programming bug (a `TypeError` in a handler, a chassis
///   wiring error). Reported as **fatal**.
/// - anything else ([Exception]s, domain failures) — an expected runtime
///   failure. Reported as non-fatal.
///
/// ```dart
/// final mediator = AppMediator(...)
///   ..addMiddleware(CrashReportingMiddleware(
///     (error, stack, {required fatal}) => FirebaseCrashlytics.instance
///         .recordError(error, stack, fatal: fatal),
///   ));
/// ```
class CrashReportingMiddleware(
  final void Function(Object error, StackTrace stack, {required bool fatal})
  _report,
) extends MediatorMiddleware {
  void _reportError(Object error, StackTrace stack) {
    _report(error, stack, fatal: error is Error);
  }

  @override
  Future<R> onRun<R>(
    Command<R> command,
    NextRun<R> next, {
    DispatchContext? context,
  }) async {
    try {
      return await next(command);
    } catch (error, stack) {
      _reportError(error, stack);
      rethrow;
    }
  }

  @override
  Future<R> onRead<R>(
    ReadQuery<R> query,
    NextRead<R> next, {
    DispatchContext? context,
  }) async {
    try {
      return await next(query);
    } catch (error, stack) {
      _reportError(error, stack);
      rethrow;
    }
  }

  /// Watch errors flow through the stream: each one is reported and
  /// forwarded to the subscriber — never swallowed. A synchronous throw of
  /// the handler itself (before a stream exists) is reported and rethrown.
  @override
  Stream<R> onWatch<R>(
    WatchQuery<R> query,
    NextWatch<R> next, {
    DispatchContext? context,
  }) {
    final Stream<R> source;
    try {
      source = next(query);
    } catch (error, stack) {
      _reportError(error, stack);
      rethrow;
    }

    // StreamTransformer.fromHandlers preserves isBroadcast, unlike an
    // async* wrapper which would force single-subscription semantics.
    return source.transform(
      StreamTransformer<R, R>.fromHandlers(
        handleError: (error, stack, sink) {
          _reportError(error, stack);
          sink.addError(error, stack);
        },
      ),
    );
  }
}
