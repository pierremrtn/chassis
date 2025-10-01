# Architecture Guide: Building Scalable Flutter Applications with Chassis

## Introduction: The Architecture Challenge

If you are reading this guide, you have likely built at least one Flutter application that started simple and gradually became difficult to work with. Perhaps you have experienced the frustration of changing a seemingly isolated feature only to watch errors cascade through unrelated parts of your application. Or maybe you have struggled to maintain consistency across a codebase as different developers approach similar problems with different patterns.

These challenges are not unique to Flutter, but Flutter's flexibility makes them particularly relevant. State management frameworks provide powerful tools for managing application state and dependencies, but they intentionally avoid prescribing how to organize your application architecture. This flexibility is valuable, particularly for teams that want to establish their own conventions. However, it requires each team to answer fundamental organizational questions: Where should business logic live? How should operations be discovered? How should read and write operations be distinguished? How should cross-cutting concerns like logging and error handling be implemented consistently?

Chassis is an architectural framework that provides definitive answers to these questions through enforced structure. Rather than requiring teams to establish and maintain their own architectural patterns, Chassis prescribes a complete organizational system with clear boundaries between presentation logic, business logic, and infrastructure. The framework makes application capabilities explicit and discoverable through commands and queries, enforces separation of concerns through layered architecture, and provides standardized patterns for implementing features consistently across large codebases.

This represents a deliberate trade-off. Where state management solutions prioritize flexibility, Chassis prioritizes structure. Where other frameworks leave organizational decisions to development teams, Chassis makes opinionated choices that reduce flexibility in exchange for consistency and discoverability. This trade-off is not universally correct but addresses specific needs that emerge in certain types of applications and team structures.

This guide will teach you the Chassis architecture by explaining the organizational challenges that arise in Flutter development and demonstrating how the framework's structure addresses these challenges. By understanding the reasoning behind each architectural decision, you will be able to evaluate whether Chassis's trade-offs align with your project's needs and apply these principles effectively if you choose to adopt the framework.

## The Organizational Challenge

Consider building a collaborative project management application where teams create projects, assign tasks, and see real-time updates as other members make changes. This feature exposes several organizational challenges that become more pronounced as applications scale and team size increases.

Most experienced Flutter developers already separate concerns using state management solutions like BLoC or Riverpod. A typical BLoC implementation might look like this:

```dart
class ProjectBloc extends Bloc<ProjectEvent, ProjectState> {
  final ProjectRepository _repository;
  
  ProjectBloc(this._repository) : super(ProjectInitial()) {
    on<LoadProject>((event, emit) async {
      emit(ProjectLoading());
      try {
        final project = await _repository.getProject(event.projectId);
        emit(ProjectLoaded(project));
      } catch (e) {
        emit(ProjectError(e.toString()));
      }
    });
    
    on<UpdateProjectName>((event, emit) async {
      try {
        await _repository.updateProjectName(event.projectId, event.newName);
        final project = await _repository.getProject(event.projectId);
        emit(ProjectLoaded(project));
      } catch (e) {
        emit(ProjectError(e.toString()));
      }
    });
  }
}
```

This approach successfully separates presentation from logic and provides clear state management. The BLoC depends on a repository abstraction, follows established patterns, and handles state transitions cleanly. This represents competent application architecture by most standards.

However, as applications grow beyond a certain threshold, several organizational questions become increasingly important. These are not deficiencies in BLoC or Riverpod but rather questions that these frameworks intentionally leave to development teams to answer.

**How do you understand the complete scope of a feature when making changes?** Consider the common scenario of modifying project creation logic to add validation rules or change default values. In a typical BLoC architecture, the investigation path requires multiple steps. You might start by searching for project-related files, finding the ProjectBloc, examining its event handlers to identify creation logic, then following repository calls to understand data persistence. If business rules exist in separate service classes, you must locate those as well. The complete picture of project creation emerges gradually through exploration across multiple locations.

**How do you enforce consistent patterns?** Each BLoC represents an independent implementation of similar concerns. Some BLoCs might validate input before calling repositories. Others might perform validation in the repository itself. Some might log operations, while others do not. Some might implement optimistic updates, while others wait for server confirmation. Without prescribed structure, developers make reasonable but different choices, creating inconsistency across features.

**Where should complex business logic live?** Simple operations that directly call repository methods have an obvious structure. But what about operations that require validation, permission checks, coordination between multiple repositories, and notification of other system components? Should this logic live in the BLoC? In a separate service class? In the repository? State management frameworks do not prescribe answers, leaving each team to establish and maintain their own conventions.

**How do you implement cross-cutting concerns consistently?** Operations often require logging for debugging, analytics tracking for business intelligence, performance monitoring for optimization, and error reporting for reliability. Implementing these concerns consistently across dozens or hundreds of BLoCs requires discipline and vigilance. A single point through which all operations flow would enable uniform implementation, but state management frameworks do not provide this structure.

These questions have answers in any well-architected application. Teams establish conventions, document patterns, conduct code reviews, and maintain consistency through discipline. This approach works successfully for many applications. Chassis provides an alternative: a framework that answers these questions through enforced structure rather than relying on team conventions.

The framework makes specific choices about how these patterns integrate, providing a complete system rather than individual components. This integration is both the framework's strength and its limitation. Teams gain consistency and structure but sacrifice flexibility to organize code according to their preferences. The final section of this guide examines these trade-offs in detail and provides guidance for evaluating whether Chassis aligns with your project's needs.


## Building the Solution: Architectural Principles

Chassis is built on three foundational architectural patterns that work together to create a complete system. Let us examine each pattern, understand the specific problem it solves, and see how they combine into a cohesive whole.

### Clean Architecture: Enforcing the Dependency Rule

The core insight of Clean Architecture is that dependencies should only point inward, toward the core business logic. Your domain logic—the rules that make your application unique—should not depend on implementation details like which HTTP library you use, which database you choose, or even which UI framework you build with.

This is not just theoretical purity. It solves concrete problems. Consider what happens when your API provider changes their authentication mechanism, or when you decide to add offline support with local caching, or when you need to expose your business logic through a CLI tool for administrators. If your business logic depends on infrastructure details, all of these changes ripple through your entire application.

Clean Architecture prevents this by organizing code into layers:

The **Domain Layer** contains your business entities and rules. In our project management example, this layer would include the Project model itself, rules about valid project states, and the contracts that define how data can be accessed (repository interfaces). This layer is pure Dart with no dependencies on Flutter, HTTP, or databases.

The **Application Layer** contains use case logic—the orchestration of domain rules to accomplish specific tasks. This is where you would put the logic for creating a new project, which might involve validating the input, checking user permissions, creating the Project entity, saving it through a repository, and then notifying other parts of the system. This layer depends on the Domain Layer but knows nothing about infrastructure.

