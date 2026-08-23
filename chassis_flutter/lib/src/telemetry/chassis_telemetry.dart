import 'package:chassis_flutter/chassis_flutter.dart';

/// The kind of dispatch reported by [ChassisTelemetry.dispatchRequested].
enum DispatchKind { command, read }

/// How the [RunPolicy] arbitration resolved a `run`/`read` call.
enum PolicyDecision {
  /// Dispatched immediately (concurrent; restartable without debounce;
  /// droppable with no run in flight; sequential with an empty queue).
  immediate,

  /// Restartable with debounce: the call joined the quiet window; only the
  /// latest call dispatches when the window fires (it gets its own
  /// `dispatchSent`).
  debounced,

  /// Droppable: a run is in flight on the key, this call will not dispatch
  /// and resolves with the in-flight run's result.
  dropped,

  /// Sequential: queued behind the run in flight on the key.
  queued,
}

/// Whether a run's result was reported to its callbacks.
enum RunInvalidation {
  /// The result was reported — the nominal case.
  none,

  /// Restartable: a newer run on the same key took over; the result arrived
  /// but was not reported.
  superseded,

  /// The ViewModel was disposed while the run was in flight; the result was
  /// not reported.
  disposed,
}

/// Why a watch subscription ended.
enum WatchEndReason {
  /// The watched stream completed on its own (onDone).
  done,

  /// Cancelled through [WatchHandle.cancel].
  cancelled,

  /// Replaced by a new watch on the same key.
  replaced,

  /// The ViewModel was disposed.
  disposed,

  /// Materializing the stream failed (a synchronous handler throw or a
  /// wiring error) — the watch was never live.
  failedToStart,
}

/// Observation point of the framework, installed through
/// [Chassis.initialize]. Observation methods are no-ops: an implementation
/// overrides only what it consumes.
///
/// Implementor contract:
/// - extract what you need synchronously; NEVER retain the references you
///   receive (ViewModel, message, states) beyond the call;
/// - never dispatch or mutate a ViewModel from a hook (re-entrancy);
/// - return immediately — queueing and I/O are the implementation's problem.
///
/// Generic types are deliberately erased to `Object?`: the receiver is a
/// heterogeneous pipeline, and runtime types stay intact for
/// `runtimeType` / pattern-matching dispatch.
abstract base class ChassisTelemetry {
  // ── ViewModel lifecycle — each ViewModel is a timeline track. ───────────

  void viewModelCreated(ViewModel<Object?, Object?> viewModel) {}

  void viewModelDisposed(ViewModel<Object?, Object?> viewModel) {}

  // ── State & one-shot events. ────────────────────────────────────────────

  void stateChanged(
    ViewModel<Object?, Object?> viewModel,
    Object? previous,
    Object? next,
  ) {}

  /// [buffered]: the event was emitted before the first listener and
  /// buffered for replay.
  void eventSent(
    ViewModel<Object?, Object?> viewModel,
    Object? event, {
    required bool buffered,
  }) {}

  // ── run / read: from intent to result, policy outcomes included. ────────

  /// Observes a dispatch intent AND mints the flow's id: the returned value
  /// names this dispatch in every subsequent call ([policyOutcome],
  /// [dispatchSent], [resultReceived]).
  ///
  /// Contract: two distinct dispatches get distinct ids — the uniqueness
  /// scope (process, session, persisted buffer) is the implementation's
  /// choice. An override that only wants to observe returns
  /// `super.dispatchRequested(...)`; an override that controls the sequence
  /// (a flight recorder surviving restarts, an OTel mapping) returns its
  /// own id.
  int dispatchRequested(
    ViewModel<Object?, Object?> viewModel,
    Object message, // Command<R> or ReadQuery<R>
    DispatchKind kind,
    Object key,
    RunPolicy policy, {
    required bool optimistic,
  }) => ++_dispatchCounter;

  /// [winnerDispatchId]: for [PolicyDecision.dropped], the id of the
  /// in-flight run whose result this call will resolve with. Null otherwise.
  void policyOutcome(
    int dispatchId,
    PolicyDecision decision, {
    int? winnerDispatchId,
  }) {}

  /// The message actually crosses to the mediator — for a debounced run,
  /// this is when the intent becomes a real dispatch.
  void dispatchSent(int dispatchId, Object message) {}

  /// [result]: [AsyncData] (success) or [AsyncError] (failure) — never
  /// [AsyncLoading]. For an optimistic failure, `AsyncError.previous`
  /// carries the rollback value (the last confirmed truth).
  void resultReceived(
    int dispatchId,
    Async<Object?> result,
    RunInvalidation invalidation, {
    required bool wasOptimistic,
  }) {}

  // ── watch: lifecycle of one subscription. ───────────────────────────────

  /// Same return contract as [dispatchRequested].
  /// [replacedPrevious]: an active watch on the same key was cancelled and
  /// replaced.
  int watchStarted(
    ViewModel<Object?, Object?> viewModel,
    Object query, // WatchQuery<R>
    Object key, {
    required bool replacedPrevious,
  }) => ++_dispatchCounter;

  /// [state]: [AsyncData] (emission) or [AsyncError] (soft error carrying
  /// the last known data in `previous`).
  void watchEmission(int dispatchId, Async<Object?> state) {}

  void watchEnded(int dispatchId, WatchEndReason reason) {}

  int _dispatchCounter = 0;
}
