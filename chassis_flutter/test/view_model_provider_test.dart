import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class TestEvent {}

final class CreatedEvent implements TestEvent {}

final class TappedEvent implements TestEvent {}

class TestViewModel extends ViewModel<int, TestEvent> {
  TestViewModel({bool emitOnCreate = false}) : super(0) {
    if (emitOnCreate) sendEvent(CreatedEvent());
  }

  void increment() => setState(state + 1);

  void tap() => sendEvent(TappedEvent());
}

class OtherViewModel extends ViewModel<String, void> {
  OtherViewModel() : super('hello');
}

void main() {
  group('ViewModelProvider', () {
    testWidgets('provides the view model to descendants', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ViewModelProvider(
            create: (_) => TestViewModel(),
            child: Builder(
              builder: (context) => Text(
                'count: ${ViewModelProvider.of<TestViewModel>(context).state}',
              ),
            ),
          ),
        ),
      );

      expect(find.text('count: 0'), findsOneWidget);
    });

    testWidgets('rebuilds dependents when state changes', (tester) async {
      late TestViewModel vm;
      await tester.pumpWidget(
        MaterialApp(
          home: ViewModelProvider(
            create: (_) => vm = TestViewModel(),
            child: Consumer<TestViewModel>(
              builder: (context, viewModel, _) =>
                  Text('count: ${viewModel.state}'),
            ),
          ),
        ),
      );

      vm.increment();
      await tester.pump();

      expect(find.text('count: 1'), findsOneWidget);
    });

    testWidgets('disposes the created view model on unmount', (tester) async {
      late TestViewModel vm;
      await tester.pumpWidget(
        MaterialApp(
          home: ViewModelProvider(
            lazy: false,
            create: (_) => vm = TestViewModel(),
            child: const SizedBox(),
          ),
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      expect(vm.disposed, isTrue);
    });

    testWidgets('.value does not dispose the view model', (tester) async {
      final vm = TestViewModel();
      await tester.pumpWidget(
        MaterialApp(
          home: ViewModelProvider.value(value: vm, child: const SizedBox()),
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      expect(vm.disposed, isFalse);
      vm.dispose();
    });

    testWidgets('of() throws a helpful error when no provider is found', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              expect(
                () => ViewModelProvider.of<TestViewModel>(context),
                throwsA(isA<FlutterError>()),
              );
              return const SizedBox();
            },
          ),
        ),
      );
    });
  });

  group('MultiViewModelProvider', () {
    testWidgets('provides all view models without nesting', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiViewModelProvider(
            providers: [
              ViewModelProvider(create: (_) => TestViewModel()),
              ViewModelProvider(create: (_) => OtherViewModel()),
            ],
            child: Builder(
              builder: (context) => Text(
                '${context.read<TestViewModel>().state}-'
                '${context.read<OtherViewModel>().state}',
              ),
            ),
          ),
        ),
      );

      expect(find.text('0-hello'), findsOneWidget);
    });
  });

  group('ViewModelProvider.withEventListener', () {
    testWidgets('delivers events emitted during construction', (tester) async {
      final received = <TestEvent>[];

      await tester.pumpWidget(
        MaterialApp(
          home: ViewModelProvider.withEventListener<TestViewModel, TestEvent>(
            create: (_) => TestViewModel(emitOnCreate: true),
            onEvent: (context, vm, event) => received.add(event),
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pump();

      expect(received.single, isA<CreatedEvent>());
    });

    testWidgets('delivers events emitted later', (tester) async {
      final received = <TestEvent>[];
      late TestViewModel vm;

      await tester.pumpWidget(
        MaterialApp(
          home: ViewModelProvider.withEventListener<TestViewModel, TestEvent>(
            create: (_) => vm = TestViewModel(),
            onEvent: (context, viewModel, event) => received.add(event),
            child: const SizedBox(),
          ),
        ),
      );

      vm.tap();
      await tester.pump();

      expect(received.single, isA<TappedEvent>());
    });

    testWidgets('stops delivering and disposes on unmount', (tester) async {
      final received = <TestEvent>[];
      late TestViewModel vm;

      await tester.pumpWidget(
        MaterialApp(
          home: ViewModelProvider.withEventListener<TestViewModel, TestEvent>(
            create: (_) => vm = TestViewModel(),
            onEvent: (context, viewModel, event) => received.add(event),
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      expect(vm.disposed, isTrue);
      expect(received, isEmpty);
    });
  });
}
