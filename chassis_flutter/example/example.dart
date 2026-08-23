import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

// --- Logic layer: query + handler ---

final class WatchCounterQuery extends WatchQuery<int> {}

class WatchCounterQueryHandler implements WatchHandler<WatchCounterQuery, int> {
  @override
  Stream<int> watch(WatchCounterQuery query) =>
      Stream.periodic(const Duration(seconds: 1), (i) => i);
}

final class ResetCounterCommand extends Command<void> {}

class ResetCounterCommandHandler
    implements CommandHandler<ResetCounterCommand, void> {
  @override
  Future<void> run(ResetCounterCommand command) async {}
}

// --- Presentation layer: state, events, view model ---

class const CounterState({final Async<int> count = const Async.loading()}) {
  CounterState copyWith({Async<int>? count}) =>
      CounterState(count: count ?? this.count);
}

sealed class CounterEvent {}

final class CounterResetEvent implements CounterEvent {}

class CounterViewModel extends ViewModel<CounterState, CounterEvent> {
  CounterViewModel({super.mediator}) : super(const CounterState()) {
    watchCounter();
  }

  void watchCounter() => watch(
    WatchCounterQuery(),
    current: state.count,
    onState: (count) => setState(state.copyWith(count: count)),
  );

  void reset() => run(
    ResetCounterCommand(),
    onSuccess: (_) => sendEvent(CounterResetEvent()),
    onError: (error, stack) =>
        setState(state.copyWith(count: state.count.toError(error, stack))),
  );
}

// --- App wiring ---

void main() {
  Chassis.initialize(
    Mediator()
      ..registerQueryHandler(WatchCounterQueryHandler())
      ..registerCommandHandler(ResetCounterCommandHandler())
      ..addMiddleware(LoggingMiddleware()),
  );

  runApp(const MyApp());
}

class const MyApp({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ViewModelProvider.withEventListener<CounterViewModel, CounterEvent>(
        create: (context) => CounterViewModel(),
        onEvent: (context, viewModel, event) {
          switch (event) {
            case CounterResetEvent():
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Counter reset')));
          }
        },
        child: const CounterScreen(),
      ),
    );
  }
}

class const CounterScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chassis counter')),
      body: Center(
        child: AsyncBuilder<int>(
          state: context.select((CounterViewModel vm) => vm.state.count),
          builder: (context, count) => Text('Count: $count'),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.read<CounterViewModel>().reset(),
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
