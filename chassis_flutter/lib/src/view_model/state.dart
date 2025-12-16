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
///   error: (error) => 'Failed: $error',
/// );
/// ```
/// {@endtemplate}
sealed class StreamState<R> {
  /// {@macro stream_state}
  const StreamState();

  factory StreamState.initial() = StreamStateInitial.new;
  factory StreamState.data(R data) = StreamStateData.new;
  factory StreamState.error(Object e, StackTrace s) = StreamStateError.new;
}

/// {@template stream_state_loading}
/// Represents the loading state of a streaming operation.
///
/// This state indicates that the stream is currently loading and no data
/// has been received yet.
/// {@endtemplate}
final class StreamStateInitial<R> extends StreamState<R> {
  /// {@macro stream_state_loading}
  const StreamStateInitial();
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

  factory FutureState.loading() = FutureStateLoading.new;
  factory FutureState.success(R data) = FutureStateSuccess.new;
  factory FutureState.error(Object e, StackTrace s) = FutureStateError.new;
}

/// {@template future_loading}
/// Represents the loading state of a future operation.
///
/// This state indicates that the future is currently executing and no result
/// has been received yet.
/// {@endtemplate}
final class FutureStateLoading<R> implements FutureState<R> {
  /// {@macro future_loading}
  const FutureStateLoading();
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
final class FutureStateSuccess<R> implements FutureResult<R> {
  /// {@macro future_success}
  const FutureStateSuccess(this.data);

  /// The data returned by the successful operation.
  final R data;
}

/// {@template future_error}
/// Represents the error state of a future operation.
///
/// This state contains information about an error that occurred during
/// the future operation.
/// {@endtemplate}
final class FutureStateError<R> implements FutureResult<R> {
  /// {@macro future_error}
  const FutureStateError(this.error, this.stackTrace);

  /// The error that occurred.
  final Object error;

  /// The stack trace at the time of the error, if available.
  final StackTrace stackTrace;
}

/// {@template future_state_utils}
/// Utility extension for [FutureState] providing convenient methods for
/// pattern matching and state handling.
///
/// This extension provides utilities for working with [FutureState] instances,
/// including pattern matching operations for handling different states.
/// {@endtemplate}
extension FutureStateUtils<R> on FutureState<R> {
  /// Transforms this state using the provided functions.
  ///
  /// If this is a [FutureStateLoading], calls [loading].
  /// If this is a [FutureStateSuccess], calls [data] with the value.
  /// If this is a [FutureStateError], calls [error] with the error.
  ///
  /// All functions are required and must return a value of type [U].
  ///
  /// Example:
  /// ```dart
  /// final message = state.when(
  ///   loading: () => 'Loading...',
  ///   data: (data) => 'Success: $data',
  ///   error: (error) => 'Failed: $error',
  /// );
  /// ```
  U when<U>({
    required U Function() loading,
    required U Function(R data) data,
    required U Function(Object error, StackTrace stackTrace) error,
  }) =>
      switch (this) {
        FutureStateLoading<R>() => loading(),
        FutureStateSuccess<R>(data: final d) => data(d),
        FutureStateError<R>(error: final e, stackTrace: final s) => error(e, s),
      };

  FutureState<U> map<U>(
    U Function(R) mapper,
  ) =>
      switch (this) {
        FutureStateLoading<R>() => FutureStateLoading<U>(),
        FutureStateSuccess<R>(data: final d) =>
          FutureStateSuccess<U>(mapper(d)),
        FutureStateError<R>(error: final e, stackTrace: final s) =>
          FutureStateError<U>(e, s),
      };
}

/// {@template future_result_utils}
/// Utility extension for [FutureResult] providing convenient methods for
/// pattern matching and result handling.
///
/// This extension provides utilities for working with [FutureResult] instances,
/// which represent completed future operations that can either succeed or fail.
/// {@endtemplate}
extension FutureResultUtils<R> on FutureResult<R> {
  /// Transforms this result using the provided functions.
  ///
  /// If this is a [FutureStateSuccess], calls [data] with the value.
  /// If this is a [FutureStateError], calls [error] with the error.
  ///
  /// Both functions are required and must return a value of type [U].
  ///
  /// Example:
  /// ```dart
  /// final message = result.when(
  ///   data: (data) => 'Success: $data',
  ///   error: (error) => 'Failed: $error',
  /// );
  /// ```
  U when<U>({
    required U Function(R data) data,
    required U Function(Object error) error,
  }) =>
      switch (this) {
        FutureStateSuccess<R>(data: final d) => data(d),
        FutureStateError<R>(error: final e) => error(e),
      };
}

/// {@template stream_state_utils}
/// Utility extension for [StreamState] providing convenient methods for
/// pattern matching, type checking, and data extraction.
///
/// This extension provides a comprehensive set of utilities for working with
/// [StreamState] instances, including functional programming operations,
/// type checking, and safe data access.
/// {@endtemplate}
extension StreamStateUtils<R> on StreamState<R> {
  /// Transforms this state using the provided functions.
  ///
  /// If this is a [StreamStateInitial], calls [loading].
  /// If this is a [StreamStateData], calls [data] with the value.
  /// If this is a [StreamStateError], calls [error] with the error.
  ///
  /// All functions are required and must return a value of type [U].
  ///
  /// Example:
  /// ```dart
  /// final message = state.when(
  ///   loading: () => 'Loading...',
  ///   data: (data) => 'Got: $data',
  ///   error: (error) => 'Failed: $error',
  /// );
  /// ```
  U when<U>({
    required U Function() loading,
    required U Function(R data) data,
    required U Function(Object error) error,
  }) =>
      switch (this) {
        StreamStateInitial<R>() => loading(),
        StreamStateData<R>(data: final d) => data(d),
        StreamStateError<R>(error: final e) => error(e),
      };

