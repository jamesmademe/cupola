import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/lexicon.dart';

/// **The brand book reads by section, and its words stay the code's.**
///
/// `design/system/README.md` had grown to 80 KB, a third of it the lexicon's
/// table: an agent that opened it for one rule spent most of its reading on
/// the rest. The reference halves now live beside it (`words.md` for the
/// lexicon and the formats, `light.md` for the title light), and this guard
/// holds the three things that keep that true:
///
/// - the README stays under its budget, and links every file beside it, so
///   nothing in `design/system/` is a page nobody reaches;
/// - every word the code holds (`StateWord`, and the plain `Lexicon`
///   constants in `lib/core/status/lexicon.dart`) is in `words.md`;
/// - every word the lexicon's table names is in the code under `lib/`, so the
///   table cannot promise a word no screen says. Service names, figures and
///   the credential's name are what the code fills in, so they are not
///   matched.
void main() {
  const system = 'design/system';
  const budget = 45 * 1024;
  final readme = File('$system/README.md').readAsStringSync();
  final words = File('$system/words.md').readAsStringSync();

  test('the README stays under its budget', () {
    expect(
      File('$system/README.md').lengthSync(),
      lessThanOrEqualTo(budget),
      reason:
          'design/system/README.md holds the principles and the rules; '
          'reference tables and long how-it-works passages go in a file '
          'beside it, linked from the section they belong to.',
    );
  });

  test('the README links every file beside it', () {
    final beside = [
      for (final entry in Directory(system).listSync())
        if (entry is File &&
            entry.path.endsWith('.md') &&
            !entry.path.endsWith('/README.md'))
          entry.uri.pathSegments.last,
    ]..sort();
    expect(beside, containsAll(['light.md', 'words.md']));
    expect(
      [
        for (final name in beside)
          if (!readme.contains(']($name')) name,
      ],
      isEmpty,
      reason: 'A file in $system the README does not link is never read.',
    );
  });

  test('every word the code holds is in words.md', () {
    final source = File('lib/core/status/lexicon.dart').readAsStringSync();
    final constants = [
      for (final m in RegExp(
        r'''static const \w+\s*=\s*(?:'([^'$\\]*)'|"([^"$\\]*)");''',
      ).allMatches(source))
        m[1] ?? m[2]!,
    ];
    expect(constants, contains('Retry'), reason: 'the scan reads constants');
    final missing = [
      for (final word in StateWord.values) word.label,
      for (final word in constants)
        if (word != Lexicon.noFigure) word,
    ].where((word) => !words.contains(word)).toList();
    expect(
      missing,
      isEmpty,
      reason:
          'A word the app says is part of its lexicon: name it in '
          '$system/words.md, with what it means.',
    );
  });

  test('every word the lexicon table names is in the code', () {
    final missing = [
      for (final word in tableWords(words))
        if (!notYetInCode.contains(word) && !saidByCode(word, libText())) word,
    ];
    expect(
      missing,
      isEmpty,
      reason:
          'The table in $system/words.md names a word no string under lib/ '
          'says. Write it in the code, or take it out of the table.',
    );
  });

  test('the words not yet in the code are still not in it', () {
    expect(
      [
        for (final word in notYetInCode)
          if (saidByCode(word, libText())) word,
      ],
      isEmpty,
      reason: 'The code says these now: take them off notYetInCode.',
    );
    expect(
      notYetInCode.difference(tableWords(words).toSet()),
      isEmpty,
      reason: 'notYetInCode names only words the table still holds.',
    );
  });

  group('the matcher', () {
    test('reads the first column of the lexicon table', () {
      const planted = '''
## The lexicon

| Word | Tone | Means |
|---|---|---|
| `Answering` | green | The service replied, `Ignored`. |
| `Timed out` · `Radarr was reached` | amber | x |

## Formats
''';
      expect(tableWords(planted), [
        'Answering',
        'Timed out',
        'Radarr was reached',
      ]);
    });

    test('lets the code fill in names, figures and the credential', () {
      const code = '''
final a = 'Address away\\u00A0· optional';
final b = "Cupola doesn't send your \$credential over plain http across the "
    'internet.';
final c = 'Downloading \$percent%';
final d = '\$name did not answer since \$time';
''';
      final text = normalisedCode(code);
      expect(saidByCode('Address away · optional', text), isTrue);
      expect(
        saidByCode(
          "Cupola doesn't send your key over plain http across the internet.",
          text,
        ),
        isTrue,
      );
      expect(saidByCode('Radarr did not answer since 20:41', text), isTrue);
      expect(saidByCode('Config loaded', text), isFalse);
    });
  });
}

/// Words the table names that no screen says yet. Each one is a promise of
/// the brand book the app does not keep; the list can only shrink.
const notYetInCode = <String>{
  // Nginx Proxy Manager's host row says its own status; the book's word for
  // a loaded configuration has no screen yet.
  'Config loaded',
};

/// The backticked words of the first column of the lexicon's table.
List<String> tableWords(String markdown) {
  final section = RegExp(
    r'## The lexicon\n([\s\S]*?)(?=\n## |$)',
  ).firstMatch(markdown)![1]!;
  return [
    for (final line in section.split('\n'))
      if (line.startsWith('| `'))
        for (final m in RegExp('`([^`]+)`').allMatches(line.split('|')[1]))
          m[1]!,
  ];
}

String? _lib;

/// Every Dart file under `lib/`, as [normalisedCode].
String libText() => _lib ??= normalisedCode(
  [
    for (final file in Directory('lib').listSync(recursive: true))
      if (file is File && file.path.endsWith('.dart')) file.readAsStringSync(),
  ].join('\n'),
);

/// [code] lower case, a no-break space as a space, and a string literal that
/// runs on in the next one joined to it.
String normalisedCode(String code) => code
    .replaceAll(r'\u00A0', ' ')
    .replaceAll('\u00A0', ' ')
    .replaceAll(RegExp(r'''['"]\s*\n\s*['"]'''), '')
    .toLowerCase();

/// What the code fills in: a service, a person, a figure, a credential.
final _filled = RegExp(
  r'Radarr 4K|Radarr|Sonarr|Lidarr|Readarr|Prowlarr|Bazarr|qBittorrent|'
  r'Transmission|SABnzbd|NZBGet|Seerr|Jellyfin|Plex|TrueNAS|Unraid|Dockge|'
  r'Nginx Proxy Manager|Cloudflare Access|Anna|tank|'
  r'\b(?:key|password|token)\b|\d+(?:[:.]\d+)?\s?%?',
);

/// Whether [text] says [word]: every part of it between what the code fills
/// in, four characters or longer.
bool saidByCode(String word, String text) {
  final parts = [
    for (final part in word.replaceAll('\u00A0', ' ').split(_filled))
      part.trim().replaceAll(RegExp(r'^[\s.,·:]+|[\s.,·:]+$'), ''),
  ].where((part) => part.length >= 4);
  return parts.every((part) => text.contains(part.toLowerCase()));
}
