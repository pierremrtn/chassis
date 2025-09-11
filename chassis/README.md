/// Framewrok for flutter app architecture


Values:
Do not rely on developer discipline to implement good architecture
RIGID in the structure FLEXIBLE in the implementation
Excellent DX and minimal boilerplate
Testable, Mockable, Observable

Names:
chassis


Packages:
- behavior_tree (standalone)
- state_tree (standalone)
- chassis 
- view_model // utils for view model
- chassis_flutter (view_model + widget tree utils + )


// TODO: first review
- ? rename watch into stream
- [can't be done] introduce private Read / Watch query type to prevent ReadHandler with ReadWatchQuery
- DONE handler<T>() method in mediator
- DONE safe emit/notify for vm
- review / improve public api types / names (especially for handles)
- Specialize handles for read, watch, command -> more expressives names and specialized features: 
- DONE isDone -> good for command/future, confusing for stream
- DONE run -> better than execute
- stream query -> update alias for run to avoid confusion
- handle.listen shorthand
- listen to handle -> no state as params because conflict with vm's state and easily accessible with handle.state
- had state utils to handle utils
- readAndWatch handle sugar in view model


// TODO: evaluate this recommendation
// In ViewModel extensions
void listenToHandles(
  Iterable<IHandle> handles,
  void Function() listener,
) {
  final mergedStream = MergeStream(handles.map((h) => h.stream));

  // By debouncing with Duration.zero, we wait for the current event loop
  // to finish, coalescing multiple rapid-fire events into one.
  autoDisposeStreamSubscription(
    mergedStream.debounceTime(Duration.zero).listen((_) => listener()),
  );
}



// TODO:

Code gen for mediator access:

```dart

class AppSettingsQuery extends IReadQuery<AppSettings> {}
class UserPresenceQuery extends IWatchQuery<UserStatus> { final String userId; ... }


// Fichier généré : chassis.g.dart
class MyMediator extends Mediator {
  MyMediator({
    required AppSettingsQueryHandler appSettingsQuery,
    required UserPresenceQueryHandler userPresenceQuery,
    });

  // Raccourci généré pour AppSettingsQuery
  Future<AppSettings> fetchAppSettings(AppSettingsQuery query) {
    return fetch<AppSettings>(query);
  }
  
  Future<AppSettings> watchAppSettings(AppSettingsQuery query) {
    return stream<AppSettings>(query);
  }

  // Raccourci généré pour UserPresenceQuery
  Stream<UserStatus> watchUserPresence(UserPresenceQuery query) {
    return watch<UserStatus>(query);
  }
}

```

// TODO: view model basic


```dart
class MyViewModelState {}

class MyViewModel extends ViewModel<MyViewModelState> {
  MyViewModel(Mediator mediator) : super(mediator, MyViewModelState()) //initial
  {
    _appSettings = watchHandle();
    _userQuery = watchHandle();
    _setSettings = commandHandle();

    mergeAndListenTo(
      [_appSettings, _userQuery, _setSettings],
      () {
        final settings = _appSettings;
        final user = _userQuery;

        if (settings.isSuccess && user.isSuccess) {
          emit(MyViewModelState( ... ));
        }
        emit(MyViewModelState( ... ));
      },
    );
  }

  late final WatchHandle<AppSettingsQuery, AppSettings> _appSettings;
  late final WatchHandle<UserQuery, User> _userQuery;
  late final CommadHandle<SetSettingsCommand, User> _setSettings;
}
```

// TODO: rule engine

rule engine:
```dart

  ruleEngine(($) => [
     $.onAllSucceeded([a, b]).then(() {
        $.emit(state) // terminal operator
     }), 

  ])

  onAllSucceeded([a, b]).then(() {
    onError(c).then(() => emit(state)) // on emit le state, les autres rules ne seront pas évaluées
    emit(state) // si c'est n'est pas en erreur, on emit
  })
```

// TODO: logs / midleware for mediator



Naming convention:

## For Future / Task (One-Time Fetches)
## For Stream / IObservable (Continuous Updates)
CQRS Naming Convention Guide

This document outlines the standard naming conventions for Commands, Queries, and their Handlers to ensure clarity, consistency, and discoverability across the codebase.
1. Command Naming Convention

Commands represent a request to change the state of the system. Their names should be imperative and specific.

Pattern: [Verb][Resource]Command

    Verb: An imperative, present-tense verb describing the business operation (e.g., Create, Update, Register, Assign, Delete).

    Resource: The entity or concept the command acts upon (e.g., Project, UserEmail, OrderItem). Use specific properties for targeted updates (e.g., UpdateProjectName instead of UpdateProject).

    Suffix: Always end with Command.

Examples:

    Create: CreateProjectCommand, RegisterUserCommand

    Update: UpdateProjectNameCommand, AssignTaskToUserCommand

    Delete: DeleteProjectCommand, RemoveItemFromCartCommand

    State Transitions: SubmitOrderCommand, ApproveTimesheetCommand

2. Query Naming Convention

Queries represent a request to read the state of the system. They are questions and should not modify state.
For One-Time Fetches (Future)

These queries ask for the state of the system right now.

Pattern: [Verb][Resource]By[Criteria]Query

    Verb: Get is standard. Find is a good alternative if the result might not exist.

    Resource: The entity or DTO being retrieved (e.g., Project, User, OrderSummary).

    Criteria (Optional): Specifies how the resource is being queried, prefixed with By (e.g., ById, ByEmail). Use All for collections.

    Suffix: Always end with Query.

Examples:

    GetProjectByIdQuery

    GetAllUsersQuery

    FindCustomerByEmailQuery

    GetOrderSummaryQuery

For Continuous Updates (Stream)

These queries subscribe to a stream of data that changes over time.

Pattern: Watch[Resource]By[Criteria]Query

    Verb: Watch is the most intuitive verb. Observe is a good alternative.

    Resource: The entity or DTO being observed.

    Criteria (Optional): Specifies what is being watched.

    Suffix: Always end with Query.

Examples:

    WatchProjectByIdQuery

    WatchAllActiveTicketsQuery

    WatchOrderStatusQuery

3. Handler Naming Convention

Handlers contain the logic to process a single Command or Query. The naming is strictly mechanical for absolute predictability.

Pattern: [FullMessageName]Handler

The handler's name is created by taking the full name of the command or query it handles and appending Handler.
Command Handler Examples:

    Handles CreateProjectCommand -> CreateProjectCommandHandler

    Handles UpdateProjectNameCommand -> UpdateProjectNameCommandHandler

    Handles SubmitOrderCommand -> SubmitOrderCommandHandler

Query Handler Examples:

    Handles GetProjectByIdQuery -> GetProjectByIdQueryHandler

    Handles GetAllUsersQuery -> GetAllUsersQueryHandler

    Handles WatchAllActiveTicketsQuery -> WatchAllActiveTicketsQueryHandler





/// About mediator, handler and type safety


return ViewModelProvider(
      create: (context) => HomeScreenVM(mediator),
      child: _HomeScreen(),
    );

Here we may decide that mediator doesn't have to be passed as parameter
the condition for it is to make a singleton

also, a type safe mediator may be nice:


Watch.allProject(...)
Get.allProject(...)
Command.createProject(...)