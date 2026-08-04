# Spike : découverte cross-package des handlers (Phase 0a)

**Date :** 2026-07-25
**Verdict : GO** — le système de modules part dans la 1.0.0.

## Question

Un Builder exécuté dans le package app peut-il découvrir les classes `@chassisHandler`
d'un package *dépendance* via `buildStep.resolver` en marchant le graphe d'import
(approche `injectable`) ? `buildStep.findAssets` ne globe que le package courant —
cause racine du « un médiateur par package » actuel.

## Résultat

Montage 4 packages (spike_core → auth_module → app + spike_builder), stack moderne.
Depuis `app/lib/main.dart` (qui importe seulement le barrel public d'auth_module),
le builder trouve **tous** les handlers du module, y compris `InternalHandler` dans
`lib/src/internal.dart` (non exporté, seulement importé par le barrel). Vérifié sur
**analyzer 13.3.0 et 14.1.0**, code identique. L'invalidation incrémentale est
correcte : un handler ajouté au module après le premier build est repris sans clean.

## Versions co-résolues

analyzer 14.1.0 (et 13.3.0) · build 4.0.8 · build_runner 2.15.2 · source_gen 4.2.4 · dart_style 3.1.12

## APIs element model 2 (analyzer 13/14) — référence pour la Phase 4

- Imports : **fragment-level uniquement** — `lib.fragments` → `fragment.importedLibraries`
  (List<LibraryElement>) et `fragment.libraryExports` → `export.exportedLibrary?`.
  Pas de `LibraryElement.importedLibraries`. Itérer les fragments couvre aussi les `part`.
- Identité/cycle-guard : `LibraryElement.uri`.
- Classes : `LibraryElement.classes` (élément-level, couvre tous les fragments).
- Annotations : `TypeChecker.fromRuntime` **supprimé** en source_gen 4. Utiliser
  `TypeChecker.typeNamedLiterally('ChassisHandler', inPackage: 'chassis')`
  (ou `typeNamed(Type, inPackage:)`). Match : `hasAnnotationOfExact(element)`.
- Constructeurs : `ClassElement.constructors` → `ConstructorElement.formalParameters`
  (plus `parameters`) → `param.type.getDisplayString()` (zéro argument, `withNullability`
  supprimé) ; `param.name` est `String?`.
- Resolver : un seul `await buildStep.inputLibrary` suffit — le graphe transitif est
  entièrement lié, la traversée franchit les frontières de packages sans `libraryFor`
  par asset. L'univers du resolver = ce qui est *atteignable depuis l'input*.

## Contraintes produit actées

1. **Découverte par atteignabilité, pas par scan de package** : un module DOIT exposer
   un barrel public qui importe/exporte tout ce qui est enregistrable, et l'app doit
   importer le barrel de chaque module. À documenter comme convention (et à valider
   par le générateur : message si un module déclaré n'expose aucun handler).
2. **Performance** : la marche visite la fermeture transitive complète (flutter, etc.).
   Mitigation : élaguer par allowlist de packages (ne descendre que dans les packages
   dépendant de chassis), skipper `dart:`.
3. **Déterminisme** : dédupe/tri par (URI de librairie, nom de classe).
4. **Churn analyzer** : APIs identiques en 13 et 14 mais surface encore remodelée →
   contrainte `analyzer: '>=13.0.0 <15.0.0'`, logique de marche isolée dans un petit
   fichier.

Code du spike : scratchpad de session (`spike/`), builder de référence recopiable.