The **Infrastructure Layer** contains the implementation details. This is where you put your HTTP clients, database connections, JSON parsing, and caching logic. This layer implements the contracts defined in the Domain Layer but can be swapped out without affecting business logic.

The **Presentation Layer** contains your Flutter widgets and ViewModels. This layer depends on the Domain and Application layers to access business logic, but it should not depend on infrastructure details.

The critical rule is that dependencies only point inward. The Domain Layer depends on nothing. The Application Layer depends only on the Domain Layer. The Infrastructure and Presentation layers depend on inner layers but never on each other.

This structure solves the hard-coding problem we identified earlier. Your widgets no longer depend directly on HTTP. Your business logic does not know whether data comes from a REST API, GraphQL, or local storage. Each layer can evolve independently as long as the contracts between them remain stable.

### CQRS: Separating Reads and Writes

Command Query Responsibility Segregation is a pattern that enforces a formal separation between operations that change state (commands) and operations that query state (queries). This might seem like an arbitrary distinction, but it solves a critical problem: it makes the capabilities of your system explicit and discoverable.

Without CQRS, your application's capabilities are hidden in method names across various classes. How do you find all the ways a project can be modified? You have to hunt through repositories, services, and BLoCs looking for methods. There is no central registry of what your application can do.

With CQRS, every operation is represented by a message class. Want to know how projects can be modified? Look at the Command classes. Want to understand how data can be queried? Look at the Query classes. The entire API of your business logic is explicit and discoverable.

Consider the project management example. Without CQRS, you might have:

```dart
abstract class IProjectRepository {
  Future<Project> getProject(String id);
  Future<Project> updateProjectName(String id, String name);
  Future<void> assignTask(String projectId, String taskId, String userId);
  Future<List<Project>> searchProjects(String query);
  // ... dozens more methods
}
```

This repository interface becomes a dumping ground for every project-related operation. There is no structure, and it is unclear which methods are related or which operations are complex use cases versus simple data access.

With CQRS in Chassis, operations are represented as message objects:

```dart
// Commands (write operations)
class UpdateProjectNameCommand extends Command<Project> {
  final String projectId;
  final String newName;
  const UpdateProjectNameCommand(this.projectId, this.newName);
}

class AssignTaskCommand extends Command<void> {
  final String projectId;
  final String taskId;
  final String userId;
  const AssignTaskCommand(this.projectId, this.taskId, this.userId);
}

// Watch Queries (stream operations)
class WatchProjectByIdQuery implements WatchQuery<Project> {
  final String projectId;
  const WatchProjectByIdQuery(this.projectId);
}

// Read Queries (read operations)
class SearchProjectsQuery implements ReadQuery<List<Project>> {
  final String searchTerm;
  const SearchProjectsQuery(this.searchTerm);
}
```

Each operation is now a first-class object. This provides several benefits. The operations are self-documenting—you can see exactly what data each operation requires. The operations are discoverable—your IDE can show you all commands and queries at once. The operations can be logged, traced, and analyzed because they flow through a single mediator.

Chassis extends the basic CQRS pattern with an additional distinction critical for Flutter applications. Dart provides two fundamental asynchronous types: Future represents a single value that arrives at some point, while Stream represents a sequence of values delivered over time. Traditional CQRS treats all queries uniformly, but Flutter applications require explicit handling of these temporal patterns.

Chassis separates queries into ReadQuery for point-in-time snapshots and WatchQuery for continuous observation. A ReadQuery returns Future and completes after providing a single response. A WatchQuery returns Stream and continues emitting updates as data changes.

We will see how ViewModels use these query types when we examine the Presentation layer.

### The Mediator: Decoupling Senders from Receivers

The final piece of the puzzle is the Mediator pattern. At first glance, this might seem like unnecessary indirection. Why not just let your ViewModel call repository methods directly? The answer involves understanding how applications evolve.

Consider what happens as your application grows. You need to add logging to track which operations users perform most frequently. You want to implement analytics to measure operation latency. You need to add caching to reduce server load. You want to implement optimistic updates for better perceived performance. You need to queue failed operations for retry when the network is restored.

Without a mediator, you have two bad options. You can implement these concerns in every ViewModel, leading to massive duplication. Or you can implement them in the repositories, mixing infrastructure concerns with cross-cutting concerns and making the repositories harder to test.

The Mediator provides a third option: a single pipeline through which all operations flow. This provides several powerful capabilities.

**Discoverability:** Every operation in your application goes through the mediator. You can query it to find out what operations are available. You can generate documentation from the registered handlers. You can build developer tools that show you all possible commands and queries.

**Observability:** Because all operations flow through a single point, you can add middleware that logs every operation, measures timing, tracks errors, and reports analytics. This is trivial to implement once and benefits your entire application.

**Testability:** Your ViewModels do not depend on concrete repository implementations. They depend only on the mediator, which is easy to mock. You can test your presentation logic by verifying that the correct commands and queries are dispatched, without needing to stub out complex repository interfaces.

**Flexibility:** You can change how operations are handled without modifying the callers. Want to add caching? Implement it in the handler. Want to batch similar queries? Intercept them in the mediator. Want to implement an undo system? Track commands as they flow through the mediator.

The trade-off is indirection. When you call `mediator.run(UpdateProjectNameCommand(id, name))`, you cannot immediately see the implementation by clicking "go to definition" in your IDE. The connection between command and handler is established through registration, not direct method calls.

This trade-off is deliberate. The indirection is precisely what enables the benefits. By breaking the compile-time link between sender and receiver, you create flexibility for evolution and opportunities for interception. For large applications, this flexibility is worth the cost.

The framework addresses this navigation challenge through a recommended practice: co-locating handler definitions with their corresponding command or query definitions. Rather than separating commands, queries, and handlers into different directory structures, place each handler in the same file as the message it handles:

```dart
// domain/use_cases/update_project_name.dart
class UpdateProjectNameCommand extends Command<Project> {
  final String projectId;
  final String newName;
  const UpdateProjectNameCommand(this.projectId, this.newName);
}

class UpdateProjectNameCommandHandler 
    implements CommandHandler<UpdateProjectNameCommand, Project> {
  // Handler implementation
}
```

This organization preserves navigability. Developers examining code that dispatches UpdateProjectNameCommand can immediately see the handler implementation in the same file. The mediator's indirection remains, but the practical navigation cost diminishes substantially. This represents a pragmatic compromise between the mediator's architectural benefits and developer experience concerns.

## Seeing It All Together: The Chassis Architecture

Now that we understand each pattern individually, let us see how they combine into a cohesive architecture by walking through our project management feature implemented properly with Chassis.

### Layer One: The Domain

The domain layer defines what a project is and what contracts are needed to work with projects. This code is pure Dart, platform-agnostic, and dependency-free:

