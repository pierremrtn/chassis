import 'dart:async';

abstract interface class Query<T> {}

abstract interface class Read<T> implements Query<T> {}

abstract interface class Watch<T> implements Query<T> {}

typedef ReadHandlerCallback<Q extends Read<R>, R> = Future<R> Function(Q query);
typedef WatchHandlerCallback<Q extends Watch<R>, R> = Stream<R> Function(
    Q query);

class QueryHandler<Q extends Query<R>, R> {}

class ReadHandler<Q extends Read<R>, R> implements QueryHandler<Q, R> {
  const ReadHandler(ReadHandlerCallback<Q, R> read)
      : _read = read,
        assert(Q is! Watch,
            "$Q: trying to register a read only handler for a query that supports watch. Try to changes the type of your handler to ReadAndWatchHandler");

  final ReadHandlerCallback<Q, R> _read;

  Future<R> read(Q query) {
    return _read.call(query);
  }
}

// A type that can handle a streaming query for Q.
class WatchHandler<Q extends Watch<R>, R> implements QueryHandler<Q, R> {
  const WatchHandler(WatchHandlerCallback<Q, R> watch)
      : _watch = watch,
        assert(Q is! Read,
            "$Q: trying to register a watch only handler for a query that supports read. Try to changes the type of your handler to ReadAndWatchHandler");

  final WatchHandlerCallback<Q, R> _watch;

  Stream<R> watch(Q query) {
    return _watch.call(query);
  }
}
