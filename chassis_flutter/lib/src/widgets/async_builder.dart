import 'package:chassis/chassis.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A widget that builds itself based on the latest snapshot of interaction with
/// an [Async].
class const AsyncBuilder<T>({
  super.key,

  /// The current state of the asynchronous operation.
  required final Async<T> state,

  /// Builder called when data is available.
  required final Widget Function(BuildContext context, T data) builder,

  /// Builder called when loading and no data is available (or maintainState is false).
  final WidgetBuilder? loadingBuilder,

  /// Builder called when error and no data is available (or maintainState is false).
  ///
  /// If omitted, an error renders a standard [ErrorWidget] in debug builds —
  /// a silent default would hide failures during development — and nothing
  /// ([SizedBox.shrink]) in release builds.
  final Widget Function(BuildContext context, Object error)? errorBuilder,

  /// Whether to maintain the previous data while loading or erroring.
  ///
  /// If true (default), [builder] is called whenever [Async.hasValue] is
  /// true, even if the state is loading or in error. This prevents
  /// flickering by showing stale data while refreshing.
  final bool maintainState = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return switch (state) {
      AsyncData<T>(:final value) => builder(context, value),

      // Anti-flickering: keep showing the carried data while refreshing
      // or after a soft error.
      AsyncLoading<T>(previous: AsyncData<T>(:final value))
          when maintainState =>
        builder(context, value),
      AsyncError<T>(previous: AsyncData<T>(:final value)) when maintainState =>
        builder(context, value),
      AsyncLoading<T>() =>
        loadingBuilder?.call(context) ??
            const Center(child: CircularProgressIndicator()),
      AsyncError<T>(:final error) =>
        errorBuilder?.call(context, error) ?? _defaultError(error),
    };
  }

  Widget _defaultError(Object error) {
    if (kDebugMode) {
      return ErrorWidget.withDetails(
        message:
            'AsyncBuilder<$T> received an error and has no '
            'errorBuilder:\n$error\n\n'
            'Provide errorBuilder to render errors in production.',
      );
    }
    return const SizedBox.shrink();
  }
}
