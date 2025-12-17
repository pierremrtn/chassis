00. Introduction & Quick Start (README.md + 00_quick_start.md)

    Objectif : "Get running in 5 minutes".

    Contenu : Installation, exemple minimal "Counter App" (Repository + Annotation + Vue).

    Argument clé intégré : Standardization (Une structure immédiate pour tous les devs).

01. Core Architecture & Principles (01_core_architecture.md)

    Remplace : "La Vision / The Pain".

    Contenu :

        Layered Architecture : Définition stricte (UI -> Logic -> Data).

        Command-Query Separation (CQS) : Pourquoi on sépare lecture et écriture.

        The Mediator Pattern : Le découplage total.

    Argument clé intégré : Discoverability (Le code comme documentation) & Maintainability.

02. Business Logic Layer (02_business_logic.md)

    Remplace : "Handler Mechanism".

    Contenu :

        Implémentation manuelle des Command et Query.

        Structure d'un Handler (Injection de dépendances).

        Testability : Focus spécifique sur comment tester un Handler en isolation (un de vos arguments forts).

    Argument clé intégré : Testability & Mockability (Tests unitaires purs sans Flutter).

03. Automated Wiring (03_code_generation.md)

    Remplace : "Chassis Builder / L'accélérateur".

    Contenu :

        Le principe "Convention over Configuration".

        Les annotations @generateQueryHandler et @generateCommandHandler.

        Quand générer vs Quand écrire manuellement (La règle 90/10 vue sous un angle technique).

    Argument clé intégré : Enforced Architecture (Le générateur garantit le respect des règles).

04. Presentation Layer (04_ui_integration.md)

    Remplace : "Reactive UI".

    Contenu :

        State Management : Le rôle du ViewModel.

        Reactive Primitives : Comprendre et utiliser Async<T> et AsyncBuilder.

        Widget Testing : Comment mocker le Mediator pour tester l'UI (l'autre facette de la testabilité).

    Argument clé intégré : Unidirectional Data Flow (UI est une fonction de l'état).