abstract class Command<R> {}

abstract interface class CommandHandler<C extends Command<R>, R> {
  factory CommandHandler({required CommandHandlerCallback<C, R> run}) =
      _CommandHandlerImpl.new;

  Future<R> run(C command);
}

typedef CommandHandlerCallback<C extends Command<R>, R> = Future<R> Function(C);

class _CommandHandlerImpl<C extends Command<R>, R>
    implements CommandHandler<C, R> {
  const _CommandHandlerImpl({required CommandHandlerCallback<C, R> run})
      : _callback = run;

  final CommandHandlerCallback<C, R> _callback;

  @override
  Future<R> run(C command) {
    return _callback.call(command);
  }
}
