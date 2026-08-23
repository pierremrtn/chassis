# chassis_flutter

[![pub package](https://img.shields.io/pub/v/chassis_flutter.svg)](https://pub.dev/packages/chassis_flutter)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/pierremrtn/chassis/blob/main/LICENSE)

The Flutter layer of **[Chassis](https://pub.dev/packages/chassis)**, an opinionated architecture framework for Flutter. It connects your business logic to the widget tree:

* **`ViewModel<State, Event>`** — holds an immutable state, dispatches command and query objects through `run`, `read`, and `watch` (via the mediator installed once with `Chassis.initialize`), reports every operation as `Async<T>`, controls concurrency with `RunPolicy`, and sends one-time events for snackbars and navigation
* **`ViewModelProvider`** and **`context.select`** — provide ViewModels and subscribe widgets to exactly the state they render
* **`AsyncBuilder`** and **`EventListener`** — widgets for rendering `Async<T>` without flickering and turning events into UI side effects

This package is one third of the framework — start with the **[chassis package](https://pub.dev/packages/chassis)** for the full picture, or dive into the **[documentation](https://pierremrtn.github.io/chassis/)**.

## License

Chassis is released under the MIT License. See [LICENSE](https://github.com/pierremrtn/chassis/blob/main/LICENSE) for details.
