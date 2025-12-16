import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:chassis/chassis.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:source_gen/source_gen.dart';

class RepositoryGenerator implements Generator {
  const RepositoryGenerator();

  @override
  FutureOr<String?> generate(LibraryReader library, BuildStep buildStep) {
    // We need to find all classes that have annotated methods
    final generatedClasses = <Spec>[];

    for (final classElement in library.classes) {
      for (final method in classElement.methods) {
        final generateQuery = _hasAnnotation(method, GenerateQueryHandler);
        final generateCommand = _hasAnnotation(method, GenerateCommandHandler);

        if (generateQuery) {
          generatedClasses.addAll(_generateArtifacts(
            classElement,
            method,
            isCommand: false,
          ));
        }

        if (generateCommand) {
          generatedClasses.addAll(_generateArtifacts(
            classElement,
            method,
            isCommand: true,
          ));
        }
      }
    }

    if (generatedClasses.isEmpty) return null;

    final lib = Library((l) => l
      ..directives.add(Directive.import('package:chassis/chassis.dart'))
      ..directives.add(Directive.import(buildStep.inputId.uri.toString()))
      ..body.addAll(generatedClasses));

    return DartFormatter().format('${lib.accept(DartEmitter.scoped())}');
  }

  bool _hasAnnotation(MethodElement method, Type type) {
    return TypeChecker.fromRuntime(type).hasAnnotationOf(method);
  }

  List<Spec> _generateArtifacts(
    ClassElement repositoryClass,
    MethodElement method, {
    required bool isCommand,
  }) {
    final specs = <Spec>[];
    String methodName = method.name;
    // Capitalize method name for class names
    String capitalizedMethodName =
        methodName.substring(0, 1).toUpperCase() + methodName.substring(1);

    String suffix = isCommand ? 'Command' : 'Query';
    String dtoName = '$capitalizedMethodName$suffix';
    String handlerName = '$capitalizedMethodName${suffix}Handler';

    final isStream = !isCommand && _isStream(method.returnType);
    final queryInterface = isStream ? 'WatchQuery' : 'ReadQuery';
    final handlerInterface = isCommand
        ? 'CommandHandler'
        : isStream
            ? 'WatchHandler'
            : 'ReadHandler';
    final handlerMethod = isCommand
        ? 'run'
        : isStream
            ? 'watch'
            : 'read';
    final returnTypeWrapper = isStream ? 'Stream' : 'Future';

    // 1. Generate DTO (Command or Query)
    final dtoClass = Class((c) => c
      ..name = dtoName
      ..implements.add(isCommand
          ? TypeReference((t) => t
            ..symbol = 'Command'
            ..types.add(_getReturnType(method.returnType)))
          : TypeReference((t) => t
            ..symbol = queryInterface
            ..types.add(_getReturnType(method.returnType))))
      ..constructors.add(Constructor((ctor) => ctor
        ..constant = true
        ..optionalParameters
            .addAll(method.parameters.map((p) => Parameter((param) => param
              ..name = p.name
              ..type = _referType(p.type)
              ..named = true
              ..required = p.isRequired
              ..toThis = true)))))
      ..fields.addAll(method.parameters.map((p) => Field((f) => f
        ..name = p.name
        ..type = _referType(p.type)
        ..modifier = FieldModifier.final$))));

    specs.add(dtoClass);

    // 2. Generate Handler
    final handlerClass = Class((c) => c
      ..name = handlerName
      ..annotations.add(refer('chassisHandler'))
      ..implements.add(TypeReference((t) => t
        ..symbol = handlerInterface
        ..types.addAll([refer(dtoName), _getReturnType(method.returnType)])))
      ..fields.add(Field((f) => f
        ..name = '_repository'
        ..type = refer(repositoryClass.name)
        ..modifier = FieldModifier.final$))
      ..constructors.add(Constructor((ctor) => ctor
        ..requiredParameters.add(Parameter((p) => p
          ..name = '_repository'
          ..toThis = true))))
      ..methods.add(Method((m) => m
        ..name = handlerMethod
        ..annotations.add(refer('override'))
        ..returns = TypeReference((t) => t
          ..symbol = returnTypeWrapper
          ..types.add(_getReturnType(method.returnType)))
        ..requiredParameters.add(Parameter((p) => p
          ..name = isCommand ? 'command' : 'query'
          ..type = refer(dtoName)))
        ..modifier = isStream ? null : MethodModifier.async
        ..body = Block((b) {
          final positionalArgs = method.parameters.where((p) => !p.isNamed).map(
              (p) => refer(isCommand ? 'command' : 'query').property(p.name));

          final namedArgs = Map.fromEntries(method.parameters
              .where((p) => p.isNamed)
              .map((p) => MapEntry(p.name,
                  refer(isCommand ? 'command' : 'query').property(p.name))));

          final invocation = refer('_repository')
              .property(method.name)
              .call(positionalArgs, namedArgs);

          if (isStream) {
            b.addExpression(invocation.returned);
          } else {
            final awaitedInvocation = invocation.awaited;
            if (_isVoid(method.returnType)) {
              b.addExpression(awaitedInvocation);
            } else {
              b.addExpression(awaitedInvocation.returned);
            }
          }
        }))));

    specs.add(handlerClass);
    return specs;
  }

  bool _isVoid(DartType type) {
    return type.isVoid ||
        (type.isDartAsyncFuture &&
            type is InterfaceType &&
            type.typeArguments.isNotEmpty &&
            type.typeArguments.first.isVoid);
  }

  bool _isStream(DartType type) {
    return type is InterfaceType &&
        (type.isDartAsyncStream ||
            (type.element.name == 'Stream' &&
                type.element.library.name == 'dart.async'));
  }

  Reference _getReturnType(DartType returnType) {
    if (returnType.isDartAsyncFuture ||
        returnType.isDartAsyncFutureOr ||
        _isStream(returnType)) {
      if (returnType is InterfaceType && returnType.typeArguments.isNotEmpty) {
        return _referType(returnType.typeArguments.first);
      }
    }
    return _referType(returnType);
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
}
