import 'dart:async';

abstract interface class Query<T> {}

abstract interface class Read<T> implements Query<T> {}

abstract interface class Watch<T> implements Query<T> {}

abstract interface class ReadAndWatch<T> implements Read<T>, Watch<T> {}

typedef ReadHandlerCallback<Q extends Read<R>, R> = Future<R> Function(Q query);
typedef WatchHandlerCallback<Q extends Watch<R>, R> = Stream<R> Function(
    Q query);

class QueryHandler<Q extends Query<R>, R> {}

class ReadHandler<Q extends Read<R>, R> implements QueryHandler<Q, R> {
  const ReadHandler({required ReadHandlerCallback<Q, R> read}) : _read = read;

  final ReadHandlerCallback<Q, R> _read;

  Future<R> read(Q query) {
    return _read.call(query);
  }
}

// A type that can handle a streaming query for Q.
class WatchHandler<Q extends Watch<R>, R> implements QueryHandler<Q, R> {
  const WatchHandler({required WatchHandlerCallback<Q, R> watch})
      : _watch = watch;

  final WatchHandlerCallback<Q, R> _watch;

  Stream<R> watch(Q query) {
    return _watch.call(query);
  }
}

class ReadAndWatchHandler<Q extends ReadAndWatch<R>, R>
    implements ReadHandler<Q, R>, WatchHandler<Q, R> {
  const ReadAndWatchHandler({
    required ReadHandlerCallback<Q, R> read,
    required WatchHandlerCallback<Q, R> watch,
  })  : _read = read,
        _watch = watch;

  @override
  final ReadHandlerCallback<Q, R> _read;
  @override
  final WatchHandlerCallback<Q, R> _watch;

  @override
  Future<R> read(Q query) {
    return _read.call(query);
  }

  @override
  Stream<R> watch(Q query) {
    return _watch.call(query);
  }
}
