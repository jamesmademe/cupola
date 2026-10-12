import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/code_scan.dart';

/// Spacing comes **from the scale**: never a token nudged by a point or three.
///
/// `AppSpacing.md - 1`, `AppSpacing.xs + 1`, `AppSpacing.sm - 3`: each one a
/// value the scale (2, 4, 6, 8, 10, 12, 14, 16, …) does not have, or has under
/// another name, written to make one screen look right on the day. Twenty-one
/// had gathered in nine files: two settings rails eleven points in, where
/// every other row is twelve, and qBittorrent's chips and pills padded by three
/// different sums. A gap the scale does not hold is a decision for the scale,
/// not for a call site.
///
/// Sums with a size (`AppSpacing.lg + 36`, an icon beside its gap) and
/// multiples (`2 * AppSpacing.lg`, both gutters) are geometry, and pass. Only
/// a token plus or minus 1, 2 or 3 is a nudge.
void main() {
  final files = libCode();

  test('lib/ has code to scan', () {
    expect(files.length, greaterThan(300));
  });

  test('no spacing token is nudged off the scale', () {
    final offenders = [
      for (final file in files) ..._hitsIn(file.path, file.code),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Use the scale step itself (AppSpacing.xxs, xs, s, sm, row, md, '
          'slabY, lg, …). If none fits, the scale is what changes.',
    );
  });

  group('the matcher', () {
    test('catches a nudge either way round, and passes geometry', () {
      const planted = '''
const a = AppSpacing.md - 1;
const b = EdgeInsets.all(AppSpacing.xs + 2);
const c = 3 + AppSpacing.sm;
const d = AppSpacing.lg + 36;
const e = 2 * AppSpacing.lg;
const f = AppSpacing.sm * 2;
const g = AppSpacing.md - 12.5;
const i = width * 3 / 2 + AppSpacing.sm;
const j = AppSpacing.sm + 2 * line(title);
// const h = AppSpacing.md - 1;
''';
      expect(_hitsIn('lib/zz_planted.dart', codeOf(planted)), [
        'lib/zz_planted.dart:1  AppSpacing.md - 1',
        'lib/zz_planted.dart:2  AppSpacing.xs + 2',
        'lib/zz_planted.dart:3  3 + AppSpacing.sm',
      ]);
    });
  });
}

final _nudge = RegExp(
  r'AppSpacing\.\w+\s*[-+]\s*[1-3](?![\d.]|\s*[*/])|(?<=[(,:=?]\s*)[1-3]\s*\+\s*AppSpacing\.\w+',
);

List<String> _hitsIn(String path, String code) => [
  for (final hit in _nudge.allMatches(code))
    '$path:${'\n'.allMatches(code.substring(0, hit.start)).length + 1}  '
        '${hit.group(0)}',
];
