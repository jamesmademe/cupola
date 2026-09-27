import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';

import '../../tool/design_tokens/generate.dart';

/// A small valid source: one shared set and two themes.
TokenSource _source({
  Map<String, Object?>? core,
  Map<String, Object?>? dark,
  Map<String, Object?>? light,
}) {
  return TokenSource(
    sets: {
      'core':
          core ??
          {
            'color': {
              'ink': {r'$type': 'color', r'$value': '#111827'},
              'paper': {r'$type': 'color', r'$value': '#f3f4f6'},
            },
            'space': {
              'lg': {r'$type': 'dimension', r'$value': '16px'},
              'gutter': {r'$type': 'dimension', r'$value': '{space.lg}'},
            },
          },
      'theme/dark':
          dark ??
          {
            'color': {
              'surface': {r'$type': 'color', r'$value': '{color.ink}'},
              'on-surface': {r'$type': 'color', r'$value': '#f0f2f8'},
            },
          },
      'theme/light':
          light ??
          {
            'color': {
              'surface': {r'$type': 'color', r'$value': '{color.paper}'},
              'on-surface': {r'$type': 'color', r'$value': '{color.ink}'},
            },
          },
    },
    setOrder: const ['core', 'theme/dark', 'theme/light'],
    themes: const [
      ThemeConfig(
        id: 'dark',
        name: 'Dark',
        selectedTokenSets: {'core': 'source', 'theme/dark': 'enabled'},
      ),
      ThemeConfig(
        id: 'light',
        name: 'Light',
        selectedTokenSets: {'core': 'source', 'theme/light': 'enabled'},
      ),
    ],
  );
}

/// The problems [source] is rejected with.
List<String> _problems(TokenSource source) {
  try {
    generate(source);
  } on TokenValidationError catch (error) {
    return error.problems;
  }
  fail('Expected the source to be rejected.');
}

