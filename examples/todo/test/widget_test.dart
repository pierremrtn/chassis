import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_app/infrastructure/in_memory_todo_repository.dart';
import 'package:todo_app/mediator.dart';
import 'package:todo_app/presentation/todo_screen.dart';

void main() {
  late InMemoryTodoRepository repository;

  setUp(() {
    // A fresh mediator per test: the real generated AppMediator wired to a
    // real in-memory repository — the same composition as main.dart.
    repository = InMemoryTodoRepository();
    Chassis.initialize(AppMediator(todoRepository: repository));
  });

  tearDown(() {
    Chassis.reset();
    repository.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: TodoScreen()));
    // Let the repository deliver its initial snapshot.
    await tester.pump();
  }

  testWidgets('adding a todo through the UI shows it in the list', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('No todos yet. Add one above!'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.tap(find.text('Add'));
    await tester.pump();

    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Todo added'), findsOneWidget); // snackbar

    // Drain the snackbar timer so the test ends without pending timers.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('tapping the checkbox toggles a todo', (tester) async {
    await repository.addTodo('Buy milk');
    await pumpApp(tester);

    Checkbox checkbox() => tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox().value, isFalse);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(checkbox().value, isTrue);
  });
}
