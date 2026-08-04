# Feedback sur le plan « Chassis → production-ready (itération 1.0.0) »

Retour issu d'une seconde review indépendante (lecture des 3 packages, `analyze` + `test` sur chacun, exécution du générateur, tests jetables pour vérifier les comportements). Les constats ci-dessous marqués « vérifié » ont été reproduits en exécutant du code, pas déduits.

---

## 1. Verdict

Le plan est solide et couvre l'hygiène mieux que la première review (workspace, CI, licences, CHANGELOGs, code mort, exemples cassés). Le redesign d'`Async` en 2a est meilleur que ce qui avait été proposé ailleurs : faire porter `previous` par `AsyncData<T>?` prouve l'existence d'une valeur **par le type** et règle d'un seul coup le bug nullable *et* l'ambiguïté `AsyncLoading(previous: null)`. La suppression du RepositoryGenerator est la bonne décision, cohérente avec ce que [`skills/README.md`](skills/README.md) annonçait déjà.

Trois réserves :

1. **Trois bugs de production vérifiés ne sont pas couverts** (tous dans `ViewModel`).
2. **La contrainte analyzer visée est fausse** : `^7.0.0` ne résout toujours pas avec l'écosystème réel. La cible est `^13`.
3. **Une décision d'architecture est actée depuis** (médiateur concret généré) et elle change le périmètre des phases 2b, 4 et 5.

---

## 2. Décision actée : médiateur concret + interfaces de module générées

`operator +` et les extensions `on Mediator` sont remplacés par une composition **à la génération**. C'est le changement structurant de cette itération ; le reste du feedback en découle.

### Modèle cible

Chaque package partagé génère **une interface**, l'app génère **l'implémentation**.

```dart
// package auth — GÉNÉRÉ
abstract interface class AuthMediator {
  Future<void> login(String user, String password);
  Future<User> getProfile(String userId);
}

// package auth — écrit à la main, réutilisable tel quel entre apps
class LoginViewModel extends ViewModel<LoginState, LoginEvent> {
  LoginViewModel(this._mediator);
  final AuthMediator _mediator;   // ne connaît pas l'app
}
```

```dart
// app — GÉNÉRÉ depuis @ChassisApp(modules: [AuthModule, PaymentModule])
class AppMediator extends Mediator implements AuthMediator, PaymentMediator {
  AppMediator({required IAuthRepository authRepository, required IPaymentGateway gateway})
      : _login = LoginHandler(authRepository), ... ;

  @override
  Future<void> login(String user, String password) =>
      _dispatch(LoginCommand(user, password), _login.run);
}
```

### Ce que ça apporte

