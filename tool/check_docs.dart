// Docs/skills validation gates, run in CI (docs-check job) and locally:
//
//   dart pub get -C tool   # once
//   dart run tool/check_docs.dart
//
// Gates:
//   1. syntax     — every ```dart fence in docs/*.md and chassis/skills/*/SKILL.md
//                   must parse as Dart: as a compilation unit, or (fragments)
//                   wrapped in a synthetic async function (statements), as a
//                   single expression, or as a class member list.
//   2. stale-api  — symbols removed in the 1.0.0 message-direct pivot must not
//                   appear anywhere (code or prose) in docs/, chassis/skills/,
//                   or the package READMEs. Opt out per line by putting
//                   <!-- check-docs:allow-stale-api --> on the preceding line.
//   3. contracts  — regex checks over dart fences only: single-parameter
//                   onError closures (the API is (error, stack)) and bare
//                   Provider<XViewModel>.value (a ViewModel is a Listenable;
//                   only deliberate bad examples marked with a throw/BAD/
//                   anti-pattern comment are allowed).
//   4. links      — relative markdown links in README/docs/skills must resolve
//                   to existing files. External URLs are not checked.
//
// Exit code 0 = all gates pass; 1 = findings printed above.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';

const _allowStaleMarker = '<!-- check-docs:allow-stale-api -->';

/// Symbols removed in the 1.0.0 message-direct pivot. Never legitimate
/// anymore, in code or prose.
final Map<String, RegExp> _staleApi = {
  'ChassisException': RegExp(r'ChassisException'),
  'HandlerNotRegisteredException': RegExp(r'HandlerNotRegisteredException'),
  'DuplicateHandlerException': RegExp(r'DuplicateHandlerException'),
  'ConsumerMixin': RegExp(r'ConsumerMixin'),
  'withEvents(': RegExp(r'withEvents\('),
  'RepositoryGenerator': RegExp(r'RepositoryGenerator'),
  'generateQueryHandler': RegExp(r'generateQueryHandler'),
  'generateCommandHandler': RegExp(r'generateCommandHandler'),
  // The pre-1.0 `mediator + FooHandler()` registration operator.
  'Mediator.operator+':
      RegExp(r'Mediator\.operator\s*\+|mediator\s*\+\s*[A-Z_$]\w*\('),
};

/// `onError: (e) => ...` / `onError: (e) { ... }` — single-argument closure.
/// The chassis API passes (error, stack); a single-parameter callback is a
/// stale pre-1.0 form.
final RegExp _singleArgOnError =
    RegExp(r'onError:\s*\(\s*[A-Za-z_$][\w$]*\s*\)\s*(?:async\s*)?(?:=>|\{)');

/// Bare `Provider<XViewModel>.value` (NOT `ViewModelProvider<...>.value`,
/// excluded by the lookbehind). A ViewModel is a Listenable, so provider's
/// debugCheckInvalidValueType throws at pumpWidget.
final RegExp _bareProviderValue =
    RegExp(r'(?<![\w$])Provider<[^<>]*ViewModel[^<>]*>\.value');

/// A deliberate bad example is marked by a comment carrying one of these.
final RegExp _badExampleComment =
    RegExp(r'//.*(throw|bad|anti-pattern)', caseSensitive: false);

final List<String> _errors = [];

void _fail(String gate, String location, String message) {
  _errors.add('[$gate] $location: $message');
}

