import 'dart:async';

import 'package:analyzer/dart/ast/ast.dart' show NamedType, SimpleIdentifier;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart' hide FunctionType, RecordType;
import 'package:source_gen/source_gen.dart';

const _handlerChecker =
    TypeChecker.typeNamedLiterally('ChassisHandler', inPackage: 'chassis');
const _moduleChecker =
    TypeChecker.typeNamedLiterally('ChassisModule', inPackage: 'chassis');
const _appChecker =
    TypeChecker.typeNamedLiterally('ChassisApp', inPackage: 'chassis');

/// Generates chassis mediator code for libraries annotated with `@ChassisApp`
/// (on the library directive) or containing a class annotated with
/// `@chassisModule`.
///
/// - `@chassisModule` on `AuthModule` → `abstract interface class
///   AuthMediator` with one typed method per handler of the module's package
///   reachable from the annotated library.
/// - `@ChassisApp(modules: [...])` on a library → a concrete mediator
///   extending `Mediator` and implementing every module interface. All
///   handlers are registered in the constructor, and every generated method
///   dispatches through `run`/`read`/`watch`, so middlewares always apply.
///
/// Any wiring mistake (missing constructor, unknown module, conflicting
/// method signatures, ...) fails the build with an actionable error. This
/// generator never emits a partial mediator.
class ChassisGenerator extends Generator {
  const ChassisGenerator();

  @override
  FutureOr<String?> generate(LibraryReader library, BuildStep buildStep) {
    final specs = <Spec>[];

    for (final classElement in library.classes) {
      if (_moduleChecker.hasAnnotationOfExact(classElement)) {
        specs.add(_generateModuleInterface(classElement));
      }
      if (_appChecker.hasAnnotationOfExact(classElement)) {
        throw InvalidGenerationSourceError(
          '@ChassisApp annotates the class ${classElement.name}, but it must '
          'annotate the library directive. Remove the class and put the '
          'annotation at the top of the file:\n'
          '  @ChassisApp(...)\n'
          '  library;',
          element: classElement,
        );
      }
    }

    final appAnnotation = _appChecker.firstAnnotationOfExact(library.element);
    if (appAnnotation != null) {
      specs.add(_generateAppMediator(
        library.element,
        ConstantReader(appAnnotation),
      ));
    }

    if (specs.isEmpty) return null;

    final lib = Library((l) => l..body.addAll(specs));
    final emitted = lib.accept(DartEmitter.scoped(useNullSafetySyntax: true));
    return '$emitted';
  }

  // --- Module interface generation ---

  Class _generateModuleInterface(ClassElement moduleClass) {
    if (moduleClass.isPrivate) {
      throw InvalidGenerationSourceError(
        '${moduleClass.name} is annotated with @chassisModule but is '
        'private. The generated app mediator implements the module '
        'interface from another file, so module classes must be public.',
        element: moduleClass,
      );
    }
    final handlers = _collectHandlers(moduleClass.library);
    if (handlers.isEmpty) {
      throw InvalidGenerationSourceError(
        'No @chassisHandler class is reachable from the library declaring '
        '${moduleClass.name}. A chassis module must be declared in a library '
        'that (transitively) imports every handler of the package — '
        'typically the package barrel.',
        element: moduleClass,
      );
    }

    final operations = _toOperations(moduleClass, handlers);

    return Class(
      (c) => c
        ..name = _interfaceNameFor(moduleClass)
        ..abstract = true
        ..modifier = ClassModifier.interface
        ..docs.add(
          '/// Typed mediator interface of the `${moduleClass.name}` module.\n'
          '///\n'
          '/// Implemented by the app mediator generated from '
          '`@ChassisApp(modules: [${moduleClass.name}])`.',
        )
        ..methods.addAll(operations.map(
          (op) => Method(
            (m) => m
              ..name = op.methodName
              ..returns = op.methodReturnType
              ..requiredParameters.addAll(op.positionalParameters)
              ..optionalParameters.addAll(op.namedAndOptionalParameters),
          ),
        )),
    );
  }

  // --- App mediator generation ---

