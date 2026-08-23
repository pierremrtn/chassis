/// Errors thrown by the [Mediator] when dispatch or registration fails.
///
/// These are always programming errors (wiring mistakes), never runtime
/// conditions to recover from — fix the registration, don't catch. They are
/// Dart [Error]s, not [Exception]s, for exactly that reason: crash reporting
/// classifies them as fatal, and `catch (e)` clauses written for domain
/// failures should not swallow them.
library;

/// Base type for all chassis mediator errors.
sealed class ChassisError extends Error {}

/// Thrown when a command or query is dispatched but no handler is registered
/// for its type.
class HandlerNotRegisteredError({
  /// The runtime type of the dispatched command or query.
  required final Type requestType,

  /// The mediator method that was called (`read`, `watch`, or `run`).
  required final String dispatchMethod,

  /// The registration method that would fix this (`registerQueryHandler` or
  /// `registerCommandHandler`).
  required final String registerMethod,

  /// The handler interface the missing handler must implement.
  required final String handlerInterface,
}) extends ChassisError {
  @override
  String toString() =>
      'HandlerNotRegisteredError: no $handlerInterface registered for '
      '$requestType (dispatched via Mediator.$dispatchMethod).\n'
      'Fix: register one with mediator.$registerMethod(...), or annotate your '
      'handler class with @chassisHandler and run '
      '`dart run build_runner build` so chassis_builder wires it into the '
      'generated mediator.';
}

/// Thrown when a handler is registered for a type that already has one.
///
/// Thrown unconditionally (debug and release behave identically): a duplicate
/// registration silently replacing an existing handler is never intended.
class DuplicateHandlerError({
  /// The command or query type registered twice.
  required final Type requestType,

  /// The runtime type of the handler already registered.
  required final Type existingHandler,

  /// The runtime type of the handler whose registration was rejected.
  required final Type newHandler,
}) extends ChassisError {
  @override
  String toString() =>
      'DuplicateHandlerError: a handler for $requestType is already '
      'registered ($existingHandler); rejected duplicate registration of '
      '$newHandler.\n'
      'Each command/query type must have exactly one handler. If you meant to '
      'replace it, remove the first registration.';
}