void main(List<String> args) {
  final root = _findRepoRoot();

  // ---- File sets -----------------------------------------------------------

  // Syntax gate: docs/*.md and chassis/skills/*/SKILL.md.
  final syntaxFiles = [
    ..._glob(root, 'docs', (p) => p.endsWith('.md')),
    ..._glob(root, 'chassis/skills', (p) => p.endsWith('/SKILL.md')),
  ];

  // Stale-API gate (code and prose) + contract gates (dart fences only):
  // docs/, chassis/skills/, and the package READMEs. archive/ is never
  // scanned (it is outside these roots, and excluded defensively in _glob).
  final proseFiles = <String>{
    ..._glob(root, 'docs', (p) => p.endsWith('.md')),
    ..._glob(root, 'chassis/skills', (p) => p.endsWith('.md')),
    for (final readme in [
      'README.md',
      'chassis/README.md',
      'chassis_flutter/README.md',
      'chassis_builder/README.md',
    ])
      if (File('$root/$readme').existsSync()) '$root/$readme',
  }.toList()
    ..sort();

  // Link gate: everything above plus the remaining package READMEs.
  final linkFiles = <String>{
    ...proseFiles,
    for (final readme in [
      'chassis_lint/README.md',
      'examples/todo/README.md',
    ])
      if (File('$root/$readme').existsSync()) '$root/$readme',
  }.toList()
    ..sort();

  // ---- Run gates -----------------------------------------------------------

  var fenceCount = 0;
  for (final file in syntaxFiles) {
    fenceCount += _checkDartSyntax(root, file);
  }

  for (final file in proseFiles) {
    _checkStaleApi(root, file);
    _checkContracts(root, file);
  }

  var linkCount = 0;
  for (final file in linkFiles) {
    linkCount += _checkRelativeLinks(root, file);
  }

  // ---- Report --------------------------------------------------------------

  stdout.writeln('check_docs: ${syntaxFiles.length} files syntax-checked '
      '($fenceCount dart fences), ${proseFiles.length} files API-checked, '
      '${linkFiles.length} files link-checked ($linkCount relative links).');

  if (_errors.isEmpty) {
    stdout.writeln('check_docs: OK');
    return;
  }
  stdout.writeln('check_docs: ${_errors.length} error(s):');
  for (final e in _errors) {
    stdout.writeln('  $e');
  }
  exit(1);
}

// ---- Gate 1: dart fence syntax ---------------------------------------------

/// Parses every dart fence in [file]; returns the number of fences checked.
int _checkDartSyntax(String root, String file) {
  final fences = _extractFences(File(file).readAsStringSync());
  final dartFences = fences.where((f) => f.lang == 'dart');
  for (final fence in dartFences) {
    final code = fence.code;
    if (code.trim().isEmpty) continue;

    // 1st attempt: parse as a compilation unit (declarations, directives).
    if (_parses(code)) continue;

    // 2nd attempt: statement fragments — wrap in a synthetic async function.
    if (_parses('Future<void> _docSnippet() async {\n$code\n}\n')) continue;

    // 3rd attempt: a single expression (widget trees quoted without `;`).
    if (_parses(
        'Future<void> _docSnippet() async {\nfinal _ =\n$code\n;\n}\n')) {
      continue;
    }

    // 4th attempt: class members (constructors, abstract signatures).
    if (_parses('abstract class _DocSnippet {\n$code\n}\n')) continue;

    // Report with the first diagnostic of the statement-wrapped parse (the
    // most common snippet shape), located back onto the file line.
    final probe = parseString(
        content: 'Future<void> _docSnippet() async {\n$code\n}\n',
        throwIfDiagnostics: false);
    final first = probe.errors.first;
    final snippetLine = probe.lineInfo.getLocation(first.offset).lineNumber - 1;
    _fail(
        'syntax',
        '${_rel(root, file)}:${fence.line}',
        'dart fence does not parse (as compilation unit, statements, '
            'expression, or class members) — '
            '${first.message} (near ${_rel(root, file)}:${fence.line + snippetLine})');
  }
  return dartFences.length;
}

bool _parses(String code) {
  final result = parseString(content: code, throwIfDiagnostics: false);
  return result.errors.isEmpty;
}

// ---- Gate 2: stale API symbols ---------------------------------------------

void _checkStaleApi(String root, String file) {
  final lines = File(file).readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final allowed = line.contains(_allowStaleMarker) ||
        (i > 0 && lines[i - 1].contains(_allowStaleMarker));
    if (allowed) continue;
    for (final entry in _staleApi.entries) {
      if (entry.value.hasMatch(line)) {
        _fail(
            'stale-api',
            '${_rel(root, file)}:${i + 1}',
            'removed 1.0.0 symbol `${entry.key}` (add $_allowStaleMarker on '
                'the preceding line to allow deliberately)');
      }
    }
  }
}

// ---- Gate 3: contract regexes over dart fences -----------------------------

void _checkContracts(String root, String file) {
  final fences = _extractFences(File(file).readAsStringSync());
  for (final fence in fences.where((f) => f.lang == 'dart')) {
    final lines = fence.code.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final fileLine = fence.line + 1 + i;

      if (_singleArgOnError.hasMatch(line)) {
        _fail('contract', '${_rel(root, file)}:$fileLine',
            'single-parameter onError callback — the API is (error, stack)');
      }

      if (_bareProviderValue.hasMatch(line)) {
        final prev = i > 0 ? lines[i - 1] : '';
        final next = i + 1 < lines.length ? lines[i + 1] : '';
        final marked = _badExampleComment.hasMatch(line) ||
            _badExampleComment.hasMatch(prev) ||
            _badExampleComment.hasMatch(next);
        if (!marked) {
          _fail(
              'contract',
              '${_rel(root, file)}:$fileLine',
              'bare Provider<XViewModel>.value — use ViewModelProvider, or '
                  'mark a deliberate bad example with a throw/BAD/anti-pattern '
                  'comment on the same or adjacent line');
        }
      }
    }
  }
}

