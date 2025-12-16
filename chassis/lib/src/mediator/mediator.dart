import 'command.dart';
import 'query.dart';
import 'middleware.dart';

/// A mediator that coordinates between commands, queries, and their handlers.
///
/// The mediator implements the Mediator pattern, providing a centralized way to
/// handle commands and queries without direct coupling between senders and receivers.
/// It maintains registries of handlers and routes requests to the appropriate handlers.
///
/// Example usage:
/// ```dart
/// // Create the mediator instance
/// final mediator = Mediator();
///
/// // Register handlers
/// mediator.registerQueryHandler<GetUserQuery, User>(
///   ReadHandler<GetUserQuery, User>(read: (query) async {
///     return await userRepository.findById(query.userId);
///   }),
/// );
///
/// mediator.registerCommandHandler<CreateUserCommand, User>(
///   CommandHandler<CreateUserCommand, User>(run: (command) async {
///     return await userRepository.create(command.name, command.email);
///   }),
/// );
///
/// // Use the mediator
/// final user = await mediator.read(GetUserQuery(userId: '123'));
/// final newUser = await mediator.run(CreateUserCommand(name: 'John', email: 'john@example.com'));
/// ```
class Mediator {
  final Map<Type, ReadHandler> _queryHandlers = {};
  final Map<Type, WatchHandler> _streamHandlers = {};
  final Map<Type, CommandHandler> _commandHandlers = {};

  final List<MediatorMiddleware> _middlewares = [];

  /// Registers a query handler for the specified query type.
  ///
  /// The handler can be either a [ReadHandler] for one-time reads or a
  /// [WatchHandler] for streaming queries. The mediator will automatically
  /// determine the handler type and register it in the appropriate registry.
  ///
  /// Throws a [StateError] if a handler is already registered for the same query type.
  ///
  /// Example:
  /// ```dart
  /// mediator.registerQueryHandler<GetUserQuery, User>(
  ///   ReadHandler<GetUserQuery, User>((query) async {
  ///     return await userRepository.findById(query.userId);
  ///   }),
  /// );
  /// ```
  void registerQueryHandler<Q extends Query<T>, T>(
    QueryHandler<Q, T> handler,
  ) {
    if (handler case ReadHandler handler) {
      assert(() {
        if (_queryHandlers.containsKey(Q)) {
          throw StateError('ReadHandler already registered for $Q');
        }
        return true;
      }());
      _queryHandlers[Q] = handler;
    }

    if (handler case WatchHandler handler) {
      assert(() {
        if (_streamHandlers.containsKey(Q)) {
          throw StateError('WatchHandler already registered for $Q');
        }
        return true;
      }());
      _streamHandlers[Q] = handler;
    }
  }

  /// Registers a command handler for the specified command type.
  ///
  /// Throws a [StateError] if a handler is already registered for the same command type.
  ///
  /// Example:
  /// ```dart
  /// mediator.registerCommandHandler<CreateUserCommand, User>(
  ///   CommandHandler<CreateUserCommand, User>((command) async {
  ///     return await userRepository.create(command.name, command.email);
  ///   }),
  /// );
  /// ```
  void registerCommandHandler<C extends Command<T>, T>(
    CommandHandler<C, T> handler,
  ) {
    assert(() {
      if (_commandHandlers.containsKey(C)) {
        throw StateError('CommandHandler already registered for $C');
      }
      return true;
    }());

    _commandHandlers[C] = handler;
  }

  /// Adds a middleware to the mediator.
  ///
  /// Middlewares are executed in the order they are added.
  void addMiddleware(MediatorMiddleware middleware) {
    _middlewares.add(middleware);
  }

  /// Merges two mediators into a new one.
  ///
  /// The returned mediator will contain the union of handlers from both mediators.
  /// Middlewares from both mediators are also combined.
  Mediator operator +(Mediator other) {
    final combined = Mediator();

    // Merge handlers
    combined._queryHandlers.addAll(_queryHandlers);
    combined._queryHandlers.addAll(other._queryHandlers);

    combined._streamHandlers.addAll(_streamHandlers);
    combined._streamHandlers.addAll(other._streamHandlers);

    combined._commandHandlers.addAll(_commandHandlers);
    combined._commandHandlers.addAll(other._commandHandlers);

    // Merge middlewares
    combined._middlewares.addAll(_middlewares);
    combined._middlewares.addAll(other._middlewares);

    return combined;
  }

  /// Executes a read query and returns the result.
  ///
  /// Looks up the appropriate [ReadHandler] for the query type and executes it.
  /// Throws an [Exception] if no handler is registered for the query type.
  ///
  /// Example:
  /// ```dart
  /// final user = await mediator.read(GetUserQuery(userId: '123'));
  /// ```
  Future<T> read<T>(ReadQuery<T> query) {
    NextRead<ReadQuery<T>, T> execution = (q) {
      final handler = _queryHandlers[q.runtimeType];
      if (handler == null) {
        throw Exception('No ReadHandler registered for ${q.runtimeType}');
      }
      return handler.read(q) as Future<T>;
    };

    // Chain middlewares
    for (final middleware in _middlewares.reversed) {
      final next = execution;
      execution = (q) => middleware.onRead(q, next);
    }

    return execution(query);
  }

  /// Executes a watch query and returns a stream of results.
  ///
  /// Looks up the appropriate [WatchHandler] for the query type and executes it.
  /// Throws an [Exception] if no handler is registered for the query type.
  ///
  /// Example:
  /// ```dart
  /// final userStream = mediator.watch(WatchUserQuery(userId: '123'));
  /// userStream.listen((user) => print('User updated: $user'));
  /// ```
  Stream<T> watch<T>(WatchQuery<T> query) {
    NextWatch<WatchQuery<T>, T> execution = (q) {
      final handler = _streamHandlers[q.runtimeType];
      if (handler == null) {
        throw Exception('No WatchHandler registered for ${q.runtimeType}');
      }
      return handler.watch(q) as Stream<T>;
    };

    // Chain middlewares
    for (final middleware in _middlewares.reversed) {
      final next = execution;
      execution = (q) => middleware.onWatch(q, next);
    }

    return execution(query);
  }

  /// Executes a command and returns the result.
  ///
  /// Looks up the appropriate [CommandHandler] for the command type and executes it.
  /// Throws an [Exception] if no handler is registered for the command type.
  ///
  /// Example:
  /// ```dart
  /// final user = await mediator.run(CreateUserCommand(name: 'John', email: 'john@example.com'));
  /// ```
  Future<T> run<T>(Command<T> command) {
    NextRun<Command<T>, T> execution = (c) {
      final handler = _commandHandlers[c.runtimeType];
      if (handler == null) {
        throw Exception('No CommandHandler registered for ${c.runtimeType}');
      }
      return handler.run(c) as Future<T>;
    };

    // Chain middlewares
    for (final middleware in _middlewares.reversed) {
      final next = execution;
      execution = (c) => middleware.onRun(c, next);
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
