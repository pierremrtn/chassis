import 'dart:async';

import 'package:chassis/chassis.dart';
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:chassis_flutter/src/safe_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/streams.dart';

/// {@template view_model}
/// A base class for view models that provides state management and event handling.
///
/// This class extends [SafeChangeNotifier] to provide safe disposal behavior
/// and integrates with the chassis mediator pattern for handling commands and queries.
/// It manages both state (of type [T]) and events (of type [E]) in a reactive way.
///
/// The ViewModel provides:
/// - State management with automatic UI updates
/// - Event emission for one-time notifications
/// - Integration with the chassis mediator for commands and queries
/// - Automatic cleanup of resources and subscriptions
/// - Stream watching with state management
///
/// Example usage:
/// ```dart
/// class UserViewModel extends ViewModel<UserState, UserEvent> {
///   UserViewModel() : super(UserState.initial());
///
///   void loadUser(String userId) {
///     read(GetUserQuery(userId: userId), (state) {
///       switch (state) {
///         case FutureLoading():
///           setState(UserState.loading());
///         case FutureSuccess(:final data):
///           setState(UserState.loaded(data));
///         case FutureError(:final error):
///           setState(UserState.error(error.toString()));
///       }
///     });
///   }
///
///   void createUser(String name, String email) {
///     run(CreateUserCommand(name: name, email: email), (state) {
///       switch (state) {
///         case FutureSuccess(:final user):
///           setState(UserState.loaded(user));
///           sendEvent(UserCreatedEvent(user));
///         case FutureError(:final error):
///           sendEvent(UserCreationFailedEvent(error.toString()));
///       }
///     });
///   }
/// }
/// ```
/// {@endtemplate}
class ViewModel<T, E> extends SafeChangeNotifier {
  /// {@macro view_model}
  ViewModel(T initial) : _state = initial;

  /// The chassis mediator instance for handling commands and queries.
  Mediator get mediator => Mediator.instance;

  /// List of cleanup functions to be called when the view model is disposed.
  final List<void Function()> _cleanups = [];

  /// Stream controller for broadcasting events.
  final StreamController<E> _events = StreamController.broadcast();

  /// The current state of the view model.
  T _state;

  /// The current state of the view model.
  T get state => _state;

  /// Stream of events emitted by this view model.
  Stream<E> get events => _events.stream;

  /// Updates the current state and notifies listeners.
  ///
  /// This method updates the internal state and triggers a rebuild of all
  /// listening widgets. It does not perform any equality checks, so it will
  /// notify listeners every time it's called.
  ///
  /// If the view model is disposed, the state will be updated but listeners
  /// won't be notified due to the safe disposal behavior.
  @protected
  void setState(T state) {
    _state = state;
    notifyListeners();
  }

  /// Sends an event to all listeners of the events stream.
  ///
  /// Events are used for one-time notifications that don't require state changes,
  /// such as navigation events, snackbar messages, or other side effects.
  @protected
  void sendEvent(E event) {
    _events.add(event);
  }

  @override
  void dispose() {
    for (final cleanup in _cleanups.reversed) {
      try {
        cleanup();
      } catch (e) {
        continue;
      }
    }
    _cleanups.clear();
    super.dispose();
  }

  /// Watches a streaming query and calls [onState] with state updates.
  ///
  /// This method subscribes to a [Watch] query and automatically manages the
  /// subscription lifecycle. It will call [onState] with:
  /// - [StreamStateLoading] initially
  /// - [StreamStateData] when data is received
  /// - [StreamStateError] when an error occurs
  ///
  /// The subscription is automatically disposed when the view model is disposed.
  @protected
  void watch<Q extends Watch<R>, R>(
    Q query,
    void Function(StreamState<R>) onState,
  ) {
    onState(StreamStateLoading());
    autoDisposeStreamSubscription(
      mediator.watch(query).listen(
            (data) => onState(StreamStateData(data)),
            onError: (e, s) => onState(StreamStateError(e, s)),
          ),
    );
  }

  /// Runs an async operation and manages its state.
  ///
  /// This is an internal method that handles the common pattern of running
  /// async operations with state management. It calls [onState] with:
  /// - [FutureLoading] when the operation starts
  /// - [FutureSuccess] when the operation succeeds
  /// - [FutureError] when the operation fails
  Future<FutureResult<R>> _runAsyncOperation<P, R>(
    P param,
    Future<R> Function(P params) executor, {
    void Function(FutureState<R>)? onState,
  }) async {
    onState?.call(FutureLoading());
    try {
      final res = await executor(param);
      final state = FutureSuccess(res);
      onState?.call(state);
      return state;
    } catch (e, s) {
      final res = FutureError<R>(e, s);
      onState?.call(res);
      return res;
    }
  }

