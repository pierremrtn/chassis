import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:chassis/chassis.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:glob/glob.dart';
import 'package:source_gen/source_gen.dart';

class ChassisBuilder implements Builder {
  @override
  final Map<String, List<String>> buildExtensions = {
    '.dart': ['.chassis.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final assetId = buildStep.inputId;
    if (assetId.path.endsWith('.g.dart') ||
        assetId.path.endsWith('.chassis.dart')) {
      return;
    }

    try {
      final library = await buildStep.resolver.libraryFor(assetId);
      final reader = LibraryReader(library);

      // Find annotated classes
      final mediators = reader
          .annotatedWith(const TypeChecker.fromRuntime(ChassisMediator))
          .where((e) => e.element is ClassElement)
          .map((e) => e.element as ClassElement)
          .toList();

      if (mediators.isEmpty) return;

      // Scan for handlers (This scans ALL files for every mediator - optimization needed in real world, but fine for now)
      final handlers = <ClassElement>[];
      final allAssets =
          await buildStep.findAssets(Glob('lib/**.dart')).toList();

      for (final id in allAssets) {
        if (id.path.endsWith('.g.dart') || id.path.endsWith('.chassis.dart'))
          continue;
        try {
          final lib = await buildStep.resolver.libraryFor(id);
          final libReader = LibraryReader(lib);
          for (final e in libReader
              .annotatedWith(const TypeChecker.fromRuntime(ChassisHandler))) {
            if (e.element is ClassElement) {
              handlers.add(e.element as ClassElement);
            }
          }
        } catch (_) {}
      }

      final outputId = assetId.changeExtension('.chassis.dart');
      final generatedCode = _generateCode(mediators, handlers);
      await buildStep.writeAsString(outputId, generatedCode);
    } catch (e) {
      // Ignore
    }
  }

  String _generateCode(
    List<ClassElement> mediators,
    List<ClassElement> handlers,
  ) {
    if (mediators.isEmpty) return '';

    final manualImports = <String>{
      'package:chassis/chassis.dart',
    };
    final dependencyMap = <String, Reference>{};

    // Analyze dependencies
    for (final handler in handlers) {
      manualImports.add(handler.source.uri.toString());

      final constructor = handler.unnamedConstructor;
      if (constructor == null) continue;
      for (final param in constructor.parameters) {
        final typeName = param.type.getDisplayString(withNullability: true);
        if (!dependencyMap.containsKey(typeName)) {
          dependencyMap[typeName] = _referType(param.type);
        }
      }
    }

    final library = Library(
      (l) => l
        ..directives.addAll(manualImports.map((url) => Directive.import(url)))
        ..body.addAll(
          mediators.expand((mediator) =>
              _generateMediatorArtifacts(mediator, handlers, dependencyMap)),
        ),
    );

    return DartFormatter().format(
      '${library.accept(DartEmitter.scoped())}',
    );
  }

  Iterable<Spec> _generateMediatorArtifacts(
    ClassElement mediator,
    List<ClassElement> handlers,
    Map<String, Reference> dependencyMap,
  ) {
    final generatedName = '\$${mediator.name}';

    final mediatorClass = Class(
      (c) => c
        ..name = generatedName
        ..extend = refer(mediator.name, mediator.source.uri.toString())
        ..constructors.add(
          Constructor(
            (ctor) => ctor
              ..optionalParameters.addAll(
                dependencyMap.entries.map(
                  (e) => Parameter(
                    (p) => p
                      ..name = _toParamName(e.key)
                      ..type = e.value
                      ..named = true
                      ..required = true,
                  ),
                ),
              )
              ..body = Block.of(
                handlers.map((h) => _generateRegistration(h)).nonNulls,
              ),
          ),
        ),
    );

    final extension = Extension(
      (e) => e
        ..name = '${mediator.name}Extensions'
        ..on = refer('Mediator')
        ..methods.addAll(
          handlers.map((h) => _generateExtensionMethod(h)).nonNulls,
        ),
    );

    return [mediatorClass, extension];
  }

  Code? _generateRegistration(ClassElement handler) {
    final constructor = handler.unnamedConstructor!;
    final args = constructor.parameters
        .map(
            (p) => _toParamName(p.type.getDisplayString(withNullability: true)))
        .join(', ');

    final handlerRef = refer(handler.name, handler.source.uri.toString());

    bool isCommand = handler.allSupertypes.any(
      (s) => s.element.name == 'CommandHandler',
    );
    bool isQuery = handler.allSupertypes.any(
      (s) =>
          s.element.name == 'ReadHandler' ||
          s.element.name == 'WatchHandler' ||
          s.element.name == 'QueryHandler',
    );

    if (isCommand) {
      return refer('registerCommandHandler').call([
        handlerRef.newInstance([CodeExpression(Code(args))]),
      ]).statement;
    } else if (isQuery) {
      return refer('registerQueryHandler').call([
        handlerRef.newInstance([CodeExpression(Code(args))]),
      ]).statement;
    }
    return null;
  }

  Method? _generateExtensionMethod(ClassElement handler) {
    InterfaceType? interfaceType;
    for (final supertype in handler.allSupertypes) {
      if ((supertype.element.name == 'CommandHandler' ||
          supertype.element.name == 'ReadHandler' ||
          supertype.element.name == 'WatchHandler')) {
        interfaceType = supertype;
        break;
      }
    }
    if (interfaceType == null)
      return null; // Should verify it is an InterfaceType

    final typeArgs = interfaceType.typeArguments;
    if (typeArgs.length < 2) return null;

    final inputType = typeArgs[0];
    final outputType = typeArgs[1];

    final methodName = _decapitalize(handler.name.replaceAll('Handler', ''));

    if (interfaceType.element.name == 'CommandHandler') {
      return Method(
        (m) => m
          ..name = methodName
          ..returns = TypeReference(
            (t) => t
              ..symbol = 'Future'
              ..types.add(_referType(outputType)),
          )
          ..requiredParameters.add(
            Parameter(
              (p) => p
                ..name = 'command'
                ..type = _referType(inputType),
            ),
          )
          ..body = refer('run').call([refer('command')]).code,
      );
    } else if (interfaceType.element.name == 'ReadHandler' ||
        interfaceType.element.name == 'WatchHandler') {
      bool isWatch = interfaceType.element.name == 'WatchHandler';
      final verb = isWatch ? 'watch' : 'read';
      final returnType = isWatch ? 'Stream' : 'Future';

      return Method(
        (m) => m
          ..name = methodName
          ..returns = TypeReference(
            (t) => t
              ..symbol = returnType
              ..types.add(_referType(outputType)),
          )
          ..requiredParameters.add(
            Parameter(
              (p) => p
                ..name = 'query'
                ..type = _referType(inputType),
            ),
          )
          ..body = refer(verb).call([refer('query')]).code,
      );
    }
    return null;
  }

  Reference _referType(DartType type) {
    final name = type.getDisplayString(withNullability: true);
    final uri = type.element?.source?.uri.toString();
    if (uri != null &&
        (uri.startsWith('dart:core') || uri.startsWith('dart:async'))) {
      return refer(name);
    }
    return refer(name, uri);
  }

  String _toParamName(String typeName) {
    return typeName.substring(0, 1).toLowerCase() + typeName.substring(1);
  }

  String _decapitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toLowerCase() + s.substring(1);
  }
}
