# In-Depth Architecture Guide: The Chassis Framework

## Philosophy & Core Principles

### Introduction

As a software project matures, its complexity inevitably increases. Without a guiding structure, this complexity can lead to tightly coupled components, making the codebase difficult to reason about, modify, and extend. Feature development slows, bug fixes become risky, and testing grows into a daunting task.

Chassis is an opinionated framework that provides a blueprint for building professional, scalable, and maintainable Flutter applications. It addresses complexity by providing a predictable and testable structure, allowing you to focus on building features that matter.

### The Three Pillars of Chassis

The core philosophy of Chassis rests on three battle-tested architectural patterns that work together to create a robust and maintainable application.

#### 1. Clean Architecture

Clean Architecture is a design philosophy that organizes a project into distinct layers to achieve a powerful separation of concerns. The goal is to isolate your core business logic from external details like UI frameworks, databases, and third-party APIs. This is governed by one simple, unbreakable rule: **dependencies can only point inward.** Your business logic should never depend on UI or infrastructure details.

#### 2. Command Query Responsibility Segregation (CQRS)

CQRS provides a formal, message-based API for your business logic by separating operations that change state from those that read it.

* **Commands:** These are messages representing an intent to perform a write operation (e.g., `CreateUserCommand`).
* **Queries:** These are messages representing a request for information (e.g., `GetUserByIdQuery`).

This separation makes the system's capabilities explicit and provides a central point for handling cross-cutting concerns.

#### 3. Model-View-ViewModel (MVVM)

MVVM is a presentation pattern that cleanly separates the UI (the View) from its state and logic (the ViewModel).

* **View:** Renders the UI based on the ViewModel's state and forwards user input.
* **ViewModel:** Holds the UI state, handles presentation logic, and communicates with the business layer.
* **Model:** The state object that the ViewModel exposes for the View to render.

This separation makes the UI layer highly testable and independent of the underlying business rules.

## The Layers of Logic

### Introduction to Logical Layers

While a project is physically organized into files and packages, the logic itself should be thought of in three distinct conceptual layers. Understanding these layers is the key to answering the fundamental architectural question: "Where should this piece of code live?"

### 1. The Business Layer (Domain & Application Logic)

This is the heart and brain of your application. It is pure Dart, platform-agnostic, and has zero dependencies on Flutter or any specific infrastructure. This layer contains both the core, enterprise-wide business rules (**Domain Logic**) and the logic that orchestrates specific use cases by coordinating data and domain rules (**Application Logic**). The `Handlers` are the primary home for Application Logic.
* **Examples:** A `Project` model and a rule that a project's end date cannot be before its start date (Domain Logic). The sequence of steps in a `CreateProjectCommandHandler` that validates input, creates the `Project` model, and saves it via a repository (Application Logic).

### 2. The Infrastructure Layer (Data & Services Logic)

This layer contains the implementation details required to connect the application to the outside world. This logic is concerned with *how* data is fetched, stored, or sent, not *what* the data represents. It provides concrete implementations for contracts defined in the Business Layer.
* **Examples:** `Repository` implementations containing API calls (`http`), database queries (`SQL`), JSON serialization/deserialization, and caching strategies.

### 3. The Presentation Layer (UI Logic)

This layer contains all logic related to the user interface. It includes both the logic for preparing data for display and managing UI state (**Presentation Logic** found in the `ViewModel`) and the logic intrinsically tied to rendering, layout, and animation (**View Logic** found in Flutter widgets).
* **Examples:** Formatting a `DateTime` into a user-friendly string in a `ViewModel` (Presentation Logic). Managing an `AnimationController` or `FocusNode` within a `StatefulWidget` (View Logic).

## Deep Dive - The Core Components

This section defines the role and responsibility of each component in the Chassis architecture, referencing the logical layers defined above.

#### Command & Query

An immutable data class representing a single, specific intention within the application. Its primary responsibility is to act as a formal message, decoupling the requester of an operation from the performer.

* **Should Contain:**
    * Only the data required to perform the operation.
* **Should NOT Contain:**
    * Business logic, validation rules, or any behavior.

#### Handler

A class that processes a single `Command` or `Query`. Its primary responsibility is to contain the **Application Logic** for a specific use case. A `Handler` acts as the orchestrator of a business transaction and can coordinate between multiple repositories or domain services to ensure an operation is completed atomically.

* **Should Contain:**
    * Orchestration logic that coordinates calls to domain models and repositories.
* **Should NOT Contain:**
    * Flutter-specific code.
    * Direct API/database calls.
    * Logic for multiple, unrelated use cases.

#### Repository

A class that implements a contract (an abstract class) defined in the Business Layer. Its primary responsibility is to abstract the data source and contain **Infrastructure Logic**. Repositories are not just simple data-fetchers; they are responsible for crucial tasks like mapping data transfer objects (DTOs) from an API into rich Domain Models and implementing caching strategies to improve performance.

* **Should Contain:**
    * Data fetching, caching, serialization, and mapping logic.