```dart
// domain/models/project.dart
class Project {
  final String id;
  final String name;
  final String description;
  final ProjectStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;
  
  const Project({
    required this.id,
    required this.name,
    required this.description,
    required this.status,
    required this.createdAt,
    this.completedAt,
  });
  
  // Domain rules can be enforced in methods
  bool canBeCompletedBy(String userId, List<String> projectOwners) {
    return projectOwners.contains(userId) && status == ProjectStatus.inProgress;
  }
}

enum ProjectStatus { draft, inProgress, completed, archived }

// domain/data/project_repository.dart
abstract class IProjectRepository {
  Future<Project> getProjectById(String id);
  Stream<Project> watchProjectById(String id);
  Future<Project> updateProject(Project project);
  Future<List<Project>> searchProjects(String query);
}
```

Notice that this layer defines the repository interface but does not implement it. It declares what operations are needed without specifying how they work. This is the dependency inversion principle in action—the domain layer defines its needs, and outer layers fulfill them.

### Layer Two: The Application (Use Cases)

The application layer contains the business logic organized as commands, queries, and their handlers. Each handler is a single use case that orchestrates domain logic and repositories:

```dart
// domain/use_cases/update_project_name_command.dart
class UpdateProjectNameCommand extends Command<Project> {
  final String projectId;
  final String newName;
  
  const UpdateProjectNameCommand(this.projectId, this.newName);
}

// domain/use_cases/update_project_name_command_handler.dart
class UpdateProjectNameCommandHandler 
    implements CommandHandler<UpdateProjectNameCommand, Project> {
  final IProjectRepository _repository;
  final IValidationService _validationService;
  final IAnalyticsService _analytics;
  
  UpdateProjectNameCommandHandler(
    this._repository,
    this._validationService,
    this._analytics,
  );
  
  @override
  Future<Project> run(UpdateProjectNameCommand command) async {
    // Business logic: validation
    if (!_validationService.isValidProjectName(command.newName)) {
      throw ValidationException('Project name must be between 3 and 100 characters');
    }
    
    // Business logic: orchestration
    final existingProject = await _repository.getProjectById(command.projectId);
    final updatedProject = existingProject.copyWith(name: command.newName);
    final result = await _repository.updateProject(updatedProject);
    
    // Cross-cutting concern: analytics
    await _analytics.trackEvent('project_renamed', {
      'project_id': command.projectId,
      'old_name': existingProject.name,
      'new_name': command.newName,
    });
    
    return result;
  }
}

// domain/use_cases/read_project_by_id_query.dart
class ReadProjectByIdQuery implements ReadQuery<Project> {
  final String projectId;
  const ReadProjectByIdQuery(this.projectId);
}

// domain/use_cases/read_project_by_id_query_handler.dart
class ReadProjectByIdQueryHandler 
    implements ReadHandler<ReadProjectByIdQuery, Project> {
  final IProjectRepository _repository;
  
  ReadProjectByIdQueryHandler(this._repository);
  
  @override
  Future<Project> read(ReadProjectByIdQuery query) {
    return _repository.getProjectById(query.projectId);
  }
}

// domain/use_cases/watch_project_by_id_query.dart
class WatchProjectByIdQuery implements WatchQuery<Project> {
  final String projectId;
  const WatchProjectByIdQuery(this.projectId);
}

// domain/use_cases/watch_project_by_id_query_handler.dart
class WatchProjectByIdQueryHandler 
    implements WatchHandler<WatchProjectByIdQuery, Project> {
  final IProjectRepository _repository;
  
  WatchProjectByIdQueryHandler(this._repository);
  
  @override
  Stream<Project> watch(WatchProjectByIdQuery query) {
    return _repository.watchProjectById(query.projectId);
  }
}
```

Notice how the handler for UpdateProjectNameCommand coordinates between multiple services. This is where business rules live—not in the repository, not in the ViewModel, but in dedicated handler classes that are easy to test and understand. Each handler has a single responsibility: implementing one use case.

Also notice the distinction between ReadProjectByIdQuery and WatchProjectByIdQuery. Both retrieve a project, but they have fundamentally different semantics. The read query gives you a snapshot. The watch query gives you a living stream. This distinction is architectural, not just an implementation detail.

### Layer Three: Infrastructure

The infrastructure layer implements the repository interface with concrete technology choices:

```dart
// app/data/repositories/project_repository_impl.dart
class ProjectRepositoryImpl implements IProjectRepository {
  final ApiClient _apiClient;
  final LocalDatabase _database;
  final CacheManager _cache;
  
  ProjectRepositoryImpl(this._apiClient, this._database, this._cache);
  
  @override
  Future<Project> getProjectById(String id) async {
    // Infrastructure logic: check cache first
    final cached = _cache.get<Project>('project_$id');
    if (cached != null) return cached;
    
    // Infrastructure logic: fetch from API
    final response = await _apiClient.get('/projects/$id');
    
    // Infrastructure logic: map DTO to domain model
    final project = _projectFromJson(response.data);
    
    // Infrastructure logic: update cache
    _cache.set('project_$id', project, duration: Duration(minutes: 5));
    
    return project;
  }
  
  @override
  Stream<Project> watchProjectById(String id) {
    // Infrastructure logic: establish WebSocket connection
    return _apiClient.watchResource('/projects/$id')
        .map((data) => _projectFromJson(data))
        .handleError((error) {
          // Infrastructure logic: error recovery
          print('WebSocket error, falling back to polling: $error');
          return Stream.periodic(
            Duration(seconds: 10),
            (_) => getProjectById(id),
          ).asyncExpand((future) => Stream.fromFuture(future));
        });
  }
  
  @override
  Future<Project> updateProject(Project project) async {
    final response = await _apiClient.put(
      '/projects/${project.id}',
      data: _projectToJson(project),
    );
    
    // Infrastructure logic: invalidate cache
    _cache.remove('project_${project.id}');
    
    return _projectFromJson(response.data);
  }
  
  Project _projectFromJson(Map<String, dynamic> json) {
    // Infrastructure logic: JSON parsing and DTO mapping
    return Project(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      status: ProjectStatus.values.firstWhere(
        (s) => s.name == json['status'],
      ),
      createdAt: DateTime.parse(json['created_at']),
      completedAt: json['completed_at'] != null 
          ? DateTime.parse(json['completed_at']) 
          : null,
    );
  }
  
  Map<String, dynamic> _projectToJson(Project project) {
    return {
      'id': project.id,
      'name': project.name,
      'description': project.description,
      'status': project.status.name,
      'created_at': project.createdAt.toIso8601String(),
      'completed_at': project.completedAt?.toIso8601String(),
    };
  }
}
```

This repository contains all the messy infrastructure details: HTTP calls, JSON parsing, caching strategies, error recovery, and DTO mapping. None of this complexity leaks into the business logic. The handlers remain clean and testable because they depend only on the IProjectRepository interface.

Notice how the infrastructure layer makes different implementation choices for read versus watch. The read operation uses HTTP with caching. The watch operation uses WebSockets with automatic fallback to polling if the connection fails. These are infrastructure concerns that the business layer does not need to know about.

