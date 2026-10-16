import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/widgets/service_ring.dart';

/// Cupola's two sentences live once, and every place that says who Cupola is
/// quotes them exactly (brand book, *Who Cupola is*).
///
/// The claim drifted the way a hand-copied line does: the Welcome said
/// *A Cupola over your server.* while the README still said *A cupola over your
/// lab.*. In `lib/` the words may stand only where [OnePunchline] defines them;
/// anywhere else in the app a second spelling would be a second claim. In the
/// documents, any sentence that starts like one of them must be it, capitals
/// and full stop included.
///
/// The launch screens are held here too: they are the first thing Cupola shows,
/// and their ground is a copy of a token the generator does not reach.
void main() {
  final sentences = [OnePunchline.claim, OnePunchline.promise];

  group('the two sentences', () {
    test('live in lib/ only where OnePunchline defines them', () {
      final home = File('lib/core/widgets/service_ring.dart').absolute.path;
      final offenders = <String>[];
      for (final file in _files(Directory('lib'), '.dart')) {
        if (file.absolute.path == home) continue;
        final text = _flat(_joinLiterals(file.readAsStringSync()));
        for (final sentence in sentences) {
          if (text.toLowerCase().contains(_flat(sentence).toLowerCase())) {
            offenders.add('${file.path}: "$sentence"');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'quote OnePunchline.claim or OnePunchline.promise instead',
      );
    });

    test('are quoted exactly wherever a document starts one', () {
      final documents = [
        File('README.md'),
        File('CONTRIBUTING.md'),
        ..._files(Directory('assets'), '.md'),
        ..._files(Directory('design'), '.md'),
      ];
      final misquoted = <String>[];
      for (final file in documents.where((f) => f.existsSync())) {
        final text = _flat(_prose(file.readAsStringSync()));
        for (final sentence in sentences) {
          final opening = sentence.split(' ').take(3).join(' ').toLowerCase();
          var at = text.toLowerCase().indexOf(opening);
          while (at != -1) {
            final end = (at + sentence.length).clamp(0, text.length);
            final quoted = text.substring(at, end);
            if (quoted != sentence) misquoted.add('${file.path}: "$quoted"');
            at = text.toLowerCase().indexOf(opening, at + 1);
          }
        }
      }
      expect(misquoted, isEmpty, reason: 'expected ${sentences.join(' / ')}');
    });

    test('the README makes the claim', () {
      final readme = _flat(_prose(File('README.md').readAsStringSync()));
      expect(readme, contains(OnePunchline.claim));
    });
  });

  group('the launch screens stand on the room\'s ground', () {
    test('iOS, in each appearance', () {
      final colors =
          (jsonDecode(
                    File(
                      'ios/Runner/Assets.xcassets/LaunchGround.colorset/'
                      'Contents.json',
                    ).readAsStringSync(),
                  )
                  as Map<String, dynamic>)['colors']
              as List<dynamic>;
      Color? appearance(String? luminosity) {
        for (final entry in colors.cast<Map<String, dynamic>>()) {
          final appearances = (entry['appearances'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
          final dark = appearances.any((a) => a['value'] == 'dark');
          if ((luminosity == 'dark') != dark) continue;
          final c = (entry['color'] as Map)['components'] as Map;
          int channel(String name) => int.parse(c[name] as String);
          return Color.fromARGB(
            255,
            channel('red'),
            channel('green'),
            channel('blue'),
          );
        }
        return null;
      }

      expect(appearance(null), DesignTokensLight.colorRoomGround);
      expect(appearance('dark'), DesignTokensDark.colorRoomGround);
      final storyboard = File(
        'ios/Runner/Base.lproj/LaunchScreen.storyboard',
      ).readAsStringSync();
      expect(storyboard, contains('name="LaunchGround"'));
    });

    test('Android, by day and by night', () {
      Color ground(String values) {
        final xml = File(
          'android/app/src/main/res/$values/colors.xml',
        ).readAsStringSync();
        final hex = RegExp(
          r'<color name="launch_ground">#([0-9A-Fa-f]{6})</color>',
        ).firstMatch(xml)!.group(1)!;
        return Color(0xFF000000 | int.parse(hex, radix: 16));
      }

      expect(ground('values'), DesignTokensLight.colorRoomGround);
      expect(ground('values-night'), DesignTokensDark.colorRoomGround);
    });
  });
}

Iterable<File> _files(Directory root, String extension) => root
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith(extension));

/// Adjacent string literals read as one: `'A Cupola over ' 'your server.'`.
String _joinLiterals(String source) =>
    source.replaceAll(RegExp(r"""['"]\s*\n\s*['"]"""), '');

/// Markdown as it reads: emphasis dropped, and a drawn line break (` / `,
/// as a card writes a two-line lockup) read as the space it is.
String _prose(String markdown) =>
    markdown.replaceAll(RegExp(r'[*_`]'), '').replaceAll(' / ', ' ');

String _flat(String text) => text.replaceAll(RegExp(r'\s+'), ' ');
