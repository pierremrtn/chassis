import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AsyncBuilder', () {
    testWidgets('renders data when state is AsyncData', (tester) async {
      final state = Async.data('test data');
      await tester.pumpWidget(MaterialApp(
        home: AsyncBuilder<String>(
          state: state,
          builder: (context, data) => Text('Data: $data'),
        ),
      ));

      expect(find.text('Data: test data'), findsOneWidget);
    });

    testWidgets('renders loading when state is AsyncLoading (initial)',
        (tester) async {
      const state = Async<String>.loading();
      await tester.pumpWidget(MaterialApp(
        home: AsyncBuilder<String>(
          state: state,
          builder: (context, data) => Text('Data: $data'),
          loadingBuilder: (context) => const Text('Loading...'),
        ),
      ));

      expect(find.text('Loading...'), findsOneWidget);
    });

    testWidgets(
        'renders default loading (CircularProgressIndicator) if no loadingBuilder provided',
        (tester) async {
      const state = Async<String>.loading();
      await tester.pumpWidget(MaterialApp(
        home: AsyncBuilder<String>(
          state: state,
          builder: (context, data) => Text('Data: $data'),
        ),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders error when state is AsyncError (initial)',
        (tester) async {
      final state = Async<String>.error(Exception('oops'));
      await tester.pumpWidget(MaterialApp(
        home: AsyncBuilder<String>(
          state: state,
          builder: (context, data) => Text('Data: $data'),
          errorBuilder: (context, error) => Text('Error: $error'),
        ),
      ));

      expect(find.textContaining('Error: Exception: oops'), findsOneWidget);
    });

    testWidgets(
        'maintains state (Anti-flickering) when refreshing (Loading with previous value)',
        (tester) async {
      final state = Async<String>.loading('previous data');

      await tester.pumpWidget(MaterialApp(
        home: AsyncBuilder<String>(
          state: state,
          builder: (context, data) => Text('Data: $data'),
          loadingBuilder: (context) => const Text('Loading...'),
          maintainState: true, // Default
        ),
      ));

      // Should show data, NOT loading
      expect(find.text('Data: previous data'), findsOneWidget);
      expect(find.text('Loading...'), findsNothing);
    });

    testWidgets(
        'shows loading if maintainState is false even with previous value',
        (tester) async {
      final state = Async<String>.loading('previous data');

      await tester.pumpWidget(MaterialApp(
        home: AsyncBuilder<String>(
          state: state,
          builder: (context, data) => Text('Data: $data'),
          loadingBuilder: (context) => const Text('Loading...'),
          maintainState: false,
        ),
      ));

      // Should show loading
      expect(find.text('Loading...'), findsOneWidget);
      expect(find.text('Data: previous data'), findsNothing);
    });

    testWidgets(
        'maintains state (Anti-flickering) when error occurs with previous value',
        (tester) async {
      final state =
          Async<String>.error(Exception('fail'), previous: 'previous data');

      await tester.pumpWidget(MaterialApp(
        home: AsyncBuilder<String>(
          state: state,
          builder: (context, data) => Text('Data: $data'),
          errorBuilder: (context, err) => Text('Error: $err'),
          maintainState: true, // Default
        ),
      ));

      // Should show data, NOT error
      expect(find.text('Data: previous data'), findsOneWidget);
      expect(find.textContaining('Error'), findsNothing);
    });
  });
}
