import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/copy_scan.dart';

/// The brand book's lexicon, held on the copy: **one word per state, the same
/// on every screen**, none of the words its *Never* list bans, and no em dash
/// as punctuation: the dash is the placeholder of a figure nobody could read,
/// and only that.
///
/// A source scan because the regression is one plausible string in a diff —
/// "Offline" reads as a fine label until the next screen says "Did not
/// answer" about the same server. The words live in `core/status/lexicon.dart`
/// and in the failure classification (`core/network/connection_failure.dart`);
/// this keeps the variants from coming back.
///
/// What it reads: every string literal in `lib/`, with its interpolations
/// blanked (an identifier such as `folded.offline` inside `${…}` is code, not
/// copy), and adjacent literals joined as Dart joins them, so a sentence
/// wrapped across lines is read whole. What it leaves alone, because none of it is read by a person:
///
///  * a literal matched against a wire value — after `==`, `!=` or `case`, as
///    a `switch` pattern (followed by `=>` or `||`), a map key or case label
///    (followed straight by `:`), an index (`json['IsPaused']`), or the
///    argument of `contains`/`startsWith`/`endsWith`;
///  * raw strings, which are patterns;
///  * a literal with no space in it that carries `/`, `-` or `_` — an API
///    path (`/api/v2/torrents/reannounce`), an RPC method
///    (`torrent-reannounce`), a key;
///  * directives (`import`, `export`, `part`).
///
/// Everything else is copy, including semantics labels and toasts. A banned
/// word that must stay is listed in [_allowed] with the reason it is not the
/// banned state.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.startsWith('lib/core/generated/'))
      .toList(growable: false);

  test('lib/ has copy to scan', () {
    final count = libFiles.fold<int>(
      0,
      (sum, f) => sum + copyOf(f.path, f.readAsStringSync()).length,
    );
    // A lexer that silently found nothing would pass every check below.
    expect(count, greaterThan(5000));
  });

  test('no copy in lib/ uses a word the lexicon bans', () {
    final offenders = <String>[];
    for (final file in libFiles) {
      for (final literal in copyOf(file.path, file.readAsStringSync())) {
        for (final MapEntry(key: word, value: pattern) in _never.entries) {
          if (!pattern.hasMatch(literal.prose)) continue;
          if (_isAllowed(literal)) continue;
          offenders.add(
            '${literal.path}:${literal.line}  [$word]  "${literal.prose}"',
          );
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Copy here uses a word the brand book bans. Use the lexicon '
          '(StateWord, Lexicon, failureLabel/failureHeadline): Answering · '
          'Did not answer · Not set up · Set up X · Retry · Stuck · Stopped · '
          'Waiting for approval · Could not (never the contraction, never '
          '"Failed to"). A word '
          'that is not the banned state goes in '
          '_allowed with its reason.',
    );
  });

  test('no copy in lib/ uses an em dash as punctuation', () {
    final offenders = [
      for (final file in libFiles)
        for (final literal in copyOf(file.path, file.readAsStringSync()))
          if (_emDashAsPunctuation(literal.prose) && !_isAllowed(literal))
            '${literal.path}:${literal.line}  "${literal.prose}"',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'An em dash between words is punctuation, and the app has none: '
          'rewrite with a full stop, a colon, a comma or " · ". The dash '
          'stays only as the placeholder of a figure nobody could read '
          '(Lexicon.noFigure), and a range takes the en dash: S2 E4–E5.',
    );
  });

  group('the em dash matcher', () {
    test('catches a dash between two words or two holes', () {
      for (final prose in [
        'Saved — Radarr',
        '$copyHole — $copyHole',
        'Radarr did not answer — Retry',
        'Radarr—Sonarr',
        '10—20',
        '($copyHole) — $copyHole',
      ]) {
        expect(_emDashAsPunctuation(prose), isTrue, reason: prose);
      }
    });

    test('lets the placeholder of a figure through', () {
      for (final prose in [
        '—',
        '— in the queue',
        '— / 24',
        '—s',
        'today · —',
        'Queue: —',
        '↓ — ↑ —',
        '$copyHole · — free',
        // The en dash is the range's, and not this guard's business.
        'S2 E4–E5',
      ]) {
        expect(_emDashAsPunctuation(prose), isFalse, reason: prose);
      }
    });

    test('a planted literal fails through the same lexer, a comment does '
        'not', () {
      const planted =
          "final a = 'Saved — Radarr';\n"
          r"final b = '${first.title} — ${second.title}';"
          '\n'
          '// A comment — not copy.\n'
          "final c = count == null ? '—' : '\$count in the queue';\n"
          "final d = '— in the queue';\n";
      final caught = [
        for (final literal in copyOf('lib/zz_planted.dart', planted))
          if (_emDashAsPunctuation(literal.prose)) literal.prose,
      ];
      expect(caught, ['Saved — Radarr', '$copyHole — $copyHole']);
    });
  });

  test('a sentence wrapped across adjacent literals is read whole', () {
    // Dart joins adjacent literals into one string, so a phrase split at the
    // wrap is one phrase on screen: read per literal, `'… try '` `'again.'`
    // hid a banned "try again" from every check above.
    const planted =
        "final a = 'Refresh the list and try '\n"
        "    // a comment between the halves\n"
        "    'again.';\n"
        "final b = ['try', 'again'];\n";
    final prose = [
      for (final literal in copyOf('lib/zz_planted.dart', planted))
        literal.prose,
    ];
    expect(prose, ['Refresh the list and try again.', 'try', 'again']);
    expect(_never['Try again → Retry']!.hasMatch(prose.first), isTrue);
  });

  test('a contracted "could not" fails through the same lexer, a comment '
      'does not', () {
    // The app writes the phrase out: a straight or a curly apostrophe, in
    // either case, inside a literal is the contraction this entry bans.
    const planted = r"""
final a = 'Cupola couldn\'t reach it';
final b = "Couldn't add $title";
final c = 'Couldn’t load more';
// Couldn't, in a comment, is not copy.
final d = 'Could not add it';
final e = "The server couldn't check $it";
""";
    final caught = [
      for (final literal in copyOf('lib/zz_planted.dart', planted))
        if (_never["Couldn't → Could not"]!.hasMatch(literal.prose))
          literal.prose,
    ];
    expect(caught, [
      "Cupola couldn't reach it",
      "Couldn't add $copyHole",
      'Couldn’t load more',
      "The server couldn't check $copyHole",
    ]);
  });

  test('"Failed to" fails through the same lexer; a comment, a wire value and '
      'a state word do not', () {
    // The app says "Could not" in a toast and a failure line alike. A server's
    // own message (`text == 'Failed to …'`) is matched, never shown, and
    // "Import failed" is a state, not the verb phrase this entry bans.
    const planted = r"""
final a = 'Failed to pause the job';
final b = "Failed to add $title";
// Failed to, in a comment, is not copy.
final c = 'Could not pause the job';
final d = 'Import failed';
final e = text == 'Failed to check Quick Connect status';
final f = 'failed to start';
""";
    final caught = [
      for (final literal in copyOf('lib/zz_planted.dart', planted))
        if (_never['Failed to → Could not']!.hasMatch(literal.prose))
          literal.prose,
    ];
    expect(caught, [
      'Failed to pause the job',
      'Failed to add $copyHole',
      'failed to start',
    ]);
  });

  test('there is no uppercase voice', () {
    // Sentence case everywhere: the eyebrow, the one style whose tracking is
    // authored for capitals, has no site left, and a new one would bring the
    // uppercase voice back with it.
    final offenders = [
      for (final file in libFiles)
        if (file.path != 'lib/core/theme.dart')
          for (final (index, line) in file.readAsLinesSync().indexed)
            if (!line.trimLeft().startsWith('//') &&
                line.contains('AppTheme.eyebrow('))
              '${file.path}:${index + 1}',
    ];
    expect(offenders, isEmpty);
  });

  test('every allow-list entry still matches something', () {
    // An entry whose site was fixed or moved is an exception nobody needs,
    // and it would quietly excuse the next occurrence in that file.
    final unused = <String>[];
    for (final entry in _allowed) {
      final source = File(entry.file).existsSync()
          ? File(entry.file).readAsStringSync()
          : '';
      final hit = copyOf(
        entry.file,
        source,
      ).any((literal) => literal.prose == entry.literal);
      if (!hit) unused.add('${entry.file}  "${entry.literal}"');
    }
    expect(unused, isEmpty);
  });
}

/// The *Never* list, as the copy spells it. Case-insensitive where the word
/// is banned in any case; a whole-label match where the word is fine inside a
/// sentence and banned only as a state or a verb on its own.
final _never = <String, RegExp>{
  'Pending → Waiting for approval': RegExp(
    r'\bpending\b',
    caseSensitive: false,
  ),
  'Offline / Online as a state': RegExp(
    r'\b(offline|online)\b',
    caseSensitive: false,
  ),
  'Connected': RegExp(r'\b(dis)?connected\b', caseSensitive: false),
  'Unreachable → Did not answer': RegExp(
    r'\bunreachable\b',
    caseSensitive: false,
  ),
  'not answering → did not answer': RegExp(
    r'\bnot answering\b',
    caseSensitive: false,
  ),
  'did not respond → did not answer': RegExp(
    r"\b(did not|didn't|does not|doesn't) respond",
    caseSensitive: false,
  ),
  'No response → did not answer': RegExp(
    r'\bno response\b',
    caseSensitive: false,
  ),
  'Down as a state': RegExp(r'^Down$'),
  'Not configured → Not set up': RegExp(
    r'\bnot configured\b',
    caseSensitive: false,
  ),
  'Connect X → Set up X': RegExp(r'\bConnect (\S)|^Connect$'),
  'Try again → Retry': RegExp(r'\btry again\b', caseSensitive: false),
  'Film → Movie': RegExp(r'\bfilms?\b', caseSensitive: false),
  'X copied to clipboard → Copied': RegExp(
    r'\b(name|hash) copied\b|\bcopied to (the )?clipboard\b',
    caseSensitive: false,
  ),
  'Paused → Stopped': RegExp(r'\bpaused\b', caseSensitive: false),
  'Stalled → Stuck': RegExp(r'\bstalled\b', caseSensitive: false),
  'Live': RegExp(r'\bLive\b'),
  'Instantly': RegExp(r'\binstantly\b', caseSensitive: false),
  'Please wait': RegExp(r'\bplease wait\b', caseSensitive: false),
  'Oops / Sorry': RegExp(r'\b(oops|sorry)\b', caseSensitive: false),
  'Error 401': RegExp(r'\bError \d{3}\b'),
  'Reannounce → Look for peers again': RegExp(
    r'\breannounce',
    caseSensitive: false,
  ),
  'Blocklist and search → Try another download': RegExp(
    r'\bblocklist and search\b',
    caseSensitive: false,
  ),
  'Snooze → Keep waiting': RegExp(r'\bsnooze', caseSensitive: false),
  'a bare Delete': RegExp(r'^Delete$'),
  "Couldn't → Could not": RegExp(r"\bcouldn['’]t\b", caseSensitive: false),
  'Failed to → Could not': RegExp(r'\bfailed to\b', caseSensitive: false),
  'Three dots at the end → no ellipsis': RegExp(r'\.\.\.$'),
  'Could not load X → the classification\'s headline': RegExp(
    r'\b(could not|failed to) load\b',
    caseSensitive: false,
  ),
};

/// The words that stay, each with the reason it is not the banned state.
const _allowed = <({String file, String literal, String reason})>[
  (
    file: 'lib/features/unraid/presentation/unraid_screen.dart',
    literal: 'paused',
    reason:
        "libvirt's PAUSED: a VM held in memory, a state apart from shut off, "
        'which already reads "stopped"; the service\'s own term for its '
        'own state',
  ),
  (
    file: 'lib/features/unraid/domain/models/unraid_models.dart',
    literal: 'paused',
    reason:
        "Docker's paused container, apart from an exited one, which reads "
        '"stopped"',
  ),
  (
    file: 'lib/features/stream/domain/stream_semantics.dart',
    literal: 'paused',
    reason:
        "a viewer's pause in a player: \"stopped\" would say they ended "
        'playback, which is a different session state',
  ),
  (
    file: 'lib/features/dockge/presentation/dockge_stack_detail_screen.dart',
    literal: 'Down',
    reason:
        "the stack action is Docker Compose's own verb (`compose down`), "
        'not a state',
  ),
  (
    file:
        'lib/features/truenas/presentation/system/truenas_diagnostics_screen.dart',
    literal:
        'Debug-only: raw JSON-RPC responses from the connected server. Copy '
        'these to help finalise parsing.',
    reason: 'a debug-only diagnostic screen, not product copy',
  ),
  (
    file: 'lib/features/transmission/presentation/transmission_screen.dart',
    literal: 'reannounce',
    reason:
        'the menu item\'s value, a code key its switch matches; the item '
        'reads "Look for peers again"',
  ),
  (
    file: 'lib/features/dockge/domain/models/dockge_agent.dart',
    literal: 'online',
    reason: "Dockge's own agent status, the wire default the model parses",
  ),
  (
    file:
        'lib/features/qbittorrent/presentation/widgets/add_torrent_button.dart',
    literal: 'magnet:?xt=urn:btih:...',
    reason: 'the shape of a magnet link, a format example and not a sentence',
  ),
  (
    file: 'lib/core/widgets/reel_command_button.dart',
    literal: '$copyHole...',
    reason:
        'a width candidate the button measures its slot on: the busy label '
        'with the full set of trailing dots the waiting animation draws',
  ),
  (
    file: 'lib/features/stream/presentation/stream_library_screen.dart',
    literal: 'Could not load more · Retry',
    reason:
        'the footer of a grid that did load, under the rows already fetched, '
        'naming the next page: not a screen failing whole, which is what '
        "the classification's headline is for",
  ),
];

bool _isAllowed(CopyLiteral literal) {
  if (_isNotConfiguredMarker(literal.prose)) return true;
  if (_isMachineString(literal.prose)) return true;
  return _allowed.any(
    (entry) => entry.file == literal.path && entry.literal == literal.prose,
  );
}

/// `'<Service> not configured'`, the throw `AsyncValueWidget` and its peers
/// detect to draw the not-set-up placeholder (the missing-config convention).
/// A marker, never drawn: the placeholder says *Radarr is not set up*.
bool _isNotConfiguredMarker(String prose) {
  const suffix = ' not configured';
  if (!prose.endsWith(suffix)) return false;
  final subject = prose.substring(0, prose.length - suffix.length);
  return subject == copyHole ||
      ServiceKey.values.any((service) => service.title == subject);
}

/// Whether [prose] uses the em dash as punctuation: a word, a figure or an
/// interpolation on either side of it (`Saved — Radarr`, `∅ — ∅`, `10—20`).
///
/// The dash that stays is the placeholder of a figure nobody could read, and
/// that one always has an edge or a separator beside it rather than a word on
/// both sides: alone (`—`), opening the phrase it counts (`— in the queue`,
/// `— / 24`, `—s`) or closing one (`today · —`, `Queue: —`).
bool _emDashAsPunctuation(String prose) {
  for (var i = prose.indexOf('—'); i >= 0; i = prose.indexOf('—', i + 1)) {
    final before = prose.substring(0, i).trimRight();
    final after = prose.substring(i + 1).trimLeft();
    if (before.isEmpty || after.isEmpty) continue;
    if (_closesWord.hasMatch(before[before.length - 1]) &&
        _opensWord.hasMatch(after[0])) {
      return true;
    }
  }
  return false;
}

/// The last character of a word, a figure or a hole, as the dash's left side.
final _closesWord = RegExp('[\\p{L}\\p{N}$copyHole)\\]"\'’]', unicode: true);

/// The first character of a word, a figure or a hole, as the dash's right side.
final _opensWord = RegExp('[\\p{L}\\p{N}$copyHole(\\["\'‘]', unicode: true);

/// An API path, an RPC method or a key: no space, and a `/`, `-` or `_`.
bool _isMachineString(String prose) =>
    !prose.contains(' ') && RegExp(r'[/_-]').hasMatch(prose);
