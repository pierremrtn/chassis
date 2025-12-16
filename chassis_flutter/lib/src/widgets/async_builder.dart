import 'package:chassis/chassis.dart';
import 'package:flutter/material.dart';

/// A widget that builds itself based on the latest snapshot of interaction with
/// a [Async].
class AsyncBuilder<T> extends StatelessWidget {
  const AsyncBuilder({
    super.key,
    required this.state,
    required this.builder,
    this.loadingBuilder,
    this.errorBuilder,
    this.maintainState = true,
  });

  /// The current state of the asynchronous operation.
  final Async<T> state;

  /// Whether to maintain the previous data while loading or erroring.
  ///
  /// If true (default), [builder] will be called if [state.hasValue] is true,
  /// even if [state.isLoading] or [state.hasError] is also true.
  /// This prevents flickering by showing stale data while refreshing.
  final bool maintainState;

  /// Builder called when data is available.
  final Widget Function(BuildContext context, T data) builder;

  /// Builder called when loading and no data is available (or maintainState is false).
  final WidgetBuilder? loadingBuilder;

  /// Builder called when error and no data is available (or maintainState is false).
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  Widget build(BuildContext context) {
    // 1. Data Priority (Anti-flickering)
    if (state.hasValue && maintainState) {
      return builder(context, state.valueOrNull as T);
    }

    // 2. Initial Loading
    if (state.isLoading) {
      return loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator());
    }

    // 3. Blocking Error
    if (state.hasError) {
      return errorBuilder?.call(context, state.errorOrNull!) ??
          const SizedBox.shrink();
    }

    // 4. Default case (should theoretically not be reachable if states are exhaustive)
    return const SizedBox.shrink();
  }
}
