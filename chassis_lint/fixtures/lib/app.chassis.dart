// Hand-written stand-in for a chassis_builder-generated library.
//
// chassis_no_dispatch_in_widget identifies "mediator types" either by
// subtyping chassis's `Mediator`, or by the declaring library's file name
// ending in `.chassis.dart` — this class exercises the second convention:
// it does NOT extend Mediator.
class GeneratedAppMediator {
  Future<Object?> run(Object command) async => null;
}
