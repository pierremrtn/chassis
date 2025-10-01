import 'package:chassis/chassis.dart';

// domain/repository
abstract interface class IGreetingRepository {
  Future<String> getGreeting();
  Stream<String> getGreetingStream();
}

abstract interface class IAnalyticsService {
  Future<void> trackEvent(String event, [Map<String, dynamic>? data]);
}

// app/repository
class GreetingRepository implements IGreetingRepository {
  @override
  Future<String> getGreeting() async => "Hello Chassis";

  @override
  Stream<String> getGreetingStream() async* {
    // Simulate a stream that emits greetings periodically
    yield "Hello Chassis";
    await Future.delayed(const Duration(seconds: 1));
    yield "Hello Chassis - Updated!";
    await Future.delayed(const Duration(seconds: 1));
    yield "Hello Chassis - Final!";
  }
}

// domain/uses_cases
class WatchGreetingsQuery implements WatchQuery<String> {
  const WatchGreetingsQuery();
}

// Simple handler using extends
class WatchGreetingsQueryHandler
    extends WatchHandler<WatchGreetingsQuery, String> {
  WatchGreetingsQueryHandler(IGreetingRepository repository)
      : super((query) => repository.getGreetingStream());
}

// More complex handler using implements (for scenarios with multiple dependencies)
class WatchGreetingsQueryHandlerComplex
    implements WatchHandler<WatchGreetingsQuery, String> {
  final IGreetingRepository _repository;
  final IAnalyticsService _analytics;

  WatchGreetingsQueryHandlerComplex(this._repository, this._analytics);

  @override
  Stream<String> watch(WatchGreetingsQuery query) async* {
    // More complex business logic with multiple dependencies
    await _analytics.trackEvent('greeting_requested');
    await for (final greeting in _repository.getGreetingStream()) {
      await _analytics.trackEvent('greeting_retrieved');
      yield greeting;
    }
  }
}

// app/main.dart
final mediator = Mediator();

Future<void> main() async {
  final greetingRepository = GreetingRepository();

  // Register the simple handler
  mediator.registerQueryHandler(WatchGreetingsQueryHandler(greetingRepository));

  // Watch the greeting stream
  final subscription =
      mediator.watch(const WatchGreetingsQuery()).listen((greeting) {
    print(greeting);
  });

  // Wait for a few seconds to see the stream updates
  await Future.delayed(const Duration(seconds: 3));
  await subscription.cancel();
}