## Layer Four: Presentation

### Understanding the ViewModel Contract

Before examining a complete ViewModel implementation, we need to understand the base ViewModel class that provides the foundation for all presentation logic in Chassis. The ViewModel is the bridge between your domain logic (commands and queries) and your Flutter widgets, managing both continuous state and one-time events in a type-safe, testable manner.

#### The ViewModel Contract

Every ViewModel in your application extends from this base class:

```dart
abstract class ViewModel<TState, TEvent> extends ChangeNotifier {
  ViewModel(Mediator mediator, TState initialState);
  
  // State access
  TState get state;
  
  // Event stream access
  Stream<TEvent> get events;
  
  // Protected methods available to subclasses:
  
  // Updates the current state and notifies listeners (triggers widget rebuilds)
  @protected
  void setState(TState newState);
  
  // Emits a one-time event to the event stream
  @protected
  void sendEvent(TEvent event);
  
  // Executes a command through the mediator, returns success or error
  @protected
  Future<AsyncResult<T>> run<T>(Command<T> command);
  
  // Executes a one-time query through the mediator, returns current data snapshot
  @protected
  Future<AsyncResult<T>> read<T>(ReadQuery<T> query);
  
  // Subscribes to continuous data updates, automatically cancelled on dispose
  @protected
  StreamSubscription<StreamState<T>> watch<T>(
    WatchQuery<T> query,
    void Function(StreamState<T>) onData,
  );
  
  // Cleanup method called by Flutter, cancels subscriptions and closes streams
  @override
  void dispose();
}
```

This contract defines everything a ViewModel can do. Let us examine each component and understand its purpose.

#### State Management: The Single Source of Truth

The ViewModel manages two generic types: `TState` represents the continuous state that describes what the UI should display, and `TEvent` represents one-time occurrences that the UI should react to but not persist.

**State** is persistent information that defines what the user sees. For a project detail screen, state includes the project data itself, whether an update is in progress, and any validation errors. State is accessed through the `state` getter and can only be modified through the protected `setState` method.

```dart
class ProjectDetailState {
  final StreamState<Project> projectState;
  final bool isUpdating;
  final String? updateError;
  
  const ProjectDetailState({
    required this.projectState,
    this.isUpdating = false,
    this.updateError,
  });
}
```

State classes should be immutable. Every state modification creates a new state object rather than mutating the existing one. This immutability enables time-travel debugging, makes state changes explicit and traceable, and prevents subtle bugs from shared mutable state.

State classes should implement `copyWith` methods to enable efficient updates of individual fields.

The `setState` method triggers widget rebuilds for any widgets watching this ViewModel. This integrates with Flutter's standard ChangeNotifier pattern, making ViewModels compatible with Provider, Consumer widgets, and other state management tools built on ChangeNotifier.

#### Event Emission: One-Time Occurrences

Some things that happen in your application should not persist in state. Showing a success snackbar, navigating to another screen, or displaying a confirmation dialog are one-time occurrences. If you stored "should show success snackbar" in state, you would need additional logic to clear that flag, and the snackbar might show again when the screen rebuilds for unrelated reasons.

Events solve this problem. An event fires once, is consumed by the UI, and disappears.

```dart
sealed class ProjectDetailEvent {}
class ProjectUpdateSuccess implements ProjectDetailEvent {}
class ProjectUpdateFailed implements ProjectDetailEvent {
  final String message;
  const ProjectUpdateFailed(this.message);
}
```

Using sealed classes and pattern matching ensures that every event type is explicitly handled. The compiler prevents you from forgetting to handle a new event type when you add it.

ViewModels emit events through the protected `sendEvent` method. Widgets listen to the event stream and react appropriately:

```dart
// In ViewModel
sendEvent(ProjectUpdateSuccess());

// In Widget
onEvent<ProjectDetailViewModel, ProjectDetailEvent>((event) {
  switch (event) {
    case ProjectUpdateSuccess():
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Project updated successfully')),
      );
    case ProjectUpdateFailed(:final message):
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $message'),
          backgroundColor: Colors.red,
        ),
      );
  }
});
```

The distinction between state and events maps cleanly to UI concerns: state determines what is rendered, events determine what side effects to perform.

#### Mediator Integration: Dispatching Operations

The ViewModel interacts with your domain layer exclusively through the mediator. It never directly calls repositories, services, or other infrastructure. This indirection provides testability—you can test ViewModels by mocking the mediator—and maintains the architectural boundary between presentation and business logic.

The base ViewModel provides three methods for mediator interaction:

**`run<T>(Command<T>)` executes commands** that modify state. Commands represent write operations: creating a project, updating a name, deleting a task. The `run` method returns an `AsyncResult<T>`, a wrapper that makes success and error handling explicit:

```dart
final result = await run(UpdateProjectNameCommand(projectId, newName));

result.when(
  data: (project) {
    // Handle success
    setState(state.copyWith(isUpdating: false));
    sendEvent(ProjectUpdateSuccess());
  },
  error: (error, stackTrace) {
    // Handle failure
    setState(state.copyWith(
      isUpdating: false,
      updateError: () => error.toString(),
    ));
    sendEvent(ProjectUpdateFailed(error.toString()));
  },
);
```

The `when` method on AsyncResult forces you to handle both success and error cases. This prevents the common mistake of forgetting error handling, which leads to silent failures and confused users.

**The AsyncResult Type:** This wrapper encodes success and failure in the type system:

```dart
sealed class AsyncResult<T> {
  const AsyncResult();
  
  factory AsyncResult.data(T data) = AsyncResultData<T>;
  factory AsyncResult.error(Object error) = AsyncResultError<T>;
  
  TResult when<TResult>({
    required TResult Function(T data) data,
    required TResult Function(Object error) error,
  });
  
  T? dataOrNull();
}
```

By encoding success and error as type variants rather than throwing exceptions, the AsyncResult type makes error handling explicit and impossible to forget.

**`read<T>(ReadQuery<T>)` executes one-time queries** that return a snapshot of data. Use read queries when you need data once for a specific operation: generating a report, performing a calculation, or displaying data that does not need to stay synchronized:

```dart
final result = await read(ReadProjectStatisticsQuery(projectId));

result.when(
  data: (statistics) {
    setState(state.copyWith(statistics: statistics));
  },
  error: (error, stackTrace) {
    setState(state.copyWith(statisticsError: () => error.toString()));
  },
);
```

**`watch<T>(WatchQuery<T>, callback)` subscribes to continuous queries** that emit updates whenever data changes. Use watch queries when your UI should remain synchronized with data that might change:

```dart
watch(WatchProjectByIdQuery(projectId), (streamState) {
  setState(state.copyWith(projectState: streamState));
});
```

