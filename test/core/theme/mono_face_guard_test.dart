import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Geist Mono is for machine strings only; a figure is never set in it.
///
/// The brand book (`design/system/README.md`, Typography) puts it in one
/// sentence: release names, paths, hashes, keys, logs, exactly as returned.
/// Figures (a size, a rate, a percentage, a clock, a count) stay in the text
/// face and take `.tabular` there, so a column of them lines up without
/// borrowing a second family. `.mono.tabular` was the shape of the mistake:
/// ten places set a figure in mono and asked for tabular digits on top of a
/// face whose digits are already one width.
///
/// A source scan, because the regression is one plausible line in a diff.
///
///  * **`.mono` and `.tabular` never meet in one expression.** A style that
///    asks for both is a figure in the wrong face; the figure moves to the
///    text face and the other half is dropped.
///  * **Every use of the mono face is listed, with what it prints.** Whether a
///    string is a machine string or a figure cannot be read off a style, so the
///    list is the control: a new `.mono` in a file that is not here, or a second
///    one in a file that is, fails until somebody says what the text is.
///
/// What it cannot see: a figure handed to a widget that sets its own mono
/// style from a flag (`_CertRow.monospace` is the one such flag today, and its
/// two callers are fingerprints). What may stay is in [_monoUses].
void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !file.path.startsWith('lib/core/generated/'))
      // The role and the getter that define the face.
      .where((file) => file.path != 'lib/core/theme.dart')
      .toList(growable: false);

  test('no figure is set in the mono face: .mono never meets .tabular', () {
    final offenders = [
      for (final file in files)
        for (final line in _monoTabularLines(file.readAsStringSync()))
          '${file.path}:$line',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'A figure is `.tabular` in the text face; mono is for machine '
          'strings, whose digits are already one width. Drop one of the two.',
    );
  });

  test('every use of the mono face says which machine string it prints', () {
    final found = <String, int>{
      for (final file in files)
        if (_countMono(file.readAsStringSync()) case final uses when uses > 0)
          file.path: uses,
    };
    final listed = {for (final entry in _monoUses) entry.file: entry.uses};

    final unlisted = [
      for (final entry in found.entries)
        if (listed[entry.key] != entry.value)
          '${entry.key}: ${entry.value} use(s) in the source, '
              '${listed[entry.key] ?? 0} listed',
    ];
    final stale = [
      for (final entry in listed.entries)
        if (!found.containsKey(entry.key))
          '${entry.key}: listed, no longer uses mono',
    ];
    expect(
      [...unlisted, ...stale],
      isEmpty,
      reason:
          'Geist Mono is for machine strings only (release names, paths, '
          'hashes, keys, logs, exactly as returned). A figure, a clock or a '
          'sentence is not one. Say what the new text is in _monoUses, or move '
          'it to the text face.',
    );
  });

  test('the scan catches a figure in mono and passes comments over', () {
    const planted = '''
Text(a, style: AppTheme.chrome(context, size: 11).mono.tabular);
Text(b, style: base.tabular.mono);
Text(
  c,
  style: AppTheme.chrome(
    context,
    size: 11,
    color: dim,
  )
      .mono
      .tabular,
);
Text(d, style: base.mono);
Text(e, style: base.tabular);
Text(f, style: base.mono, semanticsLabel: 'x'), Text(g, style: base.tabular);
// style: base.mono.tabular is a comment, not a style.
  /// `.tabular.mono` in a doc comment is not one either.
''';
    expect(_monoTabularLines(planted), [1, 2, 10]);
    expect(_countMono(planted), 5);
  });
}

/// The 1-based line of every `.mono` whose expression also carries `.tabular`
/// (in either order), on code lines only.
List<int> _monoTabularLines(String source) {
  final code = _code(source);
  final lines = <int>[];
  for (final match in _monoToken.allMatches(code)) {
    final (start, end) = _expressionAround(code, match.start);
    if (code.substring(start, end).contains(_tabularToken)) {
      lines.add(_lineOf(code, match.start));
    }
  }
  return lines;
}

/// How many times [source] reaches for the mono face, on code lines only.
int _countMono(String source) => _monoToken.allMatches(_code(source)).length;

/// A reach for the mono face: the `.mono` getter or role, or one of the tokens
/// a style could name the family through instead.
final _monoToken = RegExp(
  r'\.mono\b|\bmonoFontFamily\b|\btypeFamilyMono\b|\btypeRoleMono\w*',
);

final _tabularToken = RegExp(r'\.tabular\b|tabularFigures');

/// [source] with every comment line blanked, so line numbers survive.
String _code(String source) => source
    .split('\n')
    .map((line) => line.trimLeft().startsWith('//') ? '' : line)
    .join('\n');

int _lineOf(String text, int offset) =>
    '\n'.allMatches(text.substring(0, offset)).length + 1;

/// The span of the argument or statement that holds [index]: back to the
/// nearest `,` `;` or unbalanced `(` `{` `[`, forward to the nearest `,` `;`
/// or unbalanced `)` `}` `]`, at the same depth.
(int, int) _expressionAround(String text, int index) {
  var start = index;
  var depth = 0;
  while (start > 0) {
    final char = text[start - 1];
    if (')}]'.contains(char)) {
      depth++;
    } else if ('({['.contains(char)) {
      if (depth == 0) break;
      depth--;
    } else if ((char == ',' || char == ';') && depth == 0) {
      break;
    }
    start--;
  }
  var end = index;
  depth = 0;
  while (end < text.length) {
    final char = text[end];
    if ('({['.contains(char)) {
      depth++;
    } else if (')}]'.contains(char)) {
      if (depth == 0) break;
      depth--;
    } else if ((char == ',' || char == ';') && depth == 0) {
      break;
    }
    end++;
  }
  return (start, end);
}

