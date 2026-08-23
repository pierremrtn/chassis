/// Example chassis module: exposes auth handlers to any app without knowing
/// the app's concrete mediator.
///
/// The module class generates nothing — it marks this package's handler
/// barrel so `@ChassisApp(modules: [AuthModule])` can discover the handlers
/// reachable from this library.
library;

import 'package:chassis/chassis.dart';

export 'src/handlers.dart';

/// Module declaration: `@ChassisApp(modules: [AuthModule])` registers every
/// handler reachable from this library on the generated app mediator.
@chassisModule
final class AuthModule {}
