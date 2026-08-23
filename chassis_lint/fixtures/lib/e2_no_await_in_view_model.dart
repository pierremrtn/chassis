// Fixtures for `chassis_no_await_in_view_model` (E2).
//
// ViewModels are await-free: every `await` expression, and every
// `async`/`async*` modifier on an instance method, is flagged inside a
// ViewModel subclass.

import 'package:chassis_flutter/chassis_flutter.dart';

import 'messages.dart';

class E2ViewModel extends ViewModel<int, Object> {
  E2ViewModel() : super(0);

  // BAD: async instance method in a ViewModel (modifier + await).
  // expect_lint: chassis_no_await_in_view_model
  Future<void> refresh() async {
    // expect_lint: chassis_no_await_in_view_model
    await read(LoadTodos(), onState: (_) => setState(state + 1));
  }

  // BAD: the async modifier alone violates the doctrine, even with no await.
  // expect_lint: chassis_no_await_in_view_model
  Future<void> touch() async => setState(state + 1);

  // BAD: an await hidden inside a closure of an instance member.
  void closureAwait() {
    Future<void> job() async {
      // expect_lint: chassis_no_await_in_view_model
      await Future<void>.delayed(Duration.zero);
    }

    job();
  }

  // GOOD: synchronous, expression-bodied dispatch.
  void save() => run(
        SaveTodo('x'),
        onError: (error, stack) => sendEvent(error),
      );

  // GOOD (not flagged): static members are outside the instance doctrine.
  static Future<void> pause() async {
    await Future<void>.delayed(Duration.zero);
  }
}

// GOOD: await outside a ViewModel is none of this rule's business.
class NotAViewModelRepository {
  Future<String> fetch() async {
    await Future<void>.delayed(Duration.zero);
    return 'data';
  }
}
