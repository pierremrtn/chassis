import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'types.dart';

/// E2 — ViewModels are await-free.
///
/// Flags every `await` expression, and every `async`/`async*` modifier on a
/// method, inside instance members of a class whose supertype chain includes
/// chassis_flutter's `ViewModel`. Platform async belongs in the widget;
/// multi-step logic belongs in a handler.
class ChassisNoAwaitInViewModel extends DartLintRule {
  const ChassisNoAwaitInViewModel() : super(code: _code);

  static const _code = LintCode(
    name: 'chassis_no_await_in_view_model',
    problemMessage: 'ViewModels dispatch messages; move platform '
        'interactions to the widget and multi-step logic into a handler.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addAwaitExpression((node) {
      if (!_isInInstanceMemberOfViewModel(node)) return;
      reporter.atToken(node.awaitKeyword, _code);
    });

    context.registry.addMethodDeclaration((node) {
      if (node.isStatic) return;
      final keyword = node.body.keyword;
      if (keyword == null || !node.body.isAsynchronous) return;
      final classDeclaration = node.parent;
      if (classDeclaration is! ClassDeclaration) return;
      if (!_isViewModelDeclaration(classDeclaration)) return;
      reporter.atToken(keyword, _code);
    });
  }

  /// Whether [node] sits inside an instance member (method, getter, setter,
  /// or field initializer — including closures nested in them) of a class
  /// extending `ViewModel`.
  static bool _isInInstanceMemberOfViewModel(AstNode node) {
    // Walk up to the class member that contains the node.
    AstNode? member = node;
    while (member != null && member.parent is! ClassDeclaration) {
      member = member.parent;
    }
    if (member == null) return false;

    final isStatic = switch (member) {
      MethodDeclaration(:final isStatic) => isStatic,
      FieldDeclaration(:final isStatic) => isStatic,
      _ => false,
    };
    if (isStatic) return false;

    final classDeclaration = member.parent;
    if (classDeclaration is! ClassDeclaration) return false;
    return _isViewModelDeclaration(classDeclaration);
  }

  static bool _isViewModelDeclaration(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element == null) return false;
    return isViewModelClass(element);
  }
}
