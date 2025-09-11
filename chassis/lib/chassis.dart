/// The Chassis package provides a foundation for building scalable Dart applications.
///
/// This package implements several key architectural patterns:
///
/// ## Mediator Pattern
/// The [Mediator] class provides a centralized way to handle commands and queries
/// without direct coupling between components. It supports:
/// - [Command] objects for operations that modify state
/// - [Read] queries for one-time data retrieval
/// - [Watch] queries for streaming data that updates over time
///
/// ## Result Pattern
/// The [Result] sealed class provides a type-safe way to handle operations that
/// might fail, with [Success] and [Failure] variants. This helps avoid exceptions
/// in many cases and provides better error handling.
///
/// ## Disposal Pattern
/// The [Disposable] mixin helps manage object lifecycles by providing a standard
/// way to clean up resources when objects are no longer needed.
///
/// ## Example Usage
/// ```dart
/// import 'package:chassis/chassis.dart';
///
/// // Define a command
/// class CreateUserCommand extends Command<User> {
///   const CreateUserCommand({required this.name, required this.email});
///   final String name;
///   final String email;
/// }
///
/// // Define a query
/// class GetUserQuery implements Read<User> {
///   const GetUserQuery({required this.userId});
///   final String userId;
/// }
///
/// // Create the mediator instance
/// final mediator = Mediator();
///
/// // Register handlers
/// mediator.registerCommandHandler<CreateUserCommand, User>(
///   CommandHandler<CreateUserCommand, User>(run: (command) async {
///     return await userRepository.create(command.name, command.email);
///   }),
/// );
///
/// mediator.registerQueryHandler<GetUserQuery, User>(
///   ReadHandler<GetUserQuery, User>(read: (query) async {
///     return await userRepository.findById(query.userId);
///   }),
/// );
///
/// // Use the mediator
/// final user = await mediator.read(GetUserQuery(userId: '123'));
/// final newUser = await mediator.run(CreateUserCommand(name: 'John', email: 'john@example.com'));
/// ```
library;

export 'src/mediator/mediator.dart';
export 'src/mediator/query.dart';
export 'src/mediator/command.dart';
export 'src/disposable.dart';
