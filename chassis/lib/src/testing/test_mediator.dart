import 'dart:async';

import '../mediator/command.dart';
import '../mediator/dispatch_context.dart';
import '../mediator/errors.dart';
import '../mediator/mediator.dart';
import '../mediator/query.dart';

/// A [Mediator] for tests: closure-based stubs instead of handler classes,
/// plus a record of every dispatched message.
///
/// Production code registers one handler *class* per message. In a test that
/// ceremony is friction — what the test wants is "when this message is
/// dispatched, answer that". [whenRun], [whenRead], and [whenWatch] register
/// a closure as the handler for one concrete message type:
///
/// ```dart
/// final mediator = TestMediator()
///   ..whenRun<AddTodoCommand, Todo>((cmd) async => Todo(title: cmd.title))
///   ..whenRead<GetUserQuery, User>((q) async => testUser)
///   ..whenWatch<WatchTodosQuery, List<Todo>>((q) => controller.stream);
///
/// final vm = TodoViewModel(mediator: mediator);
/// ```
///
/// **Failure stubbing needs no dedicated API** — the closure throws, and the
/// error propagates exactly like a failing production handler (a ViewModel
/// reports it as a soft `AsyncError` through its callbacks):
///
/// ```dart
/// mediator.whenRun<AddTodoCommand, Todo>(
///   (cmd) async => throw TodoLimitReachedException(),
/// );
/// ```
///
/// **The production registration guards apply unchanged.** Each `when*` call
/// registers through the inherited [Mediator] registration methods, so a
/// second stub for the same message type throws [DuplicateHandlerError], and
/// a stub keyed by an abstract message type (`whenRun` called without type
/// arguments and without an annotated closure parameter, so inference falls
/// back to `Command<R>`) throws [ArgumentError]. Give inference the concrete
/// type: `whenRun<AddTodoCommand, Todo>(...)` or
/// `whenRun((AddTodoCommand cmd) async => ...)`.
///
/// **Every dispatch is recorded** — before it is routed, so failed and
/// unhandled dispatches are recorded too. [dispatchedCommands] and
/// [dispatchedQueries] hold the message objects in dispatch order, and
/// messages have structural equality (same type + equal `params`), so
/// assertions compare against freshly constructed messages:
///
/// ```dart
/// expect(mediator.dispatchedCommands, contains(AddTodoCommand('milk')));
/// expect(mediator.dispatchedQueries, [GetUserQuery('u1')]);
/// ```
///
/// There is no reset: create one `TestMediator` per test.
class TestMediator extends Mediator {
  final List<Command<Object?>> _dispatchedCommands = [];
  final List<Query<Object?>> _dispatchedQueries = [];

  /// Every [Command] dispatched through [run], in dispatch order.
  ///
  /// Messages have structural equality, so assert with equal instances:
  /// `expect(mediator.dispatchedCommands, contains(AddTodoCommand('milk')))`.
  List<Command<Object?>> get dispatchedCommands =>
      List.unmodifiable(_dispatchedCommands);

  /// Every [Query] dispatched through [read] or [watch], in dispatch order.
  ///
  /// A watch query is recorded when the query is dispatched (the stream is
  /// requested), not per emission.
  List<Query<Object?>> get dispatchedQueries =>
      List.unmodifiable(_dispatchedQueries);

  /// Stubs the handler for commands of concrete type [C]: dispatching a [C]
  /// through [run] answers with `handler(command)`.
  ///
  /// A throwing closure stubs a failure. Registration guards apply: a second
  /// stub for [C] throws [DuplicateHandlerError]; an abstract [C] throws
  /// [ArgumentError].
  void whenRun<C extends Command<R>, R>(Future<R> Function(C command) handler) {
    registerCommandHandler(_StubCommandHandler<C, R>(handler));
  }

  /// Stubs the handler for read queries of concrete type [Q]: dispatching a
  /// [Q] through [read] answers with `handler(query)`.
  ///
  /// A throwing closure stubs a failure. Registration guards apply: a second
  /// stub for [Q] throws [DuplicateHandlerError]; an abstract [Q] throws
  /// [ArgumentError].
  void whenRead<Q extends ReadQuery<R>, R>(
    Future<R> Function(Q query) handler,
  ) {
    registerQueryHandler(_StubReadHandler<Q, R>(handler));
  }

  /// Stubs the handler for watch queries of concrete type [Q]: dispatching a
  /// [Q] through [watch] answers with `handler(query)` — typically a
  /// `StreamController`'s stream the test feeds emissions into.
  ///
  /// A throwing closure stubs a failure. Registration guards apply: a second
  /// stub for [Q] throws [DuplicateHandlerError]; an abstract [Q] throws
  /// [ArgumentError].
  void whenWatch<Q extends WatchQuery<R>, R>(
    Stream<R> Function(Q query) handler,
  ) {
    registerQueryHandler(_StubWatchHandler<Q, R>(handler));
  }

  @override
  Future<T> run<T>(Command<T> command, {DispatchContext? context}) {
    _dispatchedCommands.add(command);
    return super.run(command, context: context);
  }

  @override
  Future<T> read<T>(ReadQuery<T> query, {DispatchContext? context}) {
    _dispatchedQueries.add(query);
    return super.read(query, context: context);
  }

  @override
  Stream<T> watch<T>(WatchQuery<T> query, {DispatchContext? context}) {
    _dispatchedQueries.add(query);
    return super.watch(query, context: context);
  }
}

/// Wraps a closure as a [CommandHandler] for [TestMediator.whenRun].
class _StubCommandHandler<C extends Command<R>, R>(
  final Future<R> Function(C command) _handler,
) implements CommandHandler<C, R> {
  @override
  Future<R> run(C command) => _handler(command);
}

/// Wraps a closure as a [ReadHandler] for [TestMediator.whenRead].
class _StubReadHandler<Q extends ReadQuery<R>, R>(
  final Future<R> Function(Q query) _handler,
) implements ReadHandler<Q, R> {
  @override
  Future<R> read(Q query) => _handler(query);
}

/// Wraps a closure as a [WatchHandler] for [TestMediator.whenWatch].
class _StubWatchHandler<Q extends WatchQuery<R>, R>(
  final Stream<R> Function(Q query) _handler,
) implements WatchHandler<Q, R> {
  @override
  Stream<R> watch(Q query) => _handler(query);
}
