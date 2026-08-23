import 'dart:io';

import 'package:test/test.dart';

/// Verifies the three chassis_lint rules against the `fixtures/` package.
///
/// The fixtures contain bad code annotated with `// expect_lint: <rule>`
/// comments and good code without annotations. Running `custom_lint` there
/// verifies both directions at once:
///
/// - a rule that fails to fire leaves its `expect_lint` unfulfilled, which
///   custom_lint reports as an `unfulfilled_expect_lint` ERROR;
/// - a rule that over-fires on good code emits an unannotated lint, which is
///   fatal (`--fatal-infos --fatal-warnings`).
///
/// So exit code 0 means: every annotated lint fired, and nothing else did.
void main() {
  test(
    'custom_lint on fixtures: every expected lint fires, nothing else does',
    () async {
      final fixturesPath =
          Directory.current.uri.resolve('fixtures').toFilePath();

      // Resolve the fixtures package (no-op when already up to date). The
      // fixtures depend on Flutter, so resolution goes through `flutter`.
      final pubGet = await Process.run(
        'flutter',
        ['pub', 'get'],
        workingDirectory: fixturesPath,
      );
      expect(
        pubGet.exitCode,
        0,
        reason: 'flutter pub get failed in fixtures/:\n'
            '${pubGet.stdout}\n${pubGet.stderr}',
      );

      final result = await Process.run(
        'dart',
        ['run', 'custom_lint', '--fatal-infos', '--fatal-warnings'],
        workingDirectory: fixturesPath,
      );
      expect(
        result.exitCode,
        0,
        reason: 'custom_lint reported unexpected or missing lints:\n'
            '${result.stdout}\n${result.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
