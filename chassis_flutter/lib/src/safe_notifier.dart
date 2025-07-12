/// Classes taken from ubuntu's safe_change_notifier package https://github.com/canonical/ubuntu-flutter-plugins/blob/main/packages/safe_change_notifier/lib/src/change_notifier.dart
/// And adapted to uses [Disposable]
library;

import 'package:chassis/chassis.dart';
import 'package:flutter/foundation.dart';

/// A safe mixin for Flutter's `ChangeNotifier` and `ValueNotifier` that makes
/// `notifyListeners()` a no-op, rather than an error, after disposal.
///
/// ![safe_change_notifier](https://github.com/canonical/ubuntu-flutter-plugins/raw/main/packages/safe_change_notifier/images/safe_change_notifier.png)
mixin SafeNotifierMixin on ChangeNotifier implements Disposable {
  @override
  bool get hasListeners => !disposed && super.hasListeners;

  @override
  void notifyListeners() {
    if (!disposed) {
      super.notifyListeners();
    }
  }

  @override
  void addListener(VoidCallback listener) {
    if (!disposed) {
      super.addListener(listener);
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    if (!disposed) {
      super.removeListener(listener);
    }
  }
}

/// A safe drop-in replacement for Flutter's `ChangeNotifier` that makes
/// `notifyListeners()` a no-op, rather than an error, after its disposal.
///
/// ![safe_change_notifier](https://github.com/canonical/ubuntu-flutter-plugins/raw/main/packages/safe_change_notifier/images/safe_change_notifier.png)
class SafeChangeNotifier extends ChangeNotifier
    with Disposable, SafeNotifierMixin {}
