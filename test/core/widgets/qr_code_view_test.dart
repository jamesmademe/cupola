import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/qr_code_view.dart';

const _side = 232.0;

/// 21 modules, the smallest code.
const _short = 'hello';

/// 33 modules: 41 across with its quiet zone, which 232 logical pixels do not
/// divide into a whole logical pixel per module (5, with 27 left over) but
/// 696 device pixels do at 3x (16, with 40 left over).
const _link = 'cupola://invite?v=1&home=http%3A%2F%2F192.168.1.10%3A5055';

QrImage _expected(String data) => QrImage(
  QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
);

/// Where the code sits in the tile, in device pixels: the whole pixels per
/// module, and the whole pixel of the tile it starts on.
({int module, int origin}) _layout(QrImage code, double dpr, [double? side]) {
  final deviceSide = (side ?? _side) * dpr;
  final module = (deviceSide / (code.moduleCount + 8)).floor();
  return (
    module: module,
    origin: ((deviceSide - module * code.moduleCount) / 2).floor(),
  );
}

Future<void> _pump(
  WidgetTester tester,
  String data, {
  double size = _side,
  double dpr = 1,
  ThemeData? theme,
}) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = Size(400 * dpr, 400 * dpr);
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme(),
      home: Material(
        child: Center(
          child: QrCodeView(
            data: data,
            size: size,
            semanticLabel: 'QR code of the invite',
          ),
        ),
      ),
    ),
  );
}

/// The tile as device pixels, at the screen's own density.
Future<({ByteData bytes, int side})> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.descendant(
      of: find.byType(QrCodeView),
      matching: find.byType(RepaintBoundary),
    ),
  );
  late ui.Image image;
  late ByteData bytes;
  await tester.runAsync(() async {
    image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
    bytes = (await image.toByteData())!;
  });
  return (bytes: bytes, side: image.width);
}

({int r, int g, int b, int a}) _at(ByteData bytes, int side, int x, int y) {
  final offset = (y * side + x) * 4;
  return (
    r: bytes.getUint8(offset),
    g: bytes.getUint8(offset + 1),
    b: bytes.getUint8(offset + 2),
    a: bytes.getUint8(offset + 3),
  );
}

bool _isBlack(({int r, int g, int b, int a}) p) =>
    p.r == 0 && p.g == 0 && p.b == 0 && p.a == 255;

bool _isWhite(({int r, int g, int b, int a}) p) =>
    p.r == 255 && p.g == 255 && p.b == 255 && p.a == 255;

/// Every module of [data]'s code is painted dark or light where the layout
/// says, whole pixel by whole pixel: the first, the middle and the last pixel
/// of each, so a module that bleeds into its neighbour or a seam between two
/// that touch is found.
Future<void> _expectPainted(
  WidgetTester tester,
  String data, {
  double size = _side,
}) async {
  final dpr = tester.view.devicePixelRatio;
  final (:bytes, :side) = await _pixels(tester);
  expect(side, (size * dpr).round());

  final code = _expected(data);
  final (:module, :origin) = _layout(code, dpr, size);
  expect(module, greaterThanOrEqualTo(1));
  for (var row = 0; row < code.moduleCount; row++) {
    for (var col = 0; col < code.moduleCount; col++) {
      for (final inner in {0, module ~/ 2, module - 1}) {
        final pixel = _at(
          bytes,
          side,
          origin + col * module + inner,
          origin + row * module + inner,
        );
        expect(
          _isBlack(pixel),
          code.isDark(row, col),
          reason: 'dpr $dpr, module $row,$col, pixel +$inner',
        );
        expect(_isWhite(pixel), !code.isDark(row, col));
      }
    }
  }
}

