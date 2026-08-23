import 'dart:async';

import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/foundation.dart';

/// Application-wide chassis configuration.
///
/// [initialize] installs the [Mediator] that every [ViewModel] dispatches
/// through. Call it once at startup, before `runApp`:
///
/// ```dart
/// void main() {
///   Chassis.initialize(AppMediator(
///     userRepository: UserRepository(),
///   ));
///   runApp(const MyApp());
/// }
/// ```
///
/// The installed mediator is resolved lazily, at a ViewModel's first
/// dispatch — never at construction. In tests, don't touch this global:
/// pass a mediator to the ViewModel under test instead
/// (`MyViewModel(initialState, mediator: fakeMediator)`), which always wins
/// over the global.
abstract final class Chassis {
  static Mediator? _mediator;
  static ChassisTelemetry? _telemetry;

  /// Installs the application's [Mediator] and, optionally, the
  /// [ChassisTelemetry] observation point. Last call wins — an initialize
  /// without [telemetry] uninstalls a previously installed hook (consistent
  /// with the mediator).
  static void initialize(Mediator mediator, {ChassisTelemetry? telemetry}) {
    _mediator = mediator;
    _telemetry = telemetry;
  }

  /// Clears the installed mediator and telemetry, so a test suite can
  /// restore the uninitialized state. Prefer the per-ViewModel `mediator`
  /// parameter over [initialize]/[reset] pairs in tests.
  @visibleForTesting
  static void reset() {
    _mediator = null;
    _telemetry = null;
  }
}

/// A handle on a subscription started with [ViewModel.watch].
///
/// Allows cancelling the subscription before the ViewModel is disposed.
class WatchHandle {
  WatchHandle._(this._cancel);

  /// A handle that was never live — returned when the watched stream could
  /// not be materialized (the error was reported through the callbacks).
  WatchHandle._cancelled()
    : _cancel = ((_) => Future<void>.value()),
      _cancelled = true;

  /// The reason is threaded so the owning ViewModel can report the exact
  /// end cause ([WatchEndReason]) to telemetry — exactly once per watch.
  final Future<void> Function(WatchEndReason reason) _cancel;
  bool _cancelled = false;

  /// Whether [cancel] has been called (directly, by a keyed replacement, by
  /// the watched stream completing, or by the ViewModel's disposal).
  bool get isCancelled => _cancelled;

  /// Cancels the underlying stream subscription. Safe to call twice.
  Future<void> cancel() => _cancelWith(WatchEndReason.cancelled);

  Future<void> _cancelWith(WatchEndReason reason) {
    if (_cancelled) return Future<void>.value();
    _cancelled = true;
    return _cancel(reason);
  }
}

