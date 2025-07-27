import 'handle.dart';

extension FutureHandleStateUtils<T> on FutureHandleState<T> {
  bool get isInitial => this is FutureHandleStateInitial;
  bool get isLoading => this is FutureHandleStateLoading;
  bool get isSuccess => this is FutureHandleStateSuccess;
  bool get isFailure => this is FutureHandleStateError;
  bool get isDone => isSuccess || isFailure;

  U when<U>({
    required HandleInitialCallback<U> initial,
    required HandleLoadingCallback<U> loading,
    required HandleSuccessCallback<T, U> success,
    required HandleErrorCallback<U> failure,
  }) =>
      switch (this) {
        FutureHandleStateInitial<T>() => initial(),
        FutureHandleStateLoading<T>() => loading(),
        final FutureHandleStateSuccess<T> state => success(state.data),
        final FutureHandleStateError<T> state =>
          failure(state.error, state.stackTrace),
      };

  U? whenOrNull<U>({
    HandleInitialCallback<U>? initial,
    HandleLoadingCallback<U>? loading,
    HandleSuccessCallback<T, U>? success,
    HandleErrorCallback<U>? failure,
  }) =>
      switch (this) {
        FutureHandleStateInitial<T>() => initial?.call(),
        FutureHandleStateLoading<T>() => loading?.call(),
        final FutureHandleStateSuccess<T> state => success?.call(state.data),
        final FutureHandleStateError<T> state =>
          failure?.call(state.error, state.stackTrace),
      };
}
