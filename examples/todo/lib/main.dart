import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

import 'package:todo_app/infrastructure/in_memory_todo_repository.dart';
import 'package:todo_app/mediator.dart';
import 'package:todo_app/presentation/todo_screen.dart';

void main() {
  // The generated constructor is the dependency manifest: it requires
  // exactly the repositories the handlers need.
  Chassis.initialize(
    AppMediator(todoRepository: InMemoryTodoRepository())
      // Traces every dispatch with its params, outcome, and duration.
      ..addMiddleware(LoggingMiddleware()),
  );

  runApp(const MaterialApp(title: 'Todo List', home: TodoScreen()));
}