/// Where the mono face is used, and what each use prints. One entry per file;
/// [uses] is how many times the file reaches for it.
const _monoUses = <({String file, int uses, String prints})>[
  (
    file:
        'lib/features/activity/presentation/widgets/activity_download_row.dart',
    uses: 1,
    prints:
        'the release a download is, exactly as the indexer and the client '
        'name it',
  ),
  (
    file:
        'lib/features/activity/presentation/widgets/activity_history_row.dart',
    uses: 1,
    prints: 'the file an import became, exactly as the library names it',
  ),
  (
    file: 'lib/features/activity/presentation/widgets/fault_card.dart',
    uses: 1,
    prints: 'the release a stuck download is, as its client names it',
  ),
  (
    file: 'lib/features/activity/presentation/widgets/download_table.dart',
    uses: 1,
    prints: "the release a download came as, under its title in the table",
  ),
  (
    file: 'lib/features/activity/presentation/widgets/download_parts.dart',
    uses: 1,
    prints:
        "a download's facts that are a machine's strings: its release, its "
        "library folder, its client's address",
  ),
  (
    file: 'lib/features/import/presentation/blocked_import_parts.dart',
    uses: 6,
    prints:
        'the files a blocked download holds, by name (also the one already on '
        'an episode), and what the arr says about them, exactly as it returns '
        'them',
  ),
  (
    file: 'lib/features/import/presentation/manual_import_fix_sheet.dart',
    uses: 3,
    prints:
        'the files being matched, by name, and the one already on an episode: '
        'file names, exactly as the arr found them',
  ),
  (
    file: 'lib/features/home/presentation/widgets/downloads_module.dart',
    uses: 1,
    prints:
        'the release a download is, exactly as the indexer and the client '
        'name it',
  ),
  (
    file: 'lib/features/media/presentation/shelf_page.dart',
    uses: 1,
    prints:
        'the folder an artist\'s or an author\'s files live in: a path, '
        'exactly as the service returns it',
  ),
  (
    file: 'lib/features/media/presentation/media_add_sheet.dart',
    uses: 1,
    prints:
        'the root folder a film is added under: a path, exactly as the '
        'service returns it',
  ),
  (
    file:
        'lib/features/discover/presentation/widgets/request_bottom_sheet.dart',
    uses: 1,
    prints:
        'the root folder a request lands under: a path, exactly as Seerr '
        'returns it',
  ),
  (
    file: 'lib/core/widgets/file_info_section.dart',
    uses: 2,
    prints:
        'a library folder path, whole, and the same path as a secondary line: '
        'paths, exactly as the service returns them',
  ),
  (
    file: 'lib/core/widgets/machine_name.dart',
    uses: 2,
    prints:
        'the machine name of a copy (release, torrent or NZB name) and its '
        'tooltip: never rewritten, copied exactly',
  ),
  (
    file:
        'lib/features/truenas/presentation/system/truenas_diagnostics_screen.dart',
    uses: 1,
    prints:
        'the JSON a diagnostics call returned, read in columns and pasted '
        'back as it came',
  ),
  (
    file: 'lib/features/settings/presentation/trusted_certificates_screen.dart',
    uses: 1,
    prints: 'a certificate SHA-256 fingerprint: a hash',
  ),
  (
    file: 'lib/features/settings/presentation/widgets/cert_trust_content.dart',
    uses: 1,
    prints:
        'the SHA-256 fingerprint of a certificate, and the one it replaced '
        '(the only two rows that pass monospace: true): hashes, compared '
        'character by character',
  ),
  (
    file: 'lib/features/onboarding/presentation/widgets/onboarding_found.dart',
    uses: 1,
    prints:
        'the SHA-256 fingerprint of a certificate a found service presents: a '
        'hash, compared character by character',
  ),
  (
    file:
        'lib/features/release_search/presentation/widgets/release_search_job_card.dart',
    uses: 1,
    prints:
        'the raw diagnostic behind a failed search (`HTTP 502\u00A0· nginx`, a '
        'Dio error type name): a code, as returned',
  ),
  (
    file: 'lib/features/release_search/presentation/release_search_sheet.dart',
    uses: 1,
    prints: 'the same raw diagnostic, in the sheet that shows a failed search',
  ),
  (
    file: 'lib/features/dockge/presentation/dockge_terminal_screen.dart',
    uses: 1,
    prints: 'the terminal of a stack: shell output, exactly as returned',
  ),
  (
    file: 'lib/features/dockge/presentation/dockge_stack_detail_screen.dart',
    uses: 1,
    prints: 'container logs, exactly as returned',
  ),
  (
    file: 'lib/features/dockge/presentation/dockge_stack_edit_screen.dart',
    uses: 1,
    prints: 'a compose file in its editor: the YAML the user is writing',
  ),
  (
    file: 'lib/features/npm/presentation/npm_advanced_config_screen.dart',
    uses: 2,
    prints:
        'an nginx block in its editor, and the message nginx refused it with: '
        'config text and a log line, as returned',
  ),
  (
    file: 'lib/features/shell/presentation/desktop/command_deck.dart',
    uses: 1,
    prints:
        'the key legend of a hint (`⌘1–⌘4`, `⌥⏎`, `↑↓`): the legend of a '
        'physical key, not a figure; the words after it are the text face',
  ),
  (
    file: 'lib/features/shell/presentation/desktop/desktop_nav_rail.dart',
    uses: 1,
    prints: 'the `⌘K` legend at the foot of the rail',
  ),
  (
    file: 'lib/features/shell/presentation/desktop/window_chrome.dart',
    uses: 1,
    prints: 'the `⌘K` legend on the way to anything (`Ctrl+K` elsewhere)',
  ),
];
