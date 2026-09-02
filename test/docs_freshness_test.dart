// Guards against the documentation drifting from the code. These are the
// mistakes that actually happened: a README that still advertised a shipped
// release as a prerelease, a CHANGELOG that lagged `pubspec.yaml`, and public
// types with no entry in the API reference.
//
// The companion check is `readme_snippets_test.dart`, which compile-checks the
// code samples themselves.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Public types that are exported but deliberately not part of the documented
/// surface: implementation detail a user never names.
const _undocumentedOnPurpose = {
  'QueryEntry', // internal cache record, exposed only because it's in the lib
};

void main() {
  group('docs stay current', () {
    test('README carries no version literals', () {
      // Versions rot. `pubspec.yaml` is the source of truth, `CHANGELOG.md` is
      // the history, and the pub.dev badge renders the current version — the
      // README should never restate any of them. (This exact rot shipped once:
      // the README described a released version as a prerelease.)
      final readme = File('README.md').readAsStringSync();
      final offenders = <String>[];
      final pattern = RegExp(r'\d+\.\d+\.(?:\d+|x)(?:-dev\.\d+)?');
      for (final line in readme.split('\n')) {
        // The badge URL carries no version, but skip image/link lines anyway so
        // a future shields.io path can't trip this.
        if (line.contains('img.shields.io')) continue;
        if (pattern.hasMatch(line)) offenders.add(line.trim());
      }
      expect(
        offenders,
        isEmpty,
        reason: 'README.md must not hardcode versions — link to CHANGELOG.md '
            'instead. Offending lines:\n${offenders.join('\n')}',
      );
    });

    test('CHANGELOG top entry matches pubspec version', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version =
          RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)?.group(1);
      expect(version, isNotNull, reason: 'pubspec.yaml has no version');

      final changelog = File('CHANGELOG.md').readAsStringSync();
      final newest =
          RegExp(r'^##\s+(\S+)', multiLine: true).firstMatch(changelog)?.group(1);
      expect(newest, isNotNull, reason: 'CHANGELOG.md has no `## <version>`');

      expect(
        newest,
        version,
        reason: 'CHANGELOG.md must open with the version in pubspec.yaml — '
            'bump both together.',
      );
    });

    test('every public type has an entry in doc/API.md', () {
      final api = File('doc/API.md').readAsStringSync();
      final declaration =
          RegExp(r'^(?:abstract\s+)?(?:class|enum)\s+([A-Z]\w*)', multiLine: true);

      final undocumented = <String>[];
      for (final file in Directory('lib/src').listSync().whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        for (final match in declaration.allMatches(file.readAsStringSync())) {
          final name = match.group(1)!;
          if (_undocumentedOnPurpose.contains(name)) continue;
          if (!api.contains(name)) undocumented.add(name);
        }
      }

      expect(
        undocumented,
        isEmpty,
        reason: 'These public types have no mention in doc/API.md: '
            '$undocumented. Document them, or add them to '
            '`_undocumentedOnPurpose` with a reason.',
      );
    });
  });
}