/// {@template view_model}
/// A base class for view models that provides state management and event
/// handling.
///
/// This class extends [SafeChangeNotifier] to provide safe disposal behavior.
/// It manages both state (of type [T]) and events (of type [E]) in a reactive
/// way.
///
/// The ViewModel provides:
/// - State management with automatic UI updates
/// - Event emission for one-time notifications
/// - Message dispatch with lifecycle reporting: [run] for a [Command],
///   [read] for a [ReadQuery], [watch] for a [WatchQuery] — each reported
///   as [Async] states
/// - Automatic cleanup of resources and subscriptions
///
/// ViewModels never reference the generated mediator class: they dispatch
/// message objects, and the mediator installed by [Chassis.initialize] (or
/// passed to the constructor, which wins — the testing seam) routes them to
/// their handlers. A ViewModel method is synchronous and expression-bodied;
/// all asynchrony lives in the dispatch machinery:
///
/// ```dart
/// void addTodo(String title) => run(
///       AddTodoCommand(title),
///       onState: (todo) => setState(state.copyWith(lastAdded: todo)),
///       onError: (error, stack) => sendEvent(AddTodoFailed(error)),
///     );
/// ```
///
/// ## Callback contract of [run], [read], and [watch]
///
/// - `onState` (if provided) is invoked for **every** transition: loading,
///   data, and error.
/// - `onSuccess` ([run]/[read]) / `onData` ([watch]) and `onError` are
///   **additive** conveniences, invoked *after* `onState` for their
///   respective transition. Providing them never suppresses `onState`. They
///   carry the same value: a [run] result is a *success*, a [watch] emission
///   is *data*.
/// - An optimistic [run] emits its `optimistic` [AsyncData] through `onState`
///   at dispatch instead of a loading state; `onSuccess`, `onError`, and the
///   result transition of `onState` fire only for the real result.
/// - `onDone` ([watch] only) is invoked when the watched stream completes —
///   never on cancellation (keyed replacement, handle cancel, or disposal).
/// - Callbacks are invoked *outside* the internal try/catch: an exception
///   thrown by your callback is a bug in the callback and propagates as such —
///   it is never converted into an [AsyncError].
///
/// ## Concurrency
///
/// Operations are keyed: by default, the key is the message's runtime type,
/// so two dispatches of the same message class interact under the same
/// [RunPolicy] (and a re-[watch] of the same query class replaces the
/// previous subscription). Pass an explicit `key` to separate them — or to
/// make *different* message types share a policy. All runs sharing a key
/// must have the same result type `R`.
///
/// Example usage:
/// ```dart
/// class UserViewModel extends ViewModel<UserState, UserEvent> {
///   UserViewModel({super.mediator}) : super(UserState.initial());
///
///   void loadUser(String userId) => read(
///         GetUserQuery(userId: userId),
///         policy: const RunPolicy.restartable(),
///         current: state.user,
///         onState: (user) => setState(state.copyWith(user: user)),
///       );
///
///   void watchUser(String userId) => watch(
///         // Re-calling watchUser with a new id replaces the previous
///         // subscription: watches are keyed by query type by default.
///         WatchUserQuery(userId: userId),
///         current: state.user,
///         onState: (user) => setState(state.copyWith(user: user)),
///       );
///
///   void createUser(String name, String email) => run(
///         CreateUserCommand(name: name, email: email),
///         policy: const RunPolicy.droppable(),
///         onState: (user) => setState(state.copyWith(user: user)),
///         onSuccess: (user) => sendEvent(UserCreatedEvent(user)),
///         onError: (error, stack) => sendEvent(UserCreationFailedEvent(error)),
///       );
/// }
/// ```
/// {@endtemplate}
class ViewModel<T, E> extends SafeChangeNotifier {
  /// {@macro view_model}
  ///
  /// [mediator] overrides the application mediator installed by
  /// [Chassis.initialize] — the seam used in tests to inject a fake. When
  /// null, the global one is resolved lazily at the first dispatch.
  ViewModel(T initial, {Mediator? mediator})
    : _state = initial,
      _mediatorOverride = mediator {
    final t = Chassis._telemetry;
    if (t != null) {
      try {
        t.viewModelCreated(this);
      } catch (error, stack) {
        _reportTelemetryError(error, stack);
      }
    }
  }

  /// Maximum number of events buffered before the first listener subscribes.
  static const int _maxPendingEvents = 128;

  final Mediator? _mediatorOverride;

  /// List of cleanup functions to be called when the view model is disposed.
  final List<void Function()> _cleanups = [];

  /// Subscriptions started with [watch], replaceable per key.
  final Map<Object, WatchHandle> _keyedWatches = {};

  /// Per-key generation counters for [RunPolicy.restartable]: a run whose
  /// epoch is no longer current has been superseded and skips its callbacks.
  final Map<Object, int> _runEpochs = {};

  /// In-flight run per key, for [RunPolicy.droppable].
  final Map<Object, Future<Async<Object?>>> _inFlightRuns = {};

  /// Telemetry dispatchId of the in-flight run per key, so a dropped call
  /// can name the winner ([ChassisTelemetry.policyOutcome]). Populated only
  /// while telemetry is active.
  final Map<Object, int> _inFlightDispatchIds = {};

  /// Tail of the run queue per key, for [RunPolicy.sequential].
  final Map<Object, Future<Async<Object?>>> _runQueues = {};

  /// Pending debounce timer per key, for [RunPolicy.restartable] with a
  /// non-zero debounce window.
  final Map<Object, Timer> _debounceTimers = {};

  /// Callers coalesced by a debounce window, per key. All of them resolve
  /// with the winning run's result once it dispatches.
  final Map<Object, List<_PendingRun>> _pendingRuns = {};

  /// Last confirmed [AsyncData] per run key: the latest data completed by a
  /// run on that key (seeded, at an optimistic dispatch, with the data
  /// carried by its `current`). Rollback target when an optimistic run
  /// fails — never the optimistic value itself.
  final Map<Object, AsyncData<Object?>> _lastConfirmed = {};

  /// Result type per active run key, tracked in debug mode only: two runs
  /// sharing a key with different result types would otherwise fail later
  /// with a cryptic CastError inside the policy machinery.
  final Map<Object, Type> _debugRunResultTypes = {};

  /// Events emitted before anyone subscribed to [events] (see [sendEvent]).
  final List<E> _pendingEvents = [];
  bool _hadFirstListener = false;

