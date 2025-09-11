/// {@template stream_state}
/// A sealed class representing the state of a streaming operation.
///
/// This class provides a type-safe way to handle the different states that
/// can occur during streaming operations: loading, data, and error states.
/// It uses pattern matching and functional programming patterns to handle
/// different states elegantly.
///
/// Example usage:
/// ```dart
/// StreamState<String> state = StreamStateLoading<String>();
///
/// // Using pattern matching
/// switch (state) {
///   case StreamStateLoading():
///     print('Loading...');
///   case StreamStateData(:final data):
///     print('Data: $data');
///   case StreamStateError(:final error):
///     print('Error: $error');
/// }
///
/// // Using the when method
/// final message = state.when(
///   loading: () => 'Loading...',
///   data: (data) => 'Got: $data',
///   error: (error, stackTrace) => 'Failed: $error',
/// );
/// ```
/// {@endtemplate}
sealed class StreamState<R> {
  /// {@macro stream_state}
  const StreamState();

  /// Transforms this state using the provided functions.
  ///
  /// If this is a [StreamStateLoading], calls [loading].
  /// If this is a [StreamStateData], calls [data] with the value.
  /// If this is a [StreamStateError], calls [error] with the error and stack trace.
  ///
  /// All functions are required and must return a value of type [U].
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

  /// Transforms this state using the provided optional functions.
  ///
  /// If this is a [StreamStateLoading] and [loading] is provided, calls it.
  /// If this is a [StreamStateData] and [data] is provided, calls it with the value.
  /// If this is a [StreamStateError] and [error] is provided, calls it with the error.
  /// Returns `null` if the appropriate function is not provided.
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

  /// Returns the data if this state contains data, otherwise returns `null`.
  R? dataOrNull() => switch (this) {
        StreamStateData<R>(data: final d) => d,
        _ => null,
      };
}

/// {@template stream_state_loading}
/// Represents the loading state of a streaming operation.
///
/// This state indicates that the stream is currently loading and no data
/// has been received yet.
/// {@endtemplate}
final class StreamStateLoading<R> extends StreamState<R> {
  /// {@macro stream_state_loading}
  const StreamStateLoading();
}

/// {@template stream_state_data}
/// Represents the data state of a streaming operation.
///
/// This state contains the actual data received from the stream.
/// {@endtemplate}
final class StreamStateData<R> extends StreamState<R> {
  /// {@macro stream_state_data}
  const StreamStateData(this.data);

  /// The data received from the stream.
  final R data;
}

/// {@template stream_state_error}
/// Represents the error state of a streaming operation.
///
/// This state contains information about an error that occurred during
/// the streaming operation.
/// {@endtemplate}
final class StreamStateError<R> extends StreamState<R> {
  /// {@macro stream_state_error}
  const StreamStateError(this.error, [this.stackTrace]);

  /// The error that occurred.
  final Object error;

  /// The stack trace at the time of the error, if available.
  final StackTrace? stackTrace;
}

/// {@template future_state}
/// A sealed class representing the state of a future operation.
///
/// This class provides a type-safe way to handle the different states that
/// can occur during future operations: loading and result states.
/// It complements the [StreamState] for handling asynchronous operations
/// that complete once rather than continuously.
///
/// Example usage:
/// ```dart
/// FutureState<String> state = FutureLoading<String>();
///
/// // Using pattern matching
/// switch (state) {
///   case FutureLoading():
///     print('Loading...');
///   case FutureSuccess(:final data):
///     print('Success: $data');
///   case FutureError(:final error):
///     print('Error: $error');
/// }
/// ```
/// {@endtemplate}
sealed class FutureState<R> {
  /// {@macro future_state}
  const FutureState();
}

/// {@template future_loading}
/// Represents the loading state of a future operation.
///
/// This state indicates that the future is currently executing and no result
/// has been received yet.
/// {@endtemplate}
final class FutureLoading<R> implements FutureState<R> {
  /// {@macro future_loading}
  const FutureLoading();
}

/// {@template future_result}
/// A sealed class representing the result of a future operation.
///
/// This class represents the completion state of a future operation,
/// which can either succeed with data or fail with an error.
/// {@endtemplate}
sealed class FutureResult<R> implements FutureState<R> {
  /// {@macro future_result}
  const FutureResult();
}

/// {@template future_success}
/// Represents the successful completion of a future operation.
///
/// This state contains the data returned by the successful future operation.
/// {@endtemplate}
final class FutureSuccess<R> implements FutureResult<R> {
  /// {@macro future_success}
  const FutureSuccess(this.data);

  /// The data returned by the successful operation.
  final R data;
}

/// {@template future_error}
/// Represents the error state of a future operation.
///
/// This state contains information about an error that occurred during
/// the future operation.
/// {@endtemplate}
final class FutureError<R> implements FutureResult<R> {
  /// {@macro future_error}
  const FutureError(this.error, [this.stackTrace]);

  /// The error that occurred.
  final Object error;

  /// The stack trace at the time of the error, if available.
  final StackTrace? stackTrace;
}
