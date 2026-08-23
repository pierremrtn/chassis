import 'command.dart';
import 'dispatch_context.dart';
import 'errors.dart';
import 'middleware.dart';
import 'query.dart';

/// A mediator that coordinates between commands, queries, and their handlers.
///
/// The mediator implements the Mediator pattern, providing a centralized way to
/// handle commands and queries without direct coupling between senders and receivers.
/// It maintains registries of handlers and routes requests to the appropriate handlers.
///
/// Registration and dispatch throw [ChassisError] subtypes on wiring
/// mistakes ([DuplicateHandlerError], [HandlerNotRegisteredError]) —
/// identically in debug and release builds.
///
/// Dispatch is keyed by the **exact runtime type** of the message: a
/// subclass of a registered command/query is not routed to the parent's
/// handler, and generic message classes are unsupported (their type
/// arguments would make the runtime key ambiguous — `chassis_builder`
/// rejects them at build time). Declare one concrete, `final` message class
/// per operation.
///
/// Example usage:
/// ```dart
/// // Create the mediator instance
/// final mediator = Mediator();
///
/// // Register handlers (handlers implement the handler interfaces)
/// mediator.registerQueryHandler<GetUserQuery, User>(
///   GetUserQueryHandler(userRepository),
/// );
///
/// mediator.registerCommandHandler<CreateUserCommand, User>(
///   CreateUserCommandHandler(userRepository),
/// );
///
/// // Use the mediator
/// final user = await mediator.read(GetUserQuery(userId: '123'));
/// final newUser = await mediator.run(CreateUserCommand(name: 'John', email: 'john@example.com'));
/// ```
class Mediator {
  final Map<Type, ReadHandler<ReadQuery<Object?>, Object?>> _queryHandlers = {};
  final Map<Type, WatchHandler<WatchQuery<Object?>, Object?>> _streamHandlers =
      {};
  final Map<Type, CommandHandler<Command<Object?>, Object?>> _commandHandlers =
      {};

  final List<MediatorMiddleware> _middlewares = [];

  /// Rejects registrations keyed by an abstract message type.
  ///
  /// `registerQueryHandler<ReadQuery<String>, String>(handler)` compiles
  /// (handler types are covariant) but registers under the abstract type,
  /// while dispatch looks up the message's concrete `runtimeType` — every
  /// dispatch would then throw [HandlerNotRegisteredError]. This happens when
  /// the handler variable is upcast (e.g. iterating a heterogeneous
  /// collection) and inference falls back to the bound.
  static void _rejectAbstractKey(Type key, Set<Type> abstractTypes) {
    if (abstractTypes.contains(key)) {
      throw ArgumentError(
        'register with the concrete message type — got the abstract $key. '
        'Let inference see the concrete handler type (avoid upcasting the '
        'handler variable), or pass the type arguments explicitly.',
      );
    }
  }

  static Type _typeOf<X>() => X;

  /// Registers a query handler for the specified query type.
  ///
  /// The handler can be either a [ReadHandler] for one-time reads or a
  /// [WatchHandler] for streaming queries. The mediator will automatically
  /// determine the handler type and register it in the appropriate registry.
  ///
  /// Throws a [DuplicateHandlerError] if a handler is already registered
  /// for the same query type.
  ///
  /// Example:
  /// ```dart
  /// mediator.registerQueryHandler<GetUserQuery, User>(
  ///   GetUserQueryHandler(userRepository),
  /// );
  /// ```
  void registerQueryHandler<Q extends Query<T>, T>(QueryHandler<Q, T> handler) {
    _rejectAbstractKey(Q, {
      _typeOf<Query<T>>(),
      _typeOf<ReadQuery<T>>(),
      _typeOf<WatchQuery<T>>(),
    });
    switch (handler) {
      case final ReadHandler<ReadQuery<Object?>, Object?> handler:
        final existing = _queryHandlers[Q];
        if (existing != null) {
          throw DuplicateHandlerError(
            requestType: Q,
            existingHandler: existing.runtimeType,
            newHandler: handler.runtimeType,
          );
        }
        _queryHandlers[Q] = handler;
      case final WatchHandler<WatchQuery<Object?>, Object?> handler:
        final existing = _streamHandlers[Q];
        if (existing != null) {
          throw DuplicateHandlerError(
            requestType: Q,
            existingHandler: existing.runtimeType,
            newHandler: handler.runtimeType,
          );
        }
        _streamHandlers[Q] = handler;
    }
  }