  /// Stream controller for broadcasting events.
  late final StreamController<E> _events = StreamController<E>.broadcast(
    onListen: _flushPendingEvents,
  );

  /// The current state of the view model.
  T _state;

  /// The current state of the view model.
  T get state => _state;

  /// Stream of events emitted by this view model.
  ///
  /// Events emitted *before the first subscription* are buffered (bounded)
  /// and delivered to the first subscriber, so events sent during
  /// construction are not lost. After the first subscription, regular
  /// broadcast semantics apply: events emitted while nobody listens are
  /// dropped.
  Stream<E> get events => _events.stream;

  void _flushPendingEvents() {
    if (_hadFirstListener) return;
    _hadFirstListener = true;
    for (final event in _pendingEvents) {
      _events.add(event);
    }
    _pendingEvents.clear();
  }

  /// Resolves the mediator to dispatch through: the constructor override if
  /// any, else the application mediator installed by [Chassis.initialize].
  Mediator _requireMediator(Object message) =>
      _mediatorOverride ??
      Chassis._mediator ??
      (throw StateError(
        'ViewModel<$T, $E> dispatched ${message.runtimeType} but no Mediator '
        'is available.\n'
        'Fix: initialize chassis once at startup, before runApp:\n'
        '  void main() {\n'
        '    Chassis.initialize(AppMediator(...));\n'
        '    runApp(const MyApp());\n'
        '  }\n'
        'In tests, prefer passing one to the ViewModel instead: '
        'MyViewModel(initialState, mediator: fakeMediator).',
      ));

  // --- Telemetry emission (all guarded: never throws into the app, no
  // work at all when no hook is installed) ---

