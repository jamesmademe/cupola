import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/code_scan.dart';

/// The tone rule's second half: **no tone is painted from its raw constant.**
///
/// `AppColors.success`, `warning`, `error` and `info` (and the two containers)
/// are the dark room's tone bytes. They are right on the dark ground and wrong
/// on paper, where the day room has its own set and every tone is walked for
/// contrast against the surface it lands on. `statusToneColor` and
/// `statusToneFill` pick the room and do the walk; `ServiceTheme.onTint` and
/// `foregroundOn` do it for an ink on a tint. A raw constant skips all of that,
/// and looks fine until the light theme: the Close hover was a salmon fill under
/// a white glyph, a chip's wash the dark room's pale blue.
///
/// A source scan because the regression is one plausible line in a diff:
/// `color: AppColors.info` reads as a decision, and nothing about it says which
/// room it was made in. It reads `lib/` through `code_scan.dart`, so a doc
/// comment that names the constant to forbid it (a dozen do) is not a use.
///
/// Nothing is exempt by file. The files that define the constants (`theme.dart`)
/// and resolve the tones (`status_badge.dart`) do not need the qualified name
/// to do it, so they are scanned like the rest. What may stay is in [_allowed],
/// keyed by file and by the line as it is written, each with the reason.
void main() {
  final files = libCode();

  test('lib/ has code to scan, and the constants the rule names exist', () {
    expect(files.length, greaterThan(300));
    final theme = File('lib/core/theme.dart').readAsStringSync();
    for (final name in _constants) {
      expect(
        theme,
        contains(RegExp('static const Color $name\\b')),
        reason:
            'AppColors.$name is gone or renamed; update the guard so it does '
            'not hold a name nobody writes.',
      );
    }
  });

  test('no tone is painted from its raw AppColors constant', () {
    final offenders = [
      for (final hit in _hits(files))
        if (!_isAllowed(hit)) '${hit.where}  ${hit.line}',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'A raw tone constant is the dark room\'s byte. Resolve it for the '
          'room and the ground it lands on: statusToneColor(colorScheme, tone, '
          'surface:) for an ink, statusToneFill(colorScheme, tone) for a fill, '
          'ServiceTheme.onTint / foregroundOn for an ink on a tint. A use that '
          'is not a status goes in _allowed with its reason.',
    );
  });

  test('every allow-list entry still matches exactly one line', () {
    // An entry whose site was fixed or moved is an exception nobody needs, and
    // it would quietly excuse the next occurrence of the same line in that file.
    final hits = _hits(files);
    final off = <String>[
      for (final entry in _allowed)
        if (hits
                .where((h) => h.path == entry.file && h.line == entry.line)
                .length !=
            1)
          '${entry.file}  ${entry.line}',
    ];
    expect(off, isEmpty);
  });

  group('the matcher', () {
    test('catches a raw tone however it is spelled, and passes the rest', () {
      const planted = '''
final a = AppColors.error.withValues(alpha: 0.24);
const b = [AppColors.info, AppColors.warning];
final c = '\${AppColors.success}';
final d = AppColors.successContainer;
// final e = AppColors.error;
/// `AppColors.warning` in a doc comment.
final f = 'AppColors.info';
final g = AppColors.errorContainerHigh;
final h = AppColors.lamp;
final i = AppColors.warningInk;
''';
      final found = _hitsIn('lib/zz_planted.dart', codeOf(planted));
      expect(found.map((hit) => hit.line), [
        'final a = AppColors.error.withValues(alpha: 0.24);',
        'const b = [AppColors.info, AppColors.warning];',
        'const b = [AppColors.info, AppColors.warning];',
        r"final c = '${AppColors.success}';",
        'final d = AppColors.successContainer;',
      ]);
    });
  });
}

/// The constants a tone's raw byte lives in, as `AppColors` declares them.
const _constants = [
  'success',
  'warning',
  'error',
  'info',
  'successContainer',
  'errorContainer',
];

final _raw = RegExp('\\bAppColors\\.(${_constants.join('|')})\\b');

/// One raw use: where, and the line as written (comments blanked, trimmed).
typedef _Hit = ({String path, int number, String line});

extension on _Hit {
  String get where => '$path:$number';
}

List<_Hit> _hits(List<LibCode> files) => [
  for (final file in files) ..._hitsIn(file.path, file.code),
];

List<_Hit> _hitsIn(String path, String code) {
  final hits = <_Hit>[];
  final lines = code.split('\n');
  for (final (index, line) in lines.indexed) {
    for (final _ in _raw.allMatches(line)) {
      hits.add((path: path, number: index + 1, line: line.trim()));
    }
  }
  return hits;
}

bool _isAllowed(_Hit hit) =>
    _allowed.any((entry) => entry.file == hit.path && entry.line == hit.line);

/// The raw uses that stay: `file`, the line as written, and why it is not a
/// status painted in the wrong room.
const _allowed = <({String file, String line, String reason})>[
  (
    file:
        'lib/features/truenas/presentation/reporting/truenas_reporting_screen.dart',
    line: 'AppColors.info,',
    reason:
        'A categorical series colour on a chart, not a status: the screen '
        'documents that it is left as found, until the chart palette is '
        'settled for the whole app. Nothing on it has a state.',
  ),
  (
    file:
        'lib/features/truenas/presentation/reporting/truenas_reporting_screen.dart',
    line: 'AppColors.warning,',
    reason: 'The same series palette: the third of six chart lines.',
  ),
  (
    file:
        'lib/features/truenas/presentation/reporting/truenas_reporting_screen.dart',
    line: 'AppColors.success,',
    reason: 'The same series palette: the fourth of six chart lines.',
  ),
];
