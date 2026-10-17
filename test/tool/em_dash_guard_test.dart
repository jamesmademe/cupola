import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// No em dash (U+2014) as punctuation, anywhere in the repository.
///
/// The app's own text has its guard in `lexicon_guard_test.dart`. This one
/// holds the rest: READMEs, the brand book, code comments, test names, the
/// platform runners' strings. Prose is rewritten with a full stop, a colon, a
/// comma or parentheses.
///
/// The em dash that stays is the placeholder of a figure nobody could read,
/// which never stands between two words: alone (`'\u2014'`), opening the
/// phrase it counts (`'\u2014 moving'`), closing one (`'Queue: \u2014'`), or
/// named in prose as a code span (reads `\u2014` and never 0).
void main() {
  test('no tracked file uses the em dash as punctuation', () {
    final offenders = <String>[];
    for (final path in _trackedTextFiles()) {
      final String source;
      try {
        source = File(path).readAsStringSync();
      } on Exception {
        continue;
      }
      final lines = const LineSplitter().convert(source);
      for (var i = 0; i < lines.length; i++) {
        if (emDashAsPunctuation(lines[i])) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'An em dash between two words is punctuation: rewrite it with a '
          'full stop, a colon, a comma or parentheses.',
    );
  });

  test('the matcher catches prose and lets the placeholder through', () {
    for (final prose in [
      '/// Retry \u2014 the request can still succeed.',
      '- **Request** \u2014 when Request leads',
      '- `name` \u2014 what it does',
      'Radarr\u2014Sonarr',
      "test('backlog is neutral \u2014 missing is not a fault', () {",
    ]) {
      expect(emDashAsPunctuation(prose), isTrue, reason: prose);
    }
    for (final placeholder in [
      "subtitle: data == null ? 'today\u00A0· \u2014' : data.subtitle,",
      "expect(vm.missingChip, '\u2014 missing');",
      "  value: '\u2014',",
      '/// empty, and the readout is `\u2014 moving`.',
      "testWidgets('a source that failed reads `\u2014` and never 0', (",
      '| `Sign in with` | \u2014 | How a Seerr connection signs in',
      'S2 E4\u2013E5',
    ]) {
      expect(emDashAsPunctuation(placeholder), isFalse, reason: placeholder);
    }
  });
}

/// Whether [line] holds an em dash with a word on either side of it. A
/// backtick right against the dash closes a code span around the placeholder;
/// a backtick a space away ends a word.
bool emDashAsPunctuation(String line) => _punctuation.hasMatch(line);

final _punctuation = RegExp(r'(?:[\w)\]*]\s?|`\s)\u2014(?:\s?[\w(\[*]|\s`)');

/// Every file git tracks whose content is text.
Iterable<String> _trackedTextFiles() {
  final listing = Process.runSync('git', ['ls-files', '-z']);
  if (listing.exitCode != 0) {
    fail('git ls-files failed: ${listing.stderr}');
  }
  return (listing.stdout as String)
      .split('\u0000')
      .where((path) => path.isNotEmpty)
      .where((path) => !_binary.hasMatch(path));
}

final _binary = RegExp(
  r'\.(png|jpe?g|gif|webp|ico|icns|ttf|otf|woff2?|jar|zip|keystore|jks|car)$',
  caseSensitive: false,
);
