/// Observation metadata for one dispatch, provided by the dispatching caller
/// (typically an instrumented ViewModel) and handed unchanged to every
/// [MediatorMiddleware] in the chain.
///
/// Purely descriptive: the mediator never interprets it. It exists so that a
/// mediator-side observer (a telemetry or logging middleware) can anchor what
/// it sees to the caller-side story of the same dispatch. Adding a field here
/// is a non-breaking evolution.
class const DispatchContext({
  /// Identity of this dispatch, minted by the caller's telemetry — one id
  /// per dispatch (a message *value* can be dispatched many times; each
  /// dispatch gets its own id).
  required final int dispatchId,
});
