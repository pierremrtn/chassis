import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'types.dart';

/// E3 — widgets never dispatch through a mediator.
///
/// Flags any method invocation whose target's static type is a "mediator
/// type" (a subtype of chassis's `Mediator`, or a type declared in a
/// generated `.chassis.dart` library) when the enclosing class extends or
/// mixes Flutter's `Widget` or `State`. Dispatch belongs to ViewModels.
class ChassisNoDispatchInWidget extends DartLintRule {
  const ChassisNoDispatchInWidget() : super(code: _code);

  static const _code = LintCode(
    name: 'chassis_no_dispatch_in_widget',
    problemMessage: 'Widgets never dispatch: move this to a ViewModel method.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((node) {
      if (!isMediatorType(node.realTarget?.staticType)) return;

      final classDeclaration = node.thisOrAncestorOfType<ClassDeclaration>();
      final element = classDeclaration?.declaredFragment?.element;
      if (element == null) return;
      if (!widgetChecker.isAssignableFrom(element) &&
          !stateChecker.isAssignableFrom(element)) {
        return;
      }

      reporter.atNode(node, _code);
    });
  }
}
