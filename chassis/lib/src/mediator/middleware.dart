import 'dart:async';
import 'command.dart';
import 'query.dart';

/// Typedef for the next function in the command middleware chain.
typedef NextRun<C extends Command<R>, R> = Future<R> Function(C command);

/// Typedef for the next function in the read middleware chain.
typedef NextRead<Q extends ReadQuery<R>, R> = Future<R> Function(Q query);

/// Typedef for the next function in the watch middleware chain.
typedef NextWatch<Q extends WatchQuery<R>, R> = Stream<R> Function(Q query);

/// Middleware interface for intersecting Mediator operations.
abstract class MediatorMiddleware {
  /// Intercepts [Mediator.run].
  Future<R> onRun<C extends Command<R>, R>(C command, NextRun<C, R> next) {
    return next(command);
  }

  /// Intercepts [Mediator.read].
  Future<R> onRead<Q extends ReadQuery<R>, R>(Q query, NextRead<Q, R> next) {
    return next(query);
  }

  /// Intercepts [Mediator.watch].
  Stream<R> onWatch<Q extends WatchQuery<R>, R>(Q query, NextWatch<Q, R> next) {
    return next(query);
  }
}