| Bénéfice | Mécanisme |
|---|---|
| **Réutilisation inter-packages étendue** | Un package peut désormais exporter ses **ViewModels** — impossible aujourd'hui, ils dépendraient du médiateur de l'app |
| **Complétude garantie par le compilateur** | Si un handler manque, `AppMediator` n'implémente pas l'interface et **ne compile pas**. Aucune validation custom nécessaire |
| **Mock trivial** | On mocke `AuthMediator`, l'interface du package, pas l'app |
| **Conflits détectés** | Deux modules exposant `getUser` avec des signatures différentes → erreur de compilation lisible, au lieu de l'ambiguïté d'extension actuelle (un des pires messages d'erreur de Dart) |
| **Plus de cast non vérifié** | Le chemin nominal n'utilise plus `_handlers[q.runtimeType]` ni `as Future<T>` |

### Invariants non négociables

- **Chaque méthode générée passe par `_dispatch(message, handler.run)`, jamais par le handler en direct.** C'est le seul endroit où l'on peut casser le bénéfice principal du framework : la chaîne de middlewares. À couvrir par un test dédié (middleware enregistreur + appel via une méthode générée).
- **La `Map<Type, Handler>` et `read`/`run`/`watch` génériques restent.** Ils cessent d'être le chemin nominal mais servent au dispatch dynamique, aux outils et aux cas non générés. Les exceptions actionnables de la phase 2b gardent donc leur utilité.
- **Signatures identiques entre deux modules** : le type system serait satisfait par une seule implémentation alors qu'il s'agit de deux opérations distinctes. Faux positif silencieux — le générateur doit le détecter et refuser explicitement.

### Inconnue technique à lever en premier

`buildStep.findAssets` ne globe que le package courant : c'est la cause racine du « un médiateur par package » actuel. La sortie est de rendre la composition **explicite** (`@ChassisApp(modules: [...])`) et de remonter aux handlers via le resolver en suivant le graphe d'import — l'approche d'`injectable`, éprouvée.

**Spike de 1 à 2 jours sur un montage à 2 packages, à placer en phase 0.** Tout le pari en dépend, et son résultat gouverne l'ordonnancement (voir §7).

---

## 3. Manquant : trois bugs de production vérifiés

### 3.1 `watch()` empile les souscriptions — le plus grave

`ViewModel.watch()` ajoute une souscription sans jamais annuler la précédente. Un re-watch sur changement de paramètre (`watchUser(newId)`) laisse **deux flux vivants qui écrivent dans le même state**, jusqu'au `dispose()`.

*Vérifié : deux `watch()` sur le même stream → les deux callbacks se déclenchent.*

La phase 3a ne traite que le contrat de callbacks. Il faut une clé d'annulation ou un handle retourné — c'est une décision d'API, à prendre dans la même phase.

### 3.2 `run()` attrape les exceptions des callbacks

Les callbacks sont invoqués **à l'intérieur du `try`** : si `onData` lève (bug UI, `copyWith` sur un state mal formé), l'exception est capturée et **un succès est rapporté comme `AsyncError`**. L'utilisateur voit un écran d'erreur pour une opération réussie, et la vraie erreur est masquée.

*Vérifié : `run(Future.value(1), onData: (_) => throw StateError(...))` retourne `AsyncError`.*

⚠️ **Rendre `onData`/`onError` additifs (3a) aggrave ce bug** si rien ne change par ailleurs : plus de callbacks dans le bloc protégé. La phase doit écrire explicitement que **les callbacks sont invoqués hors du `try`**.

### 3.3 Events perdus avant l'abonnement

`_events` est un `StreamController.broadcast()` sans buffer. Dans `_ViewModelEventsProvider`, `listen` a lieu **après** `create()` : tout event émis pendant la construction est perdu — alors que la dartdoc de `withEvents` promet précisément l'inverse (« created eagerly … so that events emitted during construction are not missed »).

*Vérifié : un event émis avant l'abonnement n'est jamais reçu.*

Fix : buffer borné jusqu'au premier abonné (rxdart est déjà une dépendance de `chassis_flutter`). Choix sémantique à assumer — rejouer un event de navigation serait un bug. Le test listé en 3c ne couvre que le cas après dispose.

---

## 4. Ajouts à coût quasi nul, dans des phases déjà ouvertes

### 4.1 Rendre les Command/Query loggables — phase 2c

`Command` et `Query` sont des classes vides sans `toString`. Le `LoggingMiddleware` produira donc `[chassis] run CreateUserCommand failed after 34ms` — **sans les paramètres**, alors que c'est exactement ce que [`Notes.md`](Notes.md) réclame.

Ajouter un `Map<String, Object?> get params => const {}` surchargeable sur les classes de base (et le faire générer par le codegen pour les messages générés). C'est la différence entre « on pourrait tout tracer » et « voilà les paramètres de la commande qui a échoué ». Quelques heures, dans la phase qui construit le middleware.

### 4.2 `==` / `hashCode` sur `Async` — phase 2a

La classe est réécrite de toute façon. Sans égalité, chaque `setState` notifie même à état identique. C'est aussi un prérequis si un cache de queries revient au programme un jour.

### 4.3 Validation de complétude au build — phase 4, **rétrogradée**

Initialement recommandée comme mécanisme principal, elle devient **un filet** : avec `implements AuthMediator`, la complétude est garantie par le compilateur. Reste utile pour les messages d'erreur en amont (« `GetUserQuery` n'a aucun handler dans les modules déclarés ») et pour le chemin dynamique.

---

## 5. Corrections techniques

### 5.1 La cible analyzer est `^13`, pas `^7`

Résolution de l'écosystème codegen actuel, faite sur un projet neuf :

```
analyzer 13.3.0 · source_gen 4.2.4 · build 4.0.8 · dart_style 3.1.12
json_serializable 6.14.0 · freezed 4.0.0-dev.3
```

Viser `^7.0.0` laisse `chassis_builder` insolvable avec toute app utilisant `freezed` ou `json_serializable` récents — c'est-à-dire à peu près toutes. *(Reproduit : `chassis_builder` + `json_serializable ^6.9.0` → version solving failed.)*

