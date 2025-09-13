# Chassis

**Rigid in the structure, Flexible in the implementation.**

## Overview

Chassis is an opinionated architectural framework for Flutter that provides a solid foundation for professional, scalable, and maintainable applications. It guides your project's structure by combining the clarity of MVVM with a pragmatic, front-end friendly implementation of CQRS principles.

Think of it like the chassis of a car: it provides a rigid, reliable frame so you can focus on building the features that make your application unique. 🏎️

_**Quick Links:**_

👉 [Quickstart Guide](00_quick_start.md)

👉 [API Reference](https://pub.dev/documentation/chassis/latest/)

👉 [Submit Issues](https://github.com/pierremrtn/chassis/issues)

👉 [Roadmap](ROADMAP.md)

### Core Philosophy

The design of Chassis is driven by a few core principles to ensure that building on a solid architecture feels productive, not restrictive.

* **Structure by Design:** Good architecture shouldn't rely on developer discipline alone. Chassis enforces a clear separation of concerns through its defined data flow, making it intuitive to write clean, organized code.

* **Rigid Structure, Flexible Logic:** The overall flow of data and execution is consistent across the framework, ensuring predictability. However, your actual business logic within each component remains isolated, flexible, and easy to change.

* **Testability First:** Every layer of the architecture, from ViewModels to business logic handlers, is decoupled and designed to be easily mockable and testable in isolation.

* **Developer Experience Focused:** We aim for minimal boilerplate and a clean, intuitive API. The goal is to make best practices the easiest path forward.

### The Chassis Architecture: A Clean and Pragmatic Approach

At its core, Chassis implements the principles of Clean Architecture to create a clear separation between your UI and your core business logic. When applied correctly, this separation results in a codebase that is significantly easier to maintain, reason about, and evolve.

However, the discipline required for a clean architecture is often traded for short-term development speed, which quickly accumulates technical debt. Chassis addresses this directly by providing a standardized, opinionated structure that makes best practices the path of least resistance, keeping the cognitive load to a minimum.

This structure establishes two primary, predictable, and unidirectional data flows: one for executing actions and another for retrieving data.

#### 1. The Flow of Action (Commands) 🎬

When you need to change the state of your application (e.g., save user data, submit a form), you use a Command. This flow is a one-way street designed to perform an action and ensure side effects are handled in a controlled way.

Flow:
ViewModel ➡️ Command ➡️ Mediator ➡️ Handler ➡️ Data Layer (e.g., Repository)

1. The ViewModel creates and dispatches a Command containing all necessary data.
2. The Mediator routes the command to its specific CommandHandler.
3. The Handler contains the business logic, validating the command and interacting with the Data Layer (like a Repository or an API client) to persist the changes.

#### 2. The Flow of Data (Queries) 📊

When you need to display data in the UI, you use a Query. This is a read-only operation. The flow goes down to fetch the data and then comes back up with the result.

Request Flow:
ViewModel ➡️ Query ➡️ Mediator ➡️ Handler ➡️ Data Layer

Data Return Flow:
ViewModel ⬅️ Data ⬅️ Handler ⬅️ Data Layer

1. The ViewModel dispatches a Query describing the data it needs.
2. The Mediator routes it to the appropriate QueryHandler.
3. The Handler fetches the data from the Data Layer.
4. The requested data is then returned back up the chain to the ViewModel, which prepares it for the UI to display.

  
### What's in the Box? 🎁

Chassis provides a concise set of tools, neatly divided into core architectural components and Flutter-specific helpers, to streamline your development process.

### **chassis:** Core Domain Building Blocks

A pure dart package that provides foundational pieces for building your application's business logic, completely independent of the UI.

* `Mediator`: The central dispatcher that decouples your presentation layer from your business logic handlers. You send a request, and it finds the right handler.

* `Command`, `ReadQuery`, `WatchQuery`: Simple, immutable message classes that represent your use cases:

        Command: An intent to change state (a write operation).

        Read: A request for a one-time data fetch (a read operation).

        WatchQuery: A request to subscribe to a continuous stream of data.

* `Handlers`: The corresponding CommandHandler, ReadHandler, and WatchHandler classes where your actual business logic lives.

* `Disposable`: A standardized interface for managing the lifecycle and cleanup of your services and ViewModels, helping to prevent memory leaks.

### **chassis_flutter:** Flutter Integration & Helpers

A flutter package that provides the MVVM part of chassis. These components seamlessly connect your domain logic to the Flutter widget tree, reducing boilerplate and simplifying state management.

* `ViewModel`: The base class for your presentation logic. It includes convenient methods (e.g., `read`, `watch`, `run`) for easily dispatching Commands and Queries and managing UI state.

* `ViewModelProvider`: A simple and efficient widget for providing your ViewModel instances to the widget tree, making them easily accessible to your UI screens.

* `ConsumerMixin`: A mixin for your StatefulWidgets that simplifies the process of listening to ViewModel changes and automatically rebuilding your UI when the state updates.

## Chassis vs. Existing Solutions (BLoC, Riverpod)

Flutter has a vibrant ecosystem with excellent state management libraries like BLoC and Riverpod. Chassis is not intended to be a "better" state management tool, but rather a more **opinionated architectural framework** that solves a slightly different set of problems.

The key difference lies in the level of architectural guidance and the enforcement of strict decoupling.

### Key Differentiators

| Aspect | BLoC / Riverpod | Chassis |
| :--- | :--- | :--- |
| **Primary Goal** | Provide powerful **state management** and/or dependency injection tools. | Provide a complete, end-to-end **application architecture** based on Clean Architecture principles. |
| **Level of Opinion** | **Flexible.** They are powerful libraries upon which you can build many different architectural patterns. | **Opinionated.** It enforces a specific, consistent data flow (`ViewModel` ➡️ `Mediator` ➡️ `Handler`) to ensure scalability and maintainability. |
| **Core Pattern** | BLoC uses **Event/State streams**. Riverpod uses declarative **Providers** for DI and state. | Uses the **Mediator pattern** to fully decouple the Presentation layer from the Business Logic (Use Case) layer. |
| **Decoupling** | The UI is decoupled from the business logic, but is typically aware of the specific `BLoC` or `Provider` it is interacting with. | The UI layer (`ViewModel`) has **zero knowledge** of who will handle its request. It only sends a message to the Mediator. |

### When to Choose Chassis

Chassis is an ideal choice when:

* **You are starting a large, complex project** and want a standardized, scalable architecture from day one.
* **You are working in a team** and want to enforce consistency and a clear separation of concerns across all developers and features.
* **You want to strictly follow Clean Architecture principles**, and value the true decoupling that the Mediator pattern provides.
* **You want your business logic to be modeled as a set of explicit Use Cases** (`Commands`/`Queries`) that are completely independent of the UI.

### When BLoC or Riverpod Might Be a Better Fit

* **For smaller projects** where a full architectural framework might be overkill.
* **When you prefer a less opinionated solution** and want the flexibility to design your own custom architecture.
