import 'package:meta/meta.dart';

mixin Disposable {
  bool get disposed => _disposed;
  bool _disposed = false;

  @mustCallSuper
  @mustBeOverridden
  void dispose() {
    _disposed = true;
  }
}