The callback receives a `StreamState<T>`, which can be in one of three states: loading, data, or error. This wrapper handles the complexity of stream state management, providing a clean API for updating your state based on stream emissions.

The `watch` method returns a `StreamSubscription` that is automatically cancelled when the ViewModel is disposed. You typically do not need to manage this subscription manually, but if you need to cancel a subscription early, you can store the returned subscription and call `cancel()` on it.

The distinction between read and watch queries determines how your ViewModel interacts with data. Watch queries establish continuous synchronization, automatically updating your UI as data changes. Read queries retrieve point-in-time snapshots for one-time operations. Choosing the appropriate pattern depends on whether the UI should reflect subsequent changes.

**Use watch queries as your default for data displayed in the UI.** Modern users expect interfaces that stay current without manual refresh. The project detail screen uses a watch query specifically because project data might change through actions by other team members, and the UI should reflect those changes automatically:

```dart
watch(WatchProjectByIdQuery(projectId), (streamState) {
  setState(state.copyWith(projectState: streamState));
});
```

The subscription begins during ViewModel construction, ensuring data loads before the first build. Updates arrive automatically whenever the underlying project changes, keeping the UI synchronized without additional logic.

**Use read queries deliberately for operations that need data once.** Consider generating a PDF report from project statistics. The report captures data at a specific moment and should not update dynamically as statistics change:

```dart
Future<void> generateReport() async {
  final result = await read(ReadProjectStatisticsQuery(projectId));
  
  result.when(
    data: (statistics) => _createPdfReport(statistics),
    error: (error) => sendEvent(ReportGenerationFailed(error.toString())),
  );
}
```

The read operation retrieves current statistics, generates the report, and completes. If statistics change while the user reviews the PDF, the report remains static because it captured a point-in-time snapshot.

Read queries also make sense when working with REST APIs that lack streaming support, when performing calculations on retrieved data, or when data changes so infrequently that manual refresh proves adequate. But for typical UI data display, favor watch queries because they provide better user experience by eliminating the "refresh hell" problem where users see stale data.

#### The StreamState Type

The `StreamState<T>` type warrants special attention because it appears throughout reactive ViewModels. It represents the state of an asynchronous data stream:

```dart
sealed class StreamState<T> {
  const StreamState();
  
  factory StreamState.loading() = StreamStateLoading<T>;
  factory StreamState.data(T data) = StreamStateData<T>;
  factory StreamState.error(Object error, StackTrace stackTrace) = StreamStateError<T>;
  
  TResult when<TResult>({
    required TResult Function() loading,
    required TResult Function(T data) data,
    required TResult Function(Object error, StackTrace stackTrace) error,
  });
  
  T? dataOrNull();
}
```

This type encodes the three possible states of streaming data: waiting for initial data (loading), having current data (data), or encountering an error (error). By encoding these states in the type system rather than using nullable fields and boolean flags, you eliminate entire categories of bugs.

Your UI code uses the `when` method to explicitly handle each state:

```dart
state.projectState.when(
  loading: () => Center(child: CircularProgressIndicator()),
  error: (error) => Center(child: Text('Error: $error')),
  data: (project) => ProjectContent(project: project),
)
```

The compiler ensures you handle all three cases. You cannot accidentally forget to show a loading indicator or handle errors.

#### ViewModel Lifecycle

ViewModels follow a straightforward lifecycle:

**Construction** occurs when the ViewModel is first created. The constructor receives the mediator and initial state. This is where you set up watch subscriptions:

```dart
ProjectDetailViewModel(Mediator mediator, this.projectId) 
    : super(
        mediator,
        ProjectDetailState(projectState: StreamState.loading()),
      ) {
  // Set up subscriptions during construction
  watch(WatchProjectByIdQuery(projectId), (streamState) {
    setState(state.copyWith(projectState: streamState));
  });
}
```

Setting up watch subscriptions in the constructor ensures they are established before the widget first builds. The initial state reflects that data is loading, and the subscription will update that state when data arrives.

**Active lifetime** is when the ViewModel is in use by widgets. During this time, widgets call methods on the ViewModel (like `updateProjectName`), which dispatch commands and queries through the mediator. State changes trigger widget rebuilds. Events are emitted and consumed by the UI.

**Disposal** occurs when the ViewModel is no longer needed. The `dispose` method is called automatically by Flutter's widget system. The base implementation handles cleanup of subscriptions and streams. Subclasses typically do not need to override `dispose` unless they have additional resources to clean up beyond what the base class manages.

#### Integrating with Flutter Widgets

The ViewModel extends `ChangeNotifier`, making it compatible with Flutter's standard state management patterns. The typical integration uses Provider or similar packages:

```dart
// Providing the ViewModel
Provider(
  create: (context) => ProjectDetailViewModel(
    context.read<Mediator>(),
    projectId,
  ),
  dispose: (context, viewModel) => viewModel.dispose(),
  child: ProjectDetailScreen(),
)

// Watching state in widgets
final viewModel = context.watch<ProjectDetailViewModel>();
final state = viewModel.state;

// Listening to events
onEvent<ProjectDetailViewModel, ProjectDetailEvent>((event) {
  // Handle one-time events
});
```

The separation between state watching (continuous rebuilding) and event listening (one-time reactions) keeps your UI code clean and intention-revealing. State determines what to render. Events determine what side effects to perform.

#### Design Principles

Several principles guide effective ViewModel design:

**ViewModels contain presentation logic only.** Business rules, validation, and orchestration belong in command and query handlers. The ViewModel coordinates these operations and manages UI state, but it does not implement business logic.

**State classes are immutable.** Every state change creates a new state object. This makes state changes explicit, enables time-travel debugging, and prevents subtle bugs from shared mutable state.

**Events are one-time occurrences.** If something should persist across rebuilds, it belongs in state. If something should happen once in reaction to an operation, it belongs in events.

**ViewModels depend only on the mediator.** They never directly call repositories, services, or other infrastructure. This maintains architectural boundaries and enables testing.

**Subscriptions are established during construction.** Watch queries should be set up in the constructor so that data begins loading before the first build.

With this foundation, we can now examine a complete ViewModel implementation that applies these principles.

---

#### Example

