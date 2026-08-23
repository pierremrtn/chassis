// Fixtures for `chassis_no_dispatch_in_widget` (E3).
//
// Widgets (and States) never invoke methods on a "mediator type": a subtype
// of chassis's `Mediator`, or a type declared in a generated
// `.chassis.dart` library. Dispatch belongs to ViewModels.

import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/widgets.dart';

import 'app.chassis.dart';
import 'messages.dart';

class E3ViewModel extends ViewModel<int, Object> {
  E3ViewModel() : super(0);

  void save() => run(
        SaveTodo('x'),
        onError: (error, stack) => sendEvent(error),
      );
}

// BAD: a widget dispatching through the mediator directly.
//
// KNOWN LIMITATION (no expect_lint): since chassis moved to Dart 3.13
// primary constructors, custom_lint's pinned analyzer (^8, via
// custom_lint_builder 0.8.x) can no longer resolve chassis's element model,
// so the "subtype of Mediator" branch of the rule does not fire. The
// generated-`.chassis.dart` branch below still does (that file lives in the
// analyzed package, in classic syntax). Restore the expect_lint when
// custom_lint supports a Dart 3.13-capable analyzer — see the "Known
// limitation" section of ../README.md.
class DispatchingWidget extends StatelessWidget {
  const DispatchingWidget({super.key, required this.mediator});

  final Mediator mediator;

  @override
  Widget build(BuildContext context) {
    mediator.run(SaveTodo('title'));
    return const SizedBox();
  }
}

class GeneratedDispatchWidget extends StatefulWidget {
  const GeneratedDispatchWidget({super.key, required this.mediator});

  final GeneratedAppMediator mediator;

  @override
  State<GeneratedDispatchWidget> createState() =>
      _GeneratedDispatchWidgetState();
}

// BAD: dispatch from a State, through a type declared in a generated
// `.chassis.dart` library (which does not extend Mediator).
class _GeneratedDispatchWidgetState extends State<GeneratedDispatchWidget> {
  @override
  void initState() {
    super.initState();
    // expect_lint: chassis_no_dispatch_in_widget
    widget.mediator.run(SaveTodo('title'));
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// GOOD: widgets talk to ViewModels, not to the mediator.
class DelegatingWidget extends StatelessWidget {
  const DelegatingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.read<E3ViewModel>().save(),
      child: const SizedBox(),
    );
  }
}

// GOOD: a non-widget service may hold and use the mediator.
class SyncService {
  SyncService(this._mediator);

  final Mediator _mediator;

  Future<void> synchronize() => _mediator.run(SaveTodo('sync'));
}