  void _reportTelemetryError(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'chassis_flutter',
        context: ErrorDescription(
          'while emitting a telemetry event from ViewModel<$T, $E>',
        ),
      ),
    );
  }

  /// Mints this dispatch's id through the hook. Null when telemetry is
  /// inactive or the hook threw — every later emission of the flow is then
  /// skipped.
  int? _telemetryDispatchRequested(
    Object message,
    DispatchKind kind,
    Object key,
    RunPolicy policy, {
    required bool optimistic,
  }) {
    final t = Chassis._telemetry;
    if (t == null) return null;
    try {
      return t.dispatchRequested(
        this,
        message,
        kind,
        key,
        policy,
        optimistic: optimistic,
      );
    } catch (error, stack) {
      _reportTelemetryError(error, stack);
      return null;
    }
  }

  void _telemetryPolicyOutcome(
    int? dispatchId,
    PolicyDecision decision, {
    int? winnerDispatchId,
  }) {
    final t = Chassis._telemetry;
    if (t == null || dispatchId == null) return;
    try {
      t.policyOutcome(dispatchId, decision, winnerDispatchId: winnerDispatchId);
    } catch (error, stack) {
      _reportTelemetryError(error, stack);
    }
  }

  void _telemetryDispatchSent(int? dispatchId, Object message) {
    final t = Chassis._telemetry;
    if (t == null || dispatchId == null) return;
    try {
      t.dispatchSent(dispatchId, message);
    } catch (error, stack) {
      _reportTelemetryError(error, stack);
    }
  }

  void _telemetryResultReceived(
    int? dispatchId,
    Async<Object?> result,
    RunInvalidation invalidation, {
    required bool wasOptimistic,
  }) {
    final t = Chassis._telemetry;
    if (t == null || dispatchId == null) return;
    try {
      t.resultReceived(
        dispatchId,
        result,
        invalidation,
        wasOptimistic: wasOptimistic,
      );
    } catch (error, stack) {
      _reportTelemetryError(error, stack);
    }
  }

  int? _telemetryWatchStarted(
    Object query,
    Object key, {
    required bool replacedPrevious,
  }) {
    final t = Chassis._telemetry;
    if (t == null) return null;
    try {
      return t.watchStarted(
        this,
        query,
        key,
        replacedPrevious: replacedPrevious,
      );
    } catch (error, stack) {
      _reportTelemetryError(error, stack);
      return null;
    }
  }

  void _telemetryWatchEmission(int? dispatchId, Async<Object?> state) {
    final t = Chassis._telemetry;
    if (t == null || dispatchId == null) return;
    try {
      t.watchEmission(dispatchId, state);
    } catch (error, stack) {
      _reportTelemetryError(error, stack);
    }
  }

  void _telemetryWatchEnded(int? dispatchId, WatchEndReason reason) {
    final t = Chassis._telemetry;
    if (t == null || dispatchId == null) return;
    try {
      t.watchEnded(dispatchId, reason);
    } catch (error, stack) {
      _reportTelemetryError(error, stack);
    }
  }

  DispatchContext? _contextFor(int? dispatchId) =>
      dispatchId == null ? null : DispatchContext(dispatchId: dispatchId);

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
    final previous = _state;
    _state = state;
    final t = Chassis._telemetry;
    if (t != null) {
      try {
        t.stateChanged(this, previous, state);
      } catch (error, stack) {
        _reportTelemetryError(error, stack);
      }
    }
    notifyListeners();
  }

  /// Sends an event to all listeners of the events stream.
  ///
  /// Events are used for one-time notifications that don't require state changes,
  /// such as navigation events, snackbar messages, or other side effects.
  ///
  /// Events sent before the first subscriber are buffered and replayed to it
  /// (bounded to the most recent [_maxPendingEvents]).
  @protected
  void sendEvent(E event) {
    if (disposed) return;
    final t = Chassis._telemetry;
    if (!_hadFirstListener) {
      assert(
        _pendingEvents.length < _maxPendingEvents,
        'ViewModel<$T, $E> buffered $_maxPendingEvents events without any '
        'listener on `events`. Are you emitting events in a loop before the '
        'UI subscribes?',
      );
      _pendingEvents.add(event);
      if (_pendingEvents.length > _maxPendingEvents) {
        _pendingEvents.removeAt(0);
      }
      if (t != null) {
        try {
          t.eventSent(this, event, buffered: true);
        } catch (error, stack) {
          _reportTelemetryError(error, stack);
        }
      }
      return;
    }
    _events.add(event);
    if (t != null) {
      try {
        t.eventSent(this, event, buffered: false);
      } catch (error, stack) {
        _reportTelemetryError(error, stack);
      }
    }
  }

  @override
  void dispose() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    for (final pending in _pendingRuns.values) {
      for (final waiter in pending) {
        waiter.onDisposed();
      }
    }
    _pendingRuns.clear();
    _runEpochs.clear();
    _inFlightRuns.clear();
    _inFlightDispatchIds.clear();
    _runQueues.clear();
    _lastConfirmed.clear();
    _debugRunResultTypes.clear();
    for (final handle in _keyedWatches.values.toList()) {
      handle._cancelWith(WatchEndReason.disposed);
    }
    _keyedWatches.clear();
    for (final cleanup in _cleanups.reversed) {
      try {
        cleanup();
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'chassis_flutter',
            context: ErrorDescription(
              'while disposing a resource of ViewModel<$T, $E>',
            ),
          ),
        );
      }
    }
    _cleanups.clear();
    _pendingEvents.clear();
    _events.close();
    final t = Chassis._telemetry;
    if (t != null) {
      try {
        t.viewModelDisposed(this);
      } catch (error, stack) {
        _reportTelemetryError(error, stack);
      }
    }
    super.dispose();
  }

  /// Dispatches a [WatchQuery] and manages the resulting subscription with
  /// [Async] state updates. See the class documentation for the callback
  /// contract.
  ///
  /// - [key]: defaults to the query's runtime type. A previous [watch] with
  ///   the same key is cancelled and replaced — so re-watching the same
  ///   query class (e.g. with new params) swaps the subscription. Pass
  ///   distinct explicit keys to watch several instances of the same query
  ///   class concurrently.
  /// - [current]: the current [Async] state, if any. The initial loading
  ///   emission and error transitions carry its data ([AsyncData]), so a
  ///   refetch does not blank the UI.
  /// - [emitLoading]: whether to emit a loading state immediately.
  /// - [onDone]: invoked when the stream itself completes — never on
  ///   cancellation (keyed replacement, [WatchHandle.cancel], or disposal).
  ///   Without it, a finite stream ending is invisible: the state stays
  ///   frozen on the last emission. The handle is cancelled before [onDone]
  ///   runs, so re-watching with the same key from inside it is safe.
  ///
  /// The stream is materialized inside the framework's protection: a handler
  /// that throws synchronously reports an [AsyncError] through the
  /// callbacks (and returns an already-cancelled handle) instead of crashing
  /// the call site.
  ///
  /// Example:
  /// ```dart
  /// watch(
  ///   WatchUserQuery(userId: '123'),
  ///   current: state.user,
  ///   onState: (user) => setState(state.copyWith(user: user)),
  /// );
  /// ```
  @protected
  WatchHandle watch<R>(
    WatchQuery<R> query, {
    Object? key,
    Async<R>? current,
    bool emitLoading = true,
    void Function(Async<R> state)? onState,
    void Function(R data)? onData,
    void Function(Object error, StackTrace stack)? onError,
    void Function()? onDone,
  }) {
    assert(
      onState != null || onData != null || onError != null || onDone != null,
      'watch() called without any callback: provide onState, onData, '
      'onError, and/or onDone.',
    );

    final mediator = _requireMediator(query);
    final k = key ?? query.runtimeType;

    // A new watch replaces the previous one on the same key.
    final replaced = _keyedWatches.remove(k);
    replaced?._cancelWith(WatchEndReason.replaced);

    final dispatchId = _telemetryWatchStarted(
      query,
      k,
      replacedPrevious: replaced != null,
    );

    var last = current?.toLoading() ?? Async<R>.loading();
    if (emitLoading) {
      onState?.call(last);
    }

    // Materialize the stream inside the framework's try/catch: a synchronous
    // throw (a non-async* handler failing, a wiring error) becomes a soft
    // AsyncError instead of a crash at the call site — the same outcome the
    // identical failure has when the handler is async*.
    final Stream<R> stream;
    try {
      stream = mediator.watch(query, context: _contextFor(dispatchId));
    } catch (error, stackTrace) {
      final errorState = last.toError(error, stackTrace);
      _telemetryWatchEnded(dispatchId, WatchEndReason.failedToStart);
      onState?.call(errorState);
      onError?.call(error, stackTrace);
      return WatchHandle._cancelled();
    }

    late final WatchHandle handle;
    final subscription = stream.listen(
      (data) {
        if (disposed) return;
        final dataState = AsyncData(data);
        last = dataState;
        _telemetryWatchEmission(dispatchId, dataState);
        onState?.call(dataState);
        onData?.call(data);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (disposed) return;
        // Carry the last known data through the error (soft error).
        final errorState = last.toError(error, stackTrace);
        last = errorState;
        _telemetryWatchEmission(dispatchId, errorState);
        onState?.call(errorState);
        onError?.call(error, stackTrace);
      },
      onDone: () {
        if (disposed) return;
        // The subscription is over: release the handle (and its key) before
        // reporting, so onDone can start a replacement watch.
        handle._cancelWith(WatchEndReason.done);
        onDone?.call();
      },
    );

    handle = WatchHandle._((reason) {
      if (identical(_keyedWatches[k], handle)) {
        _keyedWatches.remove(k);
      }
      _telemetryWatchEnded(dispatchId, reason);
      return subscription.cancel();
    });

    _keyedWatches[k] = handle;
    return handle;
  }

  /// Dispatches a [Command], reporting its lifecycle as [Async] states. See
  /// the class documentation for the callback contract, and [read] for the
  /// query counterpart.
  ///
  /// - [key] and [policy]: control how operations sharing the same [key]
  ///   interact (see [RunPolicy]). The key defaults to the command's runtime
  ///   type, so all dispatches of the same command class share the policy.
  ///   All runs sharing a key must have the same result type `R`.
  /// - [current]: the current [Async] state, if any. The initial loading
  ///   emission and an error result carry its data ([AsyncData]), so a
  ///   refetch does not blank the UI.
  /// - [optimistic]: emitted verbatim through [onState] at dispatch *instead
  ///   of* a loading state — the field takes the expected value immediately,
  ///   while `onSuccess`/`onError` still fire only for the real result. On
  ///   failure the reported [AsyncError.previous] is the last *confirmed*
  ///   data — the latest [AsyncData] completed by a run on the same [key],
  ///   or the data carried by [current] — never the optimistic value, so
  ///   the UI rolls back. Typed [AsyncData] rather than a bare value so
  ///   that, for a nullable `R`, `optimistic: AsyncData(null)` stays
  ///   distinct from "not optimistic".
  /// - [emitLoading]: whether to emit a loading state when the operation
  ///   dispatches (for a debounced run, that is when the debounce window
  ///   fires, not at the call). Irrelevant when [optimistic] is provided:
  ///   the optimistic data is emitted instead.
  ///
  /// Returns the final [Async] state ([AsyncData] or [AsyncError]). A
  /// dropped or debounce-coalesced call resolves with the winning run's
  /// result. If the ViewModel is disposed while awaiting, callbacks are not
  /// invoked.
  @protected
  Future<Async<R>> run<R>(
    Command<R> command, {
    Object? key,
    RunPolicy policy = const RunPolicy.concurrent(),
    Async<R>? current,
    AsyncData<R>? optimistic,
    bool emitLoading = true,
    void Function(Async<R> state)? onState,
    void Function(R value)? onSuccess,
    void Function(Object error, StackTrace stack)? onError,
  }) {
    final mediator = _requireMediator(command);
    final k = key ?? command.runtimeType;
    final dispatchId = _telemetryDispatchRequested(
      command,
      DispatchKind.command,
      k,
      policy,
      optimistic: optimistic != null,
    );
    return _dispatch<R>(
      () {
        _telemetryDispatchSent(dispatchId, command);
        return mediator.run(command, context: _contextFor(dispatchId));
      },
      key: k,
      dispatchId: dispatchId,
      policy: policy,
      current: current,
      optimistic: optimistic,
      emitLoading: emitLoading,
      onState: onState,
      onSuccess: onSuccess,
      onError: onError,
    );
  }

  /// Dispatches a [ReadQuery], reporting its lifecycle as [Async] states.
  ///
  /// Identical to [run] in every parameter and guarantee — including
  /// [optimistic] — with the key defaulting to the query's runtime type.
  /// A refetching read typically wants `policy: const
  /// RunPolicy.restartable()` so a newer read supersedes the in-flight one.
  @protected
  Future<Async<R>> read<R>(
    ReadQuery<R> query, {
    Object? key,
    RunPolicy policy = const RunPolicy.concurrent(),
    Async<R>? current,
    AsyncData<R>? optimistic,
    bool emitLoading = true,
    void Function(Async<R> state)? onState,
    void Function(R value)? onSuccess,
    void Function(Object error, StackTrace stack)? onError,
  }) {
    final mediator = _requireMediator(query);
    final k = key ?? query.runtimeType;
    final dispatchId = _telemetryDispatchRequested(
      query,
      DispatchKind.read,
      k,
      policy,
      optimistic: optimistic != null,
    );
    return _dispatch<R>(
      () {
        _telemetryDispatchSent(dispatchId, query);
        return mediator.read(query, context: _contextFor(dispatchId));
      },
      key: k,
      dispatchId: dispatchId,
      policy: policy,
      current: current,
      optimistic: optimistic,
      emitLoading: emitLoading,
      onState: onState,
      onSuccess: onSuccess,
      onError: onError,
    );
  }

  /// Shared machinery of [run] and [read]: policy arbitration per key, then
  /// execution with lifecycle reporting.
  Future<Async<R>> _dispatch<R>(
    Future<R> Function() operation, {
    required Object key,
    required int? dispatchId,
    required RunPolicy policy,
    required Async<R>? current,
    required AsyncData<R>? optimistic,
    required bool emitLoading,
    required void Function(Async<R> state)? onState,
    required void Function(R value)? onSuccess,
    required void Function(Object error, StackTrace stack)? onError,
  }) {
    assert(
      onState != null || onSuccess != null || onError != null,
      'run()/read() called without any callback: provide onState, onSuccess, '
      'and/or onError.',
    );
    assert(
      optimistic == null || onState != null,
      'run() with optimistic: but without onState: the optimistic value is '
      'emitted through onState only.',
    );
    assert(
      () {
        final existing = _debugRunResultTypes[key];
        if (existing != null && existing != R) return false;
        _debugRunResultTypes[key] = R;
        return true;
      }(),
      'key "$key" is shared by runs with incompatible result types '
      '${_debugRunResultTypes[key]} and $R — use distinct keys.',
    );

    Future<Async<R>> execute({int? epoch}) => _executeRun(
      operation,
      key: key,
      dispatchId: dispatchId,
      epoch: epoch,
      current: current,
      optimistic: optimistic,
      emitLoading: emitLoading,
      onState: onState,
      onSuccess: onSuccess,
      onError: onError,
    );

    switch (policy) {
      case ConcurrentRunPolicy():
        _telemetryPolicyOutcome(dispatchId, PolicyDecision.immediate);
        return execute();

      case RestartableRunPolicy(:final debounce):
        final epoch = (_runEpochs[key] ?? 0) + 1;
        _runEpochs[key] = epoch;
        if (debounce == Duration.zero) {
          _telemetryPolicyOutcome(dispatchId, PolicyDecision.immediate);
          return execute(epoch: epoch);
        }
        _telemetryPolicyOutcome(dispatchId, PolicyDecision.debounced);
        _debounceTimers.remove(key)?.cancel();
        final completer = Completer<Async<R>>();
        (_pendingRuns[key] ??= []).add(
          _PendingRun(
            onDispatch: (result) =>
                completer.complete(result.then((r) => r as Async<R>)),
            onDisposed: () => completer.complete(
              Async<R>.error(
                StateError(
                  'ViewModel<$T, $E> was disposed before the run debounced on '
                  'key "$key" dispatched.',
                ),
              ),
            ),
          ),
        );
        _debounceTimers[key] = Timer(debounce, () {
          _debounceTimers.remove(key);
          final waiters = _pendingRuns.remove(key) ?? const [];
          final result = execute(epoch: epoch);
          for (final waiter in waiters) {
            waiter.onDispatch(result);
          }
        });
        return completer.future;

      case DroppableRunPolicy():
        final existing = _inFlightRuns[key];
        if (existing != null) {
          _telemetryPolicyOutcome(
            dispatchId,
            PolicyDecision.dropped,
            winnerDispatchId: _inFlightDispatchIds[key],
          );
          return existing.then((r) => r as Async<R>);
        }
        _telemetryPolicyOutcome(dispatchId, PolicyDecision.immediate);
        final result = execute();
        _inFlightRuns[key] = result;
        if (dispatchId != null) {
          _inFlightDispatchIds[key] = dispatchId;
        }
        result.whenComplete(() {
          if (identical(_inFlightRuns[key], result)) {
            _inFlightRuns.remove(key);
            _inFlightDispatchIds.remove(key);
          }
        });
        return result;

      case SequentialRunPolicy():
        final tail = _runQueues[key];
        _telemetryPolicyOutcome(
          dispatchId,
          tail == null ? PolicyDecision.immediate : PolicyDecision.queued,
        );
        // _executeRun never throws (operation errors become AsyncError), so
        // the chain cannot break.
        final result = tail == null ? execute() : tail.then((_) => execute());
        _runQueues[key] = result;
        result.whenComplete(() {
          if (identical(_runQueues[key], result)) {
            _runQueues.remove(key);
          }
        });
        return result;
    }
  }

  Future<Async<R>> _executeRun<R>(
    Future<R> Function() operation, {
    required Object key,
    required int? dispatchId,
    required int? epoch,
    required Async<R>? current,
    required AsyncData<R>? optimistic,
    required bool emitLoading,
    required void Function(Async<R> state)? onState,
    required void Function(R value)? onSuccess,
    required void Function(Object error, StackTrace stack)? onError,
  }) async {
    // Superseded ([RunPolicy.restartable]) or disposed runs still execute,
    // but stop reporting: their transitions no longer describe the current
    // intent.
    bool invalidated() =>
        disposed || (epoch != null && _runEpochs[key] != epoch);

    if (!invalidated()) {
      if (optimistic != null) {
        // Optimistic dispatch: the field takes the unconfirmed value now.
        // Seed the confirmed record so a failure can roll back to it; a run
        // completing on this key meanwhile overwrites it with fresher truth.
        final confirmed = current?.maybeDataOrPrevious;
        if (confirmed != null) {
          _lastConfirmed.putIfAbsent(key, () => confirmed);
        }
        onState?.call(optimistic);
      } else if (emitLoading) {
        onState?.call(current?.toLoading() ?? Async<R>.loading());
      }
    }

    Async<R> result;
    try {
      // The dispatch happens inside the framework's try/catch: a handler
      // (or wiring error) throwing synchronously is caught here, exactly
      // like an asynchronous failure.
      result = AsyncData(await operation());
    } catch (error, stackTrace) {
      result = optimistic != null
          ? AsyncError(
              error,
              stackTrace: stackTrace,
              // Roll back to confirmed truth, never to the optimistic value.
              previous:
                  _lastConfirmed[key] as AsyncData<R>? ??
                  current?.maybeDataOrPrevious,
            )
          : current != null
          ? current.toError(error, stackTrace)
          : Async<R>.error(error, stackTrace: stackTrace);
    }

    // Reported to telemetry even when invalidated: a superseded or disposed
    // run still received its result — the invalidation says it was not
    // reported to the callbacks.
    final invalidation = disposed
        ? RunInvalidation.disposed
        : (epoch != null && _runEpochs[key] != epoch)
        ? RunInvalidation.superseded
        : RunInvalidation.none;
    _telemetryResultReceived(
      dispatchId,
      result,
      invalidation,
      wasOptimistic: optimistic != null,
    );

    // Callbacks run OUTSIDE the try/catch: an exception thrown by a callback
    // is a bug in the callback and must propagate, not be reported as an
    // AsyncError of the operation (which would turn a success into an error).
    if (invalidation != RunInvalidation.none) return result;
    if (result is AsyncData<R>) {
      _lastConfirmed[key] = result;
    }
    switch (result) {
      case AsyncData<R>(:final value):
        onState?.call(result);
        onSuccess?.call(value);
      case AsyncError<R>(:final error, :final stackTrace):
        onState?.call(result);
        onError?.call(error, stackTrace ?? StackTrace.empty);
      case AsyncLoading<R>():
        break; // unreachable: result is data or error.
    }
    return result;
  }
}