```dart
// app/ui/features/project_detail/project_detail_state.dart
class ProjectDetailState {
  final StreamState<Project> projectState;
  final bool isUpdating;
  final String? updateError;
  
  const ProjectDetailState({
    required this.projectState,
    this.isUpdating = false,
    this.updateError,
  });
  
  ProjectDetailState copyWith({
    StreamState<Project>? projectState,
    bool? isUpdating,
    String? Function()? updateError,
  }) {
    return ProjectDetailState(
      projectState: projectState ?? this.projectState,
      isUpdating: isUpdating ?? this.isUpdating,
      updateError: updateError != null ? updateError() : this.updateError,
    );
  }
}

sealed class ProjectDetailEvent {}
class ProjectUpdateSuccess implements ProjectDetailEvent {}
class ProjectUpdateFailed implements ProjectDetailEvent {
  final String message;
  const ProjectUpdateFailed(this.message);
}

// app/ui/features/project_detail/project_detail_view_model.dart
class ProjectDetailViewModel 
    extends ViewModel<ProjectDetailState, ProjectDetailEvent> {
  final String projectId;
  
  ProjectDetailViewModel(Mediator mediator, this.projectId) 
      : super(
          mediator,
          ProjectDetailState(projectState: StreamStateLoading()),
        ) {
    // Subscribe to real-time project updates
    watch(WatchProjectByIdQuery(projectId), (streamState) {
      setState(state.copyWith(projectState: streamState));
    });
  }
  
  Future<void> updateProjectName(String newName) async {
    setState(state.copyWith(isUpdating: true, updateError: () => null));
    
    final result = await run(
      UpdateProjectNameCommand(projectId, newName),
    );
    
    result.when(
      data: (_) {
        setState(state.copyWith(isUpdating: false));
        sendEvent(ProjectUpdateSuccess());
      },
      error: (error, _) {
        setState(state.copyWith(
          isUpdating: false,
          updateError: () => error.toString(),
        ));
        sendEvent(ProjectUpdateFailed(error.toString()));
      },
    );
  }
}
```

The ViewModel is remarkably clean. It manages UI state but contains no business logic, no infrastructure details, and no direct repository calls. Everything flows through the mediator using commands and queries.

Notice how the ViewModel uses watch to subscribe to real-time updates. This is the WatchQuery in action—the ViewModel automatically receives new project states as they change, keeping the UI synchronized without any manual refresh logic.

The View is equally straightforward:

```dart
// app/ui/features/project_detail/project_detail_screen.dart
class ProjectDetailScreen extends StatefulWidget {
  final String projectId;
  const ProjectDetailScreen({required this.projectId});
  
  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

// Notice the consumer mixin that provides `onEvent` method
class _ProjectDetailScreenState extends State<ProjectDetailScreen> 
    with ConsumerMixin {
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Listen to one-time events like success/error notifications
    onEvent<ProjectDetailViewModel, ProjectDetailEvent>((event) {
      switch (event) {
        case ProjectUpdateSuccess():
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Project updated successfully')),
          );
        case ProjectUpdateFailed(:final message):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Update failed: $message'),
              backgroundColor: Colors.red,
            ),
          );
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ProjectDetailViewModel>();
    final state = viewModel.state;
    
    return Scaffold(
      appBar: AppBar(title: Text('Project Details')),
      body: state.projectState.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (project) => ProjectContent(
          project: project,
          isUpdating: state.isUpdating,
          onUpdateName: viewModel.updateProjectName,
        ),
      ),
    );
  }
}
```

The view is a pure rendering function. It observes state from the ViewModel and forwards user actions back to it. It contains no logic beyond UI concerns like showing snackbars for events.

### Wiring It Together

The final step is registering all handlers with the mediator. This typically happens at application startup:

```dart

// you can also uses dependency injection packages like get_it
final mediator = Mediator();

// main.dart
void main() {
  
  // Infrastructure dependencies
  final apiClient = ApiClient(baseUrl: 'https://api.example.com');
  final database = LocalDatabase();
  final cache = CacheManager();
  final analytics = AnalyticsService();
  final validation = ValidationService();
  
  // Repository implementations
  final projectRepository = ProjectRepositoryImpl(apiClient, database, cache);
  
  // Register all handlers
  mediator.registerQueryHandler(
    ReadProjectByIdQueryHandler(projectRepository)
  );
  mediator.registerQueryHandler(
    WatchProjectByIdQueryHandler(projectRepository)
  );
  mediator.registerCommandHandler(
    UpdateProjectNameCommandHandler(projectRepository, validation, analytics)
  );
  
  // Additional handlers would be registered here...
  
  runApp(MyApp());
}
```

This registration code is verbose, but it serves an important purpose. It is the only place in your entire application where concrete implementations are wired to interfaces. Everything else in your codebase depends on abstractions. This single point of configuration makes it trivial to swap implementations for testing or to change technology choices.

## Testing with Chassis

Chassis shines here because every layer can be tested in complete isolation.

### Testing Handlers: Pure Business Logic Tests

Handlers contain your business logic, and they should be tested thoroughly without any Flutter dependencies, without making real API calls, and without touching databases. With Chassis, this is straightforward:

```dart
void main() {
  group('UpdateProjectNameCommandHandler', () {
    late MockProjectRepository mockRepository;
    late MockValidationService mockValidation;
    late MockAnalyticsService mockAnalytics;
    late UpdateProjectNameCommandHandler handler;
    
    setUp(() {
      mockRepository = MockProjectRepository();
      mockValidation = MockValidationService();
      mockAnalytics = MockAnalyticsService();
      handler = UpdateProjectNameCommandHandler(
        mockRepository,
        mockValidation,
        mockAnalytics,
      );
    });
    
    test('should validate project name before updating', () async {
      // Arrange
      when(mockValidation.isValidProjectName(any)).thenReturn(false);
      final command = UpdateProjectNameCommand('project-1', 'ab');
      
      // Act & Assert
      expect(
        () => handler.run(command),
        throwsA(isA<ValidationException>()),
      );
      verifyNever(mockRepository.updateProject(any));
    });
    
    test('should update project when name is valid', () async {
      // Arrange
      final existingProject = Project(
        id: 'project-1',
        name: 'Old Name',
        description: 'Description',
        status: ProjectStatus.inProgress,
        createdAt: DateTime.now(),
      );
      final updatedProject = existingProject.copyWith(name: 'New Name');
      
      when(mockValidation.isValidProjectName(any)).thenReturn(true);
      when(mockRepository.getProjectById('project-1'))
          .thenAnswer((_) async => existingProject);
      when(mockRepository.updateProject(any))
          .thenAnswer((_) async => updatedProject);
      
      final command = UpdateProjectNameCommand('project-1', 'New Name');
      
      // Act
      final result = await handler.run(command);
      
      // Assert
      expect(result.name, 'New Name');
      verify(mockRepository.updateProject(argThat(
        predicate<Project>((p) => p.name == 'New Name')
      ))).called(1);
    });
    
    test('should track analytics after successful update', () async {
      // Arrange
      final existingProject = Project(
        id: 'project-1',
        name: 'Old Name',
        description: 'Description',
        status: ProjectStatus.inProgress,
        createdAt: DateTime.now(),
      );
      
      when(mockValidation.isValidProjectName(any)).thenReturn(true);
      when(mockRepository.getProjectById(any))
          .thenAnswer((_) async => existingProject);
      when(mockRepository.updateProject(any))
          .thenAnswer((_) async => existingProject.copyWith(name: 'New Name'));
      
      final command = UpdateProjectNameCommand('project-1', 'New Name');
      
      // Act
      await handler.run(command);
      
      // Assert
      verify(mockAnalytics.trackEvent('project_renamed', any)).called(1);
    });
  });
}
```