void main() {
  group('design token generator', () {
    test('renders shared and per-theme constants, keeping aliases', () {
      final dart = generate(_source()).dart;

      expect(dart, contains('abstract final class DesignTokens {'));
      expect(dart, contains('abstract final class DesignTokensDark {'));
      expect(dart, contains('abstract final class DesignTokensLight {'));
      expect(
        dart,
        contains('static const Color colorInk = Color(0xFF111827);'),
      );
      expect(dart, contains('static const double spaceGutter = spaceLg;'));
      expect(
        dart,
        contains('static const Color colorSurface = DesignTokens.colorInk;'),
      );
    });

    test('rejects an alias that does not resolve', () {
      final problems = _problems(
        _source(
          dark: {
            'color': {
              'surface': {r'$type': 'color', r'$value': '{color.missing}'},
              'on-surface': {r'$type': 'color', r'$value': '#f0f2f8'},
            },
          },
        ),
      );

      expect(problems, [
        '"color.surface" in "theme/dark" aliases "{color.missing}", '
            'which does not resolve.',
      ]);
    });

    test('rejects a shared token that aliases a theme role', () {
      final problems = _problems(
        _source(
          core: {
            'color': {
              'ink': {r'$type': 'color', r'$value': '{color.surface}'},
              'paper': {r'$type': 'color', r'$value': '#f3f4f6'},
            },
          },
        ),
      );

      expect(problems, contains(contains('"{color.surface}"')));
    });

    test('rejects a theme that is missing a semantic role', () {
      final problems = _problems(
        _source(
          light: {
            'color': {
              'surface': {r'$type': 'color', r'$value': '{color.paper}'},
            },
          },
        ),
      );

      expect(problems, [
        'Theme "Light" does not define "color.on-surface" (defined by Dark).',
      ]);
    });

    test('rejects an unknown type and a value its type cannot hold', () {
      final problems = _problems(
        _source(
          core: {
            'color': {
              'ink': {r'$type': 'colour', r'$value': '#111827'},
              'paper': {r'$type': 'color', r'$value': 'paper-white'},
            },
          },
          dark: {
            'color': {
              'surface': {r'$type': 'color', r'$value': '#000000'},
              'on-surface': {r'$type': 'color', r'$value': '#f0f2f8'},
            },
          },
          light: {
            'color': {
              'surface': {r'$type': 'color', r'$value': '#ffffff'},
              'on-surface': {r'$type': 'color', r'$value': '#111827'},
            },
          },
        ),
      );

      expect(problems, [
        '"color.ink" in "core" has an unknown \$type "colour".',
        '"color.paper" in "core" has a value "paper-white" that is not a '
            'valid color.',
      ]);
    });

    test('rejects an alias whose type differs from the target', () {
      final problems = _problems(
        _source(
          core: {
            'color': {
              'ink': {r'$type': 'color', r'$value': '#111827'},
              'paper': {r'$type': 'dimension', r'$value': '{color.ink}'},
            },
          },
        ),
      );

      expect(problems, contains(contains('is a dimension but aliases')));
    });

    test('rejects an alias cycle', () {
      final problems = _problems(
        _source(
          core: {
            'color': {
              'ink': {r'$type': 'color', r'$value': '{color.paper}'},
              'paper': {r'$type': 'color', r'$value': '{color.ink}'},
            },
          },
        ),
      );

      expect(problems, contains(contains('alias cycle')));
    });

    test('rejects a theme set that redefines a shared token', () {
      final problems = _problems(
        _source(
          dark: {
            'color': {
              'ink': {r'$type': 'color', r'$value': '#000000'},
              'surface': {r'$type': 'color', r'$value': '#000000'},
              'on-surface': {r'$type': 'color', r'$value': '#f0f2f8'},
            },
          },
        ),
      );

      expect(problems, [
        '"color.ink" in "theme/dark" redefines a token of "core".',
      ]);
    });

    test('rejects two tokens that become the same constant', () {
      final problems = _problems(
        _source(
          core: {
            'color': {
              'ink': {r'$type': 'color', r'$value': '#111827'},
              'paper': {r'$type': 'color', r'$value': '#f3f4f6'},
            },
            'space': {
              'grid-gap': {r'$type': 'dimension', r'$value': '12px'},
              'gridGap': {r'$type': 'dimension', r'$value': '12px'},
            },
          },
        ),
      );

      expect(problems, [
        '"space.gridGap" and "space.grid-gap" both become '
            'DesignTokens.spaceGridGap.',
      ]);
    });
  });

  group('committed design tokens', () {
    final outputs = generate(loadTokenSource(Directory(tokensDirPath)));

    test('the generated Dart constants match the token sets', () {
      expect(
        File(dartOutputPath).readAsStringSync(),
        outputs.dart,
        reason:
            'design/tokens/ and $dartOutputPath disagree. Edit the token sets, '
            'never the generated file, then run '
            '`dart run tool/design_tokens/generate.dart`.',
      );
    });

    test('the design-system listing matches the token sets', () {
      expect(
        File(systemOutputPath).readAsStringSync(),
        outputs.systemJson,
        reason:
            'design/tokens/ and $systemOutputPath disagree. Run '
            '`dart run tool/design_tokens/generate.dart`.',
      );
    });

    test('the listing tracks type with the light theme curve the app uses', () {
      final listing = jsonDecode(outputs.systemJson) as Map<String, Object?>;
      final groups =
          (listing['type'] as Map<String, Object?>)['groups'] as List<Object?>;
      const authored = {'subtitle', 'eyebrow'};
      var checked = 0;
      for (final group in groups.cast<Map<String, Object?>>()) {
        for (final style
            in (group['styles'] as List<Object?>)
                .cast<Map<String, Object?>>()) {
          if (authored.contains(style['name'])) continue;
          final size = double.parse(
            (style['fontSize'] as String).replaceAll('px', ''),
          );
          final tracking = double.parse(
            (style['letterSpacing'] as String).replaceAll('px', ''),
          );
          expect(
            tracking,
            closeTo(AppTheme.interTracking(size, Brightness.light), 0.005),
            reason: '${style['name']} at ${size}px',
          );
          checked++;
        }
      }
      expect(checked, greaterThan(15));
    });
  });
}
