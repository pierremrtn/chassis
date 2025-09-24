import 'dart:async';

/// Abstract interface for queries that can be executed through the mediator.
///
/// Queries represent read operations that retrieve data without modifying state.
/// They are the foundation for both one-time reads and continuous watching.
sealed class Query<T> {}

/// Abstract interface for one-time read queries.
///
/// Read queries are used for operations that fetch data once and return a
/// single result. They are suitable for scenarios where you need the current
/// state but don't need to be notified of changes.
///
/// Example usage:
/// ```dart
/// class GetUserQuery implements ReadQuery<User> {
///   const GetUserQuery({required this.userId});
///
///   final String userId;
/// }
/// ```
abstract class ReadQuery<T> implements Query<T> {}

/// Abstract interface for streaming queries that watch for changes.
///
/// Watch queries are used for operations that need to continuously monitor
/// data changes and emit new values when the underlying data changes.
/// They return a stream of values that updates over time.
///
/// Example usage:
/// ```dart
/// class WatchUserQuery implements WatchQuery<User> {
///   const WatchUserQuery({required this.userId});
///
///   final String userId;
/// }
/// ```
abstract class WatchQuery<T> implements Query<T> {}

/// A callback function that handles one-time read queries.
///
/// This typedef defines the signature for read handler functions that take
/// a query of type [Q] and return a future with a result of type [R].
typedef ReadHandlerCallback<Q extends ReadQuery<R>, R> = Future<R> Function(
    Q query);

/// A callback function that handles streaming watch queries.
///
/// This typedef defines the signature for watch handler functions that take
/// a query of type [Q] and return a stream of results of type [R].
typedef WatchHandlerCallback<Q extends WatchQuery<R>, R> = Stream<R> Function(
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
///   (query) async {
///     // Business logic to fetch user
///     final user = await userRepository.findById(query.userId);
///     return user;
///   },
/// );
///
/// // For more complex scenarios, implement the interface instead:
/// class GetUserQueryHandler implements ReadHandler<GetUserQuery, User> {
///   final IUserRepository userRepository;
///   final ICacheService cacheService;
///
///   GetUserQueryHandler({
///     required this.userRepository,
///     required this.cacheService,
///   });
///
///   @override
///   Future<User> read(GetUserQuery query) async {
///     // Check cache first
///     final cachedUser = await cacheService.get<User>('user_${query.userId}');
///     if (cachedUser != null) {
///       return cachedUser;
///     }
///
///     // Fetch from repository
///     final user = await userRepository.findById(query.userId);
///
///     // Cache the result
///     await cacheService.set('user_${query.userId}', user);
///
///     return user;
///   }
/// }
/// ```
class ReadHandler<Q extends ReadQuery<R>, R> implements QueryHandler<Q, R> {
  /// Creates a read handler with the given [read] callback.
  ///
  /// Throws an assertion error if [Q] implements [WatchQuery], as this would
  /// indicate a type mismatch where a read-only handler is being registered
  /// for a query that supports watching.
  const ReadHandler(ReadHandlerCallback<Q, R> read)
      : _read = read,
        assert(Q is! WatchQuery,
            "$Q: trying to register a read handler for a watch query");

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
///   (query) {
///     // Business logic to watch user changes
///     return userRepository.watchById(query.userId);
///   },
/// );
///
/// // For more complex scenarios, implement the interface instead:
/// class WatchUserQueryHandler implements WatchHandler<WatchUserQuery, User> {
///   final IUserRepository userRepository;
///   final IRealtimeService realtimeService;
///
///   WatchUserQueryHandler({
///     required this.userRepository,
///     required this.realtimeService,
///   });
///
///   @override
///   Stream<User> watch(WatchUserQuery query) {
///     // Combine multiple data sources
///     final localStream = userRepository.watchById(query.userId);
///     final remoteStream = realtimeService.watchUserChanges(query.userId);
///
///     // Merge and transform the streams
///     return Stream.merge([localStream, remoteStream])
///         .distinct()
///         .map((user) => user.copyWith(lastSeen: DateTime.now()));
///   }
/// }
/// ```
class WatchHandler<Q extends WatchQuery<R>, R> implements QueryHandler<Q, R> {
  /// Creates a watch handler with the given [watch] callback.
  ///
  /// Throws an assertion error if [Q] implements [ReadQuery], as this would
  /// indicate a type mismatch where a watch-only handler is being registered
  /// for a query that supports one-time reads.
  const WatchHandler(WatchHandlerCallback<Q, R> watch)
      : _watch = watch,
        assert(Q is! ReadQuery,
            "$Q: trying to register a watch handler for a read query");

  final WatchHandlerCallback<Q, R> _watch;

  /// Executes the given [query] and returns a stream of results.
  Stream<R> watch(Q query) {
    return _watch.call(query);
  }
}