  /// Executes a read query and optionally calls [onState] with state updates.
  ///
  /// This method runs a [Read] query through the mediator and can optionally
  /// provide state updates through the [onState] callback. The callback will
  /// receive [FutureLoading], [FutureSuccess], or [FutureError] states.
  ///
  /// Returns a [FutureResult] that can be used for further processing.
  @protected
  Future<FutureResult<R>> read<Q extends Read<R>, R>(
    Q query, [
    void Function(FutureState<R>)? onState,
  ]) async {
    return await _runAsyncOperation(
      query,
      mediator.read<R>,
      onState: onState,
    );
  }

  /// Executes a command and optionally calls [onState] with state updates.
  ///
  /// This method runs a [Command] through the mediator and can optionally
  /// provide state updates through the [onState] callback. The callback will
  /// receive [FutureLoading], [FutureSuccess], or [FutureError] states.
  ///
  /// Returns a [FutureResult] that can be used for further processing.
  @protected
  Future<FutureResult<R>> run<C extends Command<R>, R>(
    C command, [
    void Function(FutureState<R>)? onState,
  ]) async {
    return await _runAsyncOperation(
      command,
      mediator.run<R>,
      onState: onState,
    );
  }
}

/// {@template base_utils}
/// Extension that provides utility methods for managing resources and subscriptions
/// in view models with automatic cleanup.
///
/// These methods help manage the lifecycle of various resources and ensure they
/// are properly disposed when the view model is disposed.
/// {@endtemplate}
extension BaseUtils on ViewModel {
  /// {@macro base_utils}
  /// Automatically disposes a [Disposable] object when the view model is disposed.
  @protected
  void autoDispose(Disposable disposable) {
    _cleanups.add(disposable.dispose);
  }

  /// {@macro base_utils}
  /// Automatically cancels a stream subscription when the view model is disposed.
  @protected
  void autoDisposeStreamSubscription(StreamSubscription sub) {
    _cleanups.add(() => sub.cancel());
  }

  /// {@macro base_utils}
  /// Listens to a [Listenable] and automatically removes the listener when disposed.
  @protected
  void listenTo(Listenable listenable, void Function() listener) {
    listenable.addListener(listener);
    _cleanups.add(() => listenable.removeListener(listener));
  }

  /// {@macro base_utils}
  /// Merges multiple [Listenable] objects and listens to the combined result.
  @protected
  void mergeAndListenTo(
    Iterable<Listenable> listenables,
    void Function() listener,
  ) {
    final merge = Listenable.merge(listenables);
    listenTo(merge, listener);
  }

  /// {@macro base_utils}
  /// Listens to multiple streams and calls [listener] when any stream emits.
  @protected
  void listenToStreams(
    Iterable<Stream> streams,
    void Function() listener,
  ) {
    final merge = MergeStream(streams);
    autoDisposeStreamSubscription(merge.listen((_) => listener()));
  }

  /// {@macro base_utils}
  /// Combines multiple streams and calls [listener] with the latest values from all streams.
  @protected
  void combineStreams<R>(
    Iterable<Stream<R>> streams,
    void Function(List<R>) listener,
  ) {
    autoDisposeStreamSubscription(
      CombineLatestStream.list<R>(streams).listen(
        listener,
      ),
    );
  }

  /// {@macro base_utils}
  /// Combines two streams and calls [listener] with the latest values from both streams.
  @protected
  void combineStreams2<R1, R2>(
    Stream<R1> a,
    Stream<R2> b,
    void Function(R1 a, R2 b) listener,
  ) {
    final combinedStream = CombineLatestStream.combine2(
      a,
      b,
      (a, b) => (a, b),
    );
    autoDisposeStreamSubscription(
      combinedStream.listen(
        (data) => listener(data.$1, data.$2),
      ),
    );
  }

  /// {@macro base_utils}
  /// Combines three streams and calls [listener] with the latest values from all streams.
  @protected
  void combineStreams3<R1, R2, R3>(
    Stream<R1> a,
    Stream<R2> b,
    Stream<R3> c,
    void Function(R1 a, R2 b, R3 c) listener,
  ) {
    final combinedStream = CombineLatestStream.combine3(
      a,
      b,
      c,
      (a, b, c) => (a, b, c),
    );
    autoDisposeStreamSubscription(
      combinedStream.listen(
        (data) => listener(data.$1, data.$2, data.$3),
      ),
    );
  }
}
