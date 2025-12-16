import 'package:chassis/chassis.dart';
import 'package:test/test.dart';

void main() {
  group('Async', () {
    test('Async.data creates AsyncData with value', () {
      const state = Async.data('test');
      expect(state, isA<AsyncData<String>>());
      expect(state.valueOrNull, 'test');
      expect(state.errorOrNull, isNull);
      expect(state.isLoading, isFalse);
      expect(state.hasValue, isTrue);
      expect(state.hasError, isFalse);
    });

    test('Async.loading creates AsyncLoading', () {
      const state = Async<String>.loading();
      expect(state, isA<AsyncLoading<String>>());
      expect(state.valueOrNull, isNull);
      expect(state.errorOrNull, isNull);
      expect(state.isLoading, isTrue);
    });

    test('Async.loading with previous keeps value', () {
      const state = Async.loading('prev');
      expect(state, isA<AsyncLoading<String>>());
      expect(state.valueOrNull, 'prev');
    });

    test('Async.error creates AsyncError', () {
      final error = Exception('oops');
      final stack = StackTrace.current;
      final state = Async<String>.error(error, stackTrace: stack);
      expect(state, isA<AsyncError<String>>());
      expect(state.errorOrNull, error);
      expect(state.valueOrNull, isNull);
      expect(state.isLoading, isFalse);
      expect(state.hasError, isTrue);
    });

    test('transitions work correctly', () {
      const initial = Async.data('initial');

      // toLoading
      final loading = initial.toLoading();
      expect(loading, isA<AsyncLoading<String>>());
      expect(loading.valueOrNull, 'initial');
      expect(loading.isLoading, isTrue);

      // toData
      final data = loading.toData('new');
      expect(data, isA<AsyncData<String>>());
      expect(data.valueOrNull, 'new');
      expect(data.isLoading, isFalse);

      // toError
      final errorObj = Exception('fail');
      final stack = StackTrace.current;
      final error = data.toError(errorObj, stack);
      expect(error, isA<AsyncError<String>>());
      expect(error.valueOrNull, 'new'); // Keeps previous data
      expect(error.errorOrNull, errorObj);
    });
  });
}
