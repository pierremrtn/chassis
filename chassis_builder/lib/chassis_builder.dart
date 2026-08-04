import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/generator.dart';

export 'src/generator.dart' show ChassisGenerator;

/// Builder factory for the chassis mediator generator.
///
/// Generates `<file>.chassis.dart` next to any library annotated with
/// `@ChassisApp` or declaring a `@chassisModule` class.
Builder chassisBuilder(BuilderOptions options) => LibraryBuilder(
      const ChassisGenerator(),
      generatedExtension: '.chassis.dart',
      header: '$defaultFileHeader\n'
          '// ignore_for_file: implementation_imports\n',
    );
