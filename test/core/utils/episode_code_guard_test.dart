import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One spelling of an episode code, the brand book's `S2 E4`, and one place
/// that spells it: `lib/core/utils/episode_code.dart`.
///
/// A source scan because the regression is one plausible line in a diff:
/// `'S${season}E${episode}'` reads fine until it sits beside `S2 E4` on the
/// next row. A dozen formatters once spelled it four ways (`S02E04`, `S2E4`,
/// `S1 · E4`, `2x4` passed through from Bazarr).
///
/// What it flags, on every line of `lib/` that is not a comment:
///
///  * a code built by interpolation, `S$season` or `E${episode}`, which is
///    how every one of them was spelled;
///  * a code written out, `S02E04` or `S2E4`.
///
/// What may stay is listed in [_allowed] with the reason: an example of a
/// file name, which is a machine string and keeps the spelling files use.
void main() {
  const home = 'lib/core/utils/episode_code.dart';
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !file.path.startsWith('lib/core/generated/'))
      .where((file) => file.path != home)
      .toList(growable: false);

  test('the formatter is where the guard thinks it is', () {
    final source = File(home).readAsStringSync();
    expect(_offences(source), isNotEmpty);
  });

  test('every episode code in lib/ is spelled by episode_code.dart', () {
    final offenders = [
      for (final file in files)
        for (final (line, text) in _offences(file.readAsStringSync()))
          if (!_isAllowed(file.path, text)) '${file.path}:$line  $text',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'An episode code is spelled once, in $home: formatEpisodeCode '
          '(S2 E4), formatArrEpisodeCode, formatPartialEpisodeCode, '
          'formatEpisodeRange (S2 E6–E10), formatSeasonCode (S2), '
          'formatEpisodeOrdinal (E4). A file-name example that must keep '
          'its spelling goes in _allowed with its reason.',
    );
  });

  test('the scan catches each spelling and passes comments over', () {
    const planted = '''
final a = 'S\${season}E\${episode}';
final b = 'S\$season · E\$episode';
final c = 'Severance S02E04';
final d = 'E\${n.toString().padLeft(2, '0')}';
// A comment naming S02E04 is not copy.
  /// Nor is a doc comment: `S\${season}`.
final e = 'Season \$season, episode \$episode';
final f = formatEpisodeCode(2, 4);
''';
    expect(_offences(planted).map((offence) => offence.$1), [1, 2, 3, 4]);
  });

  test('every allow-list entry still matches something', () {
    final unused = [
      for (final entry in _allowed)
        if (!File(entry.file).existsSync() ||
            !_offences(
              File(entry.file).readAsStringSync(),
            ).any((offence) => offence.$2.contains(entry.excerpt)))
          '${entry.file}  ${entry.excerpt}',
    ];
    expect(unused, isEmpty);
  });
}

/// `S$season`, `E${episode}`: a code assembled from numbers.
final _interpolated = RegExp(r'\b[SE]\$');

/// `S02E04`, `S2E4`: a code written out.
final _written = RegExp(r'\bS\d{1,2}E\d{1,3}\b');

/// The 1-based line and the trimmed text of every non-comment line of
/// [source] that spells an episode code.
List<(int, String)> _offences(String source) => [
  for (final (index, line) in source.split('\n').indexed)
    if (!line.trimLeft().startsWith('//') &&
        (_interpolated.hasMatch(line) || _written.hasMatch(line)))
      (index + 1, line.trim()),
];

/// The spellings that stay, each with the reason it is not an episode code.
const _allowed = <({String file, String excerpt, String reason})>[
  (
    file: 'lib/features/series/domain/sonarr_series_type.dart',
    excerpt: 'Episodes numbered by season, S01E02',
    reason:
        'what a standard series expects in its file names: the example is a '
        'file name, and files spell it S01E02',
  ),
  (
    file: 'lib/features/import/domain/manual_import_errors.dart',
    excerpt: '`Series Title/S01E01.ext`',
    reason: 'a file name to give the file, in the spelling files use',
  ),
];

bool _isAllowed(String path, String text) =>
    _allowed.any((entry) => entry.file == path && text.contains(entry.excerpt));