  Class _generateAppMediator(
      LibraryElement appLibrary, ConstantReader annotation) {
    final mediatorName = annotation.read('mediatorName').stringValue;

    // Resolve declared modules.
    final moduleClasses = <ClassElement>[];
    for (final moduleObject in annotation.read('modules').listValue) {
      final type = moduleObject.toTypeValue();
      final element = type is InterfaceType ? type.element : null;
      if (element is! ClassElement ||
          !_moduleChecker.hasAnnotationOfExact(element)) {
        throw InvalidGenerationSourceError(
          '@ChassisApp on library ${appLibrary.uri} lists '
          '`${type ?? moduleObject}` in `modules`, which is not a class '
          'annotated with @chassisModule.',
          element: appLibrary,
        );
      }
      moduleClasses.add(element);
    }

    // Collect handlers: per module (within the module's package), then the
    // app's own handlers (within the app's package).
    final operations = <_Operation>[];
    final seenMessageTypes = <String, _Operation>{};
    final seenSignatures = <String, _Operation>{};
    final seenMethodNames = <String, _Operation>{};

    void addOperations(Element owner, List<ClassElement> handlers,
        {ClassElement? module}) {
      for (final op in _toOperations(owner, handlers, module: module)) {
        final messageKey = _elementKey(op.messageType.element);
        final duplicateMessage = seenMessageTypes[messageKey];
        if (duplicateMessage != null) {
          throw InvalidGenerationSourceError(
            'Both ${duplicateMessage.handlerDescription} and '
            '${op.handlerDescription} handle ${op.messageType.element.name}. '
            'Each command/query type must have exactly one handler across '
            'the app and its modules.',
            element: appLibrary,
          );
        }
        seenMessageTypes[messageKey] = op;

        final duplicateSignature = seenSignatures[op.signatureKey];
        if (duplicateSignature != null) {
          throw InvalidGenerationSourceError(
            '${duplicateSignature.handlerDescription} and '
            '${op.handlerDescription} both produce the method '
            '`${op.methodName}` with an identical signature. The type system '
            'would silently satisfy both with one implementation, so chassis '
            'refuses this composition: rename one message class to '
            'disambiguate.',
            element: appLibrary,
          );
        }
        seenSignatures[op.signatureKey] = op;

        // Same derived method name with *different* signatures across the app
        // and its modules would emit two methods with one name — invalid
        // Dart. The per-owner check in _toOperations cannot see this.
        final duplicateName = seenMethodNames[op.methodName];
        if (duplicateName != null) {
          throw InvalidGenerationSourceError(
            '${duplicateName.handlerDescription} and '
            '${op.handlerDescription} both derive the method name '
            '`${op.methodName}` from their message. Rename one message class '
            'to disambiguate.',
            element: appLibrary,
          );
        }
        seenMethodNames[op.methodName] = op;

        operations.add(op);
      }
    }

    for (final module in moduleClasses) {
      addOperations(module, _collectHandlers(module.library), module: module);
    }
    addOperations(appLibrary, _collectHandlers(appLibrary));

    if (operations.isEmpty) {
      throw InvalidGenerationSourceError(
        '@ChassisApp on library ${appLibrary.uri} found no @chassisHandler '
        'class: none reachable from this library within package '
        '`${_packageOf(appLibrary)}`, and no modules were declared. Import '
        'your handlers (directly or via a barrel) or declare modules.',
        element: appLibrary,
      );
    }

    // Deduplicate constructor dependencies across all handlers, keyed by
    // resolved element so same-named types from different packages stay
    // distinct.
    final dependencies = <String, _Dependency>{};
    final usedParamNames = <String>{};
    for (final op in operations) {
      for (final dep in op.dependencies) {
        final key = _elementKey(dep.type.element);
        final existing = dependencies[key];
        if (existing != null) {
          dep.paramName = existing.paramName;
          continue;
        }
        var name = dep.preferredParamName;
        var suffix = 2;
        while (!usedParamNames.add(name)) {
          name = '${dep.preferredParamName}${suffix++}';
        }
        dep.paramName = name;
        dependencies[key] = dep;
      }
    }

    return Class(
      (c) => c
        ..name = mediatorName
        ..extend = refer('Mediator', 'package:chassis/chassis.dart')
        ..implements.addAll(moduleClasses.map(
          (m) => refer(_interfaceNameFor(m), _generatedUriFor(m)),
        ))
        ..docs.add(
          '/// Concrete mediator generated from the `@ChassisApp` library\n'
          '/// `${appLibrary.uri}`.\n'
          '///\n'
          '/// All handlers are registered in the constructor; every method '
          'dispatches\n/// through the mediator, so middlewares always '
          'apply.',
        )
        ..constructors.add(Constructor(
          (ctor) => ctor
            ..optionalParameters.addAll(
              dependencies.values.map(
                (dep) => Parameter(
                  (p) => p
                    ..name = dep.paramName
                    ..type = _referType(dep.type)
                    ..named = true
                    ..required = true,
                ),
              ),
            )
            ..body = Block.of(operations.map(_registration)),
        ))
        ..methods.addAll(operations.map(
          (op) => Method(
            (m) => m
              ..annotations.addAll([if (op.module != null) refer('override')])
              ..name = op.methodName
              ..returns = op.methodReturnType
              ..requiredParameters.addAll(op.positionalParameters)
              ..optionalParameters.addAll(op.namedAndOptionalParameters)
              ..lambda = true
              ..body = op.dispatchCall,
          ),
        )),
    );
  }

