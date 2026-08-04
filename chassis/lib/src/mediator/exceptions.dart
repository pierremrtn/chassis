/// Exceptions thrown by the [Mediator] when dispatch or registration fails.
///
/// These errors are always programming errors (wiring mistakes), never
/// runtime conditions to recover from — fix the registration, don't catch.
library;

/// Base type for all chassis mediator exceptions.
sealed class ChassisException implements Exception {
  const ChassisException();
}

/// Thrown when a command or query is dispatched but no handler is registered
/// for its type.
class HandlerNotRegisteredException extends ChassisException {
  const HandlerNotRegisteredException({
    required this.requestType,
    required this.dispatchMethod,
    required this.registerMethod,
    required this.handlerInterface,
  });

  /// The runtime type of the dispatched command or query.
  final Type requestType;

  /// The mediator method that was called (`read`, `watch`, or `run`).
  final String dispatchMethod;

  /// The registration method that would fix this (`registerQueryHandler` or
  /// `registerCommandHandler`).
  final String registerMethod;

  /// The handler interface the missing handler must implement.
  final String handlerInterface;

  @override
  String toString() =>
      'HandlerNotRegisteredException: no $handlerInterface registered for '
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
class DuplicateHandlerException extends ChassisException {
  const DuplicateHandlerException({
    required this.requestType,
    required this.existingHandler,
    required this.newHandler,
  });

  /// The command or query type registered twice.
  final Type requestType;

  /// The runtime type of the handler already registered.
  final Type existingHandler;

  /// The runtime type of the handler whose registration was rejected.
  final Type newHandler;

  @override
  String toString() =>
      'DuplicateHandlerException: a handler for $requestType is already '
      'registered ($existingHandler); rejected duplicate registration of '
      '$newHandler.\n'
      'Each command/query type must have exactly one handler. If you meant to '
      'replace it, remove the first registration.';
}
