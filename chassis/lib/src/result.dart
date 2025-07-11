typedef FutureResult<T> = Future<Result<T>>;

sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success;
  bool get isFailure => this is Failure;

  U when<U>({
    required U Function(T success) success,
    required U Function(Object error) failure,
  }) =>
      switch (this) {
        Success(:final value) => success(value),
        Failure(:final error) => failure(error),
      };

  U? whenOrNull<U>({
    U Function(T success)? success,
    U Function(Object error)? failure,
  }) =>
      switch (this) {
        Success(:final value) => success?.call(value),
        Failure(:final error) => failure?.call(error),
      };

  U? whenSuccess<U>(U Function(T success) success) => switch (this) {
        Success(:final value) => success(value),
        _ => null,
      };

  U? whenFailure<U>(U Function(Object failure) failure) => switch (this) {
        Failure(:final error) => failure(error),
        _ => null,
      };

  /// Return Result as [Success] or throw if result is a [Failure]
  Success<T> get asSuccess => this as Success<T>;

  /// Return Result as [Failure] or throw if result is a [Success]
  Failure<T> get asFailure => this as Failure<T>;
}

extension ResultValue<R> on Result<R> {
  Object? get error => switch (this) {
        Failure(:final error) => error,
        _ => null,
      };
  R? get value => switch (this) {
        Success(:final value) => value,
        _ => null,
      };
}

class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;
}

class Failure<T> extends Result<T> {
  const Failure(this.error, {this.stackTrace});

  final Object error;
  final StackTrace? stackTrace;

  /// Convert a failure from a Result of type T into a Result of type U
  /// Useful to return failure form inner failure with different result type
  Failure<U> propagate<U>() => Failure(error);
}
