import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

// --- Logic layer: query + handler ---

final class WatchCounterQuery extends WatchQuery<int> {}

class WatchCounterHandler implements WatchHandler<WatchCounterQuery, int> {
  @override
  Stream<int> watch(WatchCounterQuery query) =>
      Stream.periodic(const Duration(seconds: 1), (i) => i);
}

final class ResetCounterCommand extends Command<void> {}

class ResetCounterHandler implements CommandHandler<ResetCounterCommand, void> {
  @override
  Future<void> run(ResetCounterCommand command) async {}
}

// --- Presentation layer: state, events, view model ---

class CounterState {
  const CounterState({this.count = const Async.loading()});

  final Async<int> count;

  CounterState copyWith({Async<int>? count}) =>
      CounterState(count: count ?? this.count);
}

sealed class CounterEvent {}

final class CounterResetEvent implements CounterEvent {}

class CounterViewModel extends ViewModel<CounterState, CounterEvent> {
  CounterViewModel(this._mediator) : super(const CounterState()) {
    watchCounter();
  }

  final Mediator _mediator;

  void watchCounter() {
    watch(
      _mediator.watch(WatchCounterQuery()),
      current: state.count,
      onState: (count) => setState(state.copyWith(count: count)),
    );
  }

  void reset() {
    run(
      () => _mediator.run(ResetCounterCommand()),
      onSuccess: (_) => sendEvent(CounterResetEvent()),
    );
  }
}

// --- App wiring ---

void main() {
  final mediator = Mediator()
    ..registerQueryHandler(WatchCounterHandler())
    ..registerCommandHandler(ResetCounterHandler())
    ..addMiddleware(LoggingMiddleware());

  runApp(MyApp(mediator: mediator));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.mediator});

  final Mediator mediator;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ViewModelProvider.withEventListener<CounterViewModel, CounterEvent>(
        create: (context) => CounterViewModel(mediator),
        onEvent: (context, viewModel, event) {
          switch (event) {
            case CounterResetEvent():
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Counter reset')),
              );
          }
        },
        child: const CounterScreen(),
      ),
    );
  }
}

class CounterScreen extends StatelessWidget {
  const CounterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chassis counter')),
      body: Center(
        child: AsyncBuilder<int>(
          state: context.select(
            (CounterViewModel vm) => vm.state.count,
          ),
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
