/// Abstract base class for commands that can be executed through the mediator.
///
/// Commands represent operations that modify state or perform side effects.
/// They are typically used for write operations, mutations, or actions that
/// change the application state.
///
/// Example usage:
/// ```dart
/// class CreateUserCommand extends Command<User> {
///   const CreateUserCommand({
///     required this.name,
///     required this.email,
///   });
///
///   final String name;
///   final String email;
/// }
/// ```
abstract class Command<R> {
  /// Creates a new command.
  const Command();
}

/// A handler that can execute commands of type [C] and return results of type [R].
///
/// Command handlers encapsulate the business logic for executing specific commands.
/// They are registered with the mediator and called when commands are dispatched.
///
/// Example usage:
/// ```dart
/// class CreateUserCommandHandler extends CommandHandler<CreateUserCommand, User> {
///   CreateUserCommandHandler({required IUserRepository repository})
///       : super((command) async {
///             // Business logic to create user
///             final user = await repository.create(
///               name: command.name,
///               email: command.email,
///             );
///             return user;
///           },
///         );
/// }
/// ```
class CommandHandler<C extends Command<R>, R> {
  /// Creates a command handler with the given [run] callback.
  const CommandHandler(CommandHandlerCallback<C, R> run) : _callback = run;

  final CommandHandlerCallback<C, R> _callback;

  /// Executes the given [command] and returns a future with the result.
  Future<R> run(C command) {
    return _callback.call(command);
  }
}

/// A callback function that handles the execution of a command.
///
/// This typedef defines the signature for command handler functions that take
/// a command of type [C] and return a future with a result of type [R].
typedef CommandHandlerCallback<C extends Command<R>, R> = Future<R> Function(C);
