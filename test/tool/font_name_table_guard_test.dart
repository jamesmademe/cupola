import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// App Store Connect refuses a binary carrying a font whose 'name' table lacks
// the records a font is looked up by (ITMS-90853, "'name' table usability").
// Build 202610271016 was refused for CupolaServices.otf, which had only a
// family and a style. Every bundled font must name itself in full.
const _required = {
  1: 'family',
  2: 'style',
  3: 'unique identifier',
  4: 'full name',
  6: 'PostScript name',
};

/// The name IDs a font's Windows (platform 3) records carry with text.
Set<int> _namedIds(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final tables = data.getUint16(4);
  for (var i = 0; i < tables; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
    if (tag != 'name') continue;
    final table = data.getUint32(record + 8);
    final count = data.getUint16(table + 2);
    final ids = <int>{};
    for (var j = 0; j < count; j++) {
      final entry = table + 6 + j * 12;
      final platform = data.getUint16(entry);
      final id = data.getUint16(entry + 6);
      final length = data.getUint16(entry + 8);
      if (platform == 3 && length > 0) ids.add(id);
    }
    return ids;
  }
  return const {};
}

void main() {
  final fonts =
      Directory('assets/fonts')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.otf') || f.path.endsWith('.ttf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('assets/fonts holds the bundled fonts', () {
    expect(fonts, isNotEmpty);
  });

  for (final font in fonts) {
    test('${font.uri.pathSegments.last} names itself in full', () {
      final ids = _namedIds(font.readAsBytesSync());
      final missing = [
        for (final MapEntry(:key, :value) in _required.entries)
          if (!ids.contains(key)) '$key ($value)',
      ];
      expect(missing, isEmpty, reason: 'missing name records: $missing');
    });
  }
}
