/// Represents the state of an asynchronous operation.
/// Unified model for Streams and Futures.
///
/// An [Async] is always one of three states:
/// - [AsyncData]: the operation succeeded and produced a value.
/// - [AsyncLoading]: the operation is in progress.
/// - [AsyncError]: the last operation failed.
///
/// [AsyncLoading] and [AsyncError] may carry the last known [AsyncData] in
/// [AsyncLoading.previous] / [AsyncError.previous]. Carrying the whole
/// [AsyncData] (rather than a bare `T?`) makes "a value existed" provable by
/// the type system, even when `T` is nullable and the value itself is `null`:
///
/// ```dart
/// const state = Async<int?>.data(null);
/// state.hasValue; // true — data was produced, its value happens to be null.
/// ```
///
/// Prefer exhaustive pattern matching to render states:
///
/// ```dart
/// switch (state) {
///   case AsyncData(:final value): // ...
///   case AsyncLoading(): // ...
///   case AsyncError(:final error): // ...
/// }
/// ```
sealed class Async<T> {
  const Async();

  /// The current data (fresh or carried over from a previous success).
  ///
  /// Note: for nullable `T`, `null` is ambiguous (absent vs. a real `null`
  /// value). Use [hasValue] or pattern matching to discriminate.
  T? get valueOrNull => switch (this) {
        AsyncData<T>(:final value) => value,
        AsyncLoading<T>(:final previous) => previous?.value,
        AsyncError<T>(:final previous) => previous?.value,
      };

  /// The error if the LAST operation failed.
  Object? get errorOrNull =>
      switch (this) { AsyncError<T>(:final error) => error, _ => null };

  bool get isLoading => this is AsyncLoading<T>;

  /// Whether a value is available, either fresh ([AsyncData]) or carried over
  /// from a previous success while loading or in error.
  ///
  /// Unlike a null-check on [valueOrNull], this is correct for nullable `T`.
  bool get hasValue => switch (this) {
        AsyncData<T>() => true,
        AsyncLoading<T>(:final previous) => previous != null,
        AsyncError<T>(:final previous) => previous != null,
      };

  bool get hasError => this is AsyncError<T>;

  /// The available value, or throws a [StateError] if there is none.
  T get requireValue => switch (this) {
        AsyncData<T>(:final value) => value,
        AsyncLoading<T>(previous: AsyncData<T>(:final value)) => value,
        AsyncError<T>(previous: AsyncData<T>(:final value)) => value,
        _ => throw StateError(
            'Async<$T>.requireValue called on $this which holds no value. '
            'Check hasValue first, or pattern match on AsyncData.',
          ),
      };

  // --- Combinators ---

  /// Folds this state into a single value, exhaustively.
  ///
  /// `data` receives the fresh value ([AsyncData] only — a value carried by a
  /// loading or error state does not count as data here; use the receiver's
  /// [valueOrNull] inside `loading`/`error` if you need it).
  ///
  /// ```dart
  /// final label = state.when(
  ///   data: (user) => user.name,
  ///   loading: () => 'Loading…',
  ///   error: (e, _) => 'Failed: $e',
  /// );
  /// ```
  R when<R>({
    required R Function(T value) data,
    required R Function() loading,
    required R Function(Object error, StackTrace? stackTrace) error,
  }) =>
      switch (this) {
        AsyncData<T>(:final value) => data(value),
        AsyncLoading<T>() => loading(),
        AsyncError<T>(error: final e, :final stackTrace) =>
          error(e, stackTrace),
      };

  /// Transforms the value while preserving the state.
  ///
  /// [AsyncData] becomes `AsyncData(transform(value))`; loading and error
  /// states are preserved (including the error and stack trace), with any
  /// carried [AsyncLoading.previous]/[AsyncError.previous] transformed too.
  ///
  /// An exception thrown by [transform] propagates to the caller — it is a
  /// bug in the transform, not an [AsyncError] of the operation.
  ///
  /// ```dart
  /// final Async<String> name = state.map((user) => user.name);
  /// ```
  Async<R> map<R>(R Function(T value) transform) => switch (this) {
        AsyncData<T>(:final value) => AsyncData(transform(value)),
        AsyncLoading<T>(:final previous) => AsyncLoading(
            previous:
                previous == null ? null : AsyncData(transform(previous.value)),
          ),
        AsyncError<T>(:final error, :final stackTrace, :final previous) =>
          AsyncError(
            error,
            stackTrace: stackTrace,
            previous:
                previous == null ? null : AsyncData(transform(previous.value)),
          ),
      };

  // --- State Transitions (Fluent API) ---

  /// Transitions to Loading state while keeping the current data (Refetching).
  Async<T> toLoading() => AsyncLoading(previous: _carriedData);

  /// Transitions to Data state (Success).
  Async<T> toData(T value) => AsyncData(value);

  /// Transitions to Error state while keeping the current data (Soft Error).
  Async<T> toError(Object error, StackTrace stack) =>
      AsyncError(error, stackTrace: stack, previous: _carriedData);

  /// The [AsyncData] to carry through a transition: this state itself if it is
  /// data, otherwise whatever it was already carrying.
  AsyncData<T>? get _carriedData => switch (this) {
        final AsyncData<T> data => data,
        AsyncLoading<T>(:final previous) => previous,
        AsyncError<T>(:final previous) => previous,
      };

  // --- Factories ---

  const factory Async.data(T value) = AsyncData<T>;
  const factory Async.loading({AsyncData<T>? previous}) = AsyncLoading<T>;
  const factory Async.error(Object error,
      {StackTrace? stackTrace, AsyncData<T>? previous}) = AsyncError<T>;
}

// --- Subclasses Implementation ---

class AsyncData<T> extends Async<T> {
  const AsyncData(this.value);

  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AsyncData<T> && other.value == value;

  @override
  int get hashCode => Object.hash(AsyncData<T>, value);

  @override
  String toString() => 'AsyncData<$T>($value)';
}

class AsyncLoading<T> extends Async<T> {
  const AsyncLoading({this.previous});

  /// The last successful state, if any. Non-null proves a value existed,
  /// even if that value is `null` (for nullable `T`).
  final AsyncData<T>? previous;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AsyncLoading<T> && other.previous == previous;

  @override
  int get hashCode => Object.hash(AsyncLoading<T>, previous);

  @override
  String toString() =>
      'AsyncLoading<$T>(${previous == null ? '' : 'previous: $previous'})';
}

class AsyncError<T> extends Async<T> {
  const AsyncError(this.error, {this.stackTrace, this.previous});

  final Object error;
  final StackTrace? stackTrace;

  /// The last successful state, if any. Non-null proves a value existed,
  /// even if that value is `null` (for nullable `T`).
  final AsyncData<T>? previous;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AsyncError<T> &&
          other.error == error &&
          other.stackTrace == stackTrace &&
          other.previous == previous;

  @override
  int get hashCode => Object.hash(AsyncError<T>, error, stackTrace, previous);

  @override
  String toString() =>
      'AsyncError<$T>($error${previous == null ? '' : ', previous: $previous'})';
}
