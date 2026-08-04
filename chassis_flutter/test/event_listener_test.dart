import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class TestEvent {}

final class PingEvent implements TestEvent {}

final class GreetEvent implements TestEvent {
  GreetEvent(this.message);

  final String message;
}

class TestViewModel extends ViewModel<int, TestEvent> {
  TestViewModel({bool pingOnCreate = false}) : super(0) {
    if (pingOnCreate) ping();
  }

  void ping() => sendEvent(PingEvent());

  void greet(String message) => sendEvent(GreetEvent(message));

  void bump(int value) => setState(value);
}

void main() {
  group('EventListener', () {
    testWidgets('invokes onEvent for each emitted event', (tester) async {
      final received = <TestEvent>[];
      late TestViewModel vm;

      await tester.pumpWidget(MaterialApp(
        home: ViewModelProvider(
          create: (_) => vm = TestViewModel(),
          child: EventListener<TestViewModel, TestEvent>(
            onEvent: (context, event) => received.add(event),
            child: const SizedBox(),
          ),
        ),
      ));

      vm.ping();
      vm.greet('hello');
      await tester.pump();

      expect(received, [isA<PingEvent>(), isA<GreetEvent>()]);
    });

    testWidgets('receives events emitted during view model construction',
        (tester) async {
      final received = <TestEvent>[];

      await tester.pumpWidget(MaterialApp(
        home: ViewModelProvider(
          create: (_) => TestViewModel(pingOnCreate: true),
          child: EventListener<TestViewModel, TestEvent>(
            onEvent: (context, event) => received.add(event),
            child: const SizedBox(),
          ),
        ),
      ));
      await tester.pump();

      expect(received.single, isA<PingEvent>());
    });

    testWidgets('callback context resolves the emitting view model',
        (tester) async {
      late TestViewModel vm;
      TestViewModel? resolved;

      await tester.pumpWidget(MaterialApp(
        home: ViewModelProvider(
          create: (_) => vm = TestViewModel(),
          child: EventListener<TestViewModel, TestEvent>(
            onEvent: (context, event) =>
                resolved = context.read<TestViewModel>(),
            child: const SizedBox(),
          ),
        ),
      ));

      vm.ping();
      await tester.pump();

      expect(identical(resolved, vm), isTrue);
    });

    testWidgets('resubscribes when the provider swaps the instance',
        (tester) async {
      final received = <TestEvent>[];
      final first = TestViewModel();
      final second = TestViewModel();

      Widget app(TestViewModel vm) => MaterialApp(
            home: ViewModelProvider.value(
              value: vm,
              child: EventListener<TestViewModel, TestEvent>(
                onEvent: (context, event) => received.add(event),
                child: const SizedBox(),
              ),
            ),
          );

      await tester.pumpWidget(app(first));
      await tester.pumpWidget(app(second));

      first.ping();
      await tester.pump();
      expect(received, isEmpty,
          reason: 'the replaced instance must no longer be listened to');

      second.ping();
      await tester.pump();
      expect(received.single, isA<PingEvent>());

      first.dispose();
      second.dispose();
    });

    testWidgets('stops listening after unmount', (tester) async {
      final received = <TestEvent>[];
      final vm = TestViewModel();

      await tester.pumpWidget(MaterialApp(
        home: ViewModelProvider.value(
          value: vm,
          child: EventListener<TestViewModel, TestEvent>(
            onEvent: (context, event) => received.add(event),
            child: const SizedBox(),
          ),
        ),
      ));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      vm.ping();
      await tester.pump();

      expect(received, isEmpty);
      vm.dispose();
    });

    testWidgets('state changes do not rebuild the child', (tester) async {
      var childBuilds = 0;
      late TestViewModel vm;

      await tester.pumpWidget(MaterialApp(
        home: ViewModelProvider(
          create: (_) => vm = TestViewModel(),
          child: EventListener<TestViewModel, TestEvent>(
            onEvent: (context, event) {},
            child: Builder(builder: (context) {
              childBuilds++;
              return const SizedBox();
            }),
          ),
        ),
      ));

      expect(childBuilds, 1);
      vm.bump(41);
      await tester.pump();
      expect(childBuilds, 1,
          reason: 'the listener passes its child through untouched');
    });

    testWidgets('state changes do not rebuild the listener itself',
        (tester) async {
      late TestViewModel vm;

      await tester.pumpWidget(MaterialApp(
        home: ViewModelProvider(
          create: (_) => vm = TestViewModel(),
          child: EventListener<TestViewModel, TestEvent>(
            onEvent: (context, event) {},
            child: const SizedBox(),
          ),
        ),
      ));

      final rebuilt = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => rebuilt.add(message ?? '');
      debugPrintRebuildDirtyWidgets = true;
      try {
        vm.bump(41);
        await tester.pump();
      } finally {
        debugPrintRebuildDirtyWidgets = false;
        debugPrint = previousDebugPrint;
      }

      expect(
        rebuilt.where((line) => line.contains('EventListener')),
        isEmpty,
        reason: 'state notifications must not rebuild the passive listener',
      );
    });
  });
}
