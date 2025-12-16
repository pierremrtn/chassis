# Design Doc : Chassis V2 - Core & Code Gen

**Auteur :** Architecte Chassis
**Version :** 2.1 (Validé)
**Philosophie :** Type-Safety, Zéro Boilerplate, Explicite.

## 1\. Vue d'ensemble

Chassis V2 introduit la génération de code pour éliminer l'enregistrement manuel des handlers et sécuriser les appels via le médiateur.

L'expérience développeur visée est :

1.  J'annote mon Handler : `@chassisHandler`
2.  Je lance le build.
3.  J'instancie le médiateur généré (qui me demande mes repos).
4.  J'utilise des méthodes typées : `mediator.login(...)`.

## 2\. Spécifications : Code Generation

Nous introduisons un package `chassis_generator` et une annotation `chassis_annotation`.

### 2.1. L'Annotation `@chassisHandler`

Pour qu'une classe soit prise en compte, elle doit être annotée. Cela rend le code "searchable" et explicite.

```dart
@chassisHandler
class LoginHandler implements CommandHandler<LoginCommand, void> {
  // ...
}
```

### 2.2. Le Générateur (Logique)

Le générateur va scanner les classes annotées et produire une classe `[PackageName]Chassis`.

**Responsabilités du générateur :**

1.  **Scan :** Trouver toutes les classes avec `@chassisHandler`.
2.  **Analyse du Constructeur :** Lister tous les arguments des constructeurs des handlers trouvés.
3.  **Dé-duplication :** Créer une liste unique de dépendances (par Type).
4.  **Wiring :** Générer le code qui instancie les handlers en leur passant les dépendances reçues.

-----

## 3\. Spécifications : Le Médiator Amélioré

### 3.1. Structure du Médiateur Généré

Au lieu d'hériter, le générateur crée une classe dédiée qui étend ou configure un `Mediator`.

**Exemple de sortie (`auth.chassis.dart`) :**

```dart
// GENERATED CODE

class AuthChassis extends Mediator {
  // 1. Dépendances dé-dupliquées demandées au constructeur
  AuthChassis({
    required AuthRepository authRepository,
    required LoggerService logger,
  }) {
    // 2. Enregistrement automatique au démarrage
    registerCommandHandler(LoginHandler(authRepository, logger));
    registerQueryHandler(GetProfileHandler(authRepository));
  }
}
```

### 3.2. L'Opérateur `+` (Fusion de Médiateurs)

Pour gérer le cas multi-packages simplement, nous surchargeons l'opérateur `+` dans la classe de base `Mediator`.

```dart
class Mediator {
  final Map<Type, Handler> _handlers = {};
  final List<MediatorMiddleware> _middlewares = [];

  // ... méthodes register ...

  /// Fusionne deux médiateurs en un nouveau contenant l'union des handlers.
  Mediator operator +(Mediator other) {
    final combined = Mediator();
    
    // Fusion des handlers
    combined._handlers.addAll(this._handlers);
    combined._handlers.addAll(other._handlers);
    
    // Fusion des middlewares (optionnel, ou on décide que seul le parent compte)
    combined._middlewares.addAll(this._middlewares);
    combined._middlewares.addAll(other._middlewares);
    
    return combined;
  }
}
```

**Usage utilisateur :**

```dart
final mediator = AuthChassis(...) + PaymentChassis(...);
```

### 3.3. Extensions Typées (Type-Safe API)

C'est ici que la DX change radicalement. Le générateur crée des extensions sur la classe `Mediator` de base. Ainsi, même un médiateur fusionné (qui est de type `Mediator`) bénéficie de l'autocomplétion tant que l'import du fichier généré est présent.

**Généré dans `auth.chassis.dart` :**

```dart
extension AuthMediatorExtensions on Mediator {
  // Généré pour LoginHandler
  Future<void> login(LoginCommand command) => run(command);
  
  // Généré pour GetProfileHandler
  Future<User> getProfile(GetProfileQuery query) => read(query);
}
```

-----

## 4\. Spécifications : Middlewares

Le système de plugin/middleware permet d'intercepter le flux.

```dart
abstract class MediatorMiddleware {
  Future<R> onRun<C extends Command<R>, R>(C command, NextRun<C, R> next);
  // ... onRead, onWatch
}
```

**Configuration à l'initialisation :**
Le développeur peut ajouter des plugins sur son instance générée.

```dart
final mediator = AuthChassis(authRepository: repo)
  ..addMiddleware(LoggingMiddleware())
  ..addMiddleware(SentryMiddleware());
```

-----

## 5\. Guide d'Implémentation (Plan de bataille)

### Phase 1 : Core Update (`chassis`)

1.  Modifier `Mediator` pour supporter l'opérateur `+`.
2.  Ajouter le support des `MediatorMiddleware` dans la méthode `run`, `read` et `watch`.
3.  Créer le package `chassis_annotation` avec `class ChassisHandler { const ChassisHandler(); }` et `const chassisHandler = ChassisHandler();`.

### Phase 2 : Generator (`chassis_generator`)

1.  Set up `build_runner`.
2.  Implémenter le `Visitor` qui extrait les types de paramètres des constructeurs.
3.  Implémenter le template `Mustache` ou `DartBuilder` pour générer la classe `XChassis` et les extensions.

### Phase 3 : Helpers View Model (Bonus DX)

Pour solidifier l'usage des `AsyncResult`/`StreamState` (comme discuté précédemment), ajouter dans le core :

  * `StreamState.mapData(fn)`
  * `AsyncResult.fold(onSuccess, onError)`

-----

## 6\. Exemple Complet (Le résultat final)

Voici à quoi ressemblera le code du développeur :

**1. Domain (Handler)**

```dart
@chassisHandler
class LoginHandler implements CommandHandler<LoginCommand, void> {
  final AuthRepo _repo;
  LoginHandler(this._repo);
  
  @override
  Future<void> run(LoginCommand cmd) => _repo.login(cmd.user, cmd.pass);
}
```

**2. Initialization (Main)**

```dart
void main() {
  // Le constructeur généré me force à passer les dépendances requises
  final authMediator = AuthChassis(authRepo: AuthRepoImpl());
  
  // Je peux fusionner si j'ai d'autres modules
  final mediator = authMediator + OtherChassis(otherRepo: ...);
  
  // Je branche les plugins globaux
  mediator.addMiddleware(LoggerPlugin());

  runApp(MyApp(mediator));
}
```

**3. Consommation (ViewModel)**

```dart
class LoginViewModel extends ViewModel {
  // ...
  void onLoginPressed() {
    // Autocomplétion disponible grâce aux extensions générées !
    // Plus de "run(Command())" générique.
    mediator.login(LoginCommand(...));
  }
}
```

Est-ce que ce document te convient comme référence pour lancer l'implémentation ?