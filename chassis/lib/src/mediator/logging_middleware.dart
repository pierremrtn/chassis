import 'dart:async';

import 'command.dart';
import 'middleware.dart';
import 'query.dart';

/// The lifecycle moment a [ChassisLogRecord] describes.
enum ChassisLogEvent {
  /// A command or query was dispatched.
  start,

  /// A command or read query completed successfully.
  success,

  /// A command, read query, or watched stream produced an error.
  error,

  /// A watched stream emitted a value.
  streamEvent,

  /// A watched stream closed.
  streamDone,
}

/// The kind of mediator operation being traced.
enum ChassisLogKind { run, read, watch }

/// A single trace entry produced by [LoggingMiddleware].
class ChassisLogRecord {
  const ChassisLogRecord({
    required this.event,
    required this.kind,
    required this.request,
    required this.params,
    this.elapsed,
    this.error,
    this.stackTrace,
  });

  final ChassisLogEvent event;
  final ChassisLogKind kind;

  /// The dispatched command or query. Its `toString` includes [params].
  final Object request;

  /// The request's declared parameters (see `Command.params` / `Query.params`).
  final Map<String, Object?> params;

  /// Time elapsed since dispatch. Null for [ChassisLogEvent.start].
  final Duration? elapsed;

  /// The error, for [ChassisLogEvent.error] records.
  final Object? error;
  final StackTrace? stackTrace;

  @override
  String toString() {
    final verb = kind.name;
    final ms = elapsed == null ? '' : ' after ${elapsed!.inMilliseconds}ms';
    return switch (event) {
      ChassisLogEvent.start => '[chassis] $verb $request',
      ChassisLogEvent.success => '[chassis] $verb $request succeeded$ms',
      ChassisLogEvent.error => '[chassis] $verb $request failed$ms: $error',
      ChassisLogEvent.streamEvent => '[chassis] $verb $request emitted$ms',
      ChassisLogEvent.streamDone => '[chassis] $verb $request closed$ms',
    };
  }
}

/// Destination for [ChassisLogRecord]s. Implement to route traces to your
/// logger (`dart:developer`, `logging`, Sentry breadcrumbs, ...).
abstract interface class ChassisLogSink {
  void write(ChassisLogRecord record);
}

/// Default sink: prints each record.
class PrintLogSink implements ChassisLogSink {
  const PrintLogSink();

  @override
  void write(ChassisLogRecord record) {
    // ignore: avoid_print — this sink's single purpose is console output.
    print(record);
    final stack = record.stackTrace;
    if (stack != null) {
      // ignore: avoid_print
      print(stack);
    }
  }
}

/// Middleware that traces every mediator operation: dispatch, outcome,
/// duration, and errors with stack traces.
///
/// Errors are always rethrown — logging never swallows failures.
///
/// ```dart
/// final mediator = AppMediator(...)
///   ..addMiddleware(LoggingMiddleware());
/// ```
class LoggingMiddleware extends MediatorMiddleware {
  LoggingMiddleware({
    ChassisLogSink sink = const PrintLogSink(),
    this.logStart = false,
    this.logStreamEvents = false,
  }) : _sink = sink;

  final ChassisLogSink _sink;

  /// Whether to emit a record when an operation is dispatched, in addition
  /// to its outcome. Defaults to false.
  final bool logStart;

  /// Whether to emit a record for every stream emission of a watch query.
  /// Defaults to false (only subscription, errors, and completion are logged).
  final bool logStreamEvents;

  Map<String, Object?> _paramsOf(Object request) => switch (request) {
        Command<Object?>(:final params) => params,
        Query<Object?>(:final params) => params,
        _ => const {},
      };

  void _write(
    ChassisLogEvent event,
    ChassisLogKind kind,
    Object request, {
    Duration? elapsed,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _sink.write(ChassisLogRecord(
      event: event,
      kind: kind,
      request: request,
      params: _paramsOf(request),
      elapsed: elapsed,
      error: error,
      stackTrace: stackTrace,
    ));
  }

  Future<R> _traceFuture<R>(
    ChassisLogKind kind,
    Object request,
    Future<R> Function() next,
  ) async {
    final watch = Stopwatch()..start();
    if (logStart) _write(ChassisLogEvent.start, kind, request);
    try {
      final result = await next();
      _write(ChassisLogEvent.success, kind, request, elapsed: watch.elapsed);
      return result;
    } catch (e, s) {
      _write(
        ChassisLogEvent.error,
        kind,
        request,
        elapsed: watch.elapsed,
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  @override
  Future<R> onRun<C extends Command<R>, R>(C command, NextRun<C, R> next) {
    return _traceFuture(ChassisLogKind.run, command, () => next(command));
  }

  @override
  Future<R> onRead<Q extends ReadQuery<R>, R>(Q query, NextRead<Q, R> next) {
    return _traceFuture(ChassisLogKind.read, query, () => next(query));
  }

  /// Elapsed times for watch records are measured from dispatch (the
  /// `onWatch` call), and the start record (if [logStart]) is emitted at
  /// dispatch too. The returned stream preserves the source's
  /// broadcast/single-subscription nature; on a broadcast stream with
  /// several listeners, per-event and error records are emitted once per
  /// listener.
  @override
  Stream<R> onWatch<Q extends WatchQuery<R>, R>(
    Q query,
    NextWatch<Q, R> next,
  ) {
    final watch = Stopwatch()..start();
    if (logStart) _write(ChassisLogEvent.start, ChassisLogKind.watch, query);

    late final Stream<R> source;
    try {
      source = next(query);
    } catch (e, s) {
      _write(
        ChassisLogEvent.error,
        ChassisLogKind.watch,
        query,
        error: e,
        stackTrace: s,
      );
      rethrow;
    }

    // StreamTransformer.fromHandlers preserves isBroadcast, unlike an
    // async* wrapper which would force single-subscription semantics.
    return source.transform(StreamTransformer<R, R>.fromHandlers(
      handleData: (value, sink) {
        if (logStreamEvents) {
          _write(
            ChassisLogEvent.streamEvent,
            ChassisLogKind.watch,
            query,
            elapsed: watch.elapsed,
          );
        }
        sink.add(value);
      },
      handleError: (error, stackTrace, sink) {
        _write(
          ChassisLogEvent.error,
          ChassisLogKind.watch,
          query,
          elapsed: watch.elapsed,
          error: error,
          stackTrace: stackTrace,
        );
        sink.addError(error, stackTrace);
      },
      handleDone: (sink) {
        _write(
          ChassisLogEvent.streamDone,
          ChassisLogKind.watch,
          query,
          elapsed: watch.elapsed,
        );
        sink.close();
      },
    ));
  }
}
