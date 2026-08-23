import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart' hide FunctionType, RecordType;
import 'package:source_gen/source_gen.dart';

const _handlerChecker = TypeChecker.typeNamedLiterally(
  'ChassisHandler',
  inPackage: 'chassis',
);
const _moduleChecker = TypeChecker.typeNamedLiterally(
  'ChassisModule',
  inPackage: 'chassis',
);
const _appChecker = TypeChecker.typeNamedLiterally(
  'ChassisApp',
  inPackage: 'chassis',
);
const _mediatorChecker = TypeChecker.typeNamedLiterally(
  'Mediator',
  inPackage: 'chassis',
);
const _unhandledMessageChecker = TypeChecker.typeNamedLiterally(
  'UnhandledMessage',
  inPackage: 'chassis',
);

/// Generates the concrete app mediator for libraries annotated with
/// `@ChassisApp` (on the library directive).
///
/// The generated class extends `Mediator`, takes every handler dependency as
/// a required named constructor parameter (deduplicated by type), and
/// registers all handlers in its constructor. Dispatch happens through the
/// inherited `run`/`read`/`watch` — no per-message methods are generated.
///
/// `@chassisModule` classes generate nothing: they only mark a package's
/// handler barrel so `@ChassisApp(modules: [...])` can discover handlers in
/// other packages (handler discovery is scoped to each root library's own
/// package). The generator still validates module libraries so wiring
/// mistakes fail the module's own build.
///
/// Any wiring mistake (missing constructor, unknown module, a reachable
/// message without a handler, ...) fails the build with an actionable error.
/// This generator never emits a partial mediator.
class ChassisGenerator extends Generator {
  const ChassisGenerator();

  @override
  FutureOr<String?> generate(LibraryReader library, BuildStep buildStep) {
    final specs = <Spec>[];

    for (final classElement in library.classes) {
      if (_moduleChecker.hasAnnotationOfExact(classElement)) {
        _validateModule(classElement);
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
      specs.add(
        _generateAppMediator(library.element, ConstantReader(appAnnotation)),
      );
    }

    if (specs.isEmpty) return null;

    final lib = Library((l) => l..body.addAll(specs));
    final emitted = lib.accept(DartEmitter.scoped(useNullSafetySyntax: true));
    return '$emitted';
  }

  // --- Module validation ---

  /// Validates a `@chassisModule` declaration without generating anything.
  ///
  /// Modules exist for cross-package handler discovery only: the app-side
  /// generator walks the module's import graph (scoped to the module's
  /// package) to find its handlers. Validating here gives the module's own
  /// build early feedback on wiring mistakes.
  void _validateModule(ClassElement moduleClass) {
    final scan = _scanLibrary(moduleClass.library);
    if (scan.handlers.isEmpty) {
      throw InvalidGenerationSourceError(
        'No @chassisHandler class is reachable from the library declaring '
        '${moduleClass.name}. A chassis module must be declared in a library '
        'that (transitively) imports every handler of the package — '
        'typically the package barrel.',
        element: moduleClass,
      );
    }
    _toOperations(moduleClass, scan.handlers);
  }

  // --- App mediator generation ---

  Class _generateAppMediator(
    LibraryElement appLibrary,
    ConstantReader annotation,
  ) {
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

    // Collect handlers and messages: per module (within the module's
    // package), then the app's own (within the app's package).
    final operations = <_Operation>[];
    final seenMessageTypes = <String, _Operation>{};
    final scans = <_LibraryScan>[];

    void addOperations(Element owner, List<ClassElement> handlers) {
      for (final op in _toOperations(owner, handlers)) {
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
        operations.add(op);
      }
    }

    for (final module in moduleClasses) {
      final scan = _scanLibrary(module.library);
      if (scan.handlers.isEmpty) {
        throw InvalidGenerationSourceError(
          'No @chassisHandler class is reachable from the library declaring '
          '${module.name} (the module listed in @ChassisApp on '
          '${appLibrary.uri}). A chassis module must be declared in a '
          'library that (transitively) imports every handler of the package '
          '— typically the package barrel.',
          element: appLibrary,
        );
      }
      scans.add(scan);
      addOperations(module, scan.handlers);
    }
    final appScan = _scanLibrary(appLibrary);
    scans.add(appScan);
    addOperations(appLibrary, appScan.handlers);

    if (operations.isEmpty) {
      throw InvalidGenerationSourceError(
        '@ChassisApp on library ${appLibrary.uri} found no @chassisHandler '
        'class: none reachable from this library within package '
        '`${_packageOf(appLibrary)}`, and no modules were declared. Import '
        'your handlers (directly or via a barrel) or declare modules.',
        element: appLibrary,
      );
    }

    // Handlers found outside the app package and its declared modules are
    // unreachable for registration: warn, don't silently ignore them.
    _warnOnUncoveredHandlers(appLibrary, moduleClasses, scans, mediatorName);

    // A reachable concrete message without a handler could only throw
    // HandlerNotRegisteredError at runtime — fail the build instead.
    _rejectUnhandledMessages(appLibrary, scans, seenMessageTypes);

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
        ..docs.add(
          '/// Concrete mediator generated from the `@ChassisApp` library\n'
          '/// `${appLibrary.uri}`.\n'
          '///\n'
          '/// Registers every reachable handler in its constructor. '
          'Dispatch messages\n'
          '/// through the inherited `run`/`read`/`watch`; middlewares '
          'always apply.',
        )
        ..constructors.add(
          Constructor(
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
          ),
        ),
    );
  }

