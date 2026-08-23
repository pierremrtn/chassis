# Chassis Implementation Rules

This document formalizes the implementation rules embedded in the Chassis framework using the DO / DON'T / PREFER / AVOID / CONSIDER classification. Each guideline is written as a valid imperative sentence, and the reasoning is explained immediately below.

---

## Architecture & Layering

### DO organize code into four distinct layers: Presentation, Application, Domain, and Infrastructure

Chassis enforces a layered architecture where each layer has clearly defined responsibilities:

- **Presentation** (`presentation/`) — Widgets, ViewModels, State, Events. Depends on message types (application) and chassis_flutter.
- **Application** (`application/`) — Commands, Queries, Handlers. Depends on repository interfaces from domain.
- **Domain** (`domain/`) — Entities, value objects, repository interfaces, domain errors. Depends on nothing inside the project.
- **Infrastructure** (`infrastructure/`) — Repository implementations, third-party adapters. Depends on external SDKs; wired at the composition root.

Prefer a feature-first layout, where each feature owns its four layers; a layer-first layout is acceptable for small apps.

```
lib/
  ├── mediator.dart            # Composition root: @ChassisApp + handler imports
  ├── main.dart                # Chassis.initialize(AppMediator(...)) + runApp
  └── orders/
      ├── presentation/        # Widgets, ViewModels, State, Events
      ├── application/         # Commands, Queries, Handlers
      ├── domain/              # Entities, repository interfaces, domain errors
      └── infrastructure/      # Repository implementations
```

### DO point source code dependencies inward, toward higher-level policies

The Dependency Rule states that Handlers depend on Repository interfaces (not implementations), ViewModels depend on message types (not Handlers or repositories), and Widgets depend on ViewModels (not domain logic). This inversion of control enables testing, as you can substitute implementations without modifying consumers.

```dart
// ✅ Correct: Handler depends on abstraction
class CreateUserCommandHandler
    implements CommandHandler<CreateUserCommand, User> {
  CreateUserCommandHandler({required this.repository});

  final UserRepository repository; // Interface dependency

  @override
  Future<User> run(CreateUserCommand command) =>
      repository.create(command.name, command.email);
}

// ❌ Incorrect: Handler depends on concrete implementation
class CreateUserCommandHandler {
  final FirestoreUserRepository _repository; // Tight coupling
}
```

### DON'T allow ViewModels to access Repositories directly

The ViewModel is architecturally restricted to being a transformation layer for the UI. It must delegate to a Handler by dispatching a message, which creates a natural checkpoint where logic belongs in tested, reusable components. This prevention of logic leaks maintains the integrity of your architecture over time.

### DO follow the unidirectional data flow: UI → ViewModel → Mediator → Handler → Repository

Chassis enforces a specific path for all data operations. This guardrail ensures that a junior developer and a senior architect produce code with the same structural footprint, reducing code review friction and technical debt accumulation.

---

## Command-Query Separation

### DO separate operations into Commands (writes) and Queries (reads)

Command-Query Separation states that methods should either change state or return data, never both. When you see a Query in code, you know it's safe to call multiple times without unintended consequences. When you see a Command, you understand that state will change and execution should be deliberate.

```dart
// Command: Mutates state
final class UpdateUserEmailCommand extends Command<void> {
  UpdateUserEmailCommand({required this.userId, required this.newEmail});
  final String userId;
  final String newEmail;
}

// Query (Read): One-time data fetch without mutation
final class GetUserQuery extends ReadQuery<User> {
  GetUserQuery({required this.userId});
  final String userId;
}

// Query (Watch): Continuous stream without mutation
final class WatchUserQuery extends WatchQuery<User> {
  WatchUserQuery({required this.userId});
  final String userId;
}
```

### DO use `ReadQuery` for one-time data fetches and `WatchQuery` for reactive streams

This distinction routes each message to the appropriate handler type and the appropriate ViewModel method: a `ReadQuery` goes through `read()`, a `WatchQuery` through `watch()`. Passing a `ReadQuery` to `watch()` is a compile error, preventing accidental stream subscriptions for one-time operations.

```dart
// One-time fetch (in a ViewModel)
void loadUser(String userId) => read(
      GetUserQuery(userId: userId),
      current: state.user,
      onState: (user) => setState(state.copyWith(user: user)),
    );

// Continuous stream
void watchUser(String userId) => watch(
      WatchUserQuery(userId: userId),
      current: state.user,
      onState: (user) => setState(state.copyWith(user: user)),
    );
```

### PREFER `WatchQuery` streams for most data in reactive Flutter applications

In modern reactive Flutter applications, most data should come from `WatchQuery` streams to keep the UI automatically synchronized with data changes. Reserve `ReadQuery` for cases where you need the current state only once, such as loading a profile when a screen opens.

---

## Messages (Commands & Queries)

### DO declare messages as `final class` using `extends`

Commands and Queries must be declared as `final class` and use `extends` (not `implements`) for their base type. The base types are declared `base`/`sealed`, so `implements Command<T>` outside the chassis package is rejected *by the compiler* — the resolution chain is protected by the language, not by convention. Declaring the message `final` additionally prevents subclassing, which would break the Mediator's exact-runtime-type handler lookup at dispatch time.

```dart
// ✅ Correct: final class + extends
final class CreateOrderCommand extends Command<Order> {
  CreateOrderCommand({
    required this.userId,
    required this.items,
  });

  final String userId;
  final List<OrderItem> items;
}

final class GetOrderQuery extends ReadQuery<Order> {
  GetOrderQuery({required this.orderId});
  final String orderId;
}

// ❌ Incorrect: implements — rejected by the compiler (Command is a base class)
class CreateOrderCommand implements Command<Order> { /* ... */ }

// ❌ Incorrect: not final — allows subclassing which breaks type resolution
class CreateOrderCommand extends Command<Order> { /* ... */ }
```

### DO make messages immutable data structures

Both Commands and Queries must be immutable to prevent accidental mutations during handling. Use `final` fields so the message cannot be mutated after construction. Immutability also makes messages safe to log, serialize, or replay without worrying about shared mutable state.

### DO make messages self-contained with all information needed to execute

Commands and Queries should carry all the information needed to execute the operation. Avoid holding references to repositories or services — those belong in Handlers.

### DO name messages after business operations, not technical implementations

