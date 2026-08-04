import 'package:meta/meta_meta.dart';

/// Annotation used to mark a class as a Chassis handler.
///
/// Classes annotated with [ChassisHandler] will be picked up by the code
/// generator and wired into the generated mediator of the module or app
/// that reaches them.
class ChassisHandler {
  const ChassisHandler();
}

/// Annotation instance to be used on handler classes.
const chassisHandler = ChassisHandler();

/// Marks a class as a Chassis module declaration.
///
/// A module is a shareable package exposing handlers. The generator creates
/// an `abstract interface class <Name>Mediator` next to the annotated class
/// (in `<file>.chassis.dart`), with one typed method per handler reachable
/// from the annotated library's import graph within the module's package.
///
/// Convention: the annotated class must live in (or be reachable from) a
/// library that imports every handler of the module — typically the package
/// barrel.
///
/// ```dart
/// // package auth — lib/auth.dart
/// @chassisModule
/// final class AuthModule {}
/// // generates lib/auth.chassis.dart: abstract interface class AuthMediator
/// ```
class ChassisModule {
  const ChassisModule();
}

/// Annotation instance to be used on module declaration classes.
const chassisModule = ChassisModule();

/// Marks a library as the Chassis composition root of an application.
///
/// Annotate the library directive of a file that imports your handlers
/// (directly or via barrels):
///
/// ```dart
/// @ChassisApp(modules: [AuthModule], mediatorName: 'AppMediator')
/// library;
/// // generates: class AppMediator extends Mediator implements AuthMediator
/// ```
///
/// The generator creates a concrete mediator (in `<file>.chassis.dart`)
/// that:
/// - registers every handler of the app's own package reachable from the
///   annotated library, plus every handler of each listed module;
/// - `implements` each module's generated mediator interface, so a missing
///   handler is a compile error;
/// - exposes one typed method per handler, each dispatching through the
///   mediator (middlewares always apply).
@Target({TargetKind.library})
class ChassisApp {
  const ChassisApp({
    this.modules = const [],
    this.mediatorName = 'AppMediator',
  });

  /// Module declaration classes (annotated with [ChassisModule]) whose
  /// handlers are composed into the generated mediator.
  final List<Type> modules;

  /// Name of the generated mediator class.
  final String mediatorName;
}