These are pure unit tests that run in milliseconds. No Flutter test environment required. No HTTP mocking frameworks needed. Just plain Dart testing your business logic in isolation.

### Testing ViewModels: Presentation Logic Tests

ViewModels contain presentation logic, and they should be tested without rendering any widgets. With Chassis, you test ViewModels by verifying they dispatch the correct commands and queries:

```dart
void main() {
  group('ProjectDetailViewModel', () {
    late MockMediator mockMediator;
    late ProjectDetailViewModel viewModel;
    
    setUp(() {
      mockMediator = MockMediator();
      viewModel = ProjectDetailViewModel(mockMediator, 'project-1');
    });
    
    test('should watch project on initialization', () {
      // Assert
      verify(mockMediator.watch(
        argThat(isA<WatchProjectByIdQuery>())
      )).called(1);
    });
    
    test('should update state when project stream emits', () async {
      // Arrange
      final project = Project(
        id: 'project-1',
        name: 'Test Project',
        description: 'Description',
        status: ProjectStatus.inProgress,
        createdAt: DateTime.now(),
      );
      final streamController = StreamController<Project>();
      
      when(mockMediator.watch(any)).thenAnswer((_) => streamController.stream);
      
      viewModel = ProjectDetailViewModel(mockMediator, 'project-1');
      
      // Act
      streamController.add(project);
      await Future.delayed(Duration.zero);
      
      // Assert
      expect(viewModel.state.projectState, isA<StreamStateData<Project>>());
      expect(
        viewModel.state.projectState.dataOrNull()?.name,
        'Test Project'
      );
    });
    
    test('should dispatch command when updating project name', () async {
      // Arrange
      when(mockMediator.run(any)).thenAnswer(
        (_) async => Project(
          id: 'project-1',
          name: 'New Name',
          description: 'Description',
          status: ProjectStatus.inProgress,
          createdAt: DateTime.now(),
        )
      );
      
      // Act
      await viewModel.updateProjectName('New Name');
      
      // Assert
      verify(mockMediator.run(
        argThat(predicate<UpdateProjectNameCommand>(
          (cmd) => cmd.newName == 'New Name' && cmd.projectId == 'project-1'
        ))
      )).called(1);
    });
    
    test('should emit success event when update succeeds', () async {
      // Arrange
      when(mockMediator.run(any)).thenAnswer(
        (_) async => Project(
          id: 'project-1',
          name: 'New Name',
          description: 'Description',
          status: ProjectStatus.inProgress,
          createdAt: DateTime.now(),
        )
      );
      
      final events = <ProjectDetailEvent>[];
      viewModel.events.listen(events.add);
      
      // Act
      await viewModel.updateProjectName('New Name');
      
      // Assert
      expect(events, hasLength(1));
      expect(events.first, isA<ProjectUpdateSuccess>());
    });
  });
}
```

Again, no widget tests required. You are testing the presentation logic directly by mocking the mediator and verifying the correct commands and queries are dispatched. The ViewModel's state changes are easy to assert because the state is just a plain data class.

### Testing Repositories: Infrastructure Tests

Repository tests verify that infrastructure correctly translates between external systems and your domain:

```dart
void main() {
  group('ProjectRepositoryImpl', () {
    late MockApiClient mockApiClient;
    late MockCacheManager mockCache;
    late ProjectRepositoryImpl repository;
    
    setUp(() {
      mockApiClient = MockApiClient();
      mockCache = MockCacheManager();
      repository = ProjectRepositoryImpl(mockApiClient, mockCache);
    });
    
    test('should return cached project when available', () async {
      // Arrange
      final cachedProject = Project(
        id: 'project-1',
        name: 'Cached Project',
        description: 'Description',
        status: ProjectStatus.inProgress,
        createdAt: DateTime.now(),
      );
      
      when(mockCache.get<Project>('project_project-1'))
          .thenReturn(cachedProject);
      
      // Act
      final result = await repository.getProjectById('project-1');
      
      // Assert
      expect(result, cachedProject);
      verifyNever(mockApiClient.get(any));
    });
    
    test('should fetch from API and cache when not in cache', () async {
      // Arrange
      when(mockCache.get<Project>(any)).thenReturn(null);
      when(mockApiClient.get('/projects/project-1')).thenAnswer(
        (_) async => ApiResponse(data: {
          'id': 'project-1',
          'name': 'API Project',
          'description': 'Description',
          'status': 'inProgress',
          'created_at': '2024-01-01T00:00:00Z',
        })
      );
      
      // Act
      final result = await repository.getProjectById('project-1');
      
      // Assert
      expect(result.name, 'API Project');
      verify(mockCache.set('project_project-1', any, duration: anyNamed('duration')))
          .called(1);
    });
    
    test('should map JSON correctly to domain model', () async {
      // Arrange
      when(mockCache.get<Project>(any)).thenReturn(null);
      when(mockApiClient.get(any)).thenAnswer(
        (_) async => ApiResponse(data: {
          'id': 'project-1',
          'name': 'Test Project',
          'description': 'Test Description',
          'status': 'completed',
          'created_at': '2024-01-01T10:00:00Z',
          'completed_at': '2024-01-15T15:30:00Z',
        })
      );
      
      // Act
      final result = await repository.getProjectById('project-1');
      
      // Assert
      expect(result.id, 'project-1');
      expect(result.name, 'Test Project');
      expect(result.description, 'Test Description');
      expect(result.status, ProjectStatus.completed);
      expect(result.completedAt, isNotNull);
    });
  });
}
```

Repository tests focus on infrastructure concerns: caching logic, JSON mapping, error handling, and API contract verification. They do not test business rules because business rules do not live in repositories.

### Integration Tests: The Full Stack

While unit tests verify individual components, integration tests verify that the layers work together correctly:

```dart
void main() {
  group('Project Feature Integration', () {
    late Mediator mediator;
    late MockApiClient mockApiClient;
    
    setUp(() {
      mediator = Mediator();
      mockApiClient = MockApiClient();
      
      final repository = ProjectRepositoryImpl(mockApiClient, CacheManager());
      final validation = ValidationService();
      final analytics = MockAnalyticsService();
      
      mediator.registerQueryHandler(
        ReadProjectByIdQueryHandler(repository)
      );
      mediator.registerCommandHandler(
        UpdateProjectNameCommandHandler(repository, validation, analytics)
      );
    });
    
    test('should handle full update flow', () async {
      // Arrange
      when(mockApiClient.get('/projects/project-1')).thenAnswer(
        (_) async => ApiResponse(data: {
          'id': 'project-1',
          'name': 'Old Name',
          'description': 'Description',
          'status': 'inProgress',
          'created_at': '2024-01-01T00:00:00Z',
        })
      );
      when(mockApiClient.put(any, data: anyNamed('data'))).thenAnswer(
        (_) async => ApiResponse(data: {
          'id': 'project-1',
          'name': 'New Name',
          'description': 'Description',
          'status': 'inProgress',
          'created_at': '2024-01-01T00:00:00Z',
        })
      );
      
      // Act
      final originalProject = await mediator.read(
        ReadProjectByIdQuery('project-1')
      );
      final updatedProject = await mediator.run(
        UpdateProjectNameCommand('project-1', 'New Name')
      );
      
      // Assert
      expect(originalProject.name, 'Old Name');
      expect(updatedProject.name, 'New Name');
    });
  });
}
```

