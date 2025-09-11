import 'dart:async';

/// Abstract interface for queries that can be executed through the mediator.
///
/// Queries represent read operations that retrieve data without modifying state.
/// They are the foundation for both one-time reads and continuous watching.
abstract interface class Query<T> {}

/// Abstract interface for one-time read queries.
///
/// Read queries are used for operations that fetch data once and return a
/// single result. They are suitable for scenarios where you need the current
/// state but don't need to be notified of changes.
///
/// Example usage:
/// ```dart
/// class GetUserQuery implements Read<User> {
///   const GetUserQuery({required this.userId});
///
///   final String userId;
/// }
/// ```
abstract interface class Read<T> implements Query<T> {}

/// Abstract interface for streaming queries that watch for changes.
///
/// Watch queries are used for operations that need to continuously monitor
/// data changes and emit new values when the underlying data changes.
/// They return a stream of values that updates over time.
///
/// Example usage:
/// ```dart
/// class WatchUserQuery implements Watch<User> {
///   const WatchUserQuery({required this.userId});
///
///   final String userId;
/// }
/// ```
abstract interface class Watch<T> implements Query<T> {}

/// A callback function that handles one-time read queries.
///
/// This typedef defines the signature for read handler functions that take
/// a query of type [Q] and return a future with a result of type [R].
typedef ReadHandlerCallback<Q extends Read<R>, R> = Future<R> Function(Q query);

/// A callback function that handles streaming watch queries.
///
/// This typedef defines the signature for watch handler functions that take
/// a query of type [Q] and return a stream of results of type [R].
typedef WatchHandlerCallback<Q extends Watch<R>, R> = Stream<R> Function(
    Q query);

/// Abstract base class for query handlers.
///
/// This class serves as a common interface for both [ReadHandler] and
/// [WatchHandler] implementations.
class QueryHandler<Q extends Query<R>, R> {}

/// A handler that can execute one-time read queries of type [Q] and return results of type [R].
///
/// Read handlers encapsulate the business logic for executing read queries.
/// They are registered with the mediator and called when read queries are dispatched.
///
/// Example usage:
/// ```dart
/// final handler = ReadHandler<GetUserQuery, User>(
///   read: (query) async {
///     // Business logic to fetch user
///     final user = await userRepository.findById(query.userId);
///     return user;
///   },
/// );
/// ```
class ReadHandler<Q extends Read<R>, R> implements QueryHandler<Q, R> {
  /// Creates a read handler with the given [read] callback.
  ///
  /// Throws an assertion error if [Q] implements [Watch], as this would
  /// indicate a type mismatch where a read-only handler is being registered
  /// for a query that supports watching.
  const ReadHandler(ReadHandlerCallback<Q, R> read)
      : _read = read,
        assert(Q is! Watch,
            "$Q: trying to register a read only handler for a query that supports watch. Try to changes the type of your handler to ReadAndWatchHandler");

  final ReadHandlerCallback<Q, R> _read;

  /// Executes the given [query] and returns a future with the result.
  Future<R> read(Q query) {
    return _read.call(query);
  }
}

/// A handler that can execute streaming watch queries of type [Q] and return a stream of results of type [R].
///
/// Watch handlers encapsulate the business logic for executing watch queries.
/// They are registered with the mediator and called when watch queries are dispatched.
/// The returned stream will emit new values whenever the underlying data changes.
///
/// Example usage:
/// ```dart
/// final handler = WatchHandler<WatchUserQuery, User>(
///   watch: (query) {
///     // Business logic to watch user changes
///     return userRepository.watchById(query.userId);
///   },
/// );
/// ```
class WatchHandler<Q extends Watch<R>, R> implements QueryHandler<Q, R> {
  /// Creates a watch handler with the given [watch] callback.
  ///
  /// Throws an assertion error if [Q] implements [Read], as this would
  /// indicate a type mismatch where a watch-only handler is being registered
  /// for a query that supports one-time reads.
  const WatchHandler(WatchHandlerCallback<Q, R> watch)
      : _watch = watch,
        assert(Q is! Read,
            "$Q: trying to register a watch only handler for a query that supports read. Try to changes the type of your handler to ReadAndWatchHandler");

  final WatchHandlerCallback<Q, R> _watch;

  /// Executes the given [query] and returns a stream of results.
  Stream<R> watch(Q query) {
    return _watch.call(query);
  }
}
