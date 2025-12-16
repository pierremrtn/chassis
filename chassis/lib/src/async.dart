/// Represents the state of an asynchronous operation.
/// Unified model for Streams and Futures.
sealed class Async<T> {
  const Async();

  /// The current data (fresh, previous, or optimistic).
  T? get valueOrNull;

  /// The error if the LAST operation failed.
  Object? get errorOrNull;

  bool get isLoading;
  bool get hasValue => valueOrNull != null;
  bool get hasError => errorOrNull != null;

  // --- State Transitions (Fluent API) ---

  /// Transitions to Loading state while keeping the current data (Refetching).
  Async<T> toLoading() => AsyncLoading(valueOrNull);

  /// Transitions to Data state (Success).
  Async<T> toData(T value) => AsyncData(value);

  /// Transitions to Error state while keeping the current data (Soft Error).
  Async<T> toError(Object error, StackTrace stack) =>
      AsyncError(error, stackTrace: stack, previous: valueOrNull);

  // --- Factories ---

  const factory Async.data(T value) = AsyncData<T>;
  const factory Async.loading([T? previous]) = AsyncLoading<T>;
  const factory Async.error(Object error,
      {StackTrace? stackTrace, T? previous}) = AsyncError<T>;
}

// --- Subclasses Implementation ---

class AsyncData<T> extends Async<T> {
  final T value;
  const AsyncData(this.value);

  @override
  T? get valueOrNull => value;
  @override
  Object? get errorOrNull => null;
  @override
  bool get isLoading => false;
}

class AsyncLoading<T> extends Async<T> {
  final T? previous;
  const AsyncLoading([this.previous]);

  @override
  T? get valueOrNull => previous;
  @override
  Object? get errorOrNull => null;
  @override
  bool get isLoading => true;
}

class AsyncError<T> extends Async<T> {
  final Object error;
  final StackTrace? stackTrace;
  final T? previous;

  const AsyncError(this.error, {this.stackTrace, this.previous});

  @override
  T? get valueOrNull => previous;
  @override
  Object? get errorOrNull => error;
  @override
  bool get isLoading => false;
}
