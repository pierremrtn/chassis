import 'package:chassis/chassis.dart';

// domain/repository
abstract interface class IGreetingRepository {
  Future<String> getGreeting();
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

class GetGreetingQueryHandler implements ReadHandler<GetGreetingQuery, String> {
  final IGreetingRepository _repository;
  GetGreetingQueryHandler(this._repository);

  @override
  Future<String> read(GetGreetingQuery query) {
    // Your business logic lives here
    return _repository.getGreeting();
  }
}

// app/main.dart
final mediator = Mediator();

Future<void> main() async {
  final greetingRepository = GreetingRepository();
  mediator.registerQueryHandler(GetGreetingQueryHandler(greetingRepository));
  final greeting = await mediator.read(const GetGreetingQuery());
  print(greeting);
}
