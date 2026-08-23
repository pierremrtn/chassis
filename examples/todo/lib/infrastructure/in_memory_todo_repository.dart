import 'dart:async';

import 'package:todo_app/domain/todo.dart';
import 'package:todo_app/domain/todo_repository.dart';

class InMemoryTodoRepository implements TodoRepository {
  final _controller = StreamController<List<Todo>>.broadcast();
  final List<Todo> _todos = [];
  int _nextId = 0;

  @override
  Stream<List<Todo>> watchTodos() async* {
    // A broadcast stream drops emissions made before a listener subscribes,
    // so each subscriber first gets a snapshot of the current list, then the
    // live updates.
    yield List.unmodifiable(_todos);
    yield* _controller.stream;
  }

  @override
  Future<void> addTodo(String title) async {
    final todo = Todo(
      id: (_nextId++).toString(),
      title: title,
      isCompleted: false,
    );
    _todos.add(todo);
    _controller.add(List.unmodifiable(_todos));
  }

  @override
  Future<void> toggleTodo(String id) async {
    final index = _todos.indexWhere((t) => t.id == id);
    if (index != -1) {
      _todos[index] = _todos[index].copyWith(
        isCompleted: !_todos[index].isCompleted,
      );
      _controller.add(List.unmodifiable(_todos));
    }
  }

  void dispose() {
    _controller.close();
  }
}
