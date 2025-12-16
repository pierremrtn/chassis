

## The Architecture Under Pressure: Evolution Scenarios

A good architecture is not just clean—it enables change. Let us examine how the Chassis architecture handles common evolution scenarios that challenge poorly structured applications.

### Scenario One: Adding Comprehensive Caching

Your application is making too many API calls, and you need to implement an intelligent caching strategy. In a traditional architecture, this change would require modifying every place where data is fetched. With Chassis, the change is localized to the repository:

```dart
class ProjectRepositoryImpl implements IProjectRepository {
  final ApiClient _apiClient;
  final CacheManager _cache;
  
  @override
  Future<Project> getProjectById(String id) async {
    return _cache.getOrFetch(
      key: 'project_$id',
      ttl: Duration(minutes: 5),
      fetcher: () async {
        final response = await _apiClient.get('/projects/$id');
        return _projectFromJson(response.data);
      },
    );
  }
}
```

The handlers do not change. The ViewModels do not change. Only the infrastructure layer changes, exactly as it should be. The business logic remains stable while infrastructure details evolve.

### Scenario Two: Implementing Optimistic Updates

Users complain that the UI feels sluggish because they have to wait for the server to confirm changes before seeing updates. You want to implement optimistic updates where the UI changes immediately, then reverts if the server rejects the change.

In a poorly structured application, this logic would be scattered across multiple ViewModels, leading to inconsistent behavior. With Chassis, you can implement this as a concern in the handler:

```dart
class UpdateProjectNameCommandHandler 
    implements CommandHandler<UpdateProjectNameCommand, Project> {
  final IProjectRepository _repository;
  final IProjectCache _cache;
  
  @override
  Future<Project> run(UpdateProjectNameCommand command) async {
    // Optimistically update the cache
    final existingProject = await _repository.getProjectById(command.projectId);
    final optimisticProject = existingProject.copyWith(name: command.newName);
    _cache.setOptimistic('project_${command.projectId}', optimisticProject);
    
    try {
      // Attempt the real update
      final updatedProject = existingProject.copyWith(name: command.newName);
      final result = await _repository.updateProject(updatedProject);
      
      // Commit the optimistic update
      _cache.commitOptimistic('project_${command.projectId}', result);
      return result;
    } catch (e) {
      // Revert the optimistic update
      _cache.revertOptimistic('project_${command.projectId}');
      rethrow;
    }
  }
}
```

The ViewModels that call this command do not need to know about optimistic updates. They simply dispatch the command and handle success or failure. The complexity is encapsulated in the handler where it belongs.

### Scenario Three: Adding Operation Logging

You need to implement comprehensive logging to understand which operations users perform, how long they take, and whether they succeed or fail. This is a cross-cutting concern that needs to apply to every operation.

Because all operations flow through the mediator, you can implement this once:

```dart
class LoggingMediator extends Mediator {
  final ILogger _logger;
  
  LoggingMediator(this._logger);
  
  @override
  Future<T> run<T>(Command<T> command) async {
    final stopwatch = Stopwatch()..start();
    _logger.info('Executing command: ${command.runtimeType}');
    
    try {
      final result = await super.run(command);
      _logger.info(
        'Command ${command.runtimeType} succeeded in ${stopwatch.elapsedMilliseconds}ms'
      );
      return result;
    } catch (e) {
      _logger.error(
        'Command ${command.runtimeType} failed after ${stopwatch.elapsedMilliseconds}ms: $e'
      );
      rethrow;
    }
  }
  
  @override
  Future<T> read<T>(ReadQuery<T> query) async {
    final stopwatch = Stopwatch()..start();
    _logger.info('Executing query: ${query.runtimeType}');
    
    try {
      final result = await super.read(query);
      _logger.info(
        'Query ${query.runtimeType} succeeded in ${stopwatch.elapsedMilliseconds}ms'
      );
      return result;
    } catch (e) {
      _logger.error(
        'Query ${query.runtimeType} failed after ${stopwatch.elapsedMilliseconds}ms: $e'
      );
      rethrow;
    }
  }
}
```

Now every command and query is automatically logged with timing information. You did not have to modify a single handler or ViewModel. This is the power of having a single point through which all operations flow.

### Scenario Four: Implementing Offline Support

Your application needs to work offline, queuing operations when the network is unavailable and replaying them when connectivity is restored.

This is a complex change that would be nearly impossible in a tightly coupled architecture. With Chassis, you can implement it by extending the mediator:

```dart
class OfflineMediator extends Mediator {
  final INetworkMonitor _networkMonitor;
  final IOperationQueue _queue;
  
  @override
  Future<T> run<T>(Command<T> command) async {
    if (_networkMonitor.isOnline) {
      return super.run(command);
    } else {
      // Queue the command for later execution
      final queuedOperation = QueuedOperation(
        command: command,
        timestamp: DateTime.now(),
      );
      await _queue.enqueue(queuedOperation);
      
      // Return a pending result
      throw OfflineException('Operation queued for when network is available');
    }
  }
  
  Future<void> replayQueuedOperations() async {
    final operations = await _queue.getAll();
    
    for (final operation in operations) {
      try {
        await super.run(operation.command);
        await _queue.remove(operation);
      } catch (e) {
        // Keep it in the queue to retry later
        print('Failed to replay operation: $e');
      }
    }
  }
}
```

Again, handlers and ViewModels do not change. The mediator handles the offline concern transparently. When the network becomes available, you call `replayQueuedOperations()` and all queued commands execute automatically.

### Scenario Five: Migrating from REST to GraphQL

Your team decides to migrate from a REST API to GraphQL. In a traditional architecture, this change would touch every file that makes API calls. With Chassis, only the repository implementations change:

```dart
class ProjectRepositoryImpl implements IProjectRepository {
  final GraphQLClient _graphql; // Changed from ApiClient
  
  @override
  Future<Project> getProjectById(String id) async {
    final result = await _graphql.query(
      QueryOptions(
        document: gql('''
          query GetProject(\$id: ID!) {
            project(id: \$id) {
              id
              name
              description
              status
              createdAt
              completedAt
            }
          }
        '''),
        variables: {'id': id},
      ),
    );
    
    return _projectFromJson(result.data['project']);
  }
  
  @override
  Stream<Project> watchProjectById(String id) {
    return _graphql.subscribe(
      SubscriptionOptions(
        document: gql('''
          subscription WatchProject(\$id: ID!) {
            projectUpdated(id: \$id) {
              id
              name
              description
              status
              createdAt
              completedAt
            }
          }
        '''),
        variables: {'id': id},
      ),
    ).map((result) => _projectFromJson(result.data['projectUpdated']));
  }
}
```

The entire migration is confined to the infrastructure layer. Your domain models, handlers, and ViewModels are completely unaffected. This is the dependency inversion principle delivering real value—you can swap infrastructure without impacting business logic.
