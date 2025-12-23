1. [00_quick_start.md] - The "Hello World"

Goal: Prove the framework's value in under 5 minutes through a working example. Tone: Direct, action-oriented. No theory, just practice.

    Prerequisites & Installation:

        pubspec.yaml setup (chassis, chassis_flutter, chassis_builder, build_runner).

        build.yaml configuration.

    The Counter Example (Step-by-Step):

        Repository: Create CounterRepository with annotated methods (@generateQueryHandler, @generateCommandHandler).

        Generation: Run build_runner to see the output.

        ViewModel: Create CounterViewModel consuming the Mediator.

        UI: Create CounterPage using AsyncBuilder.

    What You Just Built: A brief breakdown of the flow (UI → ViewModel → Mediator → Repo) to de-mystify the example.

2. [01_core_architecture.md] - The Principles

Goal: Establish the mental model. Explain why the code is structured this way. Tone: Educational, high-level, software engineering focus.

    Layered Architecture:

        Definition of the three layers: Presentation (UI), Application (Logic), Infrastructure (Data).

        Strict dependency rules (UI depends on Logic; Logic is independent of UI).

    Command-Query Separation (CQS):

        The principle of separating Reads (Queries) from Writes (Commands).

        Why this improves reasoning about side effects.

    The Mediator Pattern:

        How the Mediator decouples the Sender (ViewModel) from the Receiver (Handler).

        Diagram: (Sequence Diagram showing ViewModel -> Mediator -> Handler).

        Benefit: Discoverability (Code as a catalog of capabilities).

3. [02_business_logic.md] - The Manual Implementation

Goal: Teach the internal mechanics. Essential for the "10% complex cases" and understanding the generated code. Tone: Technical deep-dive.

    Anatomy of Messages:

        Command<T>: Immutable intent to change state.

        ReadQuery<T> vs WatchQuery<T>: One-time fetch vs Reactive streams.

    The Handler Contract:

        Structure of a CommandHandler, ReadHandler, and WatchHandler.

        Dependency Injection: How handlers receive Repositories/Services via constructor.

    Testing Strategy (Unit Testing):

        How to test logic in isolation using pure Dart tests.

        Example: Mocking a repository to test a complex CommandHandler.

    When to Write Manually:

        Complex orchestration (multi-step flows).

        Transaction management.

        Cross-cutting business rules (e.g., validation logic that spans multiple domains).

4. [03_code_generation.md] - The Automation

Goal: Explain how to use the builder to eliminate boilerplate for standard operations. Tone: Pragmatic. "Convention over Configuration".

    The 90/10 Principle:

        Using automation for standard CRUD (90%) vs Manual for complex logic (10%).

    Annotations Reference:

        @generateQueryHandler: Mapping Future to ReadQuery and Stream to WatchQuery.

        @generateCommandHandler: Mapping Future<void> or Future<T> to Command.

        @chassisHandler: Marking manual handlers for auto-registration.

    The Generated Mediator:

        How dependency injection is automated.

        Type-safe extension methods (mediator.updateUser(...) vs mediator.run(...)).

    Architectural Enforcement:

        How the generator prevents wiring errors at compile time.

5. [04_ui_integration.md] - The Presentation Layer

Goal: Explain how to consume data and handle interactions in Flutter. Tone: Functional. "UI is a function of State".

    The ViewModel Pattern:

        Role: Transforming Domain State into UI State.

        Unidirectional Data Flow: Commands go up, Data comes down.

    Modeling State with Async<T>:

        The 3 states: AsyncLoading, AsyncData, AsyncError.

        Why sealed classes ensure exhaustiveness (no unhandled states).

    The AsyncBuilder Widget:

        Standardizing the loading/error/data UI pattern.

        Anti-Flickering: Explanation of the maintainState property for smooth refetches.

    Handling One-Time Events:

        Distinction between State (Persistent) and Events (Ephemeral - Snackbars, Navigation).

        Using ConsumerMixin to listen to events.

    Widget Testing:

        How to mock the Mediator to test UI in isolation.

---

Appendices (To be included in relevant sections or as separate files if needed)

    Glossary: Definitions of Command, Query, Handler, Mediator, DTO.

    FAQ:

        "How do I handle global errors?" (Middleware).

        "Can I use Chassis with other state management?" (Comparison/Coexistence).