A Command should describe what you want to accomplish — `UpdateUserEmail`, `ProcessPayment`, `SubmitOrder` — not how the system will accomplish it. A Query should describe the data being requested — `GetOrderSummary`, `WatchActiveTickets` — not the underlying data source.

### CONSIDER adding validation in message constructors for early failure detection

Validation in constructors provides early failure detection, catching invalid states before they reach Handlers. This applies equally to Commands and Queries whose parameters have known constraints.

```dart
final class UpdateUserEmailCommand extends Command<void> {
  UpdateUserEmailCommand({
    required this.userId,
    required this.newEmail,
  }) : assert(newEmail.length > 0, 'Email cannot be empty');

  final String userId;
  final String newEmail;
}
```

### CONSIDER overriding `params` on messages to make traces readable

Commands and Queries expose a `Map<String, Object?> get params` getter (empty by default) used by `toString()` and by `LoggingMiddleware`. Overriding it makes a trace read `UpdateUserEmailCommand{userId: u1}` instead of a bare type name, which pays off the first time you debug a production log.

`params` is also the message's *identity*: two messages of the same type with equal `params` are the same operation — the contract that caching or deduplication middlewares (and mock-based tests) rely on. A field that affects the operation but is left out of `params` breaks that contract.

```dart
final class UpdateUserEmailCommand extends Command<void> {
  UpdateUserEmailCommand({required this.userId, required this.newEmail});

  final String userId;
  final String newEmail;

  @override
  Map<String, Object?> get params => {'userId': userId};
}
```

### DON'T include secrets in `params`

`params` flows into logs, traces, and any `ChassisLogSink` you plug into `LoggingMiddleware`. Passwords, tokens, and other credentials must never appear there — expose only the fields that are safe to persist in telemetry. A `LoginCommand` would expose its `username` but never its `password`.

---

## Naming Conventions

### DO follow the `[Verb][Resource]Command` pattern for Command names

Use an imperative, present-tense verb describing the business operation (e.g., `Create`, `Update`, `Register`, `Assign`, `Delete`), followed by the entity the command acts upon, and always end with `Command`.

```text
// good
CreateProjectCommand
UpdateProjectNameCommand
SubmitOrderCommand

// bad
ProjectCreator
DoProjectUpdate
```

### DO follow the `[Get/Find][Resource]Query` pattern for ReadQuery names

Use `Get` as the standard verb, or `Find` if the result might not exist. Append `By[Criteria]` if the resource is queried by a specific parameter.

```text
// good
GetProjectByIdQuery
GetAllUsersQuery
FindCustomerByEmailQuery
```

### DO follow the `Watch[Resource]Query` pattern for WatchQuery names

Use `Watch` as the standard verb for continuous stream subscriptions. `Observe` is an acceptable alternative.

```text
// good
WatchProjectByIdQuery
WatchAllActiveTicketsQuery
WatchOrderStatusQuery
```

### DO name Handlers after their full message name, plus `Handler`

The Handler's name is the message name followed by `Handler`: `CreateProjectCommand` → `CreateProjectCommandHandler`, `GetProjectByIdQuery` → `GetProjectByIdQueryHandler`. This mechanical naming convention ensures absolute predictability and discoverability — and it keeps handler names unambiguous when a Command and a Query share a resource name. Everything the framework derives (registration, build-time checks) keys off the *message*, never the handler, so renaming a handler is a local refactor with zero blast radius.

```text
// good
CreateProjectCommandHandler
GetProjectByIdQueryHandler
WatchOrderStatusQueryHandler

// bad — dropping the message suffix loses the Command/Query distinction
CreateProjectHandler
GetProjectByIdHandler
```

### DON'T prefix repository interfaces with `I`

Dart convention gives the interface the good name — `OrderRepository`, not `IOrderRepository` — and lets implementations carry the qualifier (`FirestoreOrderRepository`, `InMemoryOrderRepository`). The generated mediator also derives constructor parameter names from dependency type names, so an `I` prefix would leak into every registration site (`iOrderRepository:`).

### AVOID abbreviations in identifiers

`formatQty`, `calcBmr`, `usrRepo` make every reader expand them mentally;
`formatQuantity`, `calculateBasalMetabolicRate`, `userRepository` cost a few
characters once, at writing time. Keep only universally established short
forms (`id`, `url`, `api`, `min`/`max`) and domain units that *are* the word
(`kcal`, `kg`, `ml`).

---

## Handlers

### DO keep Handlers stateless

Handlers are plain Dart classes that receive and process messages. They must be stateless and testable in complete isolation from the UI and the framework, allowing for pure logic verification with no Flutter dependencies.

### DO use `implements` (not `extends`) for the Handler interface

Handlers must use `implements` for their base type (`CommandHandler`, `ReadHandler`, `WatchHandler`). This is the inverse of the message rule: messages use `extends` for Mediator type resolution, while Handlers use `implements` because they fulfill a behavioral contract rather than inheriting shared state. The `implements` keyword also forces you to provide explicit method signatures, preventing accidental reliance on base class internals.

```dart
// ✅ Correct: implements
@chassisHandler
class CreateOrderCommandHandler
    implements CommandHandler<CreateOrderCommand, Order> {
  @override
  Future<Order> run(CreateOrderCommand command) async { /* ... */ }
}

// ❌ Incorrect: extends
@chassisHandler
class CreateOrderCommandHandler
    extends CommandHandler<CreateOrderCommand, Order> {
  @override
  Future<Order> run(CreateOrderCommand command) async { /* ... */ }
}
```

### DO inject dependencies via the Handler constructor