/// How concurrent [ViewModel.run]/[ViewModel.read] calls sharing the same
/// `key` interact.
///
/// A policy answers one question — when several runs collide on a key, who
/// wins?
///
/// - [RunPolicy.concurrent] — everyone: all runs execute and report; the
///   last completion writes last, which may be the oldest dispatch.
/// - [RunPolicy.restartable] — the latest: a new run invalidates the
///   callbacks of any in-flight run on the same key. An optional [debounce]
///   window additionally coalesces bursts of calls before dispatching.
/// - [RunPolicy.droppable] — the first: while a run is in flight on the
///   key, new calls do not dispatch and resolve with the in-flight result.
/// - [RunPolicy.sequential] — everyone, in order: runs are queued per key.
///
/// The key defaults to the message's runtime type, and all runs sharing a
/// key must have the same result type.
sealed class RunPolicy {
  const RunPolicy();

  /// All runs execute independently. Results may interleave.
  const factory RunPolicy.concurrent() = ConcurrentRunPolicy._;

  /// Latest wins: a newer run on the same key invalidates the callbacks of
  /// in-flight ones.
  ///
  /// With a non-zero [debounce], dispatch additionally waits for a quiet
  /// window: each new call resets the timer, and only the latest operation
  /// dispatches once the window elapses (coalesced callers resolve with its
  /// result). There is no separate "debounce" policy because debouncing
  /// alone would not fix result races — a debounced dispatch still needs
  /// latest-wins invalidation once in flight. With the default
  /// `Duration.zero`, the operation dispatches synchronously.
  const factory RunPolicy.restartable({Duration debounce}) =
      RestartableRunPolicy._;

