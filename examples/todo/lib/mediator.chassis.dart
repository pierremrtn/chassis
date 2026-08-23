// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: implementation_imports

// **************************************************************************
// ChassisGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:chassis/chassis.dart' as _i1;
import 'package:todo_app/domain/todo_repository.dart' as _i2;
import 'package:todo_app/application/todo_handlers.dart' as _i3;

/// Concrete mediator generated from the `@ChassisApp` library
/// `package:todo_app/mediator.dart`.
///
/// Registers every reachable handler in its constructor. Dispatch messages
/// through the inherited `run`/`read`/`watch`; middlewares always apply.
class AppMediator extends _i1.Mediator {
  AppMediator({required _i2.TodoRepository todoRepository}) {
    registerCommandHandler(_i3.AddTodoHandler(repository: todoRepository));
    registerCommandHandler(_i3.ToggleTodoHandler(repository: todoRepository));
    registerQueryHandler(_i3.WatchTodosHandler(repository: todoRepository));
  }
}
