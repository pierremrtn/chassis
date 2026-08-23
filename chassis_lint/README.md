# chassis_lint

[custom_lint](https://pub.dev/packages/custom_lint) rules enforcing the
chassis doctrine at analysis time.

## Rules

### `chassis_visible_error_path`

`run()` / `read()` on a `ViewModel` must include `onState` or `onError` among
their named arguments. The callback contract is additive — `onState` fires
for every transition and `onSuccess`/`onError` are conveniences on top — so a
dispatch with `onSuccess` alone (or no callbacks) covers the success path
only: its failures land nowhere. `watch()` is not checked (it has its own
runtime assert).

```dart
// BAD — failures are invisible.
void save() => run(SaveTodo(title), onSuccess: (todo) => ...);

// GOOD — onError (or onState) covers the error path.
void save() => run(
      SaveTodo(title),
      onSuccess: (todo) => ...,
      onError: (error, stack) => sendEvent(SaveFailed(error)),
    );
```

### `chassis_no_await_in_view_model`

ViewModels are await-free: every `await` expression, and every
`async`/`async*` modifier on an instance method, is flagged inside a
`ViewModel` subclass. Platform interactions belong in the widget; multi-step
logic belongs in a handler.

```dart
// BAD
Future<void> refresh() async {
  await read(LoadTodos(), onState: ...);
}

// GOOD — synchronous, expression-bodied dispatch.
void refresh() => read(LoadTodos(), onState: ...);
```

### `chassis_no_dispatch_in_widget`

Widgets never dispatch: any method invocation whose target's static type is a
"mediator type" — a subtype of chassis's `Mediator`, or a type declared in a
generated `.chassis.dart` library — is flagged inside a class extending
Flutter's `Widget` or `State`. Dispatch belongs to ViewModels.

```dart
// BAD — inside build():
mediator.run(SaveTodo(title));

// GOOD — the widget calls a ViewModel method.
onTap: () => context.read<TodosViewModel>().save(),
```

## Wiring

In the app package:

```yaml
# pubspec.yaml
dev_dependencies:
  custom_lint: ^0.8.1
  chassis_lint: ^0.1.0
```

```yaml
# analysis_options.yaml
analyzer:
  plugins:
    - custom_lint

custom_lint:
  rules:
    - chassis_visible_error_path
    - chassis_no_await_in_view_model
    - chassis_no_dispatch_in_widget
```

Then `dart run custom_lint` (or rely on IDE integration).

## Known limitation — primary constructors

`custom_lint_builder` 0.8.x pins `analyzer` ^8.0.0, which predates the
primary-constructor syntax stabilized in Dart 3.13. Files that declare
classes in header form (`class Foo(final int x);`) fail to parse inside the
plugin, so the chassis rules are silently inactive on those files until
custom_lint supports an analyzer version that understands Dart 3.13. The
rest of chassis (runtime, builder, docs) fully uses primary constructors;
only this lint package lags, upstream-bound.

## Development notes

This package is intentionally **not** a member of the chassis pub workspace:
`custom_lint_builder` requires `analyzer: ^8.0.0`, while the workspace pins
`analyzer: ">=12.0.0 <15.0.0"` (via `chassis_builder`). It resolves on its
own — run `dart pub get` here directly.

Tests are fixture-based: `fixtures/` is a small Flutter package whose bad
code is annotated with `// expect_lint: <rule>` comments and whose good code
is unannotated. `dart test` runs `custom_lint --fatal-infos
--fatal-warnings` in `fixtures/` and asserts a clean exit — which holds only
if every annotated lint fired and nothing else did.
