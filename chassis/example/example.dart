import 'package:chassis/chassis.dart';

// domain/repository
abstract interface class IGreetingRepository {
  Future<String> getGreeting();
}

abstract interface class IAnalyticsService {
  Future<void> trackEvent(String event, [Map<String, dynamic>? data]);
}

// app/repository
class GreetingRepository implements IGreetingRepository {
  @override
  Future<String> getGreeting() async => "Hello Chassis";
}

// domain/uses_cases
class GetGreetingQuery implements ReadQuery<String> {
  const GetGreetingQuery();
}

// Simple handler using extends
class GetGreetingQueryHandler extends ReadHandler<GetGreetingQuery, String> {
  GetGreetingQueryHandler(IGreetingRepository repository)
      : super((query) => repository.getGreeting());
}

// More complex handler using implements (for scenarios with multiple dependencies)
class GetGreetingQueryHandlerComplex
    implements ReadHandler<GetGreetingQuery, String> {
  final IGreetingRepository _repository;
  final IAnalyticsService _analytics;

  GetGreetingQueryHandlerComplex(this._repository, this._analytics);

  @override
  Future<String> read(GetGreetingQuery query) async {
    // More complex business logic with multiple dependencies
    await _analytics.trackEvent('greeting_requested');
    final greeting = await _repository.getGreeting();
    await _analytics.trackEvent('greeting_retrieved');
    return greeting;
  }
}

// app/main.dart
final mediator = Mediator();

Future<void> main() async {
  final greetingRepository = GreetingRepository();

  // Register the simple handler
  mediator.registerQueryHandler(GetGreetingQueryHandler(greetingRepository));

  final greeting = await mediator.read(const GetGreetingQuery());
  print(greeting);
}
