import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'src/generator.dart';

import 'src/repository_generator.dart';

/// Builder for generating handlers from repositories
Builder repositoryBuilder(BuilderOptions options) =>
    LibraryBuilder(const RepositoryGenerator(),
        generatedExtension: '.handlers.dart');

/// Builder factory
Builder chassisBuilder(BuilderOptions options) => ChassisBuilder(options);
