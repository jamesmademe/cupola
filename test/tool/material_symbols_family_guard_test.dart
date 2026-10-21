import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Material Symbols ships four glyphs per name, in three font *families*
/// (`MaterialSymbolsOutlined`, `…Rounded`, `…Sharp`), and a release build
/// tree-shakes each family into a subset holding only the names the app uses.
///
/// The subset the Outlined family produced for iOS drew nothing: TestFlight
/// 202610211159 showed the Activity tab as an empty column over its name,
/// while the Rounded family in the same build drew its glyphs, and the very
/// same binary drew the Outlined one as soon as the full font was put back.
/// The fault is in how a subset of that family survives the packaging, so the
/// rule is mechanical: in `lib/`, every `Symbols.` reference is a `_rounded`
/// one. The family then either disappears from the build (nothing asked for
/// it) or is one this app has seen render.
///
/// A source scan rather than a widget test for the reason
/// `monochrome_accent_test.dart` gives: the regression is one plausible line
/// in a diff, it compiles, and it looks right on every screen that ran the
/// full font.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList(growable: false);

  /// A `Symbols.<name>` reference that is not the rounded family.
  final outlined = RegExp(r'Symbols\.(?!\w*_rounded\b)(\w+)');

  test('every Material Symbols glyph in lib/ is the rounded family', () {
    final offenders = <String>[];
    for (final file in libFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Comment lines may name what they forbid.
        if (line.trimLeft().startsWith('//')) continue;
        for (final match in outlined.allMatches(line)) {
          offenders.add('${file.path}:${i + 1} Symbols.${match.group(1)}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'The Outlined and Sharp Symbols subsets do not draw in a release '
          'build. Use Symbols.<name>_rounded, or drop the font for that '
          'glyph.\n${offenders.join('\n')}',
    );
  });
}
