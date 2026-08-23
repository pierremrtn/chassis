// Fixtures for `chassis_visible_error_path` (E1).
//
// run()/read() on a ViewModel must include onState or onError among their
// named arguments; onSuccess alone (or no callbacks) leaves failures
// invisible. watch() is NOT covered by this rule.

// ignore_for_file: unnecessary_this

import 'package:chassis_flutter/chassis_flutter.dart';

import 'messages.dart';

class E1ViewModel extends ViewModel<int, Object> {
  E1ViewModel() : super(0);

  // BAD: onSuccess alone — the error path is invisible.
  void saveWithSuccessOnly() =>
      // expect_lint: chassis_visible_error_path
      run(SaveTodo('a'), onSuccess: (_) => setState(state + 1));

  // BAD: no callbacks at all.
  void saveWithNothing() =>
      // expect_lint: chassis_visible_error_path
      run(SaveTodo('b'));

  // BAD: read() has the same contract as run().
  void loadWithSuccessOnly() =>
      // expect_lint: chassis_visible_error_path
      read(LoadTodos(), onSuccess: (_) => setState(state + 1));

  // GOOD: onState fires for every transition, including errors.
  void saveWithOnState() =>
      run(SaveTodo('c'), onState: (_) => setState(state + 1));

  // GOOD: onError on top of onSuccess makes failures visible.
  void saveWithOnError() => run(
        SaveTodo('d'),
        onSuccess: (_) => setState(state + 1),
        onError: (error, stack) => sendEvent(error),
      );

  // GOOD: read() with onState.
  void loadWithOnState() =>
      read(LoadTodos(), onState: (_) => setState(state + 1));

  // GOOD: watch() is not this rule's business (it has its own assert).
  void watchWithDataOnly() =>
      watch(WatchTodos(), onData: (_) => setState(state + 1));
}

class E1SubViewModel extends E1ViewModel {
  // BAD: an explicit-target dispatch is checked too.
  void saveViaThis() =>
      // expect_lint: chassis_visible_error_path
      this.run(SaveTodo('e'), onSuccess: (_) => setState(state + 1));
}

// GOOD: an unrelated `run` method is not ViewModel.run.
class NotAViewModel {
  void run(String command, {void Function(String value)? onSuccess}) {}

  void call() => run('x', onSuccess: (_) {});
}
