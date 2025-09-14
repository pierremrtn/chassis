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

#### 3. Bringing it All Together: ViewModel, Mediator, and Handler 🤝

This entire architecture is built on the interplay between three key components: the ViewModel, the Mediator, and the Handler.

    The ViewModel is the Initiator. It lives in the presentation layer and translates user interactions into Command and Query messages. It knows what action needs to happen, but not how or where it will be executed.

    The Mediator is the Router. It receives a message from the ViewModel and, based on its type, finds the single, specific Handler registered to process it. This completely decouples the UI from the business logic.

    The Handler is the Executor. This is where your actual business logic lives. Each Handler is a focused class responsible for a single task: it validates the request, performs the necessary operations, and calls any required external services (like a repository or an API client).

This three-part structure—Initiator (ViewModel), Router (Mediator), and Executor (Handler)—ensures a clean, predictable, and highly testable flow for every feature in your application.


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

Of course. Here is a rewritten comparison section for the README that is more argued, realistic, and technically focused. It avoids the "salesy" tone and instead presents a balanced view of the trade-offs, aiming to help a developer make an informed architectural decision.

***

## Architectural Philosophy: Chassis vs. State Management Libraries

Flutter's ecosystem includes mature, powerful libraries like BLoC and Riverpod. Chassis is not a replacement for these; it operates at a different level of abstraction and aims to solve a different set of architectural challenges.

The fundamental difference is one of **scope**. BLoC and Riverpod are primarily **tools for state management and dependency injection**. Chassis is an **opinionated framework for application architecture** that uses state management as one of its components.

---

### Core Distinctions

This table outlines the practical differences in philosophy and implementation.

| Aspect | BLoC / Riverpod | Chassis |
| :--- | :--- | :--- |
| **Primary Goal** | To provide and manage the lifecycle of state and dependencies, and to efficiently rebuild the UI when state changes. | To enforce a consistent, scalable, and decoupled application structure based on Clean Architecture, MVVM, and CQRS principles. |
| **Locus of Business Logic** | **Flexible.** Business logic often resides within the `Bloc` or `Notifier`, but can be delegated to services or repositories. The developer decides on a case-by-case basis. | **Prescriptive.** Business logic **must** live in dedicated `Handler` classes. This is a non-negotiable rule of the framework, ensuring logic is always isolated from the presentation layer. |
| **Coupling** | **Flexible.** Business logic can live inside a `Bloc`/`Notifier`, be delegated to a Repository, or placed in a separate service/use case class. This flexibility requires strong team discipline to prevent logic from becoming scattered and creating "fat" providers or repositories. | **Prescriptive and Centralized.** Business logic **must** live in a dedicated `Handler` (which represents a specific use case). This architectural rule prevents logic from leaking into the presentation or data layers, creating a single, predictable, and testable location for every action in your app. |
| **Developer Freedom** | **High.** You are given powerful primitives and are free to design your own application structure around them. | **Low.** You are given a strict structure to follow. The framework makes many architectural decisions for you in exchange for consistency. |

---

### Understanding the Trade-offs

Choosing an architectural approach involves trade-offs. The right choice depends on your project's scale, team structure, and long-term goals.

#### When to Prefer BLoC or Riverpod:

BLoC and Riverpod are an excellent fit for a wide range of applications, particularly when:

* **Flexibility is paramount.** You want powerful tools without a framework dictating your entire project structure.
* **Rapid development is needed for smaller features.** The boilerplate for simple state changes is minimal. You can create a Notifier or Bloc and consume it immediately.
* **Your team already has strong, established architectural conventions.** If your team is disciplined in its approach to separating concerns, the enforcement offered by Chassis may be redundant.
* **The project is small to medium-sized.** For simpler applications, the structural overhead of Chassis can be unnecessary and may slow down development.

**The Trade-off:** Their flexibility means that consistency relies entirely on developer discipline. In large teams or over a long project lifecycle, this can lead to "architectural drift," where different features are implemented in vastly different ways.

#### When to Choose Chassis:

Chassis is designed for scenarios where architectural consistency and scalability are the highest priorities:

* **You are building a large, complex application.** The framework is designed to manage complexity by ensuring every feature is structured identically.
* **Consistency across a large team is critical.** Chassis provides non-negotiable guardrails, ensuring that all developers, regardless of experience level, follow the same pattern. This makes the codebase predictable and easier to navigate.
* **A strict separation of concerns is a project requirement.** The Mediator pattern ensures your business logic (use cases) is completely decoupled from the UI, making it independently testable and reusable.
* **You are explicitly implementing Clean Architecture or CQRS.** Chassis provides a ready-made, practical implementation of these patterns, saving you the effort of building the foundation yourself.

**The Trade-off:** The structure comes at a cost. There is more upfront boilerplate for simple operations (e.g., creating `Command`, `Query`, and `Handler` files for a single feature). This "ceremony" can feel like overkill for small-scale tasks and applications.