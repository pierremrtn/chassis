import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

Builder chassisSpikeBuilder(BuilderOptions options) => ChassisSpikeBuilder();

const _handlerChecker = TypeChecker.typeNamedLiterally(
  'ChassisHandler',
  inPackage: 'spike_core',
);

class ChassisSpikeBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
        'lib/main.dart': ['lib/main.chassis.txt'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputLibrary = await buildStep.inputLibrary;

    // Walk the transitive import/export graph, cycle-safe.
    final visited = <Uri>{};
    final queue = <LibraryElement>[inputLibrary];
    final allLibraries = <LibraryElement>[];

    while (queue.isNotEmpty) {
      final lib = queue.removeLast();
      if (!visited.add(lib.uri)) continue;
      if (lib.uri.isScheme('dart')) continue;
      allLibraries.add(lib);

      for (final fragment in lib.fragments) {
        for (final imported in fragment.importedLibraries) {
          queue.add(imported);
        }
        for (final export in fragment.libraryExports) {
          final exported = export.exportedLibrary;
          if (exported != null) queue.add(exported);
        }
      }
    }

    final lines = <String>[];
    for (final lib in allLibraries) {
      for (final cls in lib.classes) {
        if (!_handlerChecker.hasAnnotationOfExact(cls)) continue;
        final ctor = cls.constructors.isEmpty ? null : cls.constructors.first;
        final params = ctor == null
            ? '<no constructor>'
            : ctor.formalParameters
                .map((p) =>
                    '${p.type.getDisplayString()} ${p.name ?? '<unnamed>'}')
                .join(', ');
        lines.add('${cls.name} | ${lib.uri} | ($params)');
      }
    }
    lines.sort();

    final report = StringBuffer()
      ..writeln('# Chassis spike: cross-package handler discovery')
      ..writeln('# Libraries visited: ${allLibraries.length}')
      ..writeln('# Handlers found: ${lines.length}')
      ..writeAll(lines, '\n');

    await buildStep.writeAsString(
      buildStep.inputId.changeExtension('.chassis.txt'),
      report.toString(),
    );
  }
}
