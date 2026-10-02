import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/copy_scan.dart';

/// One rule for a percentage, and one place that applies it:
/// `lib/core/utils/percent_format.dart`.
///
/// A scan of the copy (the string literals of `lib/`, read the way the
/// compiler reads them: comments and code are not copy) because the regression
/// is one plausible string in a diff: `'${(p * 100).round()}%'` reads fine until
/// it sits beside a row that floors, and a torrent at 99.6% is `100%` on one
/// screen and `99%` on the next.
///
///  * **No percent is built outside the formatter.** A figure (a digit or an
///    interpolation) straight in front of a `%` in a literal is a percentage
///    assembled by hand. `formatPercent` and `wholePercent` are the way.
///  * **No space between a figure and its sign**, plain or no-break: `62%`,
///    never `62 %` or `62\u00A0%`.
///
/// What it cannot see: a percentage whose sign is joined from two places
/// (`'$value' + sign`), or a figure that was already formatted elsewhere with
/// its sign (a service's own `'62%'` string passed through). What may stay is
/// in [_allowed] with the reason.
void main() {
  const home = 'lib/core/utils/percent_format.dart';
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !file.path.startsWith('lib/core/generated/'))
      .where((file) => file.path != home)
      .toList(growable: false);

  test('the guard has copy to scan, and the rule is where it thinks', () {
    final count = files.fold<int>(
      0,
      (sum, file) => sum + copyOf(file.path, file.readAsStringSync()).length,
    );
    // A scan that silently found nothing would pass every check below.
    expect(count, greaterThan(5000));
    expect(File(home).readAsStringSync(), contains("'%'"));
  });

  test('no percentage in lib/ is built outside percent_format.dart', () {
    final offenders = [
      for (final file in files)
        for (final literal in copyOf(file.path, file.readAsStringSync()))
          if (_built.hasMatch(literal.prose) && !_isAllowed(literal))
            '${literal.path}:${literal.line}  "${literal.prose}"',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'A percentage is `formatPercent(value)` (or `wholePercent` for the '
          'int): nearest whole percent, glued, never 100% before 100. A '
          'literal that carries a sign for another reason goes in _allowed.',
    );
  });

  test('no copy in lib/ puts a space between a figure and its %', () {
    final offenders = [
      for (final file in files)
        for (final literal in copyOf(file.path, file.readAsStringSync()))
          if (_spaced.hasMatch(literal.prose) && !_isAllowed(literal))
            '${literal.path}:${literal.line}  "${literal.prose}"',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Percent is glued: `62%`, never `62 %` and never with a no-break '
          'space. The product owner decided it on 02/10: the English '
          'convention, and what the services print.',
    );
  });

  test('the scan catches a hand-built percentage and passes comments over', () {
    const planted = r'''
final a = '${(p * 100).round()}%';
final b = '$percent%';
final c = '62%';
final d = '$percent %';
final e = '62 %';
final f = '62\u00A0%';
final g = '${p}\u00A0% done';
// final h = '${p}%' in a comment is not copy.
final i = formatPercent(p);
final j = 'it is 100% sure';
final k = 'context%5Bdevice%5D';
final l = r'^[$%&]+$';
final m = '$value% '
    'done';
''';
    final literals = copyOf('lib/zz_planted.dart', planted);
    expect(
      [
        for (final literal in literals)
          if (_built.hasMatch(literal.prose)) literal.line,
      ],
      [1, 2, 3, 10, 13],
      reason: 'a digit or an interpolation straight before the sign',
    );
    expect(
      [
        for (final literal in literals)
          if (_spaced.hasMatch(literal.prose)) literal.line,
      ],
      [4, 5, 6, 7],
      reason: 'a plain or no-break space between the figure and the sign',
    );
  });

  test('every allow-list entry still matches something', () {
    final unused = [
      for (final entry in _allowed)
        if (!File(entry.file).existsSync() ||
            !copyOf(
              entry.file,
              File(entry.file).readAsStringSync(),
            ).any((literal) => literal.prose == entry.literal))
          '${entry.file}  "${entry.literal}"',
    ];
    expect(unused, isEmpty);
  });
}

/// A figure straight before the sign: a digit or an interpolation.
final _built = RegExp('[0-9$copyHole]%');

/// A figure, a plain or no-break space, then the sign.
final _spaced = RegExp('[0-9$copyHole][ \u00A0]%');

/// Literals that carry a `%` after a figure for a reason that is not a
/// percentage shown to a person, each with the reason.
const _allowed = <({String file, String literal, String reason})>[];

bool _isAllowed(CopyLiteral literal) => _allowed.any(
  (entry) => entry.file == literal.path && entry.literal == literal.prose,
);
