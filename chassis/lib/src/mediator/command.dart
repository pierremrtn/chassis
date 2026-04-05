/// Abstract base class for commands that can be executed through the mediator.
///
/// Commands represent operations that modify state or perform side effects.
/// They are typically used for write operations, mutations, or actions that
/// change the application state.
///
/// Example usage:
/// ```dart
/// final class CreateUserCommand extends Command<User> {
///   CreateUserCommand({
///     required this.name,
///     required this.email,
///   });
///
///   final String name;
///   final String email;
/// }
/// ```
abstract base class Command<R> {}

/// A handler that executes commands of type [C] and returns results of type [R].
///
/// Command handlers encapsulate the business logic for executing specific commands.
/// They are registered with the mediator and called when commands are dispatched.
///
/// Handlers receive dependencies via constructor injection, keeping them testable
/// and decoupled from concrete implementations.
///
/// Example usage:
/// ```dart
/// class CreateUserCommandHandler implements CommandHandler<CreateUserCommand, User> {
///   final IUserRepository _repository;
///   final IAuditLogger _auditLogger;
///
///   CreateUserCommandHandler({
///     required IUserRepository repository,
///     required IAuditLogger auditLogger,
///   })  : _repository = repository,
///         _auditLogger = auditLogger;
///
///   @override
///   Future<User> run(CreateUserCommand command) async {
///     await _auditLogger.logAction('Creating user: ${command.email}');
///
///     final user = await _repository.create(
///       name: command.name,
///       email: command.email,
///     );
///
///     await _auditLogger.logAction('User created successfully: ${user.id}');
///     return user;
///   }
/// }
/// ```
abstract interface class CommandHandler<C extends Command<R>, R> {
  /// Executes the given [command] and returns a future with the result.
  Future<R> run(C command);
}
