import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/code_scan.dart';

/// Dim text comes from the theme: **`CupolaThemeColors.of(context).dimText`,
/// never `AppColors.onSurfaceDimDark`.**
///
/// The tertiary ink is one value per room, and the constant is the dark
/// room's. Read straight off `AppColors` it is right in the dark theme and
/// wrong on paper, where it is the pale grey that a day-room surface cannot
/// carry. The theme resolves the room and falls back sensibly in a test that
/// pumps a bare `MaterialApp`, which is the whole reason the accessor exists:
/// eleven files once skipped the lookup and painted the dark byte in both
/// themes.
///
/// A source scan, because the regression is one plausible line in a diff.
/// Only the theme itself (`lib/core/theme*`) may name the constants; it is
/// where they are defined and where the accessor picks between them. The
/// light twin is held too, for the same reason read the other way round.
/// `lib/` is read through `code_scan.dart`, so a comment that names the
/// constant to forbid it is not a use.
void main() {
  final files = libCode();

  test('lib/ has code to scan, and the accessor the rule points at exists', () {
    expect(files.length, greaterThan(300));
    final theme = File('lib/core/theme.dart').readAsStringSync();
    for (final name in ['onSurfaceDimDark', 'onSurfaceDimLight']) {
      expect(
        theme,
        contains(RegExp('static const Color $name\\b')),
        reason: 'AppColors.$name is gone or renamed; update the guard.',
      );
    }
    expect(theme, contains('final Color dimText'));
  });

  test('no dim ink is read off AppColors outside the theme', () {
    final offenders = [
      for (final file in files)
        if (!_isTheme(file.path))
          for (final hit in _hitsIn(file.path, file.code)) hit,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'The dim ink is one value per room. Read it as '
          'CupolaThemeColors.of(context).dimText, never the dark (or light) '
          'constant. A surface that is dark in both themes has its own ink '
          '(AppColors.plateDimInk on the plate).',
    );
  });

  test('the theme is the one place that may name them', () {
    // If the constants stopped being used in the theme the exemption would be
    // an exemption for nothing.
    final inTheme = [
      for (final file in files)
        if (_isTheme(file.path)) ..._hitsIn(file.path, file.code),
    ];
    expect(inTheme, isNotEmpty);
  });

  group('the matcher', () {
    test('catches either room\'s constant, and passes the accessor', () {
      const planted = '''
final a = AppColors.onSurfaceDimDark;
final b = style.copyWith(color: AppColors.onSurfaceDimLight);
final c = CupolaThemeColors.of(context).dimText;
// final d = AppColors.onSurfaceDimDark;
/// `AppColors.onSurfaceDimDark` in a doc comment.
final e = 'AppColors.onSurfaceDimDark';
final f = AppColors.onSurfaceVariantDark;
final g = AppColors.plateDimInk;
''';
      expect(_hitsIn('lib/zz_planted.dart', codeOf(planted)), [
        'lib/zz_planted.dart:1  final a = AppColors.onSurfaceDimDark;',
        'lib/zz_planted.dart:2  final b = style.copyWith(color: '
            'AppColors.onSurfaceDimLight);',
      ]);
    });
  });
}

/// The theme's own files: `lib/core/theme.dart` and anything named after it.
bool _isTheme(String path) => path.startsWith('lib/core/theme');

final _dim = RegExp(r'\bonSurfaceDim(Dark|Light)\b');

List<String> _hitsIn(String path, String code) => [
  for (final (index, line) in code.split('\n').indexed)
    if (_dim.hasMatch(line)) '$path:${index + 1}  ${line.trim()}',
];
