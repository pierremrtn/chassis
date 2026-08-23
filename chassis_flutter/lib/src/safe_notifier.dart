/// Classes taken from ubuntu's safe_change_notifier package https://github.com/canonical/ubuntu-flutter-plugins/blob/main/packages/safe_change_notifier/lib/src/change_notifier.dart
/// And adapted to expose [Disposable]'s interface.
library;

import 'package:chassis/chassis.dart';
import 'package:flutter/foundation.dart';

/// {@template safe_notifier_mixin}
/// A safe mixin for Flutter's `ChangeNotifier` and `ValueNotifier` that makes
/// `notifyListeners()` a no-op, rather than an error, after disposal.
///
/// Only *notifying* is made safe: adding a listener to a disposed notifier is
/// a real bug and keeps Flutter's debug assertion. The mixin implements
/// [Disposable] so a disposed notifier can be detected via [disposed].
///
/// The mixin owns the disposal flag and chains to `ChangeNotifier.dispose()`,
/// so Flutter's own disposal machinery (debug asserts, leak tracking) stays
/// armed.
///
/// Example usage:
/// ```dart
/// class MyNotifier extends ChangeNotifier with SafeNotifierMixin {
///   void updateData() {
///     // This is safe to call even after disposal
///     notifyListeners();
///   }
/// }
/// ```
/// {@endtemplate}
mixin SafeNotifierMixin on ChangeNotifier implements Disposable {
  bool _disposed = false;

  /// {@macro safe_notifier_mixin}
  @override
  bool get disposed => _disposed;

  @override
  @mustCallSuper
  void dispose() {
    _disposed = true;
    super.dispose();
  }

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
}

/// {@template safe_change_notifier}
/// A safe drop-in replacement for Flutter's `ChangeNotifier` that makes
/// `notifyListeners()` a no-op, rather than an error, after its disposal.
///
/// This class combines [ChangeNotifier] with [SafeNotifierMixin] to provide a
/// robust foundation for state management that prevents common
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
class SafeChangeNotifier() extends ChangeNotifier with SafeNotifierMixin;
