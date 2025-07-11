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
  MyViewModel() : super(MyViewModelState()) //initial
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