  /// First wins: calls made while a run is in flight on the key are dropped
  /// and complete with the in-flight run's result.
  const factory RunPolicy.droppable() = DroppableRunPolicy._;

  /// All runs execute, one at a time, in call order (per key).
  ///
  /// Note that `current` is captured when [ViewModel.run] is called, not
  /// when the queued operation starts; prefer reading fresh state inside
  /// `onState`.
  const factory RunPolicy.sequential() = SequentialRunPolicy._;

  /// Human-readable policy name, for assertion messages.
  String get name => switch (this) {
    ConcurrentRunPolicy() => 'concurrent',
    RestartableRunPolicy() => 'restartable',
    DroppableRunPolicy() => 'droppable',
    SequentialRunPolicy() => 'sequential',
  };
}

/// See [RunPolicy.concurrent].
final class ConcurrentRunPolicy extends RunPolicy {
  const ConcurrentRunPolicy._();
}

/// See [RunPolicy.restartable].
final class RestartableRunPolicy extends RunPolicy {
  const RestartableRunPolicy._({this.debounce = Duration.zero});

  /// Quiet window to wait for before dispatching. [Duration.zero] dispatches
  /// synchronously.
  final Duration debounce;
}

/// See [RunPolicy.droppable].
final class DroppableRunPolicy extends RunPolicy {
  const DroppableRunPolicy._();
}

/// See [RunPolicy.sequential].
final class SequentialRunPolicy extends RunPolicy {
  const SequentialRunPolicy._();
}

/// A caller coalesced by a [RunPolicy.restartable] debounce window.
class _PendingRun({
  /// Called with the winning run's result when the window fires.
  required final void Function(Future<Async<Object?>> result) onDispatch,

  /// Called if the ViewModel is disposed before the window fires.
  required final void Function() onDisposed,
});

/// {@template base_utils}
/// Extension that provides utility methods for managing resources and subscriptions
/// in view models with automatic cleanup.
///
/// These methods help manage the lifecycle of various resources and ensure they
/// are properly disposed when the view model is disposed.
/// {@endtemplate}
extension BaseUtils on ViewModel<Object?, Object?> {
  /// {@macro base_utils}
  /// Automatically disposes a [Disposable] object when the view model is disposed.
  @protected
  void autoDispose(Disposable disposable) {
    _cleanups.add(disposable.dispose);
  }

  /// {@macro base_utils}
  /// Automatically cancels a stream subscription when the view model is disposed.
  @protected
  void autoDisposeStreamSubscription(StreamSubscription<Object?> sub) {
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
}
