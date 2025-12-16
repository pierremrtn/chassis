---
icon: broadcast
---

# Building a Reactive UI

A key strength of modern application architecture is the ability to create user interfaces that feel "live"—they update automatically as the underlying data changes, without requiring manual refreshes. Chassis is designed with this principle at its core, using `WatchQuery` and streams to make building reactive UIs simple and predictable.

This guide provides a focused look at the components involved in creating a reactive data flow from your data source all the way to your UI widgets.

***

## The Key: `WatchQuery` and `Stream`

In Chassis, **`WatchQuery` should be your default choice** for displaying data in the UI. Any time you need to display data that can change over time, you should use a `WatchQuery`.

Unlike a `ReadQuery`, which returns a `Future` with a single result, a **`WatchQuery`** is designed to return a `Stream`. A `Stream` is like a pipe that data can flow through over time. Your UI can listen to this pipe and rebuild itself whenever new data arrives.

This is the ideal pattern for:
* Listening to real-time database changes (e.g., Firestore snapshots).
* Subscribing to data from a WebSocket.
* Displaying any data that is periodically refreshed.

## The Reactive Data Flow

Here's how the pieces connect to create a live-updating UI:

1.  **The `WatchQuery` Message:** You define a query class that implements `WatchQuery<T>`, where `T` is the type of data in the stream (e.g., `WatchQuery<List<Todo>>`).
2.  **The Repository `Stream`:** Your repository implementation (the "how") connects to a reactive data source and returns a `Stream<T>`.
3.  **The `WatchHandler`:** The handler's job is to process the `WatchQuery` and return the `Stream` from the repository. It contains the business logic for the subscription.
4.  **The `ViewModel.watch()` Method:** This is the bridge to the UI. The `ViewModel` calls `viewModel.watch(YourQuery())`, which subscribes to the stream and provides a convenient callback to handle its lifecycle.
5.  **Handling `StreamState`:** The `watch` method's callback doesn't give you raw data directly. Instead, it gives you a sealed class called `StreamState<T>`, which can be in one of three states:
    * `StreamStateLoading`: The initial state before the first piece of data has arrived.
    * `StreamStateData`: Contains a successful data emission from the stream.
    * `StreamStateError`: Contains an error if the stream threw one.
6.  **Updating UI State:** Inside the callback, you use a `when` expression on the `StreamState` to map these three states to your `ViewModel`'s own state object (e.g., setting `isLoading`, updating `data`, or setting `errorMessage`).
7.  **The Reactive Widget:** Your Flutter widget uses `context.watch<MyViewModel>()` to listen for changes. When the `ViewModel` updates its state, the widget automatically rebuilds.

## Code Example: A Closer Look

Let's break down the `ViewModel` piece from the [Quickstart Guide](./00_quick_start.md), as it's the most critical part of the presentation layer.

```dart
class GreetingViewModel extends ViewModel<GreetingState, GreetingEvent> {
  GreetingViewModel(Mediator mediator) : super(mediator, const GreetingState()) {
    _subscribeToGreetings();
  }

  void _subscribeToGreetings() {
    // 1. Subscribe to the query. The ViewModel handles the subscription
    //    lifecycle and automatically cancels it on dispose.
    watch(const WatchGreetingQuery(), (streamState) {

      // 2. The `streamState` object safely wraps the stream's output.
      streamState.when(
        // 3. Handle the initial loading state.
        loading: () {
          setState(state.copyWith(isLoading: true, error: () => null));
        },
        // 4. Handle a new piece of data from the stream.
        data: (greeting) {
          setState(state.copyWith(isLoading: false, message: greeting));
        },
        // 5. Handle any errors from the stream.
        error: (error, _) {
          setState(state.copyWith(isLoading: false, error: () => error.toString()));
        },
      );
    });
  }
}
````

By using this pattern, your `ViewModel` becomes a simple, declarative transformer. It subscribes to a stream of business data and transforms it into a stream of UI state that your widgets can consume, resulting in a robust and maintainable reactive UI.