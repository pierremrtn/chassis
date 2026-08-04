import 'package:chassis/chassis.dart';
import 'package:test/test.dart';

void main() {
  group('Async factories', () {
    test('Async.data creates AsyncData', () {
      const state = Async.data(42);
      expect(state, isA<AsyncData<int>>());
      expect(state.hasValue, isTrue);
      expect(state.valueOrNull, 42);
      expect(state.requireValue, 42);
      expect(state.isLoading, isFalse);
      expect(state.hasError, isFalse);
    });

    test('Async.loading creates AsyncLoading without value', () {
      const state = Async<int>.loading();
      expect(state, isA<AsyncLoading<int>>());
      expect(state.isLoading, isTrue);
      expect(state.hasValue, isFalse);
      expect(state.valueOrNull, isNull);
      expect(() => state.requireValue, throwsStateError);
    });

    test('Async.loading carries a previous AsyncData', () {
      const state = Async<int>.loading(previous: AsyncData(1));
      expect(state.isLoading, isTrue);
      expect(state.hasValue, isTrue);
      expect(state.valueOrNull, 1);
      expect(state.requireValue, 1);
    });

    test('Async.error creates AsyncError', () {
      final state = Async<int>.error(StateError('x'));
      expect(state, isA<AsyncError<int>>());
      expect(state.hasError, isTrue);
      expect(state.errorOrNull, isA<StateError>());
      expect(state.hasValue, isFalse);
      expect(() => state.requireValue, throwsStateError);
    });

    test('Async.error carries a previous AsyncData', () {
      final state =
          Async<int>.error(StateError('x'), previous: const AsyncData(7));
      expect(state.hasError, isTrue);
      expect(state.hasValue, isTrue);
      expect(state.valueOrNull, 7);
      expect(state.requireValue, 7);
    });
  });

  group('Async with nullable T', () {
    test('AsyncData<int?>(null) has a value', () {
      const state = Async<int?>.data(null);
      expect(state.hasValue, isTrue);
      expect(state.valueOrNull, isNull);
      expect(state.requireValue, isNull);
    });

    test('loading carrying AsyncData(null) still proves a value existed', () {
      const state = Async<int?>.loading(previous: AsyncData(null));
      expect(state.hasValue, isTrue);
      expect(state.requireValue, isNull);
    });

    test('loading without previous has no value', () {
      const state = Async<int?>.loading();
      expect(state.hasValue, isFalse);
    });
  });

  group('Async transitions', () {
    test('toLoading from data carries the data', () {
      const data = Async.data(5);
      final loading = data.toLoading();
      expect(loading, isA<AsyncLoading<int>>());
      expect(loading.hasValue, isTrue);
      expect(loading.valueOrNull, 5);
    });

    test('toError from data carries the data', () {
      const data = Async.data(5);
      final error = data.toError(StateError('x'), StackTrace.current);
      expect(error, isA<AsyncError<int>>());
      expect(error.hasValue, isTrue);
      expect(error.valueOrNull, 5);
      expect(error.errorOrNull, isA<StateError>());
    });

    test('chained transitions keep the last data', () {
      const data = Async.data(5);
      final result = data
          .toLoading()
          .toError(StateError('x'), StackTrace.current)
          .toLoading();
      expect(result.isLoading, isTrue);
      expect(result.valueOrNull, 5);
    });

    test('toData replaces everything', () {
      final result =
          Async<int>.error(StateError('x'), previous: const AsyncData(1))
              .toData(9);
      expect(result, isA<AsyncData<int>>());
      expect(result.requireValue, 9);
    });

    test('toLoading from empty loading stays empty', () {
      final result = const Async<int>.loading().toLoading();
      expect(result.hasValue, isFalse);
    });
  });

  group('Async.when', () {
    test('folds each state exhaustively', () {
      String fold(Async<int> s) => s.when(
            data: (v) => 'data:$v',
            loading: () => 'loading',
            error: (e, _) => 'error:$e',
          );

      expect(fold(const Async.data(1)), 'data:1');
      expect(fold(const Async.loading()), 'loading');
      expect(fold(Async.error(StateError('x'))), startsWith('error:'));
    });

    test('a loading state carrying data folds as loading, not data', () {
      final result = const Async<int>.loading(previous: AsyncData(1)).when(
        data: (v) => 'data',
        loading: () => 'loading',
        error: (e, _) => 'error',
      );
      expect(result, 'loading');
    });

    test('error receives the stack trace', () {
      final stack = StackTrace.current;
      StackTrace? seen;
      Async<int>.error(StateError('x'), stackTrace: stack).when(
        data: (_) {},
        loading: () {},
        error: (e, s) => seen = s,
      );
      expect(seen, stack);
    });
  });

  group('Async.map', () {
    test('transforms data', () {
      expect(const Async.data(2).map((v) => 'v$v'), const Async.data('v2'));
    });

    test('preserves loading and transforms the carried previous', () {
      final mapped =
          const Async<int>.loading(previous: AsyncData(2)).map((v) => 'v$v');
      expect(mapped, const Async<String>.loading(previous: AsyncData('v2')));
    });

    test('preserves error, stack trace, and transforms previous', () {
      final e = StateError('x');
      final stack = StackTrace.current;
      final mapped =
          Async<int>.error(e, stackTrace: stack, previous: const AsyncData(2))
              .map((v) => 'v$v');
      expect(
        mapped,
        Async<String>.error(e,
            stackTrace: stack, previous: const AsyncData('v2')),
      );
    });

    test('empty loading maps to empty loading', () {
      expect(const Async<int>.loading().map((v) => '$v'),
          const Async<String>.loading());
    });

    test('nullable values are mapped, not dropped', () {
      final mapped = const Async<int?>.data(null).map((v) => v ?? -1);
      expect(mapped, const Async.data(-1));
    });
  });

  group('Async equality', () {
    test('AsyncData equality', () {
      expect(const Async.data(1), const Async.data(1));
      expect(const Async.data(1), isNot(const Async.data(2)));
      expect(const Async.data(1).hashCode, const Async.data(1).hashCode);
    });

    test('AsyncLoading equality includes previous', () {
      expect(const Async<int>.loading(), const Async<int>.loading());
      expect(
        const Async<int>.loading(previous: AsyncData(1)),
        const Async<int>.loading(previous: AsyncData(1)),
      );
      expect(
        const Async<int>.loading(previous: AsyncData(1)),
        isNot(const Async<int>.loading()),
      );
    });

    test('AsyncError equality includes error and previous', () {
      final e = StateError('x');
      expect(Async<int>.error(e), Async<int>.error(e));
      expect(
        Async<int>.error(e, previous: const AsyncData(1)),
        isNot(Async<int>.error(e)),
      );
    });

    test('different type arguments are not equal', () {
      expect(const Async<int>.loading(),
          isNot(equals(const Async<String>.loading())));
    });
  });
}
