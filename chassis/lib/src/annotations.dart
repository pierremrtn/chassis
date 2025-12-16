/// Annotation used to mark a class as a Chassis handler.
///
/// Classes annotated with [ChassisHandler] will be picked up by the code generator
/// to register them in the generated Mediator.
class ChassisHandler {
  const ChassisHandler();
}

/// Annotation instance to be used on handler classes.
const chassisHandler = ChassisHandler();

/// Annotation used to mark a class as a Chassis Mediator.
///
/// The code generator will generate the mixin or base class for this Mediator.
class ChassisMediator {
  const ChassisMediator();
}

/// Annotation instance to be used on Mediator classes.
const chassisMediator = ChassisMediator();

/// Annotation to generate a QueryHandler from a repository method.
class GenerateQueryHandler {
  const GenerateQueryHandler();
}

/// Annotation instance for generating query handlers.
const generateQueryHandler = GenerateQueryHandler();

/// Annotation to generate a CommandHandler from a repository method.
class GenerateCommandHandler {
  const GenerateCommandHandler();
}

/// Annotation instance for generating command handlers.
const generateCommandHandler = GenerateCommandHandler();
