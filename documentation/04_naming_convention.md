
# Chassis Naming Convention Guide 📜

A consistent naming convention is the cornerstone of a maintainable and scalable application. In large scale applications, predictability is key. Following these guidelines ensures that any developer can navigate the codebase, understand the purpose of a class at a glance, and locate files with ease.

This guide covers the naming for all major components of the Chassis architecture: **Commands**, **Queries**, **Handlers**, **ViewModels**, and their corresponding files.

---

## Commands

Commands represent an intent to **change the state** of the application. Their names should be clear, imperative, and describe a specific business action.

### **Pattern:** `[Verb][Resource]Command`

* **Verb:** Use an imperative, present-tense verb that clearly describes the operation.
    * *Examples:* `Create`, `Update`, `Register`, `Assign`, `Delete`, `Submit`, `Approve`.
* **Resource:** The business entity or concept the command acts upon. For targeted updates, be specific about the property being changed.
    * *Examples:* `Project`, `User`, `OrderItem`, `ProjectName`, `UserPassword`.
* **Suffix:** Always end the class name with `Command`.

### **Examples:**

* **Creation:** `CreateProjectCommand`, `RegisterUserCommand`
* **Updates:** `UpdateProjectNameCommand`, `AssignTaskToUserCommand`
* **Deletion:** `DeleteProjectCommand`, `RemoveItemFromCartCommand`
* **State Changes:** `SubmitOrderCommand`, `ApproveTimesheetCommand`

---

## Queries

Queries represent a request to **read data** from the application without modifying its state. Chassis distinguishes between two types of queries: one-time fetches (`Read`) and continuous streams (`Watch`).

### `Read` Queries (One-Time Fetch)

These queries ask for a snapshot of the system's state at a single point in time and return a `Future`.

#### **Pattern:** `Read[Resource]By[Criteria]Query`

* **Verb:** **`Read`** is the standard and preferred verb. Use **`Find`** as an alternative when the result is not guaranteed to exist.
* **Resource:** The entity or Data Transfer Object (DTO) being retrieved.
    * *Examples:* `Project`, `User`, `OrderSummary`, `ActiveUsers`.
* **Criteria (Optional):** Use `By` to specify the filter or condition for the query. Use `All` for fetching collections without a specific filter.
    * *Examples:* `ById`, `ByEmail`, `All`.
* **Suffix:** Always end the class name with `Query`.

#### **Examples:**

* `ReadProjectByIdQuery`
* `ReadAllUsersQuery`
* `FindCustomerByEmailQuery`
* `ReadOrderSummaryQuery`

### `Watch` Queries (Continuous Stream)

These queries subscribe to a data source and return a `Stream` of updates over time.

#### **Pattern:** `Watch[Resource]By[Criteria]Query`

* **Verb:** **`Watch`** is the standard verb. **`Observe`** is a suitable alternative.
* **Resource:** The entity or DTO being observed.
* **Criteria (Optional):** Specifies what is being watched.
* **Suffix:** Always end the class name with `Query`.

#### **Examples:**

* `WatchProjectByIdQuery`
* `WatchAllActiveTicketsQuery`
* `WatchOrderStatusQuery`

---

## Handlers

Handlers contain the business logic to process a single Command or Query. Their naming is strictly mechanical and derived directly from the message they handle, ensuring absolute predictability.

### **Pattern:** `[FullMessageName]Handler`

To name a handler, simply take the **full class name** of the `Command` or `Query` it processes and append the `Handler` suffix.

### **Examples:**

| Message (Command/Query) | Handler |
| :--- | :--- |
| `CreateProjectCommand` | `CreateProjectCommandHandler` |
| `UpdateProjectNameCommand` | `UpdateProjectNameCommandHandler` |
| `ReadProjectByIdQuery` | `ReadProjectByIdQueryHandler` |
| `WatchAllActiveTicketsQuery` | `WatchAllActiveTicketsQueryHandler` |

---

## ViewModels

ViewModels connect your business logic layer to the UI. They are responsible for managing UI state and dispatching Commands and Queries. A ViewModel should be tied to a specific screen or a significant widget.

### **Pattern:** `[Screen/WidgetName]ViewModel`

* **Screen/Widget Name:** The name of the View or Widget that the ViewModel serves.
* **Suffix:** Always end the class name with `ViewModel`.

### **Examples:**

* **Screen:** `LoginScreen` -> `LoginViewModel`
* **Screen:** `ProjectDetailsPage` -> `ProjectDetailsViewModel`
* **Widget:** `UserProfileHeader` -> `UserProfileHeaderViewModel`