La cible est donc la **migration complète vers l'element model 2** (`Element2`/fragments, `getDisplayString()` sans `withNullability`). La phase 4 n'est pas « M→L » : c'est **L**, et c'est le seul poste à incertitude réelle du plan.

### 5.2 Les phases 2a et 3a doivent être conçues ensemble

Le `previous` typé ne sert à rien si les helpers ne le propagent pas. Aujourd'hui `watch()`/`run()` émettent un `Async.loading()` nu, qui **efface la donnée courante à chaque refetch** — l'anti-flicker reste théorique tant que l'appelant doit écrire `state.user.toLoading()` à la main.

À trancher en 2a, pas à découvrir en 3 : soit les helpers reçoivent l'état précédent, soit `previous` n'existe que pour les transitions manuelles et il faut le documenter comme tel.

### 5.3 La phase 5 sous-estime la réécriture doc

Ce ne sont pas des snippets à corriger :

- **README racine** : la section « Code Generation », le « 90/10 principle » et les étapes 1–2 du Quick Example reposent **entièrement** sur le RepositoryGenerator supprimé. C'est une réécriture de section.
- **Décision médiateur** : `docs/00_quick_start.md` célèbre les extensions générées, `docs/03_code_generation.md` documente tout le flow, et les skills `chassis-bootstrap-app` (le composition root change complètement), `chassis-register-handler-with-codegen` et `chassis-organize-feature` sont à refaire, pas à auditer.

---

## 6. Impact de la décision médiateur sur les phases existantes

| Phase | Changement |
|---|---|
| **1** | Ne pas investir dans les extensions `on Mediator` — elles disparaissent |
| **2b** | **`operator +` est retiré, pas amélioré.** Le plan prévoit de faire passer sa détection de collision par le nouveau chemin : c'est payer deux fois pour une API qui saute. La composition passe au build, où le conflit est détecté au lieu d'être écrasé silencieusement |
| **4** | N'est plus « corriger le générateur » mais « réécrire le générateur sur analyzer 13 **avec un nouveau modèle de sortie** ». Les correctifs `_toParamName` (dérivé du nom d'élément, dédup par `Element` résolu) et `_generateMethodName` (`replaceFirst(RegExp(r'Handler$'), '')`) restent pertinents. Les goldens ciblent le nouveau modèle. Taille : **L → XL** |
| **5** | Voir §5.3 |

---

## 7. Ordonnancement recommandé

**Le spike modules gouverne la forme de la 1.0.0.** À placer en phase 0, avant tout engagement.

**Si le spike passe** → intégrer le système de modules dans cette itération. La phase 4 devient le cœur du produit (L→XL), mais la doc n'est écrite qu'une fois et la 1.0.0 est le vrai produit.

**Si le spike échoue ou dérape** → livrer 0-3 + 5 en **mode manuel** : enregistrement des handlers à la main dans le composition root (six lignes), sans `operator +` ni extensions. La surface publique de la 1.0.0 devient petite et stable, le système de modules s'ajoute en 1.1 **sans rien casser**, et le blocage analyzer cesse d'être sur le chemin critique. Coût : la doc montre le dispatch manuel, à réécrire en 1.1.

Dans les deux cas, ne pas publier une 1.0.0 dont la seule histoire de composition est `operator +` et les extensions : c'est la dernière fenêtre où ce choix est gratuit, et le plan note lui-même que « les breaking changes sont libres ».

---

## 8. Récapitulatif des ajouts au plan

| # | Item | Phase | Taille |
|---|---|---|---|
| 1 | Spike modules 2 packages (resolver cross-package) | **0** | S |
| 2 | `watch()` : annulation / remplacement de souscription | 3a | S |
| 3 | `run()`/`watch()` : callbacks invoqués hors du `try` | 3a | XS |
| 4 | Events : buffer borné jusqu'au premier abonné | 3b | S |
| 5 | `params` introspectables sur Command/Query | 2c | XS |
| 6 | `==`/`hashCode` sur `Async` | 2a | XS |
| 7 | Propagation de `previous` par les helpers `run`/`watch` | 2a+3a | S |
| 8 | Cible analyzer `^13` (element model 2) | 4 | — (requalification) |
| 9 | Retrait d'`operator +` et des extensions | 2b | S |
| 10 | Génération interfaces de module + `AppMediator` concret | 4 | L |
| 11 | Réécriture section README + docs codegen + 3 skills | 5 | M |
