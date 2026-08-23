import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

import 'package:todo_app/domain/todo.dart';
import 'package:todo_app/presentation/todo_view_model.dart';

class const TodoScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Todo List')),
      // The provider sits below the Scaffold: the ViewModel lives exactly as
      // long as this screen, and event side-effects stay next to the UI they
      // affect instead of leaking into main.dart.
      body: ViewModelProvider.withEventListener<TodoViewModel, TodoEvent>(
        create: (_) => TodoViewModel(),
        onEvent: (context, viewModel, event) {
          switch (event) {
            case TodoAdded():
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Todo added')));
            case TodoOpFailed():
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Something went wrong')),
              );
          }
        },
        child: const Column(
          children: [
            _TodoComposer(),
            Expanded(child: _TodoList()),
          ],
        ),
      ),
    );
  }
}

// Stateful only because it owns the TextEditingController. It never watches
// the ViewModel, so it doesn't rebuild when the todo list changes.
class const _TodoComposer() extends StatefulWidget {
  @override
  State<_TodoComposer> createState() => _TodoComposerState();
}

class _TodoComposerState extends State<_TodoComposer> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _textController.text.trim();
    if (title.isEmpty) return;
    context.read<TodoViewModel>().addTodo(title);
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: const InputDecoration(
                hintText: 'Enter todo title',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _submit, child: const Text('Add')),
        ],
      ),
    );
  }
}

class const _TodoList() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // select subscribes this widget to just the field it renders; when the
    // todo list changes, only _TodoList rebuilds — not the whole screen.
    final asyncTodos = context.select((TodoViewModel vm) => vm.state.todos);

    // Async<T> is sealed, so a switch expression covers loading, error, and
    // data exhaustively — the compiler rejects a missing case.
    return switch (asyncTodos) {
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError(:final error) => Center(child: Text('Error: $error')),
      AsyncData(value: final todos) when todos.isEmpty => const Center(
        child: Text('No todos yet. Add one above!'),
      ),
      AsyncData(value: final todos) => ListView.builder(
        itemCount: todos.length,
        itemBuilder: (context, index) => _TodoTile(todo: todos[index]),
      ),
    };
  }
}

class const _TodoTile({required final Todo todo}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Checkbox(
        value: todo.isCompleted,
        // Callbacks use context.read to call methods without subscribing.
        onChanged: (_) => context.read<TodoViewModel>().toggleTodo(todo.id),
      ),
      title: Text(
        todo.title,
        style: TextStyle(
          decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}
