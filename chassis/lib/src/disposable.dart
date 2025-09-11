import 'package:meta/meta.dart';

/// A mixin that provides disposal functionality for objects that need cleanup.
///
/// This mixin helps manage the lifecycle of objects by tracking their disposal
/// state and providing a standard way to clean up resources.
///
/// Example usage:
/// ```dart
/// class MyService with Disposable {
///   StreamSubscription? _subscription;
///
///   @override
///   void dispose() {
///     _subscription?.cancel();
///     super.dispose(); // Always call super.dispose()
///   }
/// }
/// ```
mixin Disposable {
  /// Returns `true` if this object has been disposed.
  ///
  /// This property can be used to check if the object is still valid
  /// before performing operations that require the object to be active.
  bool get disposed => _disposed;
  bool _disposed = false;

  /// Disposes this object and marks it as disposed.
  ///
  /// This method should be overridden to perform any necessary cleanup
  /// operations. Always call `super.dispose()` when overriding this method.
  ///
  /// After calling this method, [disposed] will return `true`.
  @mustCallSuper
  void dispose() {
    _disposed = true;
  }
}