Integration tests use the real mediator with real handlers but mock external dependencies like APIs. They verify that commands and queries flow correctly through the entire system.

## Trade-offs and When to Use Chassis

Chassis makes deliberate trade-offs that are appropriate for some applications but not others. Understanding these trade-offs is essential for evaluating whether the framework aligns with your project's needs.

The framework requires more upfront ceremony than simpler approaches. Each feature requires command or query classes, handler classes, and registration code. This structure pays dividends as applications scale, but represents overhead for small applications or rapid prototypes.

The framework enforces patterns through its structure, reducing flexibility in how teams organize code. This consistency benefits large teams working on long-lived applications but may feel restrictive for small teams that prefer to establish their own conventions.

The framework introduces indirection through the mediator, trading direct method calls for message-based dispatch. This enables powerful capabilities like uniform logging and operation discovery but requires developers to think in terms of messages and handlers rather than direct dependencies.

For applications with complex business logic, multiple teams, long-term maintenance requirements, and needs for comprehensive testing and observability, these trade-offs often prove worthwhile. For smaller applications, prototypes, or teams that prioritize development velocity over enforced structure, simpler approaches typically serve better.

The remainder of this guide will explain how Chassis implements these patterns, demonstrate how the framework addresses the organizational challenges described above, and provide guidance for evaluating whether Chassis's approach aligns with your architectural needs.

### The Cost: Ceremony and Indirection

Chassis requires creating multiple files and classes for even simple features. A feature that could be implemented in twenty lines of code in a single widget might require a command class, a handler class, repository interfaces, and a ViewModel—perhaps fifty lines of code across four files.

This is ceremony, and it is intentional. The separation exists to enforce boundaries and enable testing. But for small applications or rapid prototypes, this investment may not be justified.

Consider a simple counter app. In vanilla Flutter:

```dart
class CounterScreen extends StatefulWidget {
  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen> {
  int _count = 0;
  
  void _increment() => setState(() => _count++);
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text('$_count')),
      floatingActionButton: FloatingActionButton(
        onPressed: _increment,
        child: Icon(Icons.add),
      ),
    );
  }
}
```

In Chassis, you would create an IncrementCountCommand, an IncrementCountCommandHandler, a CounterRepository interface, a CounterRepositoryImpl, a CounterViewModel, and wire them through the mediator. For a counter, this is absurd overkill.

The architecture's value emerges with scale. As applications grow from tens of features to hundreds, the upfront investment in structure becomes a bargain. But for small projects, simpler approaches make sense.

Chassis requires understanding multiple patterns: Clean Architecture, CQRS, the Mediator pattern, and MVVM. For developers new to these concepts, the learning curve is steep.

Some operations are genuinely simple pass-throughs. A query that just fetches an entity by ID requires a query class and a handler, even though the handler might be a single line that delegates to the repository.

This feels like unnecessary ceremony, and in some cases, it is. But the structure provides value even for simple operations. The query class documents what data is needed for the operation. The handler provides a standard place to add caching, logging, or permissions checks if needed later. The consistency means every operation follows the same pattern, making the codebase predictable.

Still, for projects with many simple CRUD operations, the boilerplate can be tedious. Code generation tools can help, but they add another layer of complexity to the build process.

### When Chassis Is The Right Choice

Chassis is designed for specific scenarios where its benefits justify its costs:

**Large, Long-Lived Applications:** When you are building an application that will be maintained for years by multiple developers, the architectural structure pays dividends. The consistency and testability become more valuable than the initial development speed.

**Team Consistency:** When multiple developers work on the same codebase, Chassis enforces a structure that prevents each developer from organizing code differently. Everyone follows the same patterns, making code reviews easier and knowledge transfer simpler.

**Complex Business Logic:** When your application contains significant business rules that need to be thoroughly tested and evolved over time, separating that logic from infrastructure and UI is crucial. Chassis provides natural places for that logic to live.

**Real-Time and Offline Features:** When you need sophisticated data synchronization, real-time updates, offline support, or complex caching strategies, the infrastructure layer provides a natural place to implement these concerns without polluting business logic.

**High Testing Requirements:** When comprehensive testing is non-negotiable, Chassis's architecture makes it possible to test every layer in isolation. This is especially valuable in domains with compliance requirements or where bugs have serious consequences.

### When Simpler Approaches Are Better

Chassis is overkill for:

**Prototypes and MVPs:** When you need to validate an idea quickly, the upfront structure of Chassis slows you down. Use simpler patterns and consider refactoring to Chassis if the project succeeds.

**Small Utility Apps:** Applications with limited features and straightforward logic do not benefit from layered architecture. The ceremony outweighs the value.

**Content-Heavy Apps:** If your application is primarily displaying static content with minimal business logic, state management solutions like Provider or Riverpod alone are sufficient.

## Conclusion: Architecture as an Investment

Chassis is not a magic solution that makes all development easier. It is a deliberate trade-off: more structure upfront in exchange for better scalability, testability, and maintainability over time.

The architecture enforces discipline. It makes certain mistakes difficult or impossible. It provides standard patterns that make codebases navigable. It enables comprehensive testing without elaborate mocking frameworks. It allows infrastructure to evolve without affecting business logic.

But these benefits come with real costs. More files, more indirection, more ceremony. A steeper learning curve. Reduced development speed for simple features.

The question is not whether Chassis is "good" or "bad" in the abstract. The question is whether its trade-offs align with your project's needs. For large, complex, long-lived applications built by teams that value consistency and testability, Chassis provides a solid foundation. For rapid prototypes, small utilities, or teams that prioritize speed over structure, simpler approaches make more sense.

Architecture is an investment. Chassis asks you to pay upfront for benefits that compound over time. Understanding this trade-off helps you make informed decisions about when that investment is worthwhile.

The patterns that Chassis combines—Clean Architecture, CQRS, ReadQuery versus WatchQuery, the Mediator pattern, MVVM—are not arbitrary. Each solves specific problems that emerge in Flutter development at scale. By understanding the problems each pattern addresses and why they work together, you can make sound architectural decisions even in situations this guide does not explicitly cover.

That is the goal: not just to teach you the rules of Chassis, but to teach you the thinking behind the rules so you can build better Flutter applications, whether you use Chassis or not.