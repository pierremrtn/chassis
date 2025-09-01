import 'command.dart';
import 'query.dart';

class Mediator {
  static late final Mediator instance;
  static void initialize(Mediator mediator) {
    instance = mediator;
  }

  final Map<Type, ReadHandler> _queryHandlers = {};
  final Map<Type, WatchHandler> _streamHandlers = {};
  final Map<Type, CommandHandler> _commandHandlers = {};
  // Dependency injection container or service locator to create handlers

  void registerQueryHandler<Q extends Query<T>, T>(
    QueryHandler<Q, T> handler,
  ) {
    if (handler case ReadHandler handler) {
      _queryHandlers[Q] = handler;
      print("Registered ${handler.runtimeType} for GET $Q");
    }
    if (handler case WatchHandler handler) {
      _streamHandlers[Q] = handler;
      print("Registered ${handler.runtimeType} for WATCH $Q");
    }
  }

  void registerCommandHandler<C extends Command<T>, T>(
    CommandHandler<C, T> handler,
  ) {
    _commandHandlers[C] = handler;
    print("Registered ${handler.runtimeType} for COMMAND $C");
  }

  Future<T> read<T>(Read<T> query) {
    final handler = _queryHandlers[query.runtimeType];
    if (handler == null) {
      throw Exception('No ReadHandler registered for ${query.runtimeType}');
    }
    return handler.read(query) as Future<T>;
  }

  Stream<T> watch<T>(Watch<T> query) {
    final handler = _streamHandlers[query.runtimeType];
    if (handler == null) {
      throw Exception('No WatchHandler registered for ${query.runtimeType}');
    }
    return handler.watch(query) as Stream<T>;
  }

  Future<T> run<T>(Command<T> command) {
    final handler = _commandHandlers[command.runtimeType];
    if (handler == null) {
      throw Exception(
          'No CommandHandler registered for ${command.runtimeType}');
    }
    return handler.run(command) as Future<T>;
  }

  bool hasHandlerAvailableFor<T>() {
    final handler =
        _queryHandlers[T] ?? _streamHandlers[T] ?? _commandHandlers[T];
    return handler != null;
  }
}
