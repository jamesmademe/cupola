import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The lint gate has to be switched on: **`analysis_options.yaml` exists at the
/// root and includes `package:flutter_lints/flutter.yaml`.**
///
/// `flutter_lints` in `dev_dependencies` applies nothing by itself; a lint
/// package takes effect only through an `include:` from the root options file.
/// The repo once had the dependency and no such file, so `flutter analyze
/// --fatal-infos` (locally and in CI) kept passing while it checked language
/// diagnostics and not one lint rule, and enabling it surfaced 181 issues.
/// Deleting or emptying the file brings that back without a single red check,
/// because a gate that stops checking looks exactly like a gate that passes.
///
/// This reads the file, not the analyzer's output: the only visible symptom of
/// the regression is the absence of a failure. A commented-out or nested
/// `include:` does not count, so the check is on the active top-level key.
void main() {
  test(
    'analysis_options.yaml exists at the root and includes flutter_lints',
    () {
      final file = File('analysis_options.yaml');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'The lint gate needs analysis_options.yaml at the repo root.',
      );
      expect(
        _includesFlutterLints(file.readAsStringSync()),
        isTrue,
        reason:
            'analysis_options.yaml must carry an active top-level '
            '`include: package:flutter_lints/flutter.yaml`. Without it '
            'flutter_lints sits in dev_dependencies applying nothing.',
      );
    },
  );

  test('flutter_lints is a dev dependency, so the include resolves', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final declared = pubspec.any(
      (line) => RegExp(r'^  flutter_lints\s*:').hasMatch(line),
    );
    expect(declared, isTrue);
  });

  group('the reader', () {
    test('accepts the active include, quoted or not, with a trailing note', () {
      for (final yaml in [
        'include: package:flutter_lints/flutter.yaml\n',
        "include: 'package:flutter_lints/flutter.yaml'\n",
        'include: "package:flutter_lints/flutter.yaml"  # the stock set\n',
        '# a header\n\ninclude: package:flutter_lints/flutter.yaml\n'
            'linter:\n  rules:\n    avoid_print: false\n',
      ]) {
        expect(_includesFlutterLints(yaml), isTrue, reason: yaml);
      }
    });

    test(
      'refuses a comment, a nested key, another package and an empty file',
      () {
        for (final yaml in [
          '',
          '# include: package:flutter_lints/flutter.yaml\n',
          'analyzer:\n  include: package:flutter_lints/flutter.yaml\n',
          '  include: package:flutter_lints/flutter.yaml\n',
          'include: package:lints/recommended.yaml\n',
          '# a lint package takes effect through an `include:` from this file\n',
          'linter:\n  rules:\n    avoid_print: true\n',
        ]) {
          expect(_includesFlutterLints(yaml), isFalse, reason: yaml);
        }
      },
    );
  });
}

/// Whether [yaml] has an active top-level `include:` of the stock Flutter set.
bool _includesFlutterLints(String yaml) => yaml
    .split('\n')
    .any(
      (line) => RegExp(
        r'''^include:\s*['"]?package:flutter_lints/flutter\.yaml['"]?\s*(#.*)?$''',
      ).hasMatch(line.trimRight()),
    );