  Code _registration(_Operation op) {
    final handlerRef =
        refer(op.handler.name!, op.handler.library.uri.toString());
    // Dependencies are passed the way the handler declares them: positional
    // parameters positionally, named parameters by their own name.
    final instance = handlerRef.newInstance(
      [
        for (final d in op.dependencies)
          if (!d.isNamed) refer(d.paramName),
      ],
      {
        for (final d in op.dependencies)
          if (d.isNamed) d.name: refer(d.paramName),
      },
    );
    final registerMethod = switch (op.kind) {
      _OperationKind.command => 'registerCommandHandler',
      _ => 'registerQueryHandler',
    };
    return refer(registerMethod).call([instance]).statement;
  }

  // --- Handler discovery (import-graph walk, spike-validated) ---

  /// Collects every `@chassisHandler` class reachable from [rootLibrary]
  /// via imports/exports, restricted to [rootLibrary]'s own package.
  /// Deterministic order (library URI, then class name).
  List<ClassElement> _collectHandlers(LibraryElement rootLibrary) {
    final package = _packageOf(rootLibrary);

    final visited = <Uri>{};
    final queue = <LibraryElement>[rootLibrary];
    final handlers = <ClassElement>[];

    bool inPackage(Uri uri) =>
        uri.scheme == 'package' && uri.pathSegments.first == package ||
        uri.scheme == 'asset' && uri.pathSegments.first == package;

    while (queue.isNotEmpty) {
      final lib = queue.removeLast();
      if (!visited.add(lib.uri)) continue;
      if (!inPackage(lib.uri)) continue;

      for (final cls in lib.classes) {
        if (_handlerChecker.hasAnnotationOfExact(cls)) {
          handlers.add(cls);
        }
      }

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

    handlers.sort((a, b) {
      final byUri =
          a.library.uri.toString().compareTo(b.library.uri.toString());
      return byUri != 0 ? byUri : a.name!.compareTo(b.name!);
    });
    return handlers;
  }

  // --- Handler analysis ---

  List<_Operation> _toOperations(
    Element owner,
    List<ClassElement> handlers, {
    ClassElement? module,
  }) {
    final operations = <_Operation>[];
    final methodNames = <String, _Operation>{};

    for (final handler in handlers) {
      final op = _analyzeHandler(handler, module: module);

      final clash = methodNames[op.methodName];
      if (clash != null) {
        if (_elementKey(clash.messageType.element) ==
            _elementKey(op.messageType.element)) {
          throw InvalidGenerationSourceError(
            'Both ${clash.handlerDescription} and ${op.handlerDescription} '
            'handle ${op.messageType.element.name}. Each command/query type '
            'must have exactly one handler.',
            element: owner,
          );
        }
        throw InvalidGenerationSourceError(
          '${clash.handlerDescription} and ${op.handlerDescription} both '
          'derive the method name `${op.methodName}` from their message. '
          'Rename one message class to disambiguate.',
          element: owner,
        );
      }
      methodNames[op.methodName] = op;
      operations.add(op);
    }
    return operations;
  }

  _Operation _analyzeHandler(ClassElement handler, {ClassElement? module}) {
    if (handler.isPrivate) {
      throw InvalidGenerationSourceError(
        '${handler.name} is annotated with @chassisHandler but is private. '
        'The generated mediator instantiates handlers from another file, so '
        'handler classes must be public.',
        element: handler,
      );
    }
    // Identify which handler interface is implemented.
    InterfaceType? handlerInterface;
    for (final supertype in handler.allSupertypes) {
      final name = supertype.element.name;
      final uri = supertype.element.library.uri;
      final isChassis =
          uri.scheme == 'package' && uri.pathSegments.first == 'chassis';
      if (isChassis &&
          (name == 'CommandHandler' ||
              name == 'ReadHandler' ||
              name == 'WatchHandler')) {
        handlerInterface = supertype;
        break;
      }
    }
    if (handlerInterface == null) {
      throw InvalidGenerationSourceError(
        '${handler.name} is annotated with @chassisHandler but implements '
        'none of CommandHandler, ReadHandler, or WatchHandler.',
        element: handler,
      );
    }

    final typeArguments = handlerInterface.typeArguments;
    final messageType = typeArguments[0];
    final resultType = typeArguments[1];
    if (messageType is! InterfaceType) {
      throw InvalidGenerationSourceError(
        '${handler.name} implements ${handlerInterface.element.name} with '
        'a non-class message type ($messageType).',
        element: handler,
      );
    }

    final kind = switch (handlerInterface.element.name) {
      'CommandHandler' => _OperationKind.command,
      'ReadHandler' => _OperationKind.read,
      _ => _OperationKind.watch,
    };

    if (handler.typeParameters.isNotEmpty) {
      throw InvalidGenerationSourceError(
        '${handler.name} is generic. The generator instantiates handlers '
        'concretely, so a @chassisHandler class cannot declare type '
        'parameters.',
        element: handler,
      );
    }

    // Handler constructor → dependencies.
    final handlerConstructor = handler.constructors
        .where((c) => c.name == 'new' && !c.isFactory)
        .firstOrNull;
    if (handlerConstructor == null) {
      throw InvalidGenerationSourceError(
        '${handler.name} is annotated with @chassisHandler but has no '
        'unnamed generative constructor. The generator instantiates handlers '
        'by calling their constructor with the dependencies it requires.',
        element: handler,
      );
    }
    for (final param in handlerConstructor.formalParameters) {
      _rejectUnsupportedType(
        param.type,
        handler,
        "${handler.name}'s constructor parameter `${param.name}`",
      );
    }
    final dependencies = [
      for (final param in handlerConstructor.formalParameters)
        _Dependency(param.type, name: param.name!, isNamed: param.isNamed),
    ];

    // Message constructor → method parameters.
    final messageElement = messageType.element;
    if (messageElement is! ClassElement) {
      throw InvalidGenerationSourceError(
        '${handler.name}: message type ${messageElement.name} is not a '
        'class.',
        element: handler,
      );
    }
    if (messageElement.isPrivate) {
      throw InvalidGenerationSourceError(
        '${messageElement.name} (handled by ${handler.name}) is private. '
        'The generated mediator constructs and dispatches messages from '
        'another file, so message classes must be public.',
        element: messageElement,
      );
    }
    if (messageElement.typeParameters.isNotEmpty) {
      throw InvalidGenerationSourceError(
        '${messageElement.name} (handled by ${handler.name}) is generic. '
        'Mediator dispatch is keyed by the exact runtime type of the '
        'message, which type arguments would make ambiguous — declare one '
        'concrete message class per operation instead.',
        element: messageElement,
      );
    }
    final messageConstructor = messageElement.constructors
        .where((c) => c.name == 'new' && !c.isFactory)
        .firstOrNull;
    if (messageConstructor == null) {
      throw InvalidGenerationSourceError(
        '${messageElement.name} (handled by ${handler.name}) has no unnamed '
        'generative constructor, so no typed mediator method can be '
        'generated for it.',
        element: messageElement,
      );
    }
    for (final param in messageConstructor.formalParameters) {
      _rejectUnsupportedType(
        param.type,
        messageElement,
        '${messageElement.name}.${param.name} (handled by ${handler.name})',
      );
      _rejectNonCoreDefault(param, messageElement, handler);
    }

    return _Operation(
      handler: handler,
      module: module,
      kind: kind,
      messageType: messageType,
      resultType: resultType,
      messageParameters: messageConstructor.formalParameters,
      dependencies: dependencies,
      methodName: _methodNameFor(messageElement.name!),
      referType: _referType,
    );
  }

  /// Rejects default values that reference declarations outside dart:core.
  ///
  /// The generated mediator repeats the message constructor's default value
  /// verbatim, and only dart:core is in unprefixed scope in the generated
  /// file — a default like `MyEnum.a` would emit code that does not compile.
  void _rejectNonCoreDefault(
    FormalParameterElement param,
    ClassElement messageElement,
    ClassElement handler,
  ) {
    final initializer = param.constantInitializer;
    if (initializer == null) return;
    final visitor = _NonCoreReferenceFinder();
    initializer.accept(visitor);
    final offender = visitor.firstNonCoreReference;
    if (offender != null) {
      throw InvalidGenerationSourceError(
        '${messageElement.name}.${param.name} (handled by ${handler.name}) '
        'has the default value `${param.defaultValueCode}`, which references '
        '`${offender.name}` from ${offender.library?.uri}. The generated '
        'mediator repeats default values verbatim with only dart:core in '
        'scope, so a default may reference dart:core declarations only '
        '(literals, `const Duration(...)`, `const []`, ...). Remove the '
        'default value or express it with dart:core alone.',
        element: messageElement,
      );
    }
  }

  /// Rejects function and record types (including nested in type arguments):
  /// the generated mediator cannot reliably reference them.
  void _rejectUnsupportedType(DartType type, Element element, String what) {
    if (type is FunctionType || type is RecordType) {
      final kind = type is FunctionType ? 'function' : 'record';
      throw InvalidGenerationSourceError(
        '$what has a $kind type (`$type`), which the generator cannot '
        'reference in generated code. Wrap it in a class.',
        element: element,
      );
    }
    if (type is InterfaceType) {
      for (final argument in type.typeArguments) {
        _rejectUnsupportedType(argument, element, what);
      }
    }
  }

  // --- Naming ---

  String _interfaceNameFor(ClassElement moduleClass) {
    final name = moduleClass.name!;
    final base = name.endsWith('Module')
        ? name.substring(0, name.length - 'Module'.length)
        : name;
    return '${base}Mediator';
  }

  /// URI of the `.chassis.dart` file generated next to [element]'s library.
  String _generatedUriFor(ClassElement element) {
    final uri = element.library.uri.toString();
    return uri.replaceFirst(RegExp(r'\.dart$'), '.chassis.dart');
  }

  /// Derives the mediator method name from the *message* class name
  /// (`CreateUserCommand` → `createUser`), never from the handler: the
  /// message is the public concept, so renaming a handler (an implementation
  /// detail) does not change the generated API.
  String _methodNameFor(String messageName) {
    var name = messageName;
    if (name.endsWith('Query')) {
      name = name.substring(0, name.length - 'Query'.length);
    } else if (name.endsWith('Command')) {
      name = name.substring(0, name.length - 'Command'.length);
    }
    if (name.isEmpty) name = messageName;
    return name[0].toLowerCase() + name.substring(1);
  }

  static String _packageOf(LibraryElement library) {
    final uri = library.uri;
    if (uri.scheme != 'package' && uri.scheme != 'asset') {
      throw InvalidGenerationSourceError(
        'Cannot determine the package of library $uri.',
        element: library,
      );
    }
    return uri.pathSegments.first;
  }

  static String _elementKey(Element? element) =>
      '${element?.library?.uri}#${element?.name}';

  // --- Type references ---

  Reference _referType(DartType type) {
    var uri = type.element?.library?.uri.toString();

    // dart:core is imported by default.
    if (uri != null && uri.startsWith('dart:core')) {
      uri = null;
    }

    // Normalize dart: URIs to remove part file paths
    // e.g., 'dart:ui/painting.dart' -> 'dart:ui'
    if (uri != null && uri.startsWith('dart:')) {
      final slashIndex = uri.indexOf('/');
      if (slashIndex != -1) {
        uri = uri.substring(0, slashIndex);
      }
    }

    if (type is InterfaceType && type.typeArguments.isNotEmpty) {
      return TypeReference((t) => t
        ..symbol = type.element.name
        ..url = uri
        ..isNullable = type.nullabilitySuffix == NullabilitySuffix.question
        ..types.addAll(type.typeArguments.map(_referType)));
    }

    if (type is VoidType) return refer('void');
    if (type is DynamicType) return refer('dynamic');

    final name = type.getDisplayString();
    return TypeReference((t) => t
      ..symbol = type.nullabilitySuffix == NullabilitySuffix.question
          ? name.substring(0, name.length - 1)
          : name
      ..url = uri
      ..isNullable = type.nullabilitySuffix == NullabilitySuffix.question);
  }
}

/// Finds the first reference to a declaration outside dart:core in a
/// resolved constant expression.
class _NonCoreReferenceFinder extends RecursiveAstVisitor<void> {
  Element? firstNonCoreReference;

