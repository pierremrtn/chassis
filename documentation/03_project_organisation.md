# Chassis Project Structure Guide 🏗️

The recommended project structure for Chassis is based on **Clean Architecture** principles. It physically separates your core business logic from your UI and infrastructure details. This is achieved by splitting the project into at least two main packages: a pure Dart `domain` package and a Flutter `app` package.

This separation ensures your business logic remains independent and highly testable, free from any Flutter-specific code.

---

## The `domain` Package (Core Business Logic) 🧠

This is a **pure Dart package** that contains the heart of your application. It has **zero dependencies on Flutter**. It defines *what* your application does, not *how* it does it.

The recommended structure inside `lib/src/` is:

* **`models/`**: Contains your core business entities and data structures as plain Dart objects (PODOs).
    * *Example:* `user.dart`, `project.dart`.
* **`use_cases/`**: Holds all your business logic, organized as Chassis messages and handlers. It's helpful to group these by feature or entity.
    * *Example:* `use_cases/project/create_project_command.dart`
    * *Example:* `use_cases/project/create_project_command_handler.dart`
    * *Example:* `use_cases/user/read_user_by_id_query.dart`
* **`data/`**: Defines the contracts for your data layer. This folder contains the **abstract classes** (interfaces) for your repositories.
    * *Example:* `project_repository.dart` would define methods like `Future<Project> getById(String id);`.

---

## The `app` Package (Flutter UI & Infrastructure) 📱

This is your main Flutter application package. It depends on the `domain` package and provides the concrete implementations for the contracts and the UI that the user interacts with.

The recommended structure inside `lib/` is:

* **`data/`**: Contains the **implementations** of the repository interfaces defined in the `domain` package. This is where you'll have API clients, database connections, and other data source logic.
    * *Example:* `data/repositories/project_repository_impl.dart` (implements the `ProjectRepository` interface).
    * *Example:* `data/services/api_client.dart`.
* **`ui/`** or **`presentation/`**: This is where all your Flutter code lives. It should be organized **by feature**, not by widget type. This keeps all related UI files together.
    * A typical feature folder, like `ui/features/project_details/`, contains:
        * `project_details_screen.dart`: The main widget for the feature's UI.
        * `project_details_view_model.dart`: The ViewModel that manages the screen's state.
        * `widgets/`: A sub-folder for any smaller widgets that are specific to this feature.
    * You might also have a `ui/shared/` folder for widgets, constants, or utilities used across multiple features.

---

## Example Project Tree

Here’s how the structure looks in practice for a simple project:

```
chassis_project/
├── packages/
│   └── project_domain/
│       ├── lib/
│       │   ├── src/
│       │   │   ├── data/
│       │   │   │   └── project_repository.dart  // Abstract class
│       │   │   ├── models/
│       │   │   │   └── project.dart
│       │   │   └── use_cases/
│       │   │       └── project/
│       │   │           ├── create_project_command.dart
│       │   │           └── create_project_command_handler.dart
│       │   └── project_domain.dart            // Package exports
│       └── pubspec.yaml
│
└── project_app/
    ├── lib/
    │   ├── data/
    │   │   ├── repositories/
    │   │   │   └── project_repository_impl.dart // Concrete implementation
    │   │   └── services/
    │   │       └── api_client.dart
    │   ├── ui/
    │   │   ├── features/
    │   │   │   └── project_details/
    │   │   │       ├── widgets/
    │   │   │       │   └── task_list_item.dart
    │   │   │       ├── project_details_screen.dart
    │   │   │       └── project_details_view_model.dart
    │   │   └── shared/
    │   │       └── widgets/
    │   │           └── loading_spinner.dart
    │   └── main.dart                          // DI and app startup
    └── pubspec.yaml                         // Depends on project_domain
```

This structure provides a robust foundation for building scalable, testable, and maintainable Flutter applications with Chassis.