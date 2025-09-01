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

// Read
sealed class AsyncState<R> {}

final class AsyncLoading<R> implements AsyncState<R> {}

sealed class AsyncResult<R> implements AsyncState<R> {}

final class AsyncSuccess<R> implements AsyncResult<R> {
  final R data;

  const AsyncSuccess(this.data);
}

final class AsyncError<R> implements AsyncResult<R> {
  final Object error;
  final StackTrace? stackTrace;

  const AsyncError(this.error, [this.stackTrace]);
}

// Commands
sealed class CommandState<R> {}

final class CommandStateLoading<R> implements CommandState<R> {}

sealed class CommandResult<R> implements CommandState<R> {}

final class CommandSuccess<R> implements CommandResult<R> {
  final R data;

  const CommandSuccess(this.data);
}

final class CommandError<R> implements CommandResult<R> {
  final Object error;
  final StackTrace? stackTrace;

  const CommandError(this.error, [this.stackTrace]);
}
