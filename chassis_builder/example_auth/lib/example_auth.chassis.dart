// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: implementation_imports

// **************************************************************************
// ChassisGenerator
// **************************************************************************

/// Typed mediator interface of the `AuthModule` module.
///
/// Implemented by the app mediator generated from `@ChassisApp(modules: [AuthModule])`.
abstract interface class AuthMediator {
  Future<String> getProfile({required String userId});
  Future<void> login(
    String username,
    String password,
  );
}