* **Should NOT Contain:**
    * Business rules or application-specific orchestration logic.

#### ViewModel

The "brain" of a specific widget or screen. Its primary responsibility is to hold and manage UI state and contain **Presentation Logic**. The `ViewModel` acts as an adapter, taking generic data from the Business Layer and transforming it into a specific `State` object tailored to the needs of its View. It holds presentation state (e.g., `isLoading`, `errorMessage`), not just raw data.

* **Should Contain:**
    * Logic to format data for display.
    * Handling of user input events.
    * Sending `Commands` or `Queries` to the `Mediator`.
* **Should NOT Contain:**
    * Core business rules.
    * Direct knowledge of infrastructure (like API clients).

#### View

A Flutter widget. Its primary responsibility is to render the UI based on the `ViewModel`'s state and to forward user gestures to the `ViewModel`. A "dumb" view does not mean a static one; it is responsible for managing local, ephemeral state that has no business significance.

* **Should Contain:**
    * **View Logic** such as layout, styling, and animations.
    * Management of `AnimationController`s, `TextEditingController`s, and `FocusNode`s.
* **Should NOT Contain:**
    * Business, application, or presentation logic.
    * Direct calls to the `Mediator` or repositories.

### Guiding Principles

When you're unsure where a piece of logic belongs, use these first principles as a guide. They are thought experiments to help you place your code correctly.

* **"If this logic could run in a simple command-line tool, it belongs in the Business Layer."**
    This is the litmus test for pure business logic. If you can imagine the logic running without any Flutter imports (e.g., calculating a total, validating a password), it belongs in a `Handler` or domain model.

* **"If this logic is about how to fetch, cache, or transform raw data (like JSON) into domain models, it belongs in the Infrastructure Layer (Repository Logic)."**
    This logic deals with external data sources. It's not about what the data means for the business, but about the technical details of retrieving and preparing it.

* **"If this logic is about how to draw something or animate it, it belongs in the Presentation Layer (View Logic)."**
    This logic is intrinsically tied to the Flutter framework and the screen. It lives inside your `StatefulWidget`s.

* **"If this logic is about preparing data for a specific screen, it belongs in the Presentation Layer (ViewModel Logic)."**
    This logic acts as the bridge between raw data and the UI. Formatting dates, managing loading states, or combining data streams for a particular view all belong in the `ViewModel`.

## The Flow of Control

The `Mediator` is the central bus that routes messages (`Commands` and `Queries`) from the Presentation Layer to the Business Layer, ensuring the layers remain completely decoupled.

### Tracing a Command (Write Operation)

1.  **View:** A user taps a "Save" button. The `onPressed` callback calls a method on the `ViewModel`, e.g., `viewModel.saveProjectName('New Name')`.
2.  **ViewModel:** The method creates a command object (`UpdateProjectNameCommand(...)`) and sends it to the central dispatcher: `mediator.run(command)`.
3.  **Mediator:** It looks up the registered handler for `UpdateProjectNameCommand`.
4.  **CommandHandler:** The handler executes the Application Logic, calling the `IProjectRepository` to persist the change.
5.  **Repository:** The concrete implementation in the Infrastructure Layer makes the API call to save the data.

### Tracing a Query (Read Operation)

1.  **ViewModel:** During its initialization, it needs to fetch user data. It creates a query object (`GetUserByIdQuery(...)`) and sends it: `mediator.read(query)`.
2.  **Mediator:** It finds the registered `GetUserByIdQueryHandler`.
3.  **QueryHandler:** The handler executes the logic, calling `IUserRepository.getUserById(...)`.
4.  **Repository:** The implementation fetches data from the data source (e.g., a database), maps it to a `User` domain model, and returns it.
5.  **ViewModel:** The data flows back through the `Mediator`. The `ViewModel` receives the `User` model, updates its internal state, and notifies its listeners.
6.  **View:** The widget listening to the `ViewModel` rebuilds to display the user's data.

## Architectural Trade-offs

### Benefits of the Chassis Approach

* **Testability:** Each layer can be tested in isolation. Business logic can be unit-tested without any UI or infrastructure, and ViewModels can be tested without needing to render widgets.
* **Scalability & Maintainability:** The strict separation of concerns prevents tightly coupled components. This makes the codebase easier to reason about, modify, and extend over time as the application grows.
* **Explicit API:** The complete set of `Command` and `Query` classes serves as a clear, self-documenting list of every feature the application supports.
* **Observability:** The centralized `Mediator` pattern provides a single pipeline for all operations. This makes it easy to implement cross-cutting concerns like logging, performance monitoring, and analytics.

### The Costs & Considerations

* **Boilerplate/Ceremony:** Creating separate classes for messages and handlers requires more upfront effort than a simple method call. This is a deliberate architectural trade-off for the clarity, testability, and maintainability it provides in the long run.
* **Indirection:** The `Mediator` adds a layer of indirection. This can sometimes make it harder to trace the exact flow of code with a simple "go to definition" in the IDE, as the sender of a message does not know about the receiver.