  /// Transforms this state using the provided optional functions.
  ///
  /// If this is a [StreamStateInitial] and [loading] is provided, calls it.
  /// If this is a [StreamStateData] and [data] is provided, calls it with the value.
  /// If this is a [StreamStateError] and [error] is provided, calls it with the error.
  /// Returns `null` if the appropriate function is not provided.
  ///
  /// Example:
  /// ```dart
  /// final message = state.whenOrNull(
  ///   data: (data) => 'Got: $data',
  ///   error: (error) => 'Failed: $error',
  ///   // loading case will return null
  /// );
  /// ```
  U? whenOrNull<U>({
    U Function()? loading,
    U Function(R data)? data,
    U Function(Object error)? error,
  }) =>
      switch (this) {
        StreamStateInitial<R>() => loading?.call(),
        StreamStateData<R>(data: final d) => data?.call(d),
        StreamStateError<R>(error: final e) => error?.call(e),
      };

  /// Returns the data if this state contains data, otherwise returns `null`.
  ///
  /// This is a safe way to extract data from a [StreamState] without
  /// having to handle all possible states.
  ///
  /// Example:
  /// ```dart
  /// final data = state.dataOrNull();
  /// if (data != null) {
  ///   print('Data: $data');
  /// }
  /// ```
  R? dataOrNull() => switch (this) {
        StreamStateData<R>(data: final d) => d,
        _ => null,
      };

  R dataOrElse(R defaultValue) => switch (this) {
        StreamStateData<R>(data: final d) => d,
        _ => defaultValue,
      };

  /// Returns `true` if this state is a [StreamStateInitial].
  ///
  /// Example:
  /// ```dart
  /// if (state.isLoading) {
  ///   showLoadingIndicator();
  /// }
  /// ```
  bool get isLoading => this is StreamStateInitial<R>;

  /// Returns `true` if this state is a [StreamStateData].
  ///
  /// Example:
  /// ```dart
  /// if (state.isData) {
  ///   final data = state.dataOrNull()!;
  ///   displayData(data);
  /// }
  /// ```
  bool get isData => this is StreamStateData<R>;

  /// Returns `true` if this state is a [StreamStateError].
  ///
  /// Example:
  /// ```dart
  /// if (state.isError) {
  ///   final error = state.asError!;
  ///   showErrorMessage(error.error);
  /// }
  /// ```
  bool get isError => this is StreamStateError<R>;

  /// Returns this state cast as [StreamStateData] if it contains data,
  /// otherwise returns `null`.
  ///
  /// This provides safe access to the data state without throwing exceptions.
  ///
  /// Example:
  /// ```dart
  /// final dataState = state.asData;
  /// if (dataState != null) {
  ///   print('Data: ${dataState.data}');
  /// }
  /// ```
  StreamStateData<R>? get asData => switch (this) {
        StreamStateData<R>() => this as StreamStateData<R>,
        _ => null,
      };

  /// Returns this state cast as [StreamStateError] if it contains an error,
  /// otherwise returns `null`.
  ///
  /// This provides safe access to the error state without throwing exceptions.
  ///
  /// Example:
  /// ```dart
  /// final errorState = state.asError;
  /// if (errorState != null) {
  ///   print('Error: ${errorState.error}');
  ///   if (errorState.stackTrace != null) {
  ///     print('Stack trace: ${errorState.stackTrace}');
  ///   }
  /// }
  /// ```
  StreamStateError<R>? get asError => switch (this) {
        StreamStateError<R>() => this as StreamStateError<R>,
        _ => null,
      };
}
