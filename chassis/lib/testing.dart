/// Test-only helpers for chassis. Import this library from test files only:
///
/// ```dart
/// import 'package:chassis/testing.dart';
/// ```
///
/// The centerpiece is [TestMediator]: a [Mediator] with closure-based stub
/// registration (`whenRun` / `whenRead` / `whenWatch`) and a record of every
/// dispatched message ([TestMediator.dispatchedCommands],
/// [TestMediator.dispatchedQueries]).
///
/// The seam is the ViewModel constructor — the `mediator:` override always
/// wins over the application mediator installed by `Chassis.initialize`:
///
/// ```dart
/// final mediator = TestMediator()
///   ..whenRun<AddTodoCommand, Todo>((cmd) async => Todo(title: cmd.title))
///   ..whenWatch<WatchTodosQuery, List<Todo>>((q) => controller.stream);
///
/// final vm = TodoViewModel(mediator: mediator);
/// ```
///
/// **Never call `Chassis.initialize` in tests.** It is process-global state
/// that leaks across test cases; the constructor seam exists so tests never
/// touch it. Create one [TestMediator] per test.
///
/// This library is pure Dart and depends on no test framework — but it is
/// test infrastructure, so it is deliberately not exported from
/// `package:chassis/chassis.dart`.
library;

import 'package:chassis/chassis.dart';
import 'package:chassis/src/testing/test_mediator.dart';

export 'src/testing/test_mediator.dart';