  void _check(Element? element) {
    if (firstNonCoreReference != null || element == null) return;
    final uri = element.library?.uri;
    if (uri == null) return;
    if (uri.isScheme('dart') && uri.path == 'core') return;
    firstNonCoreReference = element;
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _check(node.element);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    _check(node.element);
    super.visitNamedType(node);
  }
}

enum _OperationKind { command, read, watch }

/// A constructor dependency of a handler.
class _Dependency {
  _Dependency(this.type, {required this.name, required this.isNamed});

  final DartType type;

  /// The handler constructor's own parameter name, used to pass the
  /// dependency back as a named argument when [isNamed] is true.
  final String name;
  final bool isNamed;

  /// The mediator constructor's parameter name for this dependency,
  /// assigned during dedup (derived from the type, shared across handlers).
  late String paramName;

  String get preferredParamName {
    final name = type.element?.name ?? 'dependency';
    return name[0].toLowerCase() + name.substring(1);
  }
}

/// One typed mediator operation derived from a handler.
class _Operation {
  _Operation({
    required this.handler,
    required this.module,
    required this.kind,
    required this.messageType,
    required this.resultType,
    required this.messageParameters,
    required this.dependencies,
    required this.methodName,
    required Reference Function(DartType) referType,
  }) : _referType = referType;

