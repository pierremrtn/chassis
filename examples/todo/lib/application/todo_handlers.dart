import 'package:chassis/chassis.dart';

import 'package:todo_app/domain/todo.dart';
import 'package:todo_app/domain/todo_repository.dart';

// Query to reactively watch the todo list
final class WatchTodosQuery() extends WatchQuery<List<Todo>>;

@chassisHandler // Marks this handler for wiring by chassis_builder
class WatchTodosHandler({required final TodoRepository repository})
    implements WatchHandler<WatchTodosQuery, List<Todo>> {
  @override
  Stream<List<Todo>> watch(WatchTodosQuery query) => repository.watchTodos();
}

// Command to add a new todo
final class AddTodoCommand({required final String title})
    extends Command<void> {
  @override
  Map<String, Object?> get params => {'title': title};
}

@chassisHandler
class AddTodoHandler({required final TodoRepository repository})
    implements CommandHandler<AddTodoCommand, void> {
  @override
  Future<void> run(AddTodoCommand command) => repository.addTodo(command.title);
}

// Command to toggle a todo's completion status
final class ToggleTodoCommand({required final String id})
    extends Command<void> {
  @override
  Map<String, Object?> get params => {'id': id};
}

@chassisHandler
class ToggleTodoHandler({required final TodoRepository repository})
    implements CommandHandler<ToggleTodoCommand, void> {
  @override
  Future<void> run(ToggleTodoCommand command) =>
      repository.toggleTodo(command.id);
}
