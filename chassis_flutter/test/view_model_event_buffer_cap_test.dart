// Pins the documented bound of the pre-subscription event buffer: events sent
// before the first `events` listener are buffered up to 128; in debug mode the
// 129th trips an assertion pointing at the unbounded-emission bug.
//
// (The release-mode drop-oldest behavior behind the same cap is not testable
// under `flutter test`, which always runs with asserts enabled.)
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _BufferViewModel extends ViewModel<int, int> {
  _BufferViewModel() : super(0);

  void emit(int event) => sendEvent(event);
}

void main() {
  group('ViewModel pre-subscription event buffer', () {
    test('buffers exactly 128 events; the 129th asserts in debug', () async {
      final vm = _BufferViewModel();

      // 128 events buffer without complaint...
      for (var i = 0; i < 128; i++) {
        vm.emit(i);
      }

      // ...and the 129th trips the debug assertion: the cap is 128.
      expect(() => vm.emit(128), throwsA(isA<AssertionError>()));

      // The first subscriber replays the full buffer, in order.
      final received = <int>[];
      vm.events.listen(received.add);
      await pumpEventQueue();

      expect(received, hasLength(128));
      expect(received.first, 0);
      expect(received.last, 127);
    });

    test('the cap applies only before the first subscription', () async {
      final vm = _BufferViewModel();
      final received = <int>[];
      vm.events.listen(received.add);
      await pumpEventQueue();

      // Once subscribed, emission is unbounded broadcast delivery.
      for (var i = 0; i < 200; i++) {
        vm.emit(i);
      }
      await pumpEventQueue();

      expect(received, hasLength(200));
    });
  });
}