  final ClassElement handler;

  /// The module this operation belongs to, or null for app-own handlers.
  final ClassElement? module;
  final _OperationKind kind;
  final InterfaceType messageType;
  final DartType resultType;
  final List<FormalParameterElement> messageParameters;
  final List<_Dependency> dependencies;
  final String methodName;
  final Reference Function(DartType) _referType;

  String get handlerDescription => '${handler.name} (${handler.library.uri})';

  /// Identity of the generated method signature, used to detect two modules
  /// producing indistinguishable methods.
  String get signatureKey {
    final params = messageParameters
        .map((p) => '${p.isNamed ? '${p.name}:' : ''}${p.type}')
        .join(',');
    return '$methodName($params)';
  }

  TypeReference get methodReturnType => TypeReference((t) => t
    ..symbol = kind == _OperationKind.watch ? 'Stream' : 'Future'
    ..types.add(_referType(resultType)));

  Iterable<Parameter> get positionalParameters =>
      messageParameters.where((p) => p.isRequiredPositional).map(_parameter);

  Iterable<Parameter> get namedAndOptionalParameters =>
      messageParameters.where((p) => !p.isRequiredPositional).map(_parameter);

  Parameter _parameter(FormalParameterElement param) {
    final defaultCode = param.defaultValueCode;
    return Parameter((p) => p
      ..name = param.name!
      ..type = _referType(param.type)
      ..named = param.isNamed
      ..required = param.isRequiredNamed
      ..defaultTo = defaultCode != null ? Code(defaultCode) : null);
  }

  /// `run(LoginCommand(username))` — always dispatches through the mediator
  /// so middlewares apply.
  Code get dispatchCall {
    final positionalArgs = messageParameters
        .where((p) => p.isPositional)
        .map((p) => refer(p.name!));
    final namedArgs = {
      for (final p in messageParameters.where((p) => p.isNamed))
        p.name!: refer(p.name!),
    };
    final message = refer(
      messageType.element.name!,
      messageType.element.library.uri.toString(),
    ).newInstance(positionalArgs, namedArgs);

    final verb = switch (kind) {
      _OperationKind.command => 'run',
      _OperationKind.read => 'read',
      _OperationKind.watch => 'watch',
    };
    return refer(verb).call([message]).code;
  }
}
