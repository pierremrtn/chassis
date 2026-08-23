// Pins the documented default error rendering of AsyncBuilder: when no
// errorBuilder is provided, an error state renders a standard [ErrorWidget]
// in debug builds (docs/04_ui_integration.md, chassis-render-async-state).
//
// The release-mode half of the contract (SizedBox.shrink) is not testable
// here: `flutter test` always runs with kDebugMode true.
import 'package:chassis_flutter/chassis_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AsyncBuilder default errorBuilder', () {
    testWidgets('renders ErrorWidget in debug when errorBuilder is omitted', (
      tester,
    ) async {
      final state = Async<String>.error(Exception('boom'));

      await tester.pumpWidget(
        MaterialApp(
          home: AsyncBuilder<String>(
            state: state,
            builder: (context, data) => Text('Data: $data'),
          ),
        ),
      );

      expect(find.byType(ErrorWidget), findsOneWidget);
      final errorWidget = tester.widget<ErrorWidget>(find.byType(ErrorWidget));
      expect(
        errorWidget.message,
        contains('AsyncBuilder<String>'),
        reason: 'the default names the widget so the failure is traceable',
      );
      expect(
        errorWidget.message,
        contains('errorBuilder'),
        reason: 'the default tells the developer which parameter to provide',
      );
      expect(
        errorWidget.message,
        contains('Exception: boom'),
        reason: 'the default surfaces the underlying error',
      );
    });

    testWidgets('a provided errorBuilder suppresses the ErrorWidget default', (
      tester,
    ) async {
      final state = Async<String>.error(Exception('boom'));

      await tester.pumpWidget(
        MaterialApp(
          home: AsyncBuilder<String>(
            state: state,
            builder: (context, data) => Text('Data: $data'),
            errorBuilder: (context, error) => const Text('handled'),
          ),
        ),
      );

      expect(find.text('handled'), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);
    });
  });
}
