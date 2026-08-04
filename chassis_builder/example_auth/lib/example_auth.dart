/// Example chassis module: exposes auth handlers behind a generated
/// `AuthMediator` interface, consumable by any app without knowing the
/// app's concrete mediator.
///
/// The generated interface lives in `example_auth.chassis.dart`.
library;

import 'package:chassis/chassis.dart';

export 'src/handlers.dart';

/// Module declaration: the generator emits `AuthMediator` (in
/// `example_auth.chassis.dart`) from every handler reachable from this
/// library.
@chassisModule
final class AuthModule {}
