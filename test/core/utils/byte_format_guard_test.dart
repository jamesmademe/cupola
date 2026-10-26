import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/app_sources.dart';

/// One rule for a size, and one place that applies it:
/// `lib/core/utils/byte_format.dart`.
///
/// A source scan because the regression is one plausible line in a diff:
/// `'${(bytes / 1024 / 1024).toStringAsFixed(2)} MB'` reads fine until it sits
/// beside `4.4 GB` on the next row. Five screens once grew their own ladder,
/// each with its own precision, and the same file read three different ways.
///
/// What it flags, on every line of `lib/` that is not a comment: a call to
/// `toStringAsFixed(` on a line that also divides by 1024 or names a byte unit
/// (`KB`, `MB`, `GB`, `TB`, `PB`). That is how every private ladder was spelled.
///
/// What it cannot see: a formatter split over several lines, or one that rounds
/// without `toStringAsFixed`. The rule itself is held by
/// `byte_format_test.dart`; this scan only keeps a second ladder from growing
/// beside it. What may stay is listed in [_allowed] with the reason.
void main() {
  const home = 'lib/core/utils/byte_format.dart';
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !file.path.startsWith('lib/core/generated/'))
      .where((file) => !isServerStandIn(file.path))
      .where((file) => file.path != home)
      .toList(growable: false);

  test('the rule is where the guard thinks it is', () {
    // The one file allowed to round a byte count by hand is the one that does.
    expect(File(home).readAsStringSync(), contains('toStringAsFixed('));
  });

  test('every size in lib/ is rendered by byte_format.dart', () {
    final offenders = [
      for (final file in files)
        for (final (line, text) in _offences(file.readAsStringSync()))
          if (!_isAllowed(file.path, text)) '${file.path}:$line  $text',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'A size is rendered once, in $home: formatBytes, '
          'formatBytesPerSecond, formatMegabytes, formatKilobytesPerSecond, '
          'formatBytesOfTotal. A number the user typed and sees echoed in the '
          'unit they typed it in goes in _allowed with its reason.',
    );
  });

  test('the scan catches a private ladder and passes comments over', () {
    const planted = '''
final a = '\${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
final b = '\${gb.toStringAsFixed(1)} GB';
final c = (bytes / 1024).toStringAsFixed(0);
// \${(bytes / 1024).toStringAsFixed(2)} KB is a comment, not copy.
  /// Nor is a doc comment: `x.toStringAsFixed(1)} GB`.
final d = ratio.toStringAsFixed(2);
final e = progress.toStringAsFixed(1);
final f = formatBytes(bytes);
''';
    expect(_offences(planted).map((offence) => offence.$1), [1, 2, 3]);
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

/// A line that rounds a number to a fixed count of decimals.
final _rounds = RegExp(r'toStringAsFixed\(');

/// A line that is about bytes: a division by 1024, or a binary unit label.
final _aboutBytes = RegExp(r'\b1024\b|\b[KMGTP]B\b');

/// The 1-based line and the trimmed text of every non-comment line of
/// [source] that rounds a byte count by hand.
List<(int, String)> _offences(String source) => [
  for (final (index, line) in source.split('\n').indexed)
    if (!line.trimLeft().startsWith('//') &&
        _rounds.hasMatch(line) &&
        _aboutBytes.hasMatch(line))
      (index + 1, line.trim()),
];

/// The lines that stay, each with the reason it is not a measured size.
const _allowed = <({String file, String excerpt, String reason})>[
  (
    file: 'lib/features/qbittorrent/presentation/torrent_detail_screen.dart',
    excerpt: "withUnit((bytes / 1024).toStringAsFixed(0), 'KB/s')",
    reason:
        'the snack bar repeats the limit the user just typed, in the KB/s '
        'they typed it in: a setting echoed back, not a measurement',
  ),
  (
    file:
        'lib/features/qbittorrent/presentation/widgets/torrent_edit_dialogs.dart',
    excerpt: '(currentLimitBytes / 1024).toStringAsFixed(0)',
    reason:
        'pre-fills the limit field in the KB/s the field is labelled in: '
        'an input the user edits, which has to parse back as typed',
  ),
];

bool _isAllowed(String path, String text) =>
    _allowed.any((entry) => entry.file == path && text.contains(entry.excerpt));
