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
  final String _mediatorName;
  final String _outputName;

  ChassisBuilder(BuilderOptions options)
      : _mediatorName =
            options.config['mediator_name'] as String? ?? 'AppMediator',
        _outputName =
            options.config['output_name'] as String? ?? 'app_mediator.dart';

  @override
  Map<String, List<String>> get buildExtensions => {
        r'$lib$': [_outputName],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    try {
      final handlers = <ClassElement>[];
      final allAssets =
          await buildStep.findAssets(Glob('lib/**.dart')).toList();

      for (final id in allAssets) {
        if (id.path.endsWith('.g.dart') ||
            id.path.endsWith('.chassis.dart') ||
            id.path.endsWith(_outputName)) continue;
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

      final outputId = AssetId(buildStep.inputId.package, 'lib/$_outputName');
      final generatedCode = _generateCode(handlers);
      await buildStep.writeAsString(outputId, generatedCode);
    } catch (e) {
      log.severe('Failed to generate mediator', e);
    }
  }

  String _generateCode(List<ClassElement> handlers) {
    if (handlers.isEmpty) return '';

    final manualImports = <String>{
      'package:chassis/chassis.dart',
    };
    final dependencyMap = <String, Reference>{};

    // Analyze handler constructor dependencies (for Mediator constructor)
    for (final handler in handlers) {
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
          _generateMediatorArtifacts(handlers, dependencyMap),
        ),
    );

    return DartFormatter().format(
      '${library.accept(DartEmitter.scoped())}',
    );
  }

  Iterable<Spec> _generateMediatorArtifacts(
    List<ClassElement> handlers,
    Map<String, Reference> dependencyMap,
  ) {
    final mediatorClass = Class(
      (c) => c
        ..name = _mediatorName
        ..extend = refer('Mediator')
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
        ..name = '${_mediatorName}Extensions'
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
    // Get handler interface type
    final interfaceType = _getHandlerInterface(handler);
    if (interfaceType == null) return null;

    final typeArgs = interfaceType.typeArguments;
    if (typeArgs.length < 2) return null;

    final inputType = typeArgs[0];
    final outputType = typeArgs[1];
    final methodName = _generateMethodName(handler.name);

    // Extract constructor parameters
    final constructorParams = _extractConstructorParameters(inputType);

    // Determine handler type and verb
    final handlerTypeName = interfaceType.element.name;
    final isCommand = handlerTypeName == 'CommandHandler';
    final isWatch = handlerTypeName == 'WatchHandler';
    final verb = isCommand ? 'run' : (isWatch ? 'watch' : 'read');
    final returnTypeWrapper = isCommand || !isWatch ? 'Future' : 'Stream';

    // Build method parameters from constructor parameters
    final positionalParams = <Parameter>[];
    final namedParams = <Parameter>[];

    for (final param in constructorParams) {
      final methodParam = Parameter((p) => p
        ..name = param.name
        ..type = _referType(param.type)
        ..named = param.isNamed
        ..required = param.isNamed && param.isRequired
        ..defaultTo = param.defaultValueCode != null
            ? _buildDefaultValueExpression(param)
            : null);

      if (param.isNamed) {
        namedParams.add(methodParam);
      } else {
        positionalParams.add(methodParam);
      }
    }

    // Build method body: construct command/query, then pass to mediator
    Code buildBody() {
      if (constructorParams.isEmpty) {
        // Empty constructor: mediator.method() => run/read/watch(InputType())
        final construction = _referType(inputType).newInstance([]);
        return refer(verb).call([construction]).code;
      }

      // Build positional arguments
      final positionalArgs =
          constructorParams.where((p) => !p.isNamed).map((p) => refer(p.name));

      // Build named arguments
      final namedArgs = Map.fromEntries(constructorParams
          .where((p) => p.isNamed)
          .map((p) => MapEntry(p.name, refer(p.name))));

      // Construct: InputType(args...)
      final construction =
          _referType(inputType).newInstance(positionalArgs, namedArgs);

      // Call mediator method: run/read/watch(construction)
      return refer(verb).call([construction]).code;
    }

    return Method((m) => m
      ..name = methodName
      ..returns = TypeReference((t) => t
        ..symbol = returnTypeWrapper
        ..types.add(_referType(outputType)))
      ..requiredParameters.addAll(positionalParams)
      ..optionalParameters.addAll(namedParams)
      ..body = buildBody());
  }

  Reference _referType(DartType type) {
    final name = type.getDisplayString(withNullability: true);
    var uri = type.element?.source?.uri.toString();

    // Don't include URI for dart:core and dart:async (they're imported by default)
    if (uri != null &&
        (uri.startsWith('dart:core') || uri.startsWith('dart:async'))) {
      return refer(name);
    }

    // Normalize dart: URIs to remove part file paths
    // e.g., 'dart:ui/painting.dart' -> 'dart:ui'
    if (uri != null && uri.startsWith('dart:')) {
      final slashIndex = uri.indexOf('/');
      if (slashIndex != -1) {
        uri = uri.substring(0, slashIndex);
      }
    }

    return refer(name, uri);
  }

  String _toParamName(String typeName) {
    return typeName.substring(0, 1).toLowerCase() + typeName.substring(1);
  }

  String _generateMethodName(String handlerName) {
    // Remove "Handler" suffix first
    var name = handlerName.replaceAll('Handler', '');

    // Remove redundant "Query" or "Command" suffixes
    if (name.endsWith('Query')) {
      name = name.substring(0, name.length - 'Query'.length);
    } else if (name.endsWith('Command')) {
      name = name.substring(0, name.length - 'Command'.length);
    }

    // Decapitalize first letter
    if (name.isEmpty) return name;
    return name[0].toLowerCase() + name.substring(1);
  }

  List<ParameterElement> _extractConstructorParameters(DartType inputType) {
    final element = inputType.element;
    if (element is! ClassElement) return [];

    final constructor = element.unnamedConstructor;
    if (constructor == null) return [];

    // Skip factory constructors
    if (constructor.isFactory) return [];

    return constructor.parameters;
  }

  InterfaceType? _getHandlerInterface(ClassElement handler) {
    for (final supertype in handler.allSupertypes) {
      if (supertype.element.name == 'CommandHandler' ||
          supertype.element.name == 'ReadHandler' ||
          supertype.element.name == 'WatchHandler') {
        return supertype;
      }
    }
    return null;
  }

  Code? _buildDefaultValueExpression(ParameterElement param) {
    final defaultValueCode = param.defaultValueCode;
    if (defaultValueCode == null) return null;

    // Get the constant value to access type information
    final constantValue = param.computeConstantValue();
    if (constantValue == null) {
      // Fallback to raw code if we can't analyze it
      return Code(defaultValueCode);
    }

    // For const constructor calls like "const Color(0x000000)"
    // We need to extract the type and rebuild the expression with proper reference
    final type = constantValue.type;
    if (type != null && type.element != null) {
      // Check if this is a constructor invocation
      // Pattern: const TypeName(...) or TypeName(...)
      final constructorPattern = RegExp(r'^(?:const\s+)?(\w+)\((.*)\)$');
      final match = constructorPattern.firstMatch(defaultValueCode);

      if (match != null) {
        final args = match.group(2)!;

        // Build the expression using proper type reference
        final typeRef = _referType(type);
        // Build: const _i4.Color(0x000000)
        return typeRef.constInstance([CodeExpression(Code(args))]).code;
      }
    }

    // Fallback to raw code for simple literals and other cases
    return Code(defaultValueCode);
  }
}
