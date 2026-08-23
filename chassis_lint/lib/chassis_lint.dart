/// custom_lint rules enforcing the chassis framework doctrine.
///
/// - `chassis_visible_error_path` — `run()`/`read()` must cover the error
///   path with `onState` or `onError`.
/// - `chassis_no_await_in_view_model` — ViewModels are await-free.
/// - `chassis_no_dispatch_in_widget` — widgets never dispatch through a
///   mediator.
library;

import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'src/no_await_in_view_model.dart';
import 'src/no_dispatch_in_widget.dart';
import 'src/visible_error_path.dart';

export 'src/no_await_in_view_model.dart';
export 'src/no_dispatch_in_widget.dart';
export 'src/visible_error_path.dart';

/// The custom_lint entry point.
PluginBase createPlugin() => _ChassisLintPlugin();

class _ChassisLintPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => const [
        ChassisVisibleErrorPath(),
        ChassisNoAwaitInViewModel(),
        ChassisNoDispatchInWidget(),
      ];
}
