# chassis_builder

[![pub package](https://img.shields.io/pub/v/chassis_builder.svg)](https://pub.dev/packages/chassis_builder)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/pierremrtn/chassis/blob/main/LICENSE)

Code generation for **[Chassis](https://pub.dev/packages/chassis)**, an opinionated architecture framework for Flutter. It wires your handlers into the app mediator and verifies the wiring at build time:

* **`@chassisHandler`** — marks a handler for discovery; the generated mediator instantiates and registers it
* **`@ChassisApp`** — on the composition root's library directive (`@ChassisApp(...) library;`), generates the app mediator
* **`@chassisModule`** — cross-package handler discovery only: lets `@ChassisApp(modules: [...])` find the handlers of a shared package; generates nothing itself

The generated mediator is a single class with a registration-only constructor: handler dependencies are deduplicated into required named parameters, and no per-message methods are generated. Dispatch goes through the inherited `run`/`read`/`watch`, so middlewares always apply and ViewModels depend only on message types:

```dart
class AppMediator extends Mediator {
  AppMediator({
    required AuthRepository authRepository,
    required ConfigStore configStore,
  }) {
    registerQueryHandler(GetProfileQueryHandler(repository: authRepository));
    registerCommandHandler(LoginCommandHandler(repository: authRepository));
    registerQueryHandler(WatchSessionQueryHandler(repository: authRepository));
    registerQueryHandler(GetAppConfigQueryHandler(store: configStore));
  }
}
```

**A missing handler is a build error.** Every concrete command or query reachable from the `@ChassisApp` library must have a handler, or the build fails at the declaration site with one error listing every orphan message and its fixes (annotate a handler with `@chassisHandler`, declare the module, or opt out with `@unhandledMessage`). Other wiring mistakes — two handlers for one message, a handler implementing two operation interfaces, a private type in a handler constructor, a handler depending on the mediator — fail the build too. The generator never emits a partial mediator.

Runs on `build_runner`, no `build.yaml` needed:

```bash
dart run build_runner build
```

This package is one third of the framework — start with the **[chassis package](https://pub.dev/packages/chassis)** for the full picture, or dive into the **[documentation](https://pierremrtn.github.io/chassis/)**.

## License

Chassis is released under the MIT License. See [LICENSE](https://github.com/pierremrtn/chassis/blob/main/LICENSE) for details.
