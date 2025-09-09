sealed class StreamState<R> {
  const StreamState();

  U when<U>({
    required U Function() loading,
    required U Function(R data) data,
    required U Function(Object error, [StackTrace? stackTrace]) error,
  }) =>
      switch (this) {
        StreamStateLoading<R>() => loading(),
        StreamStateData<R>(data: final d) => data(d),
        StreamStateError<R>(error: final e, stackTrace: final s) => error(e, s),
      };

  U? whenOrNull<U>({
    U Function()? loading,
    U Function(R data)? data,
    U Function(Object error, [StackTrace? stackTrace])? error,
  }) =>
      switch (this) {
        StreamStateLoading<R>() => loading?.call(),
        StreamStateData<R>(data: final d) => data?.call(d),
        StreamStateError<R>(error: final e, stackTrace: final s) =>
          error?.call(e, s),
      };

  R? dataOrNull() => switch (this) {
        StreamStateData<R>(data: final d) => d,
        _ => null,
      };
}

final class StreamStateLoading<R> extends StreamState<R> {}

final class StreamStateData<R> extends StreamState<R> {
  final R data;

  const StreamStateData(this.data);
}

final class StreamStateError<R> extends StreamState<R> {
  final Object error;
  final StackTrace? stackTrace;

  const StreamStateError(this.error, [this.stackTrace]);
}

sealed class FutureState<R> {}

final class FutureLoading<R> implements FutureState<R> {}

sealed class FutureResult<R> implements FutureState<R> {}

final class FutureSuccess<R> implements FutureResult<R> {
  final R data;

  const FutureSuccess(this.data);
}

final class FutureError<R> implements FutureResult<R> {
  final Object error;
  final StackTrace? stackTrace;

  const FutureError(this.error, [this.stackTrace]);
}
