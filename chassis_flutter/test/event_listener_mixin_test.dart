import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class TestEvent {}

final class PingEvent implements TestEvent {}

class TestViewModel extends ViewModel<int, TestEvent> {
  TestViewModel() : super(0);

  void ping() => sendEvent(PingEvent());
}

class const ListenerScreen({
  super.key,
  required final void Function(TestEvent event) onEventReceived,
}) extends StatefulWidget {
  @override
  State<ListenerScreen> createState() => _ListenerScreenState();
}

class _ListenerScreenState extends State<ListenerScreen>
    with EventListenerMixin {
  @override
  void initState() {
    super.initState();
    onEvent<TestViewModel, TestEvent>(widget.onEventReceived);
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  group('EventListenerMixin', () {
    testWidgets('receives view model events', (tester) async {
      final received = <TestEvent>[];
      late TestViewModel vm;

      await tester.pumpWidget(
        MaterialApp(
          home: ViewModelProvider(
            lazy: false,
            create: (_) => vm = TestViewModel(),
            child: ListenerScreen(onEventReceived: received.add),
          ),
        ),
      );

      vm.ping();
      await tester.pump();

      expect(received.single, isA<PingEvent>());
    });

    testWidgets('stops listening after unmount', (tester) async {
      final received = <TestEvent>[];
      final vm = TestViewModel();

      await tester.pumpWidget(
        MaterialApp(
          home: ViewModelProvider.value(
            value: vm,
            child: ListenerScreen(onEventReceived: received.add),
          ),
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      vm.ping();
      await tester.pump();

      expect(received, isEmpty);
      vm.dispose();
    });

    testWidgets(
      're-registering after a provider swap cancels the stale subscription',
      (tester) async {
        final received = <TestEvent>[];
        final first = TestViewModel();
        final second = TestViewModel();

        Widget app(TestViewModel vm) => MaterialApp(
          home: ViewModelProvider.value(
            value: vm,
            child: _ResubscribingScreen(
              viewModel: vm,
              onEventReceived: received.add,
            ),
          ),
        );

        await tester.pumpWidget(app(first));
        await tester.pumpWidget(app(second));

        first.ping();
        await tester.pump();
        expect(
          received,
          isEmpty,
          reason: 'the stale subscription must have been cancelled',
        );

        second.ping();
        await tester.pump();
        expect(received.single, isA<PingEvent>());

        first.dispose();
        second.dispose();
      },
    );

    testWidgets('registering twice for the same view model type throws', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ViewModelProvider(
            lazy: false,
            create: (_) => TestViewModel(),
            child: const _DoubleListenerScreen(),
          ),
        ),
      );

      expect(tester.takeException(), isA<StateError>());
    });
  });
}

class const _DoubleListenerScreen() extends StatefulWidget {
  @override
  State<_DoubleListenerScreen> createState() => _DoubleListenerScreenState();
}

class _DoubleListenerScreenState extends State<_DoubleListenerScreen>
    with EventListenerMixin {
  @override
  void initState() {
    super.initState();
    onEvent<TestViewModel, TestEvent>((_) {});
    onEvent<TestViewModel, TestEvent>((_) {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// Registers on init and re-registers when the provided instance swaps, as a
/// screen kept alive across a provider recreation would.
class const _ResubscribingScreen({
  required final TestViewModel viewModel,
  required final void Function(TestEvent event) onEventReceived,
}) extends StatefulWidget {
  @override
  State<_ResubscribingScreen> createState() => _ResubscribingScreenState();
}

class _ResubscribingScreenState extends State<_ResubscribingScreen>
    with EventListenerMixin {
  @override
  void initState() {
    super.initState();
    onEvent<TestViewModel, TestEvent>(widget.onEventReceived);
  }

  @override
  void didUpdateWidget(_ResubscribingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.viewModel, widget.viewModel)) {
      onEvent<TestViewModel, TestEvent>(widget.onEventReceived);
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
