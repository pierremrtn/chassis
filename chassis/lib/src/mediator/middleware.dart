import 'dart:async';

import 'command.dart';
import 'dispatch_context.dart';
import 'query.dart';

/// Typedef for the next function in the command middleware chain.
typedef NextRun<R> = Future<R> Function(Command<R> command);

/// Typedef for the next function in the read middleware chain.
typedef NextRead<R> = Future<R> Function(ReadQuery<R> query);

/// Typedef for the next function in the watch middleware chain.
typedef NextWatch<R> = Stream<R> Function(WatchQuery<R> query);

/// Middleware interface for intercepting Mediator operations.
///
/// A middleware sees every message through its abstract base type
/// ([Command], [ReadQuery], [WatchQuery]) — it is cross-cutting by design
/// (logging, crash reporting, timing). To act on a specific message, check
/// its runtime type. Middlewares never dispatch: they observe and forward.
///
/// [context] carries the caller's observation metadata ([DispatchContext])
/// when the dispatching side is instrumented — null otherwise. The same
/// instance reaches every middleware of the chain.
abstract class MediatorMiddleware {
  /// Intercepts [Mediator.run].
  Future<R> onRun<R>(
    Command<R> command,
    NextRun<R> next, {
    DispatchContext? context,
  }) {
    return next(command);
  }

  /// Intercepts [Mediator.read].
  Future<R> onRead<R>(
    ReadQuery<R> query,
    NextRead<R> next, {
    DispatchContext? context,
  }) {
    return next(query);
  }

  /// Intercepts [Mediator.watch].
  Stream<R> onWatch<R>(
    WatchQuery<R> query,
    NextWatch<R> next, {
    DispatchContext? context,
  }) {
    return next(query);
  }
}
