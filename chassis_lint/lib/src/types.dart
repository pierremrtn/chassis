import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// `ViewModel` from package:chassis_flutter.
const viewModelChecker = TypeChecker.fromName(
  'ViewModel',
  packageName: 'chassis_flutter',
);

/// `Mediator` from package:chassis.
const mediatorChecker = TypeChecker.fromName(
  'Mediator',
  packageName: 'chassis',
);

/// Flutter's `Widget`.
const widgetChecker = TypeChecker.fromName(
  'Widget',
  packageName: 'flutter',
);

/// Flutter's `State`.
const stateChecker = TypeChecker.fromName(
  'State',
  packageName: 'flutter',
);

/// Whether [type] is a "mediator type" — the same convention as
/// chassis_builder's `_rejectMediatorDependency`: a subtype of `Mediator`
/// (from package:chassis), or a type declared in a generated library whose
/// file name ends with `.chassis.dart`.
bool isMediatorType(DartType? type) {
  if (type is! InterfaceType) return false;
  if (mediatorChecker.isAssignableFromType(type)) return true;
  final uri = type.element.library.uri;
  return uri.path.endsWith('.chassis.dart');
}

/// Whether [element] declares a class whose supertype chain includes
/// chassis_flutter's `ViewModel` (including `ViewModel` itself).
bool isViewModelClass(InterfaceElement element) =>
    viewModelChecker.isAssignableFrom(element);
