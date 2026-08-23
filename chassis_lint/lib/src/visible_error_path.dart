import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'types.dart';

/// E1 — `run()`/`read()` on a ViewModel must make failures visible.
///
/// The callback contract is additive: `onState` fires for every transition
/// (loading, data, error) and `onSuccess`/`onError` are conveniences on top.
/// A dispatch whose named arguments include neither `onState` nor `onError`
/// covers the success path only — its failures land nowhere.
///
/// `watch()` is not checked here: it has its own runtime assert.
class ChassisVisibleErrorPath extends DartLintRule {
  const ChassisVisibleErrorPath() : super(code: _code);

  static const _code = LintCode(
    name: 'chassis_visible_error_path',
    problemMessage: '{0}() without onState or onError: failures are '
        'invisible. Add onError (or onState) — see docs/error_management.md.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  static const _dispatchMethods = {'run', 'read'};
  static const _errorVisibleArguments = {'onState', 'onError'};

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((node) {
      final name = node.methodName.name;
      if (!_dispatchMethods.contains(name)) return;

      // The resolved method must be ViewModel.run/read (or an override in a
      // ViewModel subclass) — this covers both the implicit-this dispatch
      // inside a ViewModel and an explicit `someViewModel.run(...)`, while
      // ignoring unrelated `run`/`read` methods (e.g. Mediator.run).
      final element = node.methodName.element;
      if (element is! ExecutableElement) return;
      final enclosing = element.enclosingElement;
      if (enclosing is! InterfaceElement) return;
      if (!isViewModelClass(enclosing)) return;

      final namedArguments = node.argumentList.arguments
          .whereType<NamedExpression>()
          .map((argument) => argument.name.label.name);
      if (namedArguments.any(_errorVisibleArguments.contains)) return;

      reporter.atNode(node, _code, arguments: [name]);
    });
  }
}