// ---- Gate 4: relative links ------------------------------------------------

/// Inline markdown links/images. Group 1 = target.
final RegExp _mdLink = RegExp(r'!?\[[^\]]*\]\(([^()\s]+)(?:\s+"[^"]*")?\)');

/// Checks relative links in [file]; returns the number checked.
int _checkRelativeLinks(String root, String file) {
  final content = File(file).readAsStringSync();
  var checked = 0;

  // Strip fenced code blocks: links inside them are illustrative.
  final lines = content.split('\n');
  var inFence = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (RegExp(r'^\s*(`{3,}|~{3,})').hasMatch(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;

    for (final match in _mdLink.allMatches(line)) {
      var target = match.group(1)!;
      if (target.contains('://') ||
          target.startsWith('mailto:') ||
          target.startsWith('#')) {
        continue; // external or intra-file anchor: not checked
      }
      // Drop fragment/query, decode %-escapes.
      target = target.split('#').first.split('?').first;
      if (target.isEmpty) continue;
      target = Uri.decodeComponent(target);

      final resolved = target.startsWith('/')
          ? '$root$target'
          : '${File(file).parent.path}/$target';
      checked++;
      final type = FileSystemEntity.typeSync(resolved);
      if (type == FileSystemEntityType.notFound) {
        _fail('link', '${_rel(root, file)}:${i + 1}',
            'relative link target does not exist: $target');
      }
    }
  }
  return checked;
}

// ---- Markdown fence extraction ---------------------------------------------

class _Fence {
  _Fence(this.line, this.lang, this.code);

  /// 1-based line of the opening ``` marker.
  final int line;
  final String lang;
  final String code;
}

List<_Fence> _extractFences(String content) {
  final lines = content.split('\n');
  final fences = <_Fence>[];

  int? openLine;
  var openTicks = 0;
  var openIndent = 0;
  var lang = '';
  var buffer = <String>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (openLine == null) {
      final m = RegExp(r'^(\s*)(`{3,})([^`]*)$').firstMatch(line);
      if (m != null) {
        openLine = i + 1;
        openIndent = m.group(1)!.length;
        openTicks = m.group(2)!.length;
        lang = m.group(3)!.trim().split(RegExp(r'\s+')).first.toLowerCase();
        buffer = [];
      }
    } else {
      final m = RegExp(r'^\s*(`{3,})\s*$').firstMatch(line);
      if (m != null && m.group(1)!.length >= openTicks) {
        fences.add(_Fence(openLine, lang, buffer.join('\n')));
        openLine = null;
      } else {
        // Strip the list-item indentation carried by indented fences.
        final stripped = line.length >= openIndent &&
                line.substring(0, openIndent).trim().isEmpty
            ? line.substring(openIndent)
            : line;
        buffer.add(stripped);
      }
    }
  }
  return fences;
}

// ---- Helpers ----------------------------------------------------------------

/// The tool runs from the repo root (`dart run tool/check_docs.dart`), but
/// also tolerates being run from tool/.
String _findRepoRoot() {
  for (final candidate in [
    Directory.current.path,
    Directory.current.parent.path
  ]) {
    if (Directory('$candidate/docs').existsSync() &&
        Directory('$candidate/chassis/skills').existsSync()) {
      return candidate;
    }
  }
  stderr.writeln('check_docs: run from the repository root: '
      'dart run tool/check_docs.dart');
  exit(2);
}

/// Recursively lists files under `root/dir` matching [select], skipping any
/// archive/ segment.
List<String> _glob(String root, String dir, bool Function(String) select) {
  final directory = Directory('$root/$dir');
  if (!directory.existsSync()) return const [];
  final paths = directory
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => !p.split('/').contains('archive'))
      .where(select)
      .toList()
    ..sort();
  return paths;
}

String _rel(String root, String path) =>
    path.startsWith('$root/') ? path.substring(root.length + 1) : path;
