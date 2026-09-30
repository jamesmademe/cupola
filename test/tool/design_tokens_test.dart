import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

  group('typography, curves and weights', () {
    Map<String, Object?> coreWith(Map<String, Object?> extra) => {
      'color': {
        'ink': {r'$type': 'color', r'$value': '#111827'},
        'paper': {r'$type': 'color', r'$value': '#f3f4f6'},
      },
      ...extra,
    };

    test('a typography role becomes one constant per property', () {
      final dart = generate(
        _source(
          core: coreWith({
            'type': {
              'family': {
                'display': {r'$type': 'fontFamily', r'$value': 'Display'},
              },
              'role': {
                'screen': {
                  r'$type': 'typography',
                  r'$value': {
                    'fontFamily': '{type.family.display}',
                    'fontSize': '36px',
                    'lineHeight': '36px',
                    'fontWeight': 600,
                    'fontWidth': '92%',
                    'letterSpacing': '-0.02em',
                  },
                },
                'mono': {
                  r'$type': 'typography',
                  r'$value': {
                    'fontFamily': ['Mono', 'monospace'],
                    'fontSize': '13px',
                    'lineHeight': '18px',
                    'fontWeight': 450,
                    'letterSpacing': '-0.01em',
                  },
                },
              },
              'headline': {
                'large': {
                  r'$type': 'typography',
                  r'$value': '{type.role.screen}',
                },
              },
            },
          }),
        ),
      ).dart;

      expect(
        dart,
        contains(
          'static const String typeRoleScreenFontFamily = typeFamilyDisplay;',
        ),
      );
      expect(
        dart,
        contains('static const double typeRoleScreenFontSize = 36;'),
      );
      expect(
        dart,
        contains('static const double typeRoleScreenLineHeight = 1;'),
      );
      expect(
        dart,
        contains('static const double typeRoleScreenFontWidth = 92;'),
      );
      // Tracking in em becomes pixels at the role's size.
      expect(
        dart,
        contains('static const double typeRoleScreenLetterSpacing = -0.72;'),
      );
      // A weight off the nine named ones keeps its exact axis value, and asks
      // the face matcher for the named weight at or below it.
      expect(
        dart,
        contains(
          'static const FontWeight typeRoleMonoFontWeight = FontWeight.w400;',
        ),
      );
      expect(dart, contains('static const double typeRoleMonoWght = 450;'));
      expect(
        dart,
        contains('static const double typeRoleMonoLineHeight = 1.3846;'),
      );
      expect(
        dart,
        contains("static const String typeRoleMonoFontFamily = 'Mono';"),
      );
      // An alias of a role is an alias of each of its properties.
      expect(
        dart,
        contains(
          'static const double typeHeadlineLargeFontSize = '
          'typeRoleScreenFontSize;',
        ),
      );
      expect(dart, contains('static const double typeHeadlineLargeWght ='));
    });

    test('a curve is written as a Cubic, from an array or from CSS', () {
      final dart = generate(
        _source(
          core: coreWith({
            'motion': {
              'standard': {
                r'$type': 'cubicBezier',
                r'$value': [0.2, 0.8, 0.2, 1],
              },
              'css': {
                r'$type': 'cubicBezier',
                r'$value': 'cubic-bezier(.05, .7, .1, 1)',
              },
              'ease': {r'$type': 'cubicBezier', r'$value': 'ease'},
              'alias': {r'$type': 'cubicBezier', r'$value': '{motion.ease}'},
            },
          }),
        ),
      ).dart;

      expect(
        dart,
        contains("import 'package:flutter/animation.dart' show Cubic;"),
      );
      expect(
        dart,
        contains(
          'static const Cubic motionStandard = Cubic(0.2, 0.8, 0.2, 1);',
        ),
      );
      expect(
        dart,
        contains('static const Cubic motionCss = Cubic(0.05, 0.7, 0.1, 1);'),
      );
      expect(
        dart,
        contains('static const Cubic motionEase = Cubic(0.25, 0.1, 0.25, 1);'),
      );
      expect(dart, contains('static const Cubic motionAlias = motionEase;'));
    });

    test('rejects a curve that is not a function of time', () {
      final problems = _problems(
        _source(
          core: coreWith({
            'motion': {
              'loop': {
                r'$type': 'cubicBezier',
                r'$value': [1.2, 0, 0.5, 1],
              },
            },
          }),
        ),
      );

      expect(problems, [
        '"motion.loop" in "core" has a value [1.2,0,0.5,1] that is not a '
            'valid cubicBezier.',
      ]);
    });

    test('rejects a typography role without a size or with a bad weight', () {
      final problems = _problems(
        _source(
          core: coreWith({
            'type': {
              'a': {
                r'$type': 'typography',
                r'$value': {
                  'fontFamily': 'X',
                  'lineHeight': '20px',
                  'fontWeight': 400,
                },
              },
              'b': {
                r'$type': 'typography',
                r'$value': {
                  'fontFamily': 'X',
                  'fontSize': '14px',
                  'lineHeight': '20px',
                  'fontWeight': 1200,
                },
              },
              'c': {
                r'$type': 'typography',
                r'$value': {
                  'fontFamily': '{color.ink}',
                  'fontSize': '14px',
                  'lineHeight': '20px',
                  'fontWeight': 400,
                },
              },
            },
          }),
        ),
      );

      expect(problems, [
        '"type.a" in "core" is a typography composite without [fontSize].',
        '"type.b" in "core" has a fontWeight 1200 that is not a weight from 1 '
            'to 1000.',
        '"type.c" in "core" needs a fontFamily for fontFamily but aliases '
            '"{color.ink}", a color.',
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

    test('the listing sets every type slot in the role it stands for', () {
      final listing = jsonDecode(outputs.systemJson) as Map<String, Object?>;
      final groups =
          ((listing['type'] as Map<String, Object?>)['groups'] as List<Object?>)
              .cast<Map<String, Object?>>();
      final roles = {
        for (final style
            in (groups.firstWhere((g) => g['name'] == 'Role')['styles']
                    as List<Object?>)
                .cast<Map<String, Object?>>())
          style['name']: style,
      };
      // The roles' tracking is authored in em and listed in pixels.
      expect(roles['screen']!['letterSpacing'], '-0.72px');
      expect(roles['micro']!['letterSpacing'], '0.11px');
      expect(roles['mono']!['fontWeight'], 450);
      expect(roles['section']!['fontWidth'], '96%');

      var checked = 0;
      for (final group in groups) {
        if (group['name'] == 'Role') continue;
        for (final style
            in (group['styles'] as List<Object?>)
                .cast<Map<String, Object?>>()) {
          final roleName = style['role'];
          if (roleName == null) continue; // an authored slot (the eyebrow)
          final role = roles[roleName];
          expect(role, isNotNull, reason: '${style['name']} → $roleName');
          for (final property in const [
            'family',
            'fontSize',
            'lineHeight',
            'fontWeight',
            'fontWidth',
            'letterSpacing',
          ]) {
            expect(
              style[property],
              role![property],
              reason: '${style['name']}.$property',
            );
          }
          checked++;
        }
      }
      expect(checked, greaterThan(15));
    });
  });
}
