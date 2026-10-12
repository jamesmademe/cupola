import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/code_scan.dart';

/// Every top bar is [GlassAppBar]: a transparent bar over the room's glass.
/// Material's own `AppBar` paints an opaque strip in Material's colours, and
/// that strip cuts across a room that is glass everywhere else, so one screen
/// with it reads as a different app. [GlassAppBar] is the only file that builds
/// the Material bar, which makes it the one place this rule exempts.
///
/// A source scan, because the regression is one new `AppBar(` in a diff.
/// `SliverAppBar(` and `GlassAppBar(` are other names and pass. `lib/` is read
/// through `code_scan.dart`, so a comment or a string that names the widget is
/// not a use.
void main() {
  final files = libCode();

  test(
    'lib/ has code to scan, and the glass bar the rule points at exists',
    () {
      expect(files.length, greaterThan(300));
      final glass = files.singleWhere((file) => file.path == _glassBar);
      expect(
        glass.code,
        matches(_materialBar),
        reason:
            'GlassAppBar no longer builds the Material bar; update the guard.',
      );
    },
  );

  test('no Material AppBar is built outside GlassAppBar', () {
    final offenders = [
      for (final file in files)
        if (file.path != _glassBar)
          for (final hit in _hitsIn(file.path, file.code)) hit,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Build GlassAppBar instead of AppBar. It keeps the room\'s glass '
          'behind the bar, and it takes the same title, leading, actions, '
          'bottom and toolbarHeight. Do not pass backgroundColor: the glass is '
          'the background.',
    );
  });

  group('the matcher', () {
    test(
      'catches Material\'s AppBar, and passes the glass and sliver bars',
      () {
        const planted = '''
final a = AppBar(title: title);
final b = GlassAppBar(title: title);
final c = SliverAppBar(floating: true);
final d = AppBarTheme(backgroundColor: color);
// final e = AppBar(title: title);
/// `AppBar(` in a doc comment.
final f = 'AppBar(';
''';
        expect(_hitsIn('lib/zz_planted.dart', codeOf(planted)), [
          'lib/zz_planted.dart:1  final a = AppBar(title: title);',
        ]);
      },
    );
  });
}

const _glassBar = 'lib/core/widgets/glass_app_bar.dart';

/// The Material bar's constructor, from the start of an identifier (so
/// `GlassAppBar(`, `SliverAppBar(` and `AppBarTheme(` do not match).
final _materialBar = RegExp(r'(?<![A-Za-z0-9])AppBar\(');

List<String> _hitsIn(String path, String code) => [
  for (final (index, line) in code.split('\n').indexed)
    if (_materialBar.hasMatch(line)) '$path:${index + 1}  ${line.trim()}',
];
