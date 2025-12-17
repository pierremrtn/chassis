### Golden Sample : `04_reactive_ui.md` (Extrait)

```markdown
# Reactive UI with AsyncBuilder

## Overview
In modern application development, the user interface must reflect the state of asynchronous operations—whether data is loading, fully available, or has failed. Managing these states manually often leads to verbose code and inconsistent behavior.

Chassis addresses this through the **Async Primitive** pattern. Instead of treating loading and error states as side effects, they are modeled as explicit types within the `Async<T>` union.

## The Async<T> Type

The `Async<T>` class is a sealed union that represents the complete lifecycle of a piece of data. It guarantees that a value exists in exactly one of three states:

* **`AsyncLoading`**: The operation is currently in progress.
* **`AsyncData<T>`**: The operation completed successfully and holds a value of type `T`.
* **`AsyncError`**: The operation failed with an exception.

This strict typing ensures that your UI code accounts for all possible scenarios at compile time, reducing runtime errors.

## Consuming Data with AsyncBuilder

The `AsyncBuilder` widget is designed to consume an `Async<T>` object and render the appropriate UI widget. It simplifies the boilerplate typically associated with `FutureBuilder` or `StreamBuilder` by standardizing the state handling.

### Usage

The following example demonstrates how to display a user profile. The `AsyncBuilder` listens to the `state` provided by the view model and rebuilds only when necessary.

```dart
class UserProfile extends StatelessWidget {
  const UserProfile({super.key, required this.userState});

  final Async<User> userState;

  @override
  Widget build(BuildContext context) {
    return AsyncBuilder<User>(
      state: userState,
      
      // Called when data is available
      builder: (context, user) {
        return Column(
          children: [
            Avatar(url: user.avatarUrl),
            Text(user.name),
          ],
        );
      },

      // Optional: Custom error handling
      errorBuilder: (context, error) => ErrorView(message: error.toString()),
      
      // Optional: Custom loading indicator (defaults to CircularProgressIndicator)
      loadingBuilder: (context) => const ProfileSkeleton(),
    );
  }
}

```

## Handling Refetches (Anti-Flickering)

A common challenge in reactive UIs is handling "refetching"—when data is being updated but valid data is already on screen. A naive implementation might revert to a loading spinner, causing a jarring "flicker."

`AsyncBuilder` solves this with the `maintainState` property.

* **Principle**: When `maintainState` is `true` (default), the widget continues to display the *previous* `AsyncData` while the new state is `AsyncLoading`.
* **Benefit**: This preserves user context and scroll position during background updates, creating a smoother perceived performance.

To opt out of this behavior (e.g., for a "pull-to-refresh" that should clear the screen), explicitly set `maintainState: false`.