void main() {
  for (final dpr in [1.0, 2.0, 3.0, 2.625]) {
    testWidgets('it paints the code it was given, a whole device pixel per '
        'module, at ${dpr}x', (tester) async {
      await _pump(tester, _short, dpr: dpr);
      await _expectPainted(tester, _short);

      await _pump(tester, _link, dpr: dpr);
      await _expectPainted(tester, _link);
    });
  }

  testWidgets('a dense code uses the tile the screen gives it', (tester) async {
    // 77 modules, 85 across with its quiet zone. At 3x: 696 device pixels,
    // 8 each. Snapped to a logical pixel it was 2 (6 device pixels), and 22
    // logical pixels of the tile went unused.
    final data = 'cupola://invite?v=1&home=${'a' * 380}';
    expect(_expected(data).moduleCount, 77);

    await _pump(tester, data, dpr: 3);
    expect(_layout(_expected(data), 3).module, 8);
    await _expectPainted(tester, data);

    await _pump(tester, data, dpr: 1);
    expect(_layout(_expected(data), 1).module, 2);
    await _expectPainted(tester, data);
  });

  testWidgets('a screen of another density paints the same widget again', (
    tester,
  ) async {
    await _pump(tester, _link, dpr: 1);
    await _expectPainted(tester, _link);
    expect(_layout(_expected(_link), 1).module, 5);

    await _pump(tester, _link, dpr: 3);
    await _expectPainted(tester, _link);
    expect(_layout(_expected(_link), 3).module, 16);
  });

  testWidgets('a quiet zone of four modules is white all round the code', (
    tester,
  ) async {
    await _pump(tester, _short, dpr: 3);
    final (:bytes, :side) = await _pixels(tester);
    final (:module, :origin) = _layout(_expected(_short), 3);

    expect(origin, greaterThanOrEqualTo(4 * module));
    final lastEdge = origin + 21 * module;
    for (final point in [
      (origin - 1, origin - 1),
      (origin - 1, side ~/ 2),
      (side ~/ 2, origin - 1),
      (lastEdge, side ~/ 2),
      (side ~/ 2, lastEdge),
      (lastEdge, lastEdge),
      (origin - 4 * module, side ~/ 2),
    ]) {
      expect(_isWhite(_at(bytes, side, point.$1, point.$2)), isTrue);
    }
  });

  testWidgets('black on white in the dark room and in the light one', (
    tester,
  ) async {
    for (final theme in [AppTheme.darkTheme(), AppTheme.lightTheme()]) {
      await _pump(tester, _short, theme: theme, dpr: 3);
      final (:bytes, :side) = await _pixels(tester);
      final (:module, :origin) = _layout(_expected(_short), 3);
      // The first module of a finder pattern is always dark.
      expect(
        _isBlack(_at(bytes, side, origin + 1, origin + 1)),
        isTrue,
        reason: '${theme.brightness} room: modules are black',
      );
      expect(
        _isWhite(_at(bytes, side, origin - 2, origin - 2)),
        isTrue,
        reason: '${theme.brightness} room: the tile is white',
      );
      expect(module, greaterThan(1));
    }
  });

  testWidgets('the tile\'s corners are rounded and outside the tile is clear', (
    tester,
  ) async {
    await _pump(tester, _short, dpr: 2);
    final (:bytes, :side) = await _pixels(tester);

    expect(_at(bytes, side, 0, 0).a, 0, reason: 'the corner is cut away');
    expect(
      _isWhite(_at(bytes, side, (AppRadius.md * 2).ceil() + 2, 0)),
      isTrue,
    );
    expect(_isWhite(_at(bytes, side, side ~/ 2, 0)), isTrue);
  });

  testWidgets('the tile is the size it was given, whatever the code', (
    tester,
  ) async {
    await _pump(tester, 'x' * 400, size: 200);
    expect(tester.getSize(find.byType(QrCodeView)), const Size(200, 200));
    await _pump(tester, _short, size: 232);
    expect(tester.getSize(find.byType(QrCodeView)), const Size(232, 232));
  });

  testWidgets('a tile too small for a pixel a module still holds the code', (
    tester,
  ) async {
    // 77 modules need 85 device pixels: a 60 pixel tile cannot give one each.
    final data = 'cupola://invite?v=1&home=${'a' * 380}';
    await _pump(tester, data, size: 60);
    final (:bytes, :side) = await _pixels(tester);

    // Nothing is painted into the quiet zone along the edges, and the tile is
    // not blank: the modules are fractions of a pixel, so grey, not black.
    expect(side, 60);
    for (var i = 20; i < side - 20; i++) {
      for (final edge in [0, 1, side - 3, side - 2, side - 1]) {
        expect(_isWhite(_at(bytes, side, i, edge)), isTrue);
        expect(_isWhite(_at(bytes, side, edge, i)), isTrue);
      }
    }
    var dark = 0;
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        if (_at(bytes, side, x, y).r < 200) dark++;
      }
    }
    expect(dark, greaterThan(300));
  });

  testWidgets('a different payload paints a different code', (tester) async {
    await _pump(tester, _short);
    final first = (await _pixels(tester)).bytes.buffer.asUint8List().toList();

    await _pump(tester, 'goodbye, and thanks for all the fish');
    final second = (await _pixels(tester)).bytes.buffer.asUint8List().toList();

    expect(second, isNot(first));

    // And the same payload again paints the same pixels.
    await _pump(tester, _short);
    final again = (await _pixels(tester)).bytes.buffer.asUint8List().toList();
    expect(again, first);
  });

  testWidgets('a screen reader meets one image, with the label it was given', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _short);

    expect(
      tester.getSemantics(find.byType(QrCodeView)),
      matchesSemantics(label: 'QR code of the invite', isImage: true),
    );
    handle.dispose();
  });
}
