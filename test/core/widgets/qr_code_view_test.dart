import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/qr_code_view.dart';

/// The smallest code (21 modules) with its quiet zone is 29 modules across:
/// at 232 the module is a whole 8 pixels and the code sits 4 modules in.
const _short = 'hello';
const _side = 232.0;
const _module = 8;
const _origin = 4 * _module;

QrImage _expected(String data) => QrImage(
  QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
);

Future<void> _pump(
  WidgetTester tester,
  String data, {
  double size = _side,
  ThemeData? theme,
}) => tester.pumpWidget(
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

/// The tile as pixels, `side` by `side`, at one device pixel per logical one.
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
    image = await boundary.toImage();
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

void main() {
  testWidgets('it paints the code it was given, module by module', (
    tester,
  ) async {
    await _pump(tester, _short);
    final (:bytes, :side) = await _pixels(tester);
    expect(side, _side.toInt());

    final code = _expected(_short);
    expect(code.moduleCount, 21);
    for (var row = 0; row < code.moduleCount; row++) {
      for (var col = 0; col < code.moduleCount; col++) {
        // The middle of the module, clear of any edge.
        final pixel = _at(
          bytes,
          side,
          _origin + col * _module + _module ~/ 2,
          _origin + row * _module + _module ~/ 2,
        );
        expect(
          _isBlack(pixel),
          code.isDark(row, col),
          reason: 'module $row,$col',
        );
        expect(_isWhite(pixel), !code.isDark(row, col));
      }
    }
  });

  testWidgets('a quiet zone of four modules is white all round the code', (
    tester,
  ) async {
    await _pump(tester, _short);
    final (:bytes, :side) = await _pixels(tester);

    for (final point in [
      (_origin - 1, _origin - 1),
      (_origin - 1, side ~/ 2),
      (side ~/ 2, _origin - 1),
      (side - _origin, side ~/ 2),
      (side ~/ 2, side - _origin),
      (side - _origin, side - _origin),
    ]) {
      expect(_isWhite(_at(bytes, side, point.$1, point.$2)), isTrue);
    }
  });

  testWidgets('black on white in the dark room and in the light one', (
    tester,
  ) async {
    for (final theme in [AppTheme.darkTheme(), AppTheme.lightTheme()]) {
      await _pump(tester, _short, theme: theme);
      final (:bytes, :side) = await _pixels(tester);
      // The first module of a finder pattern is always dark.
      expect(
        _isBlack(_at(bytes, side, _origin + 1, _origin + 1)),
        isTrue,
        reason: '${theme.brightness} room: modules are black',
      );
      expect(
        _isWhite(_at(bytes, side, _origin - 2, _origin - 2)),
        isTrue,
        reason: '${theme.brightness} room: the tile is white',
      );
    }
  });

  testWidgets('the tile\'s corners are rounded and outside the tile is clear', (
    tester,
  ) async {
    await _pump(tester, _short);
    final (:bytes, :side) = await _pixels(tester);

    expect(_at(bytes, side, 0, 0).a, 0, reason: 'the corner is cut away');
    expect(_isWhite(_at(bytes, side, AppRadius.md.ceil() + 2, 0)), isTrue);
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

  testWidgets('a dense code stays inside its tile', (tester) async {
    // Version 15 and up is 77 modules and more: 85 across with its quiet zone
    // is under 3 pixels a module at 232.
    final data = 'cupola://invite?v=1&home=${'a' * 400}';
    await _pump(tester, data);
    final (:bytes, :side) = await _pixels(tester);

    final code = _expected(data);
    final module = (_side / (code.moduleCount + 8)).floor();
    final origin = ((_side - module * code.moduleCount) / 2).floor();
    expect(module, greaterThanOrEqualTo(2));
    for (var row = 0; row < code.moduleCount; row += 5) {
      for (var col = 0; col < code.moduleCount; col += 5) {
        final pixel = _at(
          bytes,
          side,
          origin + col * module + module ~/ 2,
          origin + row * module + module ~/ 2,
        );
        expect(_isBlack(pixel), code.isDark(row, col), reason: '$row,$col');
      }
    }
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
