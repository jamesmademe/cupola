import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app draws one glyph family: `_rounded`, with `_outlined` as the
/// unselected twin of a selected `_rounded` (the tabs, a radio, a toggle).
/// The baseline name (`Icons.settings`) and the `_outline` spelling
/// (`Icons.delete_outline`) are another family with square corners, and one
/// of them beside a rounded set reads as a stray.
///
/// A source scan, comments and doc examples included: an example that shows
/// the baseline glyph is the first thing a new call site copies.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.startsWith('lib/core/generated/'))
      .toList(growable: false);

  test('no icon in lib/ is a baseline Material glyph', () {
    final offenders = <String>[];
    for (final file in libFiles) {
      for (final (index, line) in file.readAsLinesSync().indexed) {
        for (final name in _iconNames(line)) {
          if (_isFamily(name) || _allowed.contains(name)) continue;
          offenders.add('${file.path}:${index + 1}  Icons.$name');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use the _rounded glyph (or _outlined for the unselected twin of a '
          'selected _rounded one). A baseline glyph with a reason to stay '
          'goes in _allowed.',
    );
  });

  test('the matcher tells the families apart', () {
    const planted = '''
const a = Icon(Icons.settings);
const b = Icon(Icons.delete_outline);
const c = Icon(Icons.delete_outline_rounded);
const d = Icon(Icons.settings_outlined);
/// selectedIcon: Icons.home,
''';
    final caught = [
      for (final line in planted.split('\n'))
        for (final name in _iconNames(line))
          if (!_isFamily(name)) name,
    ];
    expect(caught, ['settings', 'delete_outline', 'home']);
  });

  test('every allowed glyph is still used', () {
    final source = libFiles.map((f) => f.readAsStringSync()).join('\n');
    final unused = [
      for (final name in _allowed)
        if (!RegExp('Icons\\.$name\\b').hasMatch(source)) name,
    ];
    expect(unused, isEmpty);
  });
}

/// The glyphs that stay baseline, each with the reason.
const _allowed = <String>{
  // The filled twin of `circle_outlined`: an 8pt status dot. A circle has no
  // corner for a rounded cut to soften, and the pair is the interface list's
  // up/down marker.
  'circle',
};

final _iconPattern = RegExp(r'\bIcons\.([a-z][a-z0-9_]*)');

Iterable<String> _iconNames(String line) =>
    _iconPattern.allMatches(line).map((m) => m.group(1)!);

bool _isFamily(String name) =>
    name.endsWith('_rounded') || name.endsWith('_outlined');
