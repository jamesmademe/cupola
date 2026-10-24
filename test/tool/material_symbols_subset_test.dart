import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// These two release subsets exposed missing glyphs despite valid codepoints
// and outlines. Keep the exact sets: the broken subsetter misaligned gvar
// blocks when converting long offsets to short ones. A full-font widget test
// cannot catch that corruption, and changing families only moves the failure.
const _releaseGlyphs = {
  'MaterialSymbolsRounded': [
    0xe156,
    0xe53b,
    0xe650,
    0xe87a,
    0xe8b8,
    0xe9b2,
    0xf88a,
  ],
  'MaterialSymbolsOutlined': [0xe650, 0xf7e5, 0xf88a],
};

void main() {
  for (final entry in _releaseGlyphs.entries) {
    testWidgets('${entry.key} release subset preserves every glyph', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // flutter_tester and font-subset are supplied by the same host engine.
        // Testing that executable also checks the tool used by release builds.
        final subsetter = File.fromUri(
          File(Platform.resolvedExecutable).parent.uri.resolve(
            'font-subset${Platform.isWindows ? '.exe' : ''}',
          ),
        );
        expect(subsetter.existsSync(), isTrue, reason: subsetter.path);
        final temporary = await Directory.systemTemp.createTemp(
          'cupola-symbol-subset-',
        );
        addTearDown(() => temporary.delete(recursive: true));

        final source = await rootBundle.load(
          'packages/material_symbols_icons/lib/fonts/${entry.key}.ttf',
        );
        final original = File.fromUri(temporary.uri.resolve('original.ttf'));
        final subset = File.fromUri(temporary.uri.resolve('subset.ttf'));
        await original.writeAsBytes(Uint8List.sublistView(source));
        final process = await Process.start(subsetter.path, [
          subset.path,
          original.path,
        ]);
        final errors = process.stderr.transform(utf8.decoder).join();
        final output = process.stdout.drain<void>();
        process.stdin.writeln(entry.value.join(' '));
        await process.stdin.close();
        final exitCode = await process.exitCode;
        await output;
        expect(exitCode, 0, reason: await errors);
        expect(await subset.length(), lessThan(await original.length()));

        final fullFamily = 'SubsetTestFull${entry.key}';
        final subsetFamily = 'SubsetTestReduced${entry.key}';
        await _loadFont(fullFamily, source);
        await _loadFont(
          subsetFamily,
          ByteData.sublistView(await subset.readAsBytes()),
        );
        for (final codepoint in entry.value) {
          for (final sidebar in [false, true]) {
            final expected = await _rasterize(fullFamily, codepoint, sidebar);
            final actual = await _rasterize(subsetFamily, codepoint, sidebar);
            final description =
                '${entry.key} U+${codepoint.toRadixString(16)} '
                '(${sidebar ? 'sidebar axes' : 'default axes'})';
            expect(
              [
                for (var i = 3; i < expected.length; i += 4) expected[i],
              ].any((alpha) => alpha > 0),
              isTrue,
              reason: 'The original glyph must draw: $description',
            );
            expect(
              listEquals(actual, expected),
              isTrue,
              reason:
                  'Subsetting must preserve the rendered glyph: $description',
            );
          }
        }
      });
    });
  }
}

Future<void> _loadFont(String family, ByteData bytes) async {
  final loader = FontLoader(family)..addFont(SynchronousFuture(bytes));
  await loader.load();
}

Future<Uint8List> _rasterize(String family, int codepoint, bool sidebar) async {
  final paragraph =
      (ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: family,
                fontSize: 80,
                textDirection: ui.TextDirection.ltr,
              ),
            )
            ..pushStyle(
              ui.TextStyle(
                color: const ui.Color(0xff000000),
                fontVariations: sidebar
                    ? const [
                        ui.FontVariation('wght', 300),
                        ui.FontVariation('FILL', 0),
                        ui.FontVariation('opsz', 20),
                      ]
                    : null,
              ),
            )
            ..addText(String.fromCharCode(codepoint)))
          .build()
        ..layout(const ui.ParagraphConstraints(width: 100));
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawParagraph(paragraph, ui.Offset.zero);
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 100);
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  paragraph.dispose();
  return Uint8List.sublistView(pixels!);
}
