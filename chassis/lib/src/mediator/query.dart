import 'dart:async';

/// Abstract interface for queries that can be executed through the mediator.
///
/// Queries represent read operations that retrieve data without modifying state.
/// They are the foundation for both one-time reads and continuous watching.
sealed class Query<T> {
  /// Parameters of this query, for logging and tracing purposes.
  ///
  /// Override to expose the query's fields. Used by [toString] and by
  /// `LoggingMiddleware` so a trace reads `GetUserQuery{id: 42}` instead of
  /// a bare type name.
  ///
  /// Never include secrets (passwords, tokens) in [params].
  Map<String, Object?> get params => const {};

  @override
  String toString() => params.isEmpty ? '$runtimeType' : '$runtimeType$params';
}

/// Abstract interface for one-time read queries.
///
/// Read queries are used for operations that fetch data once and return a
/// single result. They are suitable for scenarios where you need the current
/// state but don't need to be notified of changes.
///
/// Example usage:
/// ```dart
/// final class GetUserQuery extends ReadQuery<User> {
///   GetUserQuery({required this.userId});
///
///   final String userId;
/// }
/// ```
abstract base class ReadQuery<T> extends Query<T> {}

/// Abstract interface for streaming queries that watch for changes.
///
/// Watch queries are used for operations that need to continuously monitor
/// data changes and emit new values when the underlying data changes.
/// They return a stream of values that updates over time.
///
/// Example usage:
/// ```dart
/// final class WatchUserQuery extends WatchQuery<User> {
///   WatchUserQuery({required this.userId});
///
///   final String userId;
/// }
/// ```
abstract base class WatchQuery<T> extends Query<T> {}

/// Abstract base class for query handlers.
///
/// This class serves as a common interface for both [ReadHandler] and
/// [WatchHandler] implementations.
sealed class QueryHandler<Q extends Query<R>, R> {}

/// A handler that executes one-time read queries of type [Q] and returns results of type [R].
///
/// Read handlers encapsulate the business logic for executing read queries.
/// They are registered with the mediator and called when read queries are dispatched.
///
/// Handlers receive dependencies via constructor injection, keeping them testable
/// and decoupled from concrete implementations.
///
/// Example usage:
/// ```dart
/// @chassisHandler
/// class GetUserQueryHandler implements ReadHandler<GetUserQuery, User> {
///   GetUserQueryHandler(this._userRepository, this._cacheService);
///
///   final UserRepository _userRepository;
///   final CacheService _cacheService;
///
///   @override
///   Future<User> read(GetUserQuery query) async {
///     // Check cache first
///     final cachedUser = await _cacheService.get<User>('user_${query.userId}');
///     if (cachedUser != null) {
///       return cachedUser;
///     }
///
///     // Fetch from repository
///     final user = await _userRepository.findById(query.userId);
///
///     // Cache the result
///     await _cacheService.set('user_${query.userId}', user);
///
///     return user;
///   }
/// }
/// ```
abstract interface class ReadHandler<Q extends ReadQuery<R>, R>
    implements QueryHandler<Q, R> {
  /// Executes the given [query] and returns a future with the result.
  Future<R> read(Q query);
}

/// A handler that executes streaming watch queries of type [Q] and returns a stream of results of type [R].
///
/// Watch handlers encapsulate the business logic for executing watch queries.
/// They are registered with the mediator and called when watch queries are dispatched.
/// The returned stream will emit new values whenever the underlying data changes.
///
/// Handlers receive dependencies via constructor injection, keeping them testable
/// and decoupled from concrete implementations.
///
/// Example usage:
/// ```dart
/// @chassisHandler
/// class WatchUserQueryHandler implements WatchHandler<WatchUserQuery, User> {
///   WatchUserQueryHandler(this._userRepository, this._realtimeService);
///
///   final UserRepository _userRepository;
///   final RealtimeService _realtimeService;
///
///   @override
///   Stream<User> watch(WatchUserQuery query) {
///     // Combine multiple data sources
///     final localStream = _userRepository.watchById(query.userId);
///     final remoteStream = _realtimeService.watchUserChanges(query.userId);
///
///     // Merge and transform the streams
///     return Stream.merge([localStream, remoteStream])
///         .distinct()
///         .map((user) => user.copyWith(lastSeen: DateTime.now()));
///   }
/// }
/// ```
abstract interface class WatchHandler<Q extends WatchQuery<R>, R>
    implements QueryHandler<Q, R> {
  /// Executes the given [query] and returns a stream of results.
  Stream<R> watch(Q query);
}
