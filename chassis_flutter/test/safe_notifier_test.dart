import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class TestNotifier extends SafeChangeNotifier {
  void notify() => notifyListeners();
}

void main() {
  group('SafeChangeNotifier', () {
    test('notifies listeners while alive', () {
      final notifier = TestNotifier();
      var count = 0;
      notifier.addListener(() => count++);

      notifier.notify();
      expect(count, 1);
    });

    test('notifyListeners after dispose is a no-op, not an error', () {
      final notifier = TestNotifier();
      var count = 0;
      notifier.addListener(() => count++);
      notifier.dispose();

      expect(notifier.disposed, isTrue);
      expect(notifier.notify, returnsNormally);
      expect(count, 0);
    });

    test('addListener after dispose is a no-op', () {
      final notifier = TestNotifier();
      notifier.dispose();
      expect(() => notifier.addListener(() {}), returnsNormally);
    });

    test('removeListener after dispose is a no-op', () {
      final notifier = TestNotifier();
      void listener() {}
      notifier.addListener(listener);
      notifier.dispose();
      expect(() => notifier.removeListener(listener), returnsNormally);
    });
  });
}
