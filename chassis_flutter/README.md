# chassis_flutter

Flutter UI integration for the [Chassis](https://pub.dev/packages/chassis) framework. This package provides ViewModel base classes, reactive widgets, and presentation layer utilities following the MVVM pattern.

## Overview

The `chassis_flutter` package connects business logic from the `chassis` core package to the Flutter widget tree. It provides:

* **ViewModel** - State management and command/query dispatch
* **AsyncBuilder** - Renders `Async<T>` states with anti-flickering
* **ViewModelProvider** - Dependency injection using `provider`
* **ConsumerMixin** - One-time event handling with automatic cleanup

## Core Components

### ViewModel

Bridges UI and business logic by holding state and dispatching operations through the Mediator:

```dart
class UserProfileState {
  const UserProfileState({required this.user});
  final Async<User> user;

  UserProfileState copyWith({Async<User>? user}) {
    return UserProfileState(user: user ?? this.user);
  }

  static UserProfileState initial() {
    return UserProfileState(user: Async.loading());
  }
}

sealed class UserProfileEvent {}
class UserUpdatedEvent implements UserProfileEvent {}

class UserProfileViewModel extends ViewModel<UserProfileState, UserProfileEvent> {
  UserProfileViewModel(Mediator mediator)
      : super(mediator, initial: UserProfileState.initial());

  void loadUser(String userId) {
    watch(
      mediator.watchUser(userId: userId),
      onState: (asyncUser) {
        setState(state.copyWith(user: asyncUser));
      },
    );
  }

  void updateEmail(String userId, String newEmail) {
    run(
      mediator.updateUserEmail(userId: userId, newEmail: newEmail),
      onData: (_) => sendEvent(UserUpdatedEvent()),
    );
  }
}
```

### AsyncBuilder

Renders `Async<T>` states with custom loading, error, and data builders:

```dart
AsyncBuilder<User>(
  state: viewModel.state.user,
  builder: (context, user) {
    return Column(
      children: [
        CircleAvatar(backgroundImage: NetworkImage(user.avatarUrl)),
        Text(user.name),
        Text(user.email),
      ],
    );
  },
  loadingBuilder: (context) => CircularProgressIndicator(),
  errorBuilder: (context, error) => Text('Error: $error'),
  maintainState: true, // Show previous data during refetch (anti-flickering)
)
```

**Parameters:**

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `state` | `Async<T>` | The async state to render | Required |
| `builder` | `Widget Function(BuildContext, T)` | Renders when data is available | Required |
| `loadingBuilder` | `WidgetBuilder?` | Renders during loading | `CircularProgressIndicator` |
| `errorBuilder` | `Widget Function(BuildContext, Object)?` | Renders on error | `SizedBox.shrink()` |
| `maintainState` | `bool` | Show previous data during refetch | `true` |

### ViewModelProvider

Provides ViewModels to the widget tree using the `provider` package:

```dart
ViewModelProvider<UserProfileViewModel>(
  create: (context) => UserProfileViewModel(mediator),
  child: UserProfileScreen(),
)
```

Access ViewModel in widgets:

```dart
// Rebuild when state changes
final viewModel = context.watch<UserProfileViewModel>();

// Access without rebuilding
final viewModel = context.read<UserProfileViewModel>();
```

### Listening to events

Handle one-time events from a ViewModel via `ViewModelProvider.withEvents`, which wires up the subscription at the point of provision and cleans it up automatically:

```dart
ViewModelProvider.withEvents<UserProfileViewModel, UserProfileEvent>(
  create: (_) => UserProfileViewModel(mediator),
  onEvent: (context, viewModel, event) {
    switch (event) {
      case UserUpdatedEvent():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile updated')),
        );
    }
  },
  child: UserProfileScreen(),
);
```

The `context` passed to `onEvent` sits *above* the provided ViewModel in the tree, so `ScaffoldMessenger.of(context)` and `Navigator.of(context)` work as expected. Use the `viewModel` argument instead of `context.read` when you need the VM itself.

When a descendant widget deep in the subtree needs to listen to a ViewModel provided by an ancestor, use `ConsumerMixin` instead:

```dart
class _UserProfileDetailsState extends State<UserProfileDetails> with ConsumerMixin {
  @override
  void initState() {
    super.initState();
    onEvent<UserProfileViewModel, UserProfileEvent>((event) {
      // React to events from an ancestor-provided VM.
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

## Complete Example

```dart
// Data Model
class Todo {
  const Todo({
    required this.id,
    required this.title,
    required this.isCompleted,
  });

  final String id;
  final String title;
  final bool isCompleted;

  Todo copyWith({String? id, String? title, bool? isCompleted}) {
    return Todo(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

// State
class TodoState {
  const TodoState({required this.todos});
  final Async<List<Todo>> todos;

  TodoState copyWith({Async<List<Todo>>? todos}) {
    return TodoState(todos: todos ?? this.todos);
  }

  static TodoState initial() {
    return TodoState(todos: Async.loading());
  }
}

// Events
sealed class TodoEvent {}
class TodoAddedEvent implements TodoEvent {}

// ViewModel
class TodoViewModel extends ViewModel<TodoState, TodoEvent> {
  TodoViewModel(Mediator mediator) : super(mediator, initial: TodoState.initial());

  void watchTodos() {
    watch(
      mediator.watchTodos(),
      onState: (asyncTodos) {
        setState(state.copyWith(todos: asyncTodos));
      },
    );
  }

  void addTodo(String title) {
    run(
      mediator.addTodo(title: title),
      onData: (_) => sendEvent(TodoAddedEvent()),
    );
  }

  void toggleTodo(String id) {
    run(mediator.toggleTodo(id: id));
  }
}

// Widget
class TodoScreen extends StatefulWidget {
  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<TodoViewModel>().watchTodos();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<TodoViewModel>();

    return Scaffold(
      appBar: AppBar(title: Text('Todo List')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'Enter todo title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final title = _textController.text.trim();
                    if (title.isNotEmpty) {
                      viewModel.addTodo(title);
                    }
                  },
                  child: Text('Add'),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBuilder<List<Todo>>(
              state: viewModel.state.todos,
              builder: (context, todos) {
                if (todos.isEmpty) {
                  return Center(child: Text('No todos yet. Add one above!'));
                }
                return ListView.builder(
                  itemCount: todos.length,
                  itemBuilder: (context, index) {
                    final todo = todos[index];
                    return ListTile(
                      leading: Checkbox(
                        value: todo.isCompleted,
                        onChanged: (_) => viewModel.toggleTodo(todo.id),
                      ),
                      title: Text(
                        todo.title,
                        style: TextStyle(
                          decoration: todo.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// App
void main() {
  final mediator = AppMediator(todoRepository: TodoRepository());

  runApp(MaterialApp(
    home: ViewModelProvider.withEvents<TodoViewModel, TodoEvent>(
      create: (_) => TodoViewModel(mediator),
      onEvent: (context, viewModel, event) {
        if (event is TodoAddedEvent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Todo added')),
          );
        }
      },
      child: TodoScreen(),
    ),
  ));
}
```

## ViewModel Lifecycle Methods

ViewModels provide two methods for handling asynchronous operations:

**watch()** - Subscribe to reactive streams:

```dart
void watchUser(String userId) {
  watch(
    mediator.watchUser(userId: userId),
    onState: (asyncUser) {
      setState(state.copyWith(user: asyncUser));
    },
  );
}
```

**run()** - Execute futures (queries or commands):

```dart
// One-time data fetch
void loadUser(String userId) {
  run(
    mediator.getUser(userId: userId),
    onState: (asyncUser) {
      setState(state.copyWith(user: asyncUser));
    },
  );
}

// Command execution with event handling
void deleteUser(String userId) {
  run(
    mediator.deleteUser(userId: userId),
    onData: (_) => sendEvent(UserDeletedEvent()),
    onError: (error) => sendEvent(DeleteFailedEvent(error.toString())),
  );
}
```

**Callback Options:**

Both methods support three callback patterns:
- `onState: (Async<T>)` - Full lifecycle control for all states
- `onData: (T)` - Success-only callback with unwrapped value
- `onError: (Object)` - Error-only callback

All subscriptions are automatically disposed when the ViewModel is disposed.

## State vs Events

**State** - Persistent data that determines UI rendering:

```dart
class UserListState {
  const UserListState({required this.users});
  final Async<List<User>> users;
}
```

**Events** - One-time notifications for side effects:

```dart
sealed class UserListEvent {}
class UserDeletedEvent implements UserListEvent {}
class UserDeleteFailedEvent implements UserListEvent {
  const UserDeleteFailedEvent(this.message);
  final String message;
}
```

Events handle navigation, dialogs, snackbars—actions that happen once and should not persist in state.

## Testing

### ViewModel Testing

```dart
class MockMediator extends Mock implements Mediator {}

test('loadUser dispatches WatchUserQuery', () {
  final mockMediator = MockMediator();
  final viewModel = UserViewModel(mockMediator);

  when(() => mockMediator.watch(any<WatchUserQuery>()))
      .thenAnswer((_) => Stream.value(User(id: '1', name: 'John')));

  viewModel.loadUser('1');

  verify(() => mockMediator.watch(any<WatchUserQuery>())).called(1);
});
```

### Widget Testing

```dart
class MockUserViewModel extends Mock implements UserViewModel {}

testWidgets('UserScreen displays user from ViewModel', (tester) async {
  final mockViewModel = MockUserViewModel();

  when(() => mockViewModel.state).thenReturn(
    UserState(user: Async.data(User(id: '1', name: 'Alice'))),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Provider<UserViewModel>.value(
        value: mockViewModel,
        child: UserScreen(),
      ),
    ),
  );

  expect(find.text('Alice'), findsOneWidget);
});
```

## Installation

Add to `pubspec.yaml`:

```yaml
dependencies:
  chassis: ^0.0.1
  chassis_flutter: ^0.0.1
  provider: ^6.0.0
```

## Next Steps

* **[Quick Start](../documentation/00_quick_start.md)** - Build a complete application
* **[UI Integration](../documentation/04_ui_integration.md)** - Deep dive into ViewModel and AsyncBuilder
* **[Core Architecture](../documentation/01_core_architecture.md)** - Understand the architectural principles
* **[chassis](../chassis/README.md)** - Core package documentation

## License

MIT License - See [LICENSE](../LICENSE) for details.