Handlers receive Repositories and Services via constructor injection, following the Dependency Inversion Principle. This pattern keeps handlers testable and prevents them from creating their own dependencies. The code generator injects the dependencies through the constructor — see [Code Generation](#code-generation).

```dart
@chassisHandler
class CreateOrderCommandHandler
    implements CommandHandler<CreateOrderCommand, Order> {
  CreateOrderCommandHandler({
    required this.orderRepository,
    required this.paymentGateway,
  });

  final OrderRepository orderRepository;
  final PaymentGateway paymentGateway;

  @override
  Future<Order> run(CreateOrderCommand command) async {
    // Business logic here
  }
}
```

### DO implement a single responsibility per Handler

Each Handler focuses on a single responsibility: receive a message, execute business logic, call repositories as needed, and return results. Unlike patterns like Bloc that encourage coarse-grained classes handling many events, Chassis enforces one Handler per Command or Query.

### DO model a multi-step flow as a single Command whose Handler composes the repositories involved

A flow like "log in, then load the profile" is one use case, so it is one Command. The Handler is the Application-layer orchestrator: it depends on every port the flow needs and coordinates them. Sequencing several dispatches from a ViewModel — chaining a second `run` inside an `onSuccess` callback — moves application logic into the Presentation layer, exactly the leak the architecture exists to prevent. Single responsibility (see above) is about the *use case*, not about one repository call per handler.

```dart
// ✅ One use case, one Command — the Handler orchestrates both ports
@chassisHandler
class LoginCommandHandler implements CommandHandler<LoginCommand, void> {
  LoginCommandHandler({
    required this.authRepository,
    required this.profileRepository,
  });

  final AuthRepository authRepository;
  final ProfileRepository profileRepository;

  @override
  Future<void> run(LoginCommand command) async {
    await authRepository.login(command.username, command.password);
    await profileRepository.refresh();
  }
}

// ❌ The flow is sequenced in the ViewModel — application logic in Presentation
void login(String username, String password) => run(
      LoginCommand(username: username, password: password),
      onError: (error, stack) => sendEvent(LoginFailedEvent(error)),
      onSuccess: (_) => run(
        RefreshProfileCommand(), // orchestration leaked into a callback chain
        onState: (profile) => setState(state.copyWith(profile: profile)),
      ),
    );
```

When the second step is a standing *reaction* to state rather than a step of this flow — the profile should reload whenever the authenticated user changes, no matter why it changed — prefer solving it in the Infrastructure layer: let `ProfileRepository` observe the auth state stream, and no layer orchestrates anything.

### DON'T dispatch Commands or Queries from Handlers or Middleware

Handlers and middleware sit *inside* the dispatch pipeline; only the Presentation layer initiates dispatch. Handler-to-handler dispatch dissolves the guarantees the mediator provides: the dependency graph is no longer visible in constructor signatures (and cycles become possible), and every nested dispatch re-enters the middleware chain, so one user gesture shows up as several units of work to logging, transaction, or retry middleware. The generator enforces the handler half of this rule — declaring a `Mediator`-typed (or generated-mediator-typed) constructor dependency fails the build.

Reuse belongs one level down. When two handlers need the same behavior, extract it into a service or repository method and inject it into both — the composition stays visible, testable with plain fakes, and outside the pipeline.

```dart
// ❌ Handler reaching back into the pipeline — rejected at build time
@chassisHandler
class LoginCommandHandler implements CommandHandler<LoginCommand, void> {
  LoginCommandHandler({required this.authRepository, required this.mediator});

  final AuthRepository authRepository;
  final Mediator mediator; // build error

  @override
  Future<void> run(LoginCommand command) async {
    await authRepository.login(command.username, command.password);
    await mediator.run(RefreshProfileCommand());
  }
}

// ✅ Shared behavior lives in a service injected into both handlers
@chassisHandler
class LoginCommandHandler implements CommandHandler<LoginCommand, void> {
  LoginCommandHandler({
    required this.authRepository,
    required this.profileSynchronizer,
  });

  final AuthRepository authRepository;
  final ProfileSynchronizer profileSynchronizer;

  @override
  Future<void> run(LoginCommand command) async {
    await authRepository.login(command.username, command.password);
    await profileSynchronizer.refresh();
  }
}
```

For middleware the same boundary holds mechanically: hooks receive `(message, next)` and nothing else. A middleware tempted to trigger business logic — say, dispatching a logout command on authentication failure — is infrastructure logic in disguise: detect the condition at its source (an HTTP interceptor), surface it through a repository's state stream, and let the UI react. See [Core Architecture](01_core_architecture.md#middleware) for the full session-expiry example.

### DO create business-specific error classes for domain failures

Handlers should throw typed exceptions that represent meaningful business failures rather than relying on generic exceptions. Typed errors allow the ViewModel to react differently to distinct failure modes (e.g., showing a retry button for a network error versus a validation message for bad input), and they make error-handling logic explicit and exhaustive.

```dart
// ✅ Business-specific errors
class InsufficientInventoryException implements Exception {
  const InsufficientInventoryException(this.missingItems);
  final List<String> missingItems;
}

class PaymentDeclinedException implements Exception {
  const PaymentDeclinedException(this.reason);
  final String reason;
}
```

```dart
// ❌ Generic errors obscure intent
throw Exception('Not enough items'); // What kind of failure? How should the UI react?
```

### DO document thrown exceptions using `///` doc comments in Handlers and Repositories

Every Handler and Repository method that can throw should declare its failure modes in its documentation comment. Consumers of these methods — other Handlers, ViewModels — need to know which exceptions to anticipate without reading the implementation. This also serves as a contract between layers.

```dart
/// Creates an order by validating inventory, processing payment, and persisting the result.
///
/// Throws [InsufficientInventoryException] if any requested item is out of stock.
/// Throws [PaymentDeclinedException] if the payment gateway rejects the charge.
class CreateOrderCommandHandler
    implements CommandHandler<CreateOrderCommand, Order> {
  @override
  Future<Order> run(CreateOrderCommand command) async {
    // ...
  }
}
```

---

## File Organization

### DO define each Command or Query alongside its Handler in a dedicated file

Each message-handler pair should live in its own file. Co-locating the message definition with its handler makes navigation immediate: finding a Command immediately reveals the logic that handles it, and vice versa. This also prevents large files from accumulating unrelated handlers.

```
lib/
  └── orders/
      └── application/
          ├── create_order_command.dart       # CreateOrderCommand + CreateOrderCommandHandler
          ├── get_order_query.dart            # GetOrderQuery + GetOrderQueryHandler
          └── watch_order_status_query.dart   # WatchOrderStatusQuery + WatchOrderStatusQueryHandler
```

### DO create one file per Command/Query-Handler pair

Splitting each pair into its own file enforces the single-responsibility principle at the file level and makes the project's capabilities scannable from the directory listing alone. When a new developer opens the `orders/application/` folder, they immediately see every operation the order domain supports.

### DO use package imports everywhere under `lib/`

Relative imports that climb the tree (`import '../../../../mediator.dart'`)
hide the dependency direction, break on file moves, and read as noise. Use the
canonical `package:` form for every import under `lib/`; the standard
`always_use_package_imports` lint enforces it.

---

## Code Generation

### DO annotate Handlers with `@chassisHandler` to trigger code generation

The `@chassisHandler` annotation marks a handler for automatic registration in the generated mediator. The `chassis_builder` collects annotated handlers reachable from the `@ChassisApp` library's import graph (plus declared `@chassisModule` packages) and produces the mediator class with every handler registered in its constructor. Without this annotation the handler is invisible to the generator — it will not be wired, and its message will fail the build as unhandled (see below).

```dart
@chassisHandler
class CreateOrderCommandHandler
    implements CommandHandler<CreateOrderCommand, Order> {
  const CreateOrderCommandHandler({
    required this.orderRepository,
    required this.paymentGateway,
  });

  final OrderRepository orderRepository;
  final PaymentGateway paymentGateway;

  @override
  Future<Order> run(CreateOrderCommand command) async {
    // Business logic
  }
}
```

### PREFER named constructor parameters for handler dependencies

An annotated handler needs an unnamed generative constructor; its parameters — positional or named — are the dependencies the generated mediator injects, each passed back the way it is declared. Prefer named parameters, especially with two or more dependencies: registration sites and tests read unambiguously, and adding a dependency cannot silently swap two same-typed arguments.

```dart
// ✅ Preferred: named dependencies — unambiguous at every call site
@chassisHandler
class CreateOrderCommandHandler
    implements CommandHandler<CreateOrderCommand, Order> {
  const CreateOrderCommandHandler({
    required this.orderRepository,
    required this.inventoryService,
  });

  final OrderRepository orderRepository;
  final InventoryService inventoryService;
}

// Acceptable for a single dependency: positional
@chassisHandler
class DeleteOrderCommandHandler
    implements CommandHandler<DeleteOrderCommand, void> {
  const DeleteOrderCommandHandler(this._orderRepository);

  final OrderRepository _orderRepository;
}
```

### DO declare the composition root in a dedicated `lib/mediator.dart`

Place `@ChassisApp` on the library directive of `lib/mediator.dart`. This file has exactly two jobs: carry the annotation, and hold the imports that make every handler reachable from the generator's import-graph walk (directly or through feature barrels). The generator emits the mediator in the adjacent `mediator.chassis.dart`: a `class AppMediator extends Mediator` whose *only* member is a constructor taking every deduplicated handler dependency as a required named parameter and registering all handlers. There are no per-message methods and nothing else to generate — the mediator's public API is the `run`/`read`/`watch` it inherits.

The import-graph walk never crosses package boundaries: handlers living in another package are contributed by declaring that package's `@chassisModule` class in `@ChassisApp(modules: [...])`.

```dart
// lib/mediator.dart — the composition root
@ChassisApp(mediatorName: 'AppMediator')
library;

import 'package:chassis/chassis.dart';

// These imports make the handlers reachable from the generator's walk.
import 'package:app/orders/application/application.dart';
import 'package:app/users/application/application.dart';

export 'mediator.chassis.dart';

// Generated in mediator.chassis.dart:
// class AppMediator extends Mediator {
//   AppMediator({
//     required OrderRepository orderRepository,
//     required PaymentGateway paymentGateway,
//     required UserRepository userRepository,
//   }) {
//     registerCommandHandler(CreateOrderCommandHandler(
//       orderRepository: orderRepository,
//       paymentGateway: paymentGateway,
//     ));
//     // ... every reachable handler
//   }
// }
```

### DO give every reachable Command and Query a handler

A concrete Command or Query reachable from the `@ChassisApp` import graph with no `@chassisHandler` handler is a **build error** — chassis fails the build instead of letting the dispatch throw `HandlerNotRegisteredError` at runtime. This is the framework's flagship guarantee, enforced at the declaration site: since ViewModels dispatch message objects directly, the "does a handler exist?" proof cannot live at the call site, so the builder proves it once for the whole graph.

For a message whose handler is not written yet, opt out explicitly with `@unhandledMessage` — the annotation is a visible, greppable TODO rather than a silent gap.

```dart
@unhandledMessage // handler lands in the next commit
final class ExportReportCommand extends Command<void> {
  ExportReportCommand({required this.reportId});
  final String reportId;
}
```

### DO run `dart run build_runner build` after adding or changing a handler

The generated mediator is only as fresh as the last build. After adding, renaming, or changing the constructor of any handler, re-run the generator (or keep `dart run build_runner watch` running during development). No `build.yaml` is required — the builder applies itself to any package that depends on `chassis_builder`.

### DON'T edit generated `.chassis.dart` files

Generated files are overwritten on every build. If the generated output looks wrong, fix the source — the handler's constructor, the message's constructor, or the annotation site — and rebuild.

---

## ViewModel

### DO use the `ViewModel<State, Event>` base class for all ViewModels

ViewModels serve as the bridge between business logic and the widget tree. They hold current UI state, translate user actions into message objects dispatched through `run`/`read`/`watch`, and emit events for one-time occurrences. A ViewModel never references the generated mediator class — it depends only on message types, and dispatch is routed through the mediator installed by `Chassis.initialize` (see [Dependency Wiring](#dependency-wiring)).

```dart
class UserProfileViewModel extends ViewModel<UserProfileState, UserProfileEvent> {
  UserProfileViewModel({super.mediator}) : super(UserProfileState.initial());
}
```

### DO forward the `{super.mediator}` constructor parameter as the testing seam

`ViewModel(T initial, {Mediator? mediator})` — the optional `mediator` overrides the application mediator installed by `Chassis.initialize` and is resolved lazily at the first dispatch. Production code never passes it (`UserProfileViewModel()`); tests pass a fake (`UserProfileViewModel(mediator: fakeMediator)`), which always wins over the global. Forwarding it with `{super.mediator}` costs one parameter and keeps every ViewModel testable without touching global state.

```dart
// ✅ The seam is there when the test needs it
class UserProfileViewModel extends ViewModel<UserProfileState, UserProfileEvent> {
  UserProfileViewModel({super.mediator}) : super(UserProfileState.initial());
}

// ❌ No seam: this ViewModel can only be tested through Chassis.initialize —
// global state shared across the whole test suite
class UserProfileViewModel extends ViewModel<UserProfileState, UserProfileEvent> {
  UserProfileViewModel() : super(UserProfileState.initial());
}
```

### DO use immutable state classes with `copyWith` for state updates

State immutability ensures predictable behavior. The `copyWith` pattern creates new state objects rather than mutating existing ones, making state transitions explicit and debuggable.

```dart
class UserProfileState {
  const UserProfileState({required this.user, required this.isEditing});

  final Async<User> user;
  final bool isEditing;

  UserProfileState copyWith({Async<User>? user, bool? isEditing}) {
    return UserProfileState(
      user: user ?? this.user,
      isEditing: isEditing ?? this.isEditing,
    );
  }

  static UserProfileState initial() {
    return UserProfileState(user: Async.loading(), isEditing: false);
  }
}
```

### DO use `Async<T>` to wrap all asynchronous data in state

The `Async<T>` sealed union models the complete lifecycle of asynchronous operations — `Loading`, `Data`, and `Error` — preventing common UI bugs where loading states are not handled.

### DO dispatch message objects through `run()`, `read()`, and `watch()`

Each method takes the message itself — a `Command` for `run()`, a `ReadQuery` for `read()`, a `WatchQuery` for `watch()` — dispatches it through the installed mediator, and reports the lifecycle as `Async<T>` states. Operations are keyed by the message's runtime type by default: dispatches of the same command class share their `RunPolicy`, and a re-`watch` of the same query class *replaces* the previous subscription (pass distinct explicit `key`s to watch several instances of one query class concurrently). Pass `current:` so loading and error emissions carry the existing data instead of blanking the UI.

```dart
void watchUser(String userId) => watch(
      // Re-calling with a new id replaces the previous subscription:
      // watches are keyed by query type by default.
      WatchUserQuery(userId: userId),
      current: state.user,
      onState: (user) => setState(state.copyWith(user: user)),
    );

void deleteUser(String userId) => run(
      DeleteUserCommand(userId: userId),
      onSuccess: (_) => sendEvent(UserDeletedEvent()),
      onError: (error, stack) => sendEvent(DeleteUserFailedEvent(error)),
    );
```

Dispatch failures never crash the call site: a throwing handler — even one that throws synchronously — surfaces as an `AsyncError` through the callbacks.

### DO cover the error path of every dispatch with `onState` or `onError`

The callback contract is additive: `onState` (if provided) fires for **every** transition — loading, data, error — and `onSuccess` (`run`/`read`) / `onData` (`watch`) / `onError` are conveniences fired *after* it for their respective transition. `onError` receives `(Object error, StackTrace stack)`. Providing only `onSuccess` is the "invisible failure" anti-pattern: on failure nothing updates, nothing is emitted, and the user stares at a stale screen while the error vanishes. Every `run`, `read`, and `watch` must include `onState` or `onError`.

bad
```dart
void submit() => run(
      SubmitOrderCommand(items: state.items),
      // A failure is invisible: no state transition, no event, no message.
      onSuccess: (order) => sendEvent(OrderConfirmedEvent(order.id)),
    );
```

good
```dart
void submit() => run(
      SubmitOrderCommand(items: state.items),
      current: state.order,
      onState: (order) => setState(state.copyWith(order: order)),
      onSuccess: (order) => sendEvent(OrderConfirmedEvent(order.id)),
    );
```

### DON'T await inside a ViewModel

A ViewModel method is synchronous and expression-bodied: it builds a message, hands it to `run`/`read`/`watch`, and returns — all asynchrony lives in the dispatch machinery and the handler. An `await` in a ViewModel is always one of two leaks. Multi-step business logic (`await login; await refresh`) belongs in a single handler (see [Handlers](#handlers)). Platform and UI async — image picker, permission prompts, biometrics, share sheet — belongs in the *widget*: the widget awaits it, guards `context.mounted` (the `use_build_context_synchronously` lint enforces this) and disables the button while awaiting (two concurrent `pickImage` calls throw `PlatformException(already_active)`), then passes plain data to a synchronous ViewModel method.

bad
```dart
// ❌ Platform async and awaited dispatch inside the ViewModel
Future<void> changeAvatar() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (file == null) return;
  await run(
    UpdateAvatarCommand(file.path),
    onState: (avatar) => setState(state.copyWith(avatar: avatar)),
  );
}
```

good
```dart
// ✅ ViewModel: synchronous and expression-bodied
void changeAvatar(XFile file) => run(
      UpdateAvatarCommand(file.path),
      current: state.avatar,
      onState: (avatar) => setState(state.copyWith(avatar: avatar)),
    );

// ✅ Widget: owns the platform interaction (button disabled while awaiting)
final pickButton = ElevatedButton(
  onPressed: () async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (!context.mounted || file == null) return;
    context.read<ProfileViewModel>().changeAvatar(file);
  },
);
```

### CONSIDER setting a `RunPolicy` when concurrent dispatches of the same message collide

Runs sharing a key (by default, the message class) are arbitrated by their `RunPolicy`: `concurrent` (default — everyone runs), `restartable({debounce})` (latest wins — for search-as-you-type and refetches), `droppable` (first wins — for double-submit protection), `sequential` (queued in order). Note that `restartable` does **not** cancel the underlying execution — only the superseded run's callbacks are cut; the network call completes and its side effects land.

```dart
void search(String term) => read(
      SearchUsersQuery(term: term),
      policy: const RunPolicy.restartable(debounce: Duration(milliseconds: 300)),
      current: state.results,
      onState: (results) => setState(state.copyWith(results: results)),
    );

void submitPayment() => run(
      SubmitPaymentCommand(cartId: state.cartId),
      policy: const RunPolicy.droppable(), // a second tap resolves with the in-flight result
      onState: (receipt) => setState(state.copyWith(receipt: receipt)),
    );
```

### DON'T implement business logic directly inside ViewModels

ViewModels cannot accidentally implement business logic because they lack direct access to repositories. They must delegate to a Handler by dispatching a message. This prevents logic leaks and ensures that business rules live in tested, reusable Handlers.

---

## State vs Events

### DO use state for persistent data that determines UI rendering

State represents what should appear on screen. It is held by the ViewModel and observed by widgets through `ChangeNotifier`.

### DO use events for one-time occurrences like navigation, snackbars, and dialogs

Events fire once per occurrence through a stream, regardless of widget rebuilds. No manual cleanup is required.

```dart
sealed class CheckoutEvent {}
class PaymentSuccessEvent implements CheckoutEvent {
  const PaymentSuccessEvent(this.orderId);
  final String orderId;
}
class NavigateToOrderConfirmationEvent implements CheckoutEvent {
  const NavigateToOrderConfirmationEvent(this.orderId);
  final String orderId;
}
```

### DO carry the error object in failure events

A failure event that stores `error.toString()` destroys pattern matching: the listener can no longer switch on the domain error type to choose between retry, message, or navigation — it holds an opaque string. Carry the error *object* (the domain error, or a dedicated type) and translate it to user-facing text at the edge, in the widget that consumes the event.

bad
```dart
class DeleteUserFailedEvent implements UserEvent {
  const DeleteUserFailedEvent(this.message);
  final String message; // the type is gone — nothing to match on
}

void deleteUser() => run(
      DeleteUserCommand(userId),
      onError: (error, stack) => sendEvent(DeleteUserFailedEvent(error.toString())),
    );
```

good
```dart
class DeleteUserFailedEvent implements UserEvent {
  const DeleteUserFailedEvent(this.error);
  final Object error;
}

void deleteUser() => run(
      DeleteUserCommand(userId),
      onError: (error, stack) => sendEvent(DeleteUserFailedEvent(error)),
    );
```

### DON'T model one-time occurrences as nullable state properties

Modeling events as nullable state properties (e.g., `String? snackbarMessage`) causes rebuilds to replay events, requires manual cleanup by nulling out properties after consumption, and pollutes the state object with ephemeral data.

```dart
// ❌ Don't do this
class BadState {
  final String? snackbarMessage;  // Will replay on every rebuild
  final String? navigationRoute;  // Causes navigation loops
  BadState({this.snackbarMessage, this.navigationRoute});
}

// ✅ Do this
sealed class GoodEvent {}
class ShowSnackbarEvent implements GoodEvent {
  const ShowSnackbarEvent(this.message);
  final String message;
}
```

---

## Using freezed

[freezed](https://pub.dev/packages/freezed) pairs naturally with chassis on the presentation and domain side — it generates the `copyWith`/`==`/`toString` that immutable state classes and entities need, and a chassis app already runs `build_runner`, so the marginal cost of one more generator is small. It does *not* pair with messages, which come with their own identity contract.

### CONSIDER generating state classes and entities with freezed

Hand-written `copyWith` is mechanical and drifts silently: add a field, forget its `copyWith` parameter, and the compiler says nothing while state updates quietly drop the field. freezed derives `copyWith`, `==`, and `toString` from a single declaration, and `Async<T>` fields compose like any other value. The hand-written form (see [ViewModel](#viewmodel)) remains perfectly acceptable — the rule there only requires immutability and `copyWith`, not a specific tool.

```dart
@freezed
abstract class FavoritesState with _$FavoritesState {
  const factory FavoritesState({
    @Default(Async<List<Favorite>>.loading()) Async<List<Favorite>> favorites,
    @Default(false) bool isEditing,
  }) = _FavoritesState;
}
```

### CONSIDER modeling event families as freezed sealed unions

An event family is a sealed hierarchy (see [State vs Events](#state-vs-events)), and freezed's union syntax declares one in fewer lines while giving every case `==` and `toString`. The generated case classes are public, so event listeners pattern-match on them exactly as they would on hand-written ones — and a failure case still carries the error *object*, never a string.

```dart
@freezed
sealed class FavoritesEvent with _$FavoritesEvent {
  const factory FavoritesEvent.toggleFailed(Object error) = ToggleFailed;
  const factory FavoritesEvent.allCleared() = AllCleared;
}

// In the event listener — same pattern matching as a hand-written family:
void onEvent(FavoritesEvent event) {
  switch (event) {
    case ToggleFailed(:final error): /* ... */
    case AllCleared(): /* ... */
  }
}
```

### DON'T declare Commands or Queries as freezed classes

A message is not missing anything freezed provides. `Command`, `ReadQuery`, and `WatchQuery` already define structural equality and logging-safe `toString` in terms of `params` (see [Messages](#messages-commands-queries)), and `copyWith` is dead weight on an object constructed at the dispatch site and consumed by one handler.

Annotating a message buys nothing and breaks things in the current freezed major (3.x). The factory-constructor form is shape-incompatible outright: freezed 3 requires those classes to be `abstract` or `sealed`, while messages are concrete `final class`es. The generative-constructor form ("simple" classes, supported since freezed 3) is the closest fit, since a plain generative constructor can keep the mandatory `extends Command<R>` clause — but the `_$X` mixin it requires brings its own `==`, `hashCode`, and `toString` computed over *all* fields, and in Dart, mixin members override the ones inherited from the superclass. That silently replaces the params-based identity that caching and deduplication middlewares and mock-based ViewModel tests rely on, and `toString` stops being secret-safe: `Command.toString` prints only `params`, where a field like a password is deliberately omitted; freezed prints every field. You still write `params` by hand either way — freezed knows nothing about it.

bad
```dart
@freezed
final class LoginCommand extends Command<void> with _$LoginCommand {
  LoginCommand({required this.username, required this.password});

  @override
  final String username;
  @override
  final String password;

  // _$LoginCommand overrides ==/hashCode/toString from Command:
  // identity is no longer params-based, and toString prints the password.
  @override
  Map<String, Object?> get params => {'username': username};
}
```

good
```dart
final class LoginCommand extends Command<void> {
  LoginCommand({required this.username, required this.password});

  final String username;
  final String password;

  @override
  Map<String, Object?> get params => {'username': username}; // never the password
}
```

Reserve freezed for state, entities, and events; keep messages as plain classes.

---

## UI Integration

### PREFER rendering `Async<T>` with an inline `switch` expression

`Async<T>` is sealed, so a `switch` expression is exhaustive: the compiler forces every case — data, loading, error — to produce a widget, which is the whole point of the type. Reserve `AsyncBuilder` for when you need its `maintainState` behavior — keeping the previous data on screen through a refetch instead of flashing a spinner.

```dart
// Simple rendering: the compiler proves all three cases are handled.
final header = switch (context.select((UserViewModel vm) => vm.state.user)) {
  AsyncData(:final value) => UserHeader(user: value),
  AsyncLoading() => const UserHeaderSkeleton(),
  AsyncError(:final error) => UserHeaderError(error: error),
};

// Anti-flicker refetch: AsyncBuilder keeps the previous list visible
// while a new page loads (maintainState defaults to true).
final todoList = AsyncBuilder<List<Todo>>(
  state: context.select((TodoViewModel vm) => vm.state.todos),
  builder: (context, todos) => TodoList(todos: todos),
  errorBuilder: (context, error) => TodoListError(error: error),
);
```

### DON'T collapse an `Async<T>` error into a default with `valueOrNull ?? fallback`

`state.day.valueOrNull ?? JournalDay.empty(date)` renders an `AsyncError` as
if it were data: on a screen's primary content the error becomes
indistinguishable from a legitimately empty value, and nobody — user,
developer, logs — knows anything failed.

Degrading on error IS sometimes the right design: secondary or optional
content whose absence is an acceptable rendering (a badge, an avatar ring, a
coach quote); a section that falls back while the error is surfaced through
another channel (screen-level banner, event → snackbar); `maintainState`
keeping the previous data through a transient refetch error. The problem with
`??` is that it cannot express that this was a decision — the same characters
also spell "I forgot the error case".

So route every collapse through an explicit channel: a dedicated `AsyncError`
branch in the `switch` — or an `errorBuilder` on `AsyncBuilder` — even one
that returns the default or `SizedBox.shrink()`, states the degradation in
code, is reviewable, and is greppable. A data-shaped fallback that encodes
a business case ("document absent → empty day") belongs at the data layer,
decided once in the repository — by the time a value is an `AsyncError`, it
is not data anymore.

bad
```dart
// Decision or accident? The reader cannot tell — and on primary
// content it silently masks permission/network failures.
JournalSections(
  day: state.day.valueOrNull ?? JournalDay.empty(state.selectedDate),
)
```

good
```dart
// Primary content: the error reaches a visible branch.
final daySection = switch (state.day) {
  AsyncData(:final value) => JournalSections(day: value),
  AsyncLoading() => const JournalSkeleton(),
  AsyncError(:final error) => JournalUnavailableBanner(error: error),
};

// Optional content: degradation is the design — stated explicitly.
final quoteSection = switch (state.quote) {
  AsyncData(:final value) => CoachQuoteCard(quote: value),
  AsyncLoading() || AsyncError() => const SizedBox.shrink(), // deliberate
};
```

### DO read state with `context.select` and dispatch actions with `context.read`

`context.select` scopes the rebuild to the selected slice — the widget rebuilds only when that value changes, not on every `notifyListeners`. Use the inferred-parameter form (`(TodoViewModel vm) => ...`), never explicit type arguments. In callbacks, use `context.read` — a callback needs the ViewModel once and must not subscribe. Reserve `context.watch` for a widget that genuinely consumes the whole state.

```dart
// Build: rebuilds only when the todo list changes.
final todos = context.select((TodoViewModel vm) => vm.state.todos);

// Callback: dispatch without subscribing.
final addButton = ElevatedButton(
  onPressed: () => context.read<TodoViewModel>().addTodo(title),
  child: const Text('Add'),
);
```

### DO use `ViewModelProvider.withEventListener` to listen to events from a ViewModel you provide

`ViewModelProvider.withEventListener` co-locates event handling with ViewModel provision and manages the subscription lifecycle automatically. Use the `EventListener` widget when a descendant subtree needs to listen to a ViewModel provided by an ancestor, and `EventListenerMixin` only when the event handler needs access to local state (controllers, local variables) held inside a `State` object.

```dart
ViewModelProvider.withEventListener<CheckoutViewModel, CheckoutEvent>(
  create: (_) => CheckoutViewModel(),
  onEvent: (context, viewModel, event) {
    switch (event) {
      case PaymentSuccessEvent(:final orderId):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment successful! Order #$orderId')),
        );
      // ...
    }
  },
  child: const CheckoutScreen(),
);
```

### DO use `ViewModelProvider` for ViewModel dependency injection

`ViewModelProvider` integrates with the `provider` package and manages the ViewModel lifecycle automatically, ensuring proper creation and disposal. Since ViewModels resolve the mediator themselves, `create` takes no wiring — there is nothing to thread through the widget tree.

```dart
ViewModelProvider<TodoViewModel>(
  create: (_) => TodoViewModel(),
  child: const TodoScreen(),
)
```

---

## Mediator

### DO dispatch all operations through the Mediator

The Mediator is the single entry point for business logic: every dispatch traverses the middleware chain, and handler wiring is proven at build time. ViewModels participate implicitly — their `run`/`read`/`watch` dispatch through the mediator installed by `Chassis.initialize` — and never hold a mediator reference of their own. The generated `AppMediator` adds no API on top of the base class: it is a registration constructor, and dispatch always goes through the inherited `run`/`read`/`watch`.

### CONSIDER using Middleware for cross-cutting concerns

Middleware intercepts messages before they reach handlers, enabling logging, performance monitoring, authentication checks, and caching to be implemented once rather than duplicated across handlers. For tracing, wire the built-in `LoggingMiddleware`; for custom concerns, extend `MediatorMiddleware` and override only the hooks you need — each has a pass-through default.

```dart
// Built-in tracing: dispatch, outcome, duration, errors with stack traces
mediator.addMiddleware(LoggingMiddleware());
```

```dart
// Custom middleware
class AuditMiddleware extends MediatorMiddleware {
  AuditMiddleware(this._audit);

  final AuditService _audit;

  @override
  Future<R> onRun<R>(Command<R> command, NextRun<R> next) async {
    await _audit.record(command);
    return next(command);
  }
}
```

### DO report failures through `CrashReportingMiddleware`

The middleware chain is chassis's observability channel — there is deliberately no `BlocObserver`/`ProviderObserver` equivalent. `CrashReportingMiddleware` reports every failure crossing the mediator (including errors flowing through watch streams) and then rethrows — reporting never swallows a failure. Classification uses Dart's own distinction: an `Error` is a programming bug and reports as `fatal: true`; anything else is an expected domain failure and reports as non-fatal.

```dart
final mediator = AppMediator(/* dependencies */)
  ..addMiddleware(LoggingMiddleware())
  ..addMiddleware(CrashReportingMiddleware(
    (error, stack, {required fatal}) => FirebaseCrashlytics.instance
        .recordError(error, stack, fatal: fatal),
  ));
```

### DON'T catch `ChassisError`

`HandlerNotRegisteredError` and `DuplicateHandlerError` extend `Error` under the sealed `ChassisError`: they signal wiring bugs — a missing `@chassisHandler`, a stale build, a duplicate manual registration — never runtime conditions to recover from. Fix the registration and rebuild; a `catch` that swallows them turns a build-time-preventable bug into silent misbehavior. (This is also why they are `Error`s, not `Exception`s: an `on Exception` clause written for domain failures cannot accidentally absorb them, and `CrashReportingMiddleware` classifies them as fatal.)

---

## Repository

### DO define Repository interfaces to abstract data operations

A Repository interface defines what data operations are possible without specifying how they are implemented. This abstraction enables testing and allows you to swap implementations — in-memory for development, Firebase for production, or a mock for tests — without changing business logic or UI code.

---

## Testing

### DO test Handlers in complete isolation using mocked Repository interfaces

Handlers are pure Dart classes testable without the Flutter framework. Inject mock repositories via the constructor and verify business logic without UI or database dependencies.

```dart
test('CreateUserCommandHandler validates email', () async {
  final mockRepository = MockUserRepository();
  final handler = CreateUserCommandHandler(repository: mockRepository);

  final command = CreateUserCommand(name: 'John', email: '');

  expect(
    () => handler.run(command),
    throwsA(isA<ValidationException>()),
  );

  verifyNever(() => mockRepository.create(any(), any()));
});
```

### DO test ViewModels by passing a fake mediator to the constructor

The `{super.mediator}` parameter is the seam: pass a mock of the base `Mediator` and stub `run`/`read`/`watch` with the expected message. Messages have structural equality — same type, equal `params` — so a stub set up with an equal message instance matches the one the ViewModel dispatches, with no argument matchers (another reason to override `params`: a field left out of it is invisible to equality). This isolates the ViewModel from every downstream dependency, including the generated mediator.

```dart
class MockMediator extends Mock implements Mediator {}
```

```dart
test('loadUser watches the user', () {
  final mediator = MockMediator();
  when(() => mediator.watch(WatchUserQuery(userId: '1')))
      .thenAnswer((_) => Stream.value(User(id: '1', name: 'John')));

  final viewModel = UserViewModel(mediator: mediator);
  viewModel.loadUser('1');

  verify(() => mediator.watch(WatchUserQuery(userId: '1'))).called(1);
});
```

### DON'T call `Chassis.initialize` in tests

The global mediator is process-wide state: initializing it in one test leaks into every test that runs after, and parallel suites step on each other. The constructor override always wins over the global, so `MyViewModel(initialState, mediator: fakeMediator)` needs no global setup and no teardown. (`Chassis.reset` exists for restoring a clean state, but a suite that needs it is usually a suite that should have used the constructor seam.)

### DO test widgets by mocking the ViewModel

Widget tests verify UI rendering and user interaction handling without executing business logic. Mock the ViewModel to control state and verify method calls.

### DO provide mocked ViewModels with `ViewModelProvider<T>.value` in widget tests

A ViewModel IS a `Listenable`, and the `provider` package's `debugCheckInvalidValueType` rejects raw `Provider<T>.value` for listenable values — the test throws at `pumpWidget`. `ViewModelProvider<T>.value` provides an existing instance without taking ownership of its lifecycle, which is exactly what a test that constructed the mock itself needs.

bad
```dart
await tester.pumpWidget(
  Provider<TodoViewModel>.value( // throws at pumpWidget: value is a Listenable
    value: mockViewModel,
    child: const TodoScreen(),
  ),
);
```

good
```dart
await tester.pumpWidget(
  MaterialApp(
    home: ViewModelProvider<TodoViewModel>.value(
      value: mockViewModel,
      child: const TodoScreen(),
    ),
  ),
);
```

### PREFER testing events through StreamControllers in widget tests

Simulating events through a `StreamController` allows testing UI reactions to ViewModel events without executing real business logic. This verifies that snackbars, dialogs, and navigation occur correctly in response to events.

---

## Resource Management

### DO rely on `watch()` for subscription lifecycle management

Every subscription started with `watch()` is tracked by the framework: it is cancelled when the ViewModel is disposed, replaced when a new `watch` reuses its key, and cancellable early through the returned `WatchHandle`. For the rare stream subscribed outside `watch()`, register it with `autoDisposeStreamSubscription` so disposal cancels it.

### DO use `autoDispose` for any `Disposable` resource the ViewModel owns

Resources registered with `autoDispose` are cleaned up in reverse order when the ViewModel is disposed. This prevents common Flutter errors from forgotten cleanups.

### DON'T manually manage stream subscriptions in ViewModels

The framework handles subscription lifecycle through `watch()` and `autoDisposeStreamSubscription`. Manual management introduces the risk of forgotten cancellations and memory leaks.

---

## Dependency Wiring

### DO install the mediator with `Chassis.initialize` before `runApp`

`main()` is the only place that sees infrastructure: it constructs the repository implementations, passes them to the generated `AppMediator` constructor — the application's dependency manifest, where a missing dependency is a compile error — and installs the result with `Chassis.initialize`. Every ViewModel resolves that mediator lazily at its first dispatch; if initialization was forgotten, the first dispatch throws an actionable `StateError` naming the fix.

```dart
// lib/main.dart
import 'package:app/mediator.dart';
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  Chassis.initialize(
    AppMediator(
      orderRepository: FirestoreOrderRepository(),
      paymentGateway: StripePaymentGateway(),
      userRepository: FirestoreUserRepository(),
    )
      ..addMiddleware(LoggingMiddleware())
      ..addMiddleware(CrashReportingMiddleware(
        (error, stack, {required fatal}) => FirebaseCrashlytics.instance
            .recordError(error, stack, fatal: fatal),
      )),
  );

  runApp(const MyApp());
}
```

The composition root itself — the `@ChassisApp` annotation and the imports that make handlers reachable — lives in `lib/mediator.dart` (see [Code Generation](#code-generation)); `main.dart` only constructs and installs.

### DON'T store the mediator in a global variable

The old pattern — `late final AppMediator mediator;` initialized at startup and referenced from ViewModels and route builders — is dead. `Chassis.initialize` already provides the single installation point, and ViewModels resolve it themselves, so the global's only remaining effect is to invite bypasses: presentation code importing `main.dart` (a backward import — presentation must never depend on the composition root) and raw `await mediator.run(...)` calls that skip the ViewModel pipeline (`RunPolicy`, `Async` lifecycle, error reporting). The only other legitimate path from a mediator to a ViewModel is the constructor seam, in tests.

bad
```dart
late final AppMediator mediator; // global — anyone can import and bypass

void initializeDependencies() {
  mediator = AppMediator(todoRepository: InMemoryTodoRepository());
}

void main() {
  initializeDependencies();
  runApp(const MyApp());
}
```

good
```dart
void main() {
  Chassis.initialize(
    AppMediator(todoRepository: InMemoryTodoRepository())
      ..addMiddleware(LoggingMiddleware()),
  );
  runApp(const MyApp());
}
```