  Code _registration(_Operation op) {
    final handlerRef = refer(
      op.handler.name!,
      op.handler.library.uri.toString(),
    );
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

  /// Warns about `@chassisHandler` classes reachable from the walked graphs
  /// but living in a package that is neither the app's nor a declared
  /// module's: those handlers are never registered.
  void _warnOnUncoveredHandlers(
    LibraryElement appLibrary,
    List<ClassElement> moduleClasses,
    List<_LibraryScan> scans,
    String mediatorName,
  ) {
    final coveredPackages = {
      _packageOf(appLibrary),
      for (final module in moduleClasses) _packageOf(module.library),
    };
    final warned = <String>{};
    for (final scan in scans) {
      for (final handler in scan.foreignHandlers) {
        final package = handler.library.uri.pathSegments.first;
        if (coveredPackages.contains(package)) continue;
        if (!warned.add(_elementKey(handler))) continue;
        log.warning(
          '${handler.name} (${handler.library.uri}) is annotated with '
          '@chassisHandler but belongs to package `$package`, which is '
          'neither the app package nor a declared module — it will NOT be '
          'registered on $mediatorName. If the package declares a '
          '@chassisModule class, add it to @ChassisApp(modules: [...]).',
        );
      }
    }
  }

  /// Fails the build when a reachable concrete message has no handler.
  ///
  /// Messages annotated with `@unhandledMessage` are skipped.
  void _rejectUnhandledMessages(
    LibraryElement appLibrary,
    List<_LibraryScan> scans,
    Map<String, _Operation> handledMessages,
  ) {
    final orphans = <ClassElement>[];
    final seen = <String>{};
    for (final scan in scans) {
      for (final message in scan.messages) {
        final key = _elementKey(message);
        if (handledMessages.containsKey(key)) continue;
        if (!seen.add(key)) continue;
        if (_unhandledMessageChecker.hasAnnotationOfExact(
          message,
          throwOnUnresolved: false,
        )) {
          continue;
        }
        orphans.add(message);
      }
    }
    if (orphans.isEmpty) return;

    final listing = orphans
        .map((m) => '  - ${m.name} (${m.library.uri})')
        .join('\n');
    final label = orphans.length == 1
        ? 'this message, which is'
        : 'these messages, which are';
    throw InvalidGenerationSourceError(
      'No handler is registered for $label reachable from the @ChassisApp '
      'library ${appLibrary.uri}:\n'
      '$listing\n'
      'Dispatching an unhandled message throws HandlerNotRegisteredError at '
      'runtime, so chassis fails the build instead. Fix: annotate a handler '
      'with @chassisHandler and rerun build_runner. If the message lives in '
      "another package, declare that package's @chassisModule class in "
      '@ChassisApp(modules: [...]). To opt out while the handler is being '
      'written, annotate the message with @unhandledMessage.',
      element: appLibrary,
    );
  }

  // --- Discovery (import-graph walk, spike-validated) ---

  /// Walks the import graph from [rootLibrary] and collects:
  ///
  /// - `handlers`: `@chassisHandler` classes in [rootLibrary]'s own package;
  /// - `messages`: concrete `Command`/`ReadQuery`/`WatchQuery` subclasses,
  ///   both in-package and in the export closure of directly imported
  ///   foreign libraries (anything the package's own code can name);
  /// - `foreignHandlers`: `@chassisHandler` classes found outside the
  ///   package (candidates for the missing-module warning).
  ///
  /// In-package libraries are traversed through imports and exports. A
  /// foreign library is scanned and traversed through its exports only (its
  /// public API); its imports are never followed. `dart:` libraries are
  /// skipped. Deterministic order (library URI, then class name).
  _LibraryScan _scanLibrary(LibraryElement rootLibrary) {
    final package = _packageOf(rootLibrary);

    final visited = <Uri>{};
    final queue = <LibraryElement>[rootLibrary];
    final handlers = <ClassElement>[];
    final messages = <ClassElement>[];
    final foreignHandlers = <ClassElement>[];

    bool inPackage(Uri uri) =>
        (uri.scheme == 'package' || uri.scheme == 'asset') &&
        uri.pathSegments.first == package;

    while (queue.isNotEmpty) {
      final lib = queue.removeLast();
      if (!visited.add(lib.uri)) continue;
      if (lib.uri.scheme == 'dart') continue;

      final isOwn = inPackage(lib.uri);

      for (final cls in lib.classes) {
        if (_handlerChecker.hasAnnotationOfExact(
          cls,
          throwOnUnresolved: isOwn,
        )) {
          (isOwn ? handlers : foreignHandlers).add(cls);
        }
        if (!cls.isAbstract && _isMessageClass(cls)) {
          messages.add(cls);
        }
      }

      for (final fragment in lib.fragments) {
        if (isOwn) {
          for (final imported in fragment.importedLibraries) {
            queue.add(imported);
          }
        }
        for (final export in fragment.libraryExports) {
          final exported = export.exportedLibrary;
          if (exported != null) queue.add(exported);
        }
      }
    }

    int byUriThenName(ClassElement a, ClassElement b) {
      final byUri = a.library.uri.toString().compareTo(
        b.library.uri.toString(),
      );
      return byUri != 0 ? byUri : a.name!.compareTo(b.name!);
    }

    handlers.sort(byUriThenName);
    messages.sort(byUriThenName);
    foreignHandlers.sort(byUriThenName);
    return _LibraryScan(
      handlers: handlers,
      messages: messages,
      foreignHandlers: foreignHandlers,
    );
  }

  /// Whether [cls] is a chassis message class (`Command`, `ReadQuery`, or
  /// `WatchQuery` subclass).
  bool _isMessageClass(ClassElement cls) {
    for (final supertype in cls.allSupertypes) {
      final name = supertype.element.name;
      if (name != 'Command' && name != 'ReadQuery' && name != 'WatchQuery') {
        continue;
      }
      final uri = supertype.element.library.uri;
      if (uri.scheme == 'package' && uri.pathSegments.first == 'chassis') {
        return true;
      }
    }
    return false;
  }

  // --- Handler analysis ---

  List<_Operation> _toOperations(Element owner, List<ClassElement> handlers) {
    final operations = <_Operation>[];
    final byMessage = <String, _Operation>{};

    for (final handler in handlers) {
      final op = _analyzeHandler(handler);

      final key = _elementKey(op.messageType.element);
      final clash = byMessage[key];
      if (clash != null) {
        throw InvalidGenerationSourceError(
          'Both ${clash.handlerDescription} and ${op.handlerDescription} '
          'handle ${op.messageType.element.name}. Each command/query type '
          'must have exactly one handler.',
          element: owner,
        );
      }
      byMessage[key] = op;
      operations.add(op);
    }
    return operations;
  }

  _Operation _analyzeHandler(ClassElement handler) {
    if (handler.isPrivate) {
      throw InvalidGenerationSourceError(
        '${handler.name} is annotated with @chassisHandler but is private. '
        'The generated mediator instantiates handlers from another file, so '
        'handler classes must be public.',
        element: handler,
      );
    }
    // Identify which handler interfaces are implemented. One handler = one
    // operation: implementing two interfaces is refused, not silently
    // truncated. (ReadHandler + WatchHandler is already impossible: both
    // implement the sealed QueryHandler with incompatible type arguments.)
    final handlerInterfaces = <String, InterfaceType>{};
    for (final supertype in handler.allSupertypes) {
      final name = supertype.element.name;
      final uri = supertype.element.library.uri;
      final isChassis =
          uri.scheme == 'package' && uri.pathSegments.first == 'chassis';
      if (isChassis &&
          (name == 'CommandHandler' ||
              name == 'ReadHandler' ||
              name == 'WatchHandler')) {
        handlerInterfaces[name!] = supertype;
      }
    }
    if (handlerInterfaces.isEmpty) {
      throw InvalidGenerationSourceError(
        '${handler.name} is annotated with @chassisHandler but implements '
        'none of CommandHandler, ReadHandler, or WatchHandler.',
        element: handler,
      );
    }
    if (handlerInterfaces.length > 1) {
      throw InvalidGenerationSourceError(
        '${handler.name} implements both '
        '${handlerInterfaces.keys.join(' and ')}. One handler class handles '
        'exactly one operation — split it into two handler classes.',
        element: handler,
      );
    }
    final handlerInterface = handlerInterfaces.values.single;

    final typeArguments = handlerInterface.typeArguments;
    final messageType = typeArguments[0];
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
      final what = "${handler.name}'s constructor parameter `${param.name}`";
      _rejectUnsupportedType(param.type, handler, what);
      _rejectPrivateType(param.type, handler, what);
      _rejectMediatorDependency(param, handler);
    }
    final dependencies = [
      for (final param in handlerConstructor.formalParameters)
        _Dependency(param.type, name: param.name!, isNamed: param.isNamed),
    ];

    final messageElement = messageType.element;
    if (messageElement is! ClassElement) {
      throw InvalidGenerationSourceError(
        '${handler.name}: message type ${messageElement.name} is not a '
        'class.',
        element: handler,
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

    return _Operation(
      handler: handler,
      kind: kind,
      messageType: messageType,
      dependencies: dependencies,
    );
  }

  /// Rejects handler dependencies that would let the handler dispatch — the
  /// `Mediator` itself, a subclass, or anything from a generated
  /// `.chassis.dart` library.
  ///
  /// Handlers must not dispatch commands or queries: handler-to-handler
  /// dispatch hides the dependency graph from constructor signatures and
  /// re-enters the middleware chain, and the mediator does not exist yet
  /// when the generated constructor instantiates its handlers.
  void _rejectMediatorDependency(
    FormalParameterElement param,
    ClassElement handler,
  ) {
    final type = param.type;
    if (type is! InterfaceType) return;
    final uri = type.element.library.uri;
    if (!_mediatorChecker.isAssignableFromType(type) &&
        !uri.path.endsWith('.chassis.dart')) {
      return;
    }
    throw InvalidGenerationSourceError(
      "${handler.name}'s constructor parameter `${param.name}` is typed "
      '`${type.element.name}`, which would let the handler dispatch through '
      'the mediator. Handlers must not dispatch commands or queries: model '
      'the whole flow as one command whose handler composes the '
      'repositories it needs, and share logic between handlers through an '
      'injected service.',
      element: handler,
    );
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

  /// Rejects private types (including nested in type arguments): the
  /// generated mediator declares dependencies as constructor parameters in
  /// another library, where a private type cannot be referenced.
  void _rejectPrivateType(DartType type, Element element, String what) {
    final name = type.element?.name;
    if (name != null && name.startsWith('_')) {
      throw InvalidGenerationSourceError(
        '$what has the private type `$name` '
        '(${type.element?.library?.uri}). The generated mediator declares '
        'this dependency as a constructor parameter in another library, '
        'where a private type cannot be referenced. Make the type public or '
        'wrap it in a public class.',
        element: element,
      );
    }
    if (type is InterfaceType) {
      for (final argument in type.typeArguments) {
        _rejectPrivateType(argument, element, what);
      }
    }
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
      return TypeReference(
        (t) => t
          ..symbol = type.element.name
          ..url = uri
          ..isNullable = type.nullabilitySuffix == NullabilitySuffix.question
          ..types.addAll(type.typeArguments.map(_referType)),
      );
    }

    if (type is VoidType) return refer('void');
    if (type is DynamicType) return refer('dynamic');

    final name = type.getDisplayString();
    return TypeReference(
      (t) => t
        ..symbol = type.nullabilitySuffix == NullabilitySuffix.question
            ? name.substring(0, name.length - 1)
            : name
        ..url = uri
        ..isNullable = type.nullabilitySuffix == NullabilitySuffix.question,
    );
  }
}

enum _OperationKind { command, read, watch }

/// Everything the import-graph walk found from one root library.
class _LibraryScan {
  _LibraryScan({
    required this.handlers,
    required this.messages,
    required this.foreignHandlers,
  });

  /// `@chassisHandler` classes of the root library's own package.
  final List<ClassElement> handlers;

  /// Concrete message classes (in-package, plus the public API of directly
  /// imported foreign libraries).
  final List<ClassElement> messages;

  /// `@chassisHandler` classes found outside the root library's package.
  final List<ClassElement> foreignHandlers;
}

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

/// One handler registration derived from a `@chassisHandler` class.
class _Operation {
  _Operation({
    required this.handler,
    required this.kind,
    required this.messageType,
    required this.dependencies,
  });

  final ClassElement handler;
  final _OperationKind kind;
  final InterfaceType messageType;
  final List<_Dependency> dependencies;

  String get handlerDescription => '${handler.name} (${handler.library.uri})';
}
