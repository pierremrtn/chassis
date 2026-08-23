import 'package:chassis_flutter/chassis_flutter.dart';

import 'package:todo_app/application/todo_handlers.dart';
import 'package:todo_app/domain/todo.dart';

class const TodoState({
  // Async<T> represents an asynchronous value as loading / data / error,
  // so the UI always knows which of the three states to render.
  required final Async<List<Todo>> todos,
}) {
  TodoState copyWith({Async<List<Todo>>? todos}) {
    return TodoState(todos: todos ?? this.todos);
  }

  static TodoState initial() => const TodoState(todos: Async.loading());
}

sealed class TodoEvent {}

final class const TodoAdded() implements TodoEvent;

final class const TodoOpFailed(
  // The error OBJECT, never error.toString(): listeners can still
  // pattern-match on the error type to choose their reaction.
  final Object error,
) implements TodoEvent;

class TodoViewModel extends ViewModel<TodoState, TodoEvent> {
  TodoViewModel({super.mediator}) : super(TodoState.initial()) {
    // Start watching the todo list immediately.
    watch(
      WatchTodosQuery(),
      onState: (todos) => setState(state.copyWith(todos: todos)),
    );
  }

  void addTodo(String title) => run(
    AddTodoCommand(title: title),
    onSuccess: (_) => sendEvent(const TodoAdded()),
    onError: (error, stack) => sendEvent(TodoOpFailed(error)),
  );

  void toggleTodo(String id) => run(
    ToggleTodoCommand(id: id),
    onError: (error, stack) => sendEvent(TodoOpFailed(error)),
  );
}
