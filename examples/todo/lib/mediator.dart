@ChassisApp(mediatorName: 'AppMediator')
library;

import 'package:chassis/chassis.dart';

// The generator collects every @chassisHandler reachable from this
// library's imports — this import is what makes the handlers visible.
// It is only read by the generator, hence the analyzer ignore.
// ignore: unused_import
import 'package:todo_app/application/todo_handlers.dart';

// Re-export the generated mediator so main.dart imports only this file.
export 'package:todo_app/mediator.chassis.dart';
