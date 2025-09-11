import 'package:chassis_flutter/src/view_model/view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/single_child_widget.dart';

/// {@template view_model_provider}
/// Takes a `create` function that is responsible for
/// creating the [ViewModel] and a [child] which will have access
/// to the instance via `ViewModelProvider.of(context)`.
/// It is used as a dependency injection (DI) widget so that a single instance
/// of a [ViewModel] can be provided to multiple widgets within a subtree.
///
/// ```dart
/// ViewModelProvider(
///   create: (BuildContext context) => UserViewModel(mediator),
///   child: UserScreen(),
/// );
/// ```
///
/// It automatically handles disposing the instance when the widget is disposed.
/// By default, `create` is called only when the instance is accessed.
/// To override this behavior, set [lazy] to `false`.
///
/// ```dart
/// ViewModelProvider(
///   lazy: false,
///   create: (BuildContext context) => UserViewModel(mediator),
///   child: UserScreen(),
/// );
/// ```
///
/// {@endtemplate}
class ViewModelProvider<T extends ViewModel<Object?, Object?>>
    extends SingleChildStatelessWidget {
  /// {@macro view_model_provider}
  const ViewModelProvider({
    required T Function(BuildContext context) create,
    super.key,
    this.child,
    this.lazy = true,
  })  : _create = create,
        _value = null,
        super(child: child);

  /// {@template view_model_provider_value}
  /// Takes a [value] and a [child] which will have access to the [value] via
  /// `ViewModelProvider.of(context)`.
  /// When `ViewModelProvider.value` is used, the [ViewModel]
  /// will not be automatically disposed.
  /// As a result, `ViewModelProvider.value` should only be used for providing
  /// existing instances to new subtrees.
  ///
  /// A new [ViewModel] should not be created in `ViewModelProvider.value`.
  /// New instances should always be created using the
  /// default constructor within the `create` function.
  ///
  /// ```dart
  /// ViewModelProvider.value(
  ///   value: ViewModelProvider.of<UserViewModel>(context),
  ///   child: UserScreen(),
  /// );
  /// ```
  /// {@endtemplate}
  const ViewModelProvider.value({
    required T value,
    super.key,
    this.child,
  })  : _value = value,
        _create = null,
        lazy = true,
        super(child: child);

  /// Widget which will have access to the [ViewModel].
  final Widget? child;

  /// Whether the [ViewModel] should be created lazily.
  /// Defaults to `true`.
  final bool lazy;

  final T Function(BuildContext context)? _create;

  final T? _value;

  /// {@template view_model_provider_of}
  /// Method that allows widgets to access a [ViewModel] instance
  /// as long as their `BuildContext` contains a [ViewModelProvider] instance.
  ///
  /// If we want to access an instance of `UserViewModel` which was provided higher up
  /// in the widget tree we can do so via:
  ///
  /// ```dart
  /// ViewModelProvider.of<UserViewModel>(context);
  /// ```
  ///
  /// Set [listen] to `true` to automatically rebuild the widget when the
  /// view model's state changes.
  /// {@endtemplate}
  static T of<T extends ViewModel<Object?, Object?>>(
    BuildContext context, {
    bool listen = false,
  }) {
    try {
      return Provider.of<T>(context, listen: listen);
    } on ProviderNotFoundException catch (e) {
      if (e.valueType != T) rethrow;
      throw FlutterError(
        '''
        ViewModelProvider.of() called with a context that does not contain a $T.
        No ancestor could be found starting from the context that was passed to ViewModelProvider.of<$T>().

        This can happen if the context you used comes from a widget above the ViewModelProvider.

        The context used was: $context
        ''',
      );
    }
  }

  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    assert(
      child != null,
      '$runtimeType used outside of MultiViewModelProvider must specify a child',
    );
    final value = _value;
    return value != null
        ? InheritedProvider<T>.value(
            value: value,
            startListening: _startListening,
            lazy: lazy,
            child: child,
          )
        : InheritedProvider<T>(
            create: _create,
            dispose: (_, vm) => vm.dispose(),
            startListening: _startListening,
            lazy: lazy,
            child: child,
          );
  }

  static VoidCallback _startListening(
    InheritedContext<ViewModel<dynamic, dynamic>?> e,
    ViewModel<dynamic, dynamic> value,
  ) {
    value.addListener(e.markNeedsNotifyDependents);

    return () => value.removeListener(e.markNeedsNotifyDependents);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<bool>('lazy', lazy));
  }
}
