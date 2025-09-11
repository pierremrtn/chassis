/// Classes taken from ubuntu's safe_change_notifier package https://github.com/canonical/ubuntu-flutter-plugins/blob/main/packages/safe_change_notifier/lib/src/change_notifier.dart
/// And adapted to uses [Disposable]
library;

import 'package:chassis/chassis.dart';
import 'package:flutter/foundation.dart';

/// {@template safe_notifier_mixin}
/// A safe mixin for Flutter's `ChangeNotifier` and `ValueNotifier` that makes
/// `notifyListeners()` a no-op, rather than an error, after disposal.
///
/// This mixin prevents common Flutter errors that occur when trying to notify
/// listeners after a notifier has been disposed. It integrates with the [Disposable]
/// mixin to provide safe disposal behavior.
///
/// ![safe_change_notifier](https://github.com/canonical/ubuntu-flutter-plugins/raw/main/packages/safe_change_notifier/images/safe_change_notifier.png)
///
/// Example usage:
/// ```dart
/// class MyNotifier extends ChangeNotifier with Disposable, SafeNotifierMixin {
///   void updateData() {
///     // This is safe to call even after disposal
///     notifyListeners();
///   }
/// }
/// ```
/// {@endtemplate}
mixin SafeNotifierMixin on ChangeNotifier implements Disposable {
  /// {@macro safe_notifier_mixin}
  @override
  bool get hasListeners => !disposed && super.hasListeners;

  /// {@macro safe_notifier_mixin}
  @override
  void notifyListeners() {
    if (!disposed) {
      super.notifyListeners();
    }
  }

  /// {@macro safe_notifier_mixin}
  @override
  void addListener(VoidCallback listener) {
    if (!disposed) {
      super.addListener(listener);
    }
  }

  /// {@macro safe_notifier_mixin}
  @override
  void removeListener(VoidCallback listener) {
    if (!disposed) {
      super.removeListener(listener);
    }
  }
}

/// {@template safe_change_notifier}
/// A safe drop-in replacement for Flutter's `ChangeNotifier` that makes
/// `notifyListeners()` a no-op, rather than an error, after its disposal.
///
/// This class combines [ChangeNotifier] with [Disposable] and [SafeNotifierMixin]
/// to provide a robust foundation for state management that prevents common
/// disposal-related errors.
///
/// ![safe_change_notifier](https://github.com/canonical/ubuntu-flutter-plugins/raw/main/packages/safe_change_notifier/images/safe_change_notifier.png)
///
/// Example usage:
/// ```dart
/// class MyViewModel extends SafeChangeNotifier {
///   String _data = '';
///
///   String get data => _data;
///
///   void updateData(String newData) {
///     _data = newData;
///     notifyListeners(); // Safe to call even after disposal
///   }
/// }
/// ```
/// {@endtemplate}
class SafeChangeNotifier extends ChangeNotifier
    with Disposable, SafeNotifierMixin {
  /// {@macro safe_change_notifier}
  SafeChangeNotifier();
}
