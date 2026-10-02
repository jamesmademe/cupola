import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/code_scan.dart';

/// Type goes through a role: **no bare `TextStyle(fontSize:)`, no
/// `copyWith(fontWeight:)`, no `copyWith(fontSize:)`.**
///
/// The three bundled families are each one variable file, registered once.
/// Flutter resolves `fontWeight` against that single face without touching an
/// axis, so a style that asks for a size or a weight any other way than
/// through a role renders the file's default instance: for Bricolage Grotesque
/// that is 96pt ExtraBold at full width. `copyWith(fontWeight:)` is the same
/// trap from the other side: it moves `fontWeight` and leaves `fontVariations`
/// pointing at the old weight, so the glyphs keep the weight they had.
/// `copyWith(fontSize:)` leaves the optical-size axis where the role set it,
/// so a display role resized that way is drawn for the wrong size.
///
/// The way out is a `textTheme` role, `AppType.*` or one of
/// `AppTheme.chrome/subtitle/panelHeader/rowTitle/data`, then `.weight()`,
/// which moves the `wght` axis and carries the rest. `weight_ceiling_test`
/// holds the weight (nothing above 600) and `type_axes_test` that every role
/// sets its axes; this holds the door they stand behind.
///
/// A source scan, because the regression is one plausible line in a diff.
/// It reads `lib/` through `code_scan.dart` and fails on:
///
///  * a `TextStyle(` call that names `fontSize` or `fontWeight`, and
///  * a `copyWith(` call that names `fontWeight` or `fontSize`,
///
/// anywhere outside `lib/core/theme*`, which is where the roles are built and
/// `.weight()` is written. A `TextStyle(` that names neither (a decoration, a
/// colour merged onto the inherited style) is not bare in this sense and is
/// left alone.
void main() {
  final files = libCode();
  final textStyle = RegExp(r'\bTextStyle\(');
  final copyWith = RegExp(r'\bcopyWith\(');

  List<String> offendersIn(String path, String code) => [
    for (final call in callsOf(path, code, textStyle))
      if (call.names('fontSize') || call.names('fontWeight'))
        '${call.where}  TextStyle(${call.named.keys.where(_axes.contains).join(', ')}:)',
    for (final call in callsOf(path, code, copyWith))
      if (call.names('fontSize') || call.names('fontWeight'))
        '${call.where}  copyWith(${call.named.keys.where(_axes.contains).join(', ')}:)',
  ];

  test('lib/ has style calls to scan, and the theme is where they live', () {
    final outside = [
      for (final file in files)
        if (!_isTheme(file.path)) ...callsOf(file.path, file.code, copyWith),
    ];
    // A scanner that found nothing would pass the check below.
    expect(outside.length, greaterThan(100));
    final theme = files.singleWhere(
      (file) => file.path == 'lib/core/theme.dart',
    );
    expect(
      callsOf(
        theme.path,
        theme.code,
        textStyle,
      ).any((call) => call.names('fontSize') && call.names('fontWeight')),
      isTrue,
      reason: 'The roles are built in theme.dart; the exemption is for them.',
    );
  });

  test('no style outside the theme sets its own size or weight', () {
    final offenders = [
      for (final file in files)
        if (!_isTheme(file.path)) ...offendersIn(file.path, file.code),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'A bare TextStyle(fontSize:) renders the variable font\'s default '
          'instance, and copyWith(fontWeight:) or copyWith(fontSize:) leaves '
          'an axis where the role set it. Take a textTheme role, AppType.* '
          'or AppTheme.chrome/subtitle/panelHeader/rowTitle/data, then '
          '.weight(FontWeight.wNNN), never above 600.',
    );
  });

  group('the matcher', () {
    test('catches a bare style and a re-weight, and passes the rest', () {
      const planted = '''
final a = TextStyle(fontSize: 12);
final b = const TextStyle(color: c, fontWeight: FontWeight.w600);
final c = base.copyWith(
  color: c,
  fontWeight: FontWeight.w500,
);
final d = TextStyle(decoration: TextDecoration.underline);
final e = base.copyWith(color: c);
final f = base.weight(FontWeight.w600).copyWith(color: c);
// final g = TextStyle(fontSize: 12);
/// `copyWith(fontWeight: w)` in a doc comment.
final h = 'TextStyle(fontSize: 12)';
final i = DefaultTextStyle(fontSize: 12);
final j = base.copyWith(fontFamily: f, shadows: [Shadow(fontSize: 1)]);
final k = base.copyWith(fontSize: 14);
final l = base.copyWith(color: c, fontSize: 14, fontWeight: w);
''';
      expect(offendersIn('lib/zz_planted.dart', codeOf(planted)), [
        'lib/zz_planted.dart:1  TextStyle(fontSize:)',
        'lib/zz_planted.dart:2  TextStyle(fontWeight:)',
        'lib/zz_planted.dart:3  copyWith(fontWeight:)',
        'lib/zz_planted.dart:15  copyWith(fontSize:)',
        'lib/zz_planted.dart:16  copyWith(fontSize, fontWeight:)',
      ]);
    });
  });
}

const _axes = {'fontSize', 'fontWeight'};

/// The theme's own files: `lib/core/theme.dart` and anything named after it.
bool _isTheme(String path) => path.startsWith('lib/core/theme');
