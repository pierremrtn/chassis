abstract class Command<R> {
  const Command();
}

class CommandHandler<C extends Command<R>, R> {
  const CommandHandler({required CommandHandlerCallback<C, R> run})
      : _callback = run;

  final CommandHandlerCallback<C, R> _callback;

  Future<R> run(C command) {
    return _callback.call(command);
  }
}

typedef CommandHandlerCallback<C extends Command<R>, R> = Future<R> Function(C);