  /// Registers a command handler for the specified command type.
  ///
  /// Throws a [DuplicateHandlerError] if a handler is already registered
  /// for the same command type.
  ///
  /// Example:
  /// ```dart
  /// mediator.registerCommandHandler<CreateUserCommand, User>(
  ///   CreateUserCommandHandler(userRepository),
  /// );
  /// ```
  void registerCommandHandler<C extends Command<T>, T>(
    CommandHandler<C, T> handler,
  ) {
    _rejectAbstractKey(C, {_typeOf<Command<T>>()});
    final existing = _commandHandlers[C];
    if (existing != null) {
      throw DuplicateHandlerError(
        requestType: C,
        existingHandler: existing.runtimeType,
        newHandler: handler.runtimeType,
      );
    }
    _commandHandlers[C] = handler;
  }

  /// Adds a middleware to the mediator.
  ///
  /// Middlewares are executed in the order they are added.
  void addMiddleware(MediatorMiddleware middleware) {
    _middlewares.add(middleware);
  }

  /// Executes a read query and returns the result.
  ///
  /// Looks up the appropriate [ReadHandler] for the query type and executes it.
  /// Throws a [HandlerNotRegisteredError] if no handler is registered for
  /// the query type.
  ///
  /// Example:
  /// ```dart
  /// final user = await mediator.read(GetUserQuery(userId: '123'));
  /// ```
  Future<T> read<T>(ReadQuery<T> query, {DispatchContext? context}) {
    NextRead<T> execution = (q) {
      final handler = _queryHandlers[q.runtimeType];
      if (handler == null) {
        throw HandlerNotRegisteredError(
          requestType: q.runtimeType,
          dispatchMethod: 'read',
          registerMethod: 'registerQueryHandler',
          handlerInterface: 'ReadHandler',
        );
      }
      return handler.read(q) as Future<T>;
    };

    // Chain middlewares
    for (final middleware in _middlewares.reversed) {
      final next = execution;
      execution = (q) => middleware.onRead(q, next, context: context);
    }

    return execution(query);
  }

  /// Executes a watch query and returns a stream of results.
  ///
  /// Looks up the appropriate [WatchHandler] for the query type and executes it.
  /// Throws a [HandlerNotRegisteredError] if no handler is registered for
  /// the query type.
  ///
  /// Example:
  /// ```dart
  /// final userStream = mediator.watch(WatchUserQuery(userId: '123'));
  /// userStream.listen((user) => print('User updated: $user'));
  /// ```
  Stream<T> watch<T>(WatchQuery<T> query, {DispatchContext? context}) {
    NextWatch<T> execution = (q) {
      final handler = _streamHandlers[q.runtimeType];
      if (handler == null) {
        throw HandlerNotRegisteredError(
          requestType: q.runtimeType,
          dispatchMethod: 'watch',
          registerMethod: 'registerQueryHandler',
          handlerInterface: 'WatchHandler',
        );
      }
      return handler.watch(q) as Stream<T>;
    };

    // Chain middlewares
    for (final middleware in _middlewares.reversed) {
      final next = execution;
      execution = (q) => middleware.onWatch(q, next, context: context);
    }

    return execution(query);
  }

  /// Executes a command and returns the result.
  ///
  /// Looks up the appropriate [CommandHandler] for the command type and executes it.
  /// Throws a [HandlerNotRegisteredError] if no handler is registered for
  /// the command type.
  ///
  /// Example:
  /// ```dart
  /// final user = await mediator.run(CreateUserCommand(name: 'John', email: 'john@example.com'));
  /// ```
  Future<T> run<T>(Command<T> command, {DispatchContext? context}) {
    NextRun<T> execution = (c) {
      final handler = _commandHandlers[c.runtimeType];
      if (handler == null) {
        throw HandlerNotRegisteredError(
          requestType: c.runtimeType,
          dispatchMethod: 'run',
          registerMethod: 'registerCommandHandler',
          handlerInterface: 'CommandHandler',
        );
      }
      return handler.run(c) as Future<T>;
    };

    // Chain middlewares
    for (final middleware in _middlewares.reversed) {
      final next = execution;
      execution = (c) => middleware.onRun(c, next, context: context);
    }

    return execution(command);
  }

  /// Checks if a handler is available for the specified type.
  ///
  /// Returns `true` if any handler (query, watch, or command) is registered
  /// for the given type, `false` otherwise.
  ///
  /// This can be useful for conditional logic or debugging purposes.
  bool hasHandlerAvailableFor<T>() {
    final handler =
        _queryHandlers[T] ?? _streamHandlers[T] ?? _commandHandlers[T];
    return handler != null;
  }
}
