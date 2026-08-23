import 'params_equality.dart';

/// Abstract base class for commands that can be executed through the mediator.
///
/// Commands represent operations that modify state or perform side effects.
/// They are typically used for write operations, mutations, or actions that
/// change the application state.
///
/// Example usage:
/// ```dart
/// final class CreateUserCommand({
///   required final String name,
///   required final String email,
/// }) extends Command<User>;
/// ```
abstract base class Command<R> {
  /// Parameters of this command, for logging, tracing, and identity.
  ///
  /// Override to expose the command's fields. Used by [toString], by
  /// `LoggingMiddleware` so a trace reads `CreateUserCommand{name: John}`
  /// instead of a bare type name, and by [operator ==] as the message's
  /// identity.
  ///
  /// Never include secrets (passwords, tokens) in [params].
  Map<String, Object?> get params => const {};

  /// Two messages of the same type with equal [params] are the same
  /// operation.
  ///
  /// This is the identity contract middlewares (caching, deduplication)
  /// and tooling may rely on: a message is fully described by its type and
  /// its [params]. A field that affects the operation but is left out of
  /// [params] breaks that contract.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Command<R> &&
          other.runtimeType == runtimeType &&
          paramsEquals(other.params, params);

  @override
  int get hashCode => Object.hash(runtimeType, paramsHash(params));

  @override
  String toString() => params.isEmpty ? '$runtimeType' : '$runtimeType$params';
}

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
/// @chassisHandler
/// class CreateUserCommandHandler(
///   final UserRepository _repository,
///   final AuditLogger _auditLogger,
/// ) implements CommandHandler<CreateUserCommand, User> {
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
