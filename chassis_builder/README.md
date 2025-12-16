# Chassis Builder

A code generator for the [Chassis](https://pub.dev/packages/chassis) framework.

`chassis_builder` scans your code for `@chassisHandler` annotations and automatically generates a concrete `Mediator` class that wires up all your dependencies and handlers.

## Installation

Add `chassis` and `chassis_builder` to your `pubspec.yaml`:

```yaml
dependencies:
  chassis: ^1.0.0

dev_dependencies:
  chassis_builder: ^1.0.0
  build_runner: ^2.4.0
```

## Configuration

Configure the builder in your `build.yaml` file to define the name and location of the generated mediator.

```yaml
targets:
  $default:
    builders:
      chassis_builder:
        options:
          # The name of the generated Mediator class.
          # Default: AppMediator
          mediator_name: MyMediator
          
          # The output filename relative to the lib/ folder.
          # Default: app_mediator.dart
          output_name: my_app_mediator.dart
```

By default, the builder generates `lib/app_mediator.dart` containing an `AppMediator` class.

## Usage

### 1. Define Handlers

Annotate your command and query handlers with `@chassisHandler`.

```dart
import 'package:chassis/chassis.dart';

@chassisHandler
class LoginHandler implements CommandHandler<LoginCommand, void> {
  final AuthRepo authRepo;

  LoginHandler(this.authRepo);

  @override
  Future<void> run(LoginCommand command) async {
    // ... logic
  }
}
```

### 2. Run the Builder

Run `build_runner` to generate the mediator code.

```bash
dart run build_runner build
```

### 3. Use the Mediator

Instantiate the generated mediator class (e.g. `MyMediator` or `AppMediator`) and use it in your application.

```dart
import 'package:chassis/chassis.dart';
import 'my_app_mediator.dart'; // The generated file

void main() {
  final authRepo = AuthRepo();
  
  // The generated class constructor automatically requires dependencies 
  // needed by your handlers.
  final mediator = MyMediator(
    authRepo: authRepo,
  );

  // Use the mediator as usual, or use the generated type-safe extensions
  mediator.login(LoginCommand('username'));
}
```
