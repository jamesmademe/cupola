import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/dot_separator.dart';

import '../../test_helpers/copy_scan.dart';

/// A line that wraps never starts with the dot between two parts: the space
/// before the dot is a no-break space (U+00A0), so `Bluray-1080p · 8.4 GB`
/// breaks after the dot, and the next line starts with a word.
///
/// The separator is `dotSeparator` in `lib/core/utils/dot_separator.dart`;
/// inside a longer literal the same spacing is the escape, `\u00A0· `. This
/// guard reads the copy (the string literals of `lib/`, as the compiler reads
/// them) and fails on a plain space before a dot.
void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !file.path.startsWith('lib/core/generated/'))
      .toList(growable: false);

  test('no copy in lib/ puts a plain space before the separating dot', () {
    final offenders = [
      for (final file in files)
        for (final literal in copyOf(file.path, file.readAsStringSync()))
          if (_plainBeforeDot.hasMatch(literal.prose))
            '${literal.path}:${literal.line}  "${literal.prose}"',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Join parts with `dotSeparator` (or write `\\u00A0· ` inside a '
          'literal), so a wrapped line never starts with the dot.',
    );
  });

  test('the scan catches a plain space before the dot and passes the rest', () {
    const planted = r'''
final a = '$size · $age';
final b = ' · ';
final c = '$size\u00A0· $age';
final d = [x, y].join(dotSeparator);
final e = 'Home · Discover';
''';
    expect(
      [
        for (final literal in copyOf('lib/zz_planted.dart', planted))
          if (_plainBeforeDot.hasMatch(literal.prose)) literal.line,
      ],
      [1, 2, 5],
    );
  });

  test('dotSeparator keeps the dot with the part before it', () {
    expect(dotSeparator.codeUnits, [0xA0, 0xB7, 0x20]);
  });

  test('splitParts splits a new line and one saved before the rule', () {
    expect(splitParts('Bluray-1080p\u00A0· 8.4 GB'), [
      'Bluray-1080p',
      '8.4 GB',
    ]);
    expect(splitParts('Bluray-1080p · 8.4 GB'), ['Bluray-1080p', '8.4 GB']);
    expect(splitParts('Bluray-1080p'), ['Bluray-1080p']);
  });
}

/// A plain space (not the no-break one) straight before the middle dot.
final _plainBeforeDot = RegExp(' ·');
