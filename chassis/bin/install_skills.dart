// Installs the chassis LLM skills into a project by symlinking each skill
// directory of the resolved `chassis` package (in the local pub cache, or the
// path/git checkout the project depends on) into the agent's skills folder.
//
// Usage, from the root of a project that depends on chassis:
//
//   dart run chassis:install_skills            # links into .claude/skills/
//   dart run chassis:install_skills ai/skills  # custom target directory
//   dart run chassis:install_skills --copy     # copy instead of symlinking
//
// Symlinks point into the pub cache of the *pinned* chassis version, so the
// skills always match the API the project actually uses. Re-run the command
// after upgrading chassis to re-point the links. On file systems where
// symlinks are unavailable (e.g. Windows without Developer Mode), the script
// falls back to copying.
import 'dart:io';
import 'dart:isolate';

Future<void> main(List<String> args) async {
  final copyRequested = args.contains('--copy');
  final positional =
      args.where((argument) => !argument.startsWith('--')).toList();
  if (positional.length > 1) {
    stderr.writeln(
        'Usage: dart run chassis:install_skills [target-dir] [--copy]');
    exitCode = 64;
    return;
  }
  final targetRoot =
      Directory(positional.isNotEmpty ? positional.single : '.claude/skills');

  final libUri = await Isolate.resolvePackageUri(
      Uri.parse('package:chassis/chassis.dart'));
  if (libUri == null) {
    stderr.writeln(
        'Could not resolve package:chassis — run this from a project that '
        'depends on chassis, after `dart pub get`.');
    exitCode = 1;
    return;
  }
  // lib/chassis.dart -> lib -> package root -> skills/
  final packageRoot = File.fromUri(libUri).parent.parent;
  final skillsDir = Directory(_join(packageRoot.path, 'skills'));
  if (!skillsDir.existsSync()) {
    stderr.writeln(
        'The resolved chassis package (${packageRoot.path}) ships no skills/ '
        'directory. Skills are bundled with chassis 1.0.0 and later.');
    exitCode = 1;
    return;
  }

  targetRoot.createSync(recursive: true);
  var installed = 0, skipped = 0;
  final skills = skillsDir
      .listSync()
      .whereType<Directory>()
      .where((d) => File(_join(d.path, 'SKILL.md')).existsSync())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final skill in skills) {
    final name = skill.path.split(Platform.pathSeparator).last;
    final targetPath = _join(targetRoot.path, name);
    final existing = FileSystemEntity.typeSync(targetPath, followLinks: false);

    if (existing == FileSystemEntityType.link) {
      // A previous install: re-point it at the currently resolved version.
      Link(targetPath).deleteSync();
    } else if (existing != FileSystemEntityType.notFound) {
      stdout.writeln('  skipped   $name (already exists and is not a link — '
          'remove it to reinstall)');
      skipped++;
      continue;
    }

    if (copyRequested) {
      _copyDirectory(skill, Directory(targetPath));
      stdout.writeln('  copied    $name');
    } else {
      try {
        Link(targetPath).createSync(skill.absolute.path);
        stdout.writeln('  linked    $name');
      } on FileSystemException {
        _copyDirectory(skill, Directory(targetPath));
        stdout.writeln('  copied    $name (symlink unavailable)');
      }
    }
    installed++;
  }

  stdout.writeln('\n$installed skill(s) installed into ${targetRoot.path}'
      '${skipped > 0 ? ', $skipped skipped' : ''}.');
  if (!copyRequested) {
    stdout.writeln('Links target the resolved chassis package '
        '(${skillsDir.path}); re-run after upgrading chassis.');
  }
}

String _join(String a, String b) => '$a${Platform.pathSeparator}$b';

void _copyDirectory(Directory source, Directory destination) {
  destination.createSync(recursive: true);
  for (final entity in source.listSync(recursive: false)) {
    final name = entity.path.split(Platform.pathSeparator).last;
    final targetPath = _join(destination.path, name);
    if (entity is Directory) {
      _copyDirectory(entity, Directory(targetPath));
    } else if (entity is File) {
      entity.copySync(targetPath);
    }
  }
}
