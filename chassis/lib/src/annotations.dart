import 'package:meta/meta_meta.dart';

/// Annotation used to mark a class as a Chassis handler.
///
/// Classes annotated with [ChassisHandler] are picked up by the code
/// generator and registered in the constructor of the app mediator
/// generated from the [ChassisApp] library that reaches them.
class const ChassisHandler();

/// Annotation instance to be used on handler classes.
const chassisHandler = ChassisHandler();

/// Marks a command or query class as intentionally having no handler yet.
///
/// The generator fails the build when a concrete message reachable from the
/// `@ChassisApp` library has no `@chassisHandler` handler — a dispatch of
/// that message could only throw at runtime. Annotate a message with
/// [unhandledMessage] to opt out while it is being written:
///
/// ```dart
/// @unhandledMessage // handler comes in the next commit
/// final class ExportDataCommand extends Command<void> {}
/// ```
class const UnhandledMessage();

/// Annotation instance to be used on message classes without a handler.
const unhandledMessage = UnhandledMessage();

/// Marks a class as a Chassis module declaration.
///
/// A module is a shareable package exposing handlers. Its single role is
/// cross-package handler discovery: the generator scopes its import-graph
/// walk to each root library's own package, so handlers living in another
/// package are only found when that package's module class is listed in
/// `@ChassisApp(modules: [...])`. The module class itself generates
/// nothing — it marks the library (and package) whose graph the app-side
/// generator walks.
///
/// Convention: the annotated class must live in a library that
/// (transitively) imports every handler of the package — typically the
/// package barrel.
///
/// ```dart
/// // package auth — lib/auth.dart
/// @chassisModule
/// final class AuthModule {}
///
/// // app — composition root
/// @ChassisApp(modules: [AuthModule])
/// library;
/// ```
class const ChassisModule();

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
/// // generates: class AppMediator extends Mediator { AppMediator({...}) }
/// ```
///
/// The generator creates a concrete mediator (in `<file>.chassis.dart`)
/// that extends `Mediator` and registers every handler in its constructor:
/// the handlers of the app's own package reachable from the annotated
/// library, plus the handlers of each listed module. Handler dependencies
/// become required named constructor parameters (deduplicated by type).
/// Dispatch messages through the inherited `run`/`read`/`watch` —
/// middlewares always apply.
///
/// The build fails when a reachable concrete command or query has no
/// handler (`HandlerNotRegisteredError` would be the runtime alternative);
/// annotate such a message with [unhandledMessage] to opt out while its
/// handler is being written.
@Target({TargetKind.library})
class const ChassisApp({
  /// Module declaration classes (annotated with [ChassisModule]) whose
  /// handlers are composed into the generated mediator.
  final List<Type> modules = const [],

  /// Name of the generated mediator class.
  final String mediatorName = 'AppMediator',
});
