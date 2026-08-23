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

    test('addListener after dispose throws in debug: ChangeNotifier.dispose '
        'really ran', () {
      final notifier = TestNotifier();
      notifier.dispose();
      // Only notifying is made safe. Adding a listener to a disposed
      // notifier is a real bug, and Flutter's own debug assert must stay
      // armed — it fires only if the dispose chain reached
      // ChangeNotifier.dispose (regression test: the chain used to stop at
      // a pure-Dart mixin, silently disarming every use-after-dispose
      // assert and leak tracking).
      expect(() => notifier.addListener(() {}), throwsFlutterError);
    });

    test('removeListener after dispose is allowed, as in plain Flutter', () {
      final notifier = TestNotifier();
      void listener() {}
      notifier.addListener(listener);
      notifier.dispose();
      expect(() => notifier.removeListener(listener), returnsNormally);
    });
  });
}
