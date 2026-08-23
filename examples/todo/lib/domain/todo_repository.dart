import 'package:todo_app/domain/todo.dart';

abstract interface class TodoRepository {
  Stream<List<Todo>> watchTodos();
  Future<void> addTodo(String title);
  Future<void> toggleTodo(String id);
}
