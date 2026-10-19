import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/room_art.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/widgets/ambient_background.dart';

/// A [width] by [height] picture of one opaque colour.
RoomArtSource _flat(Color color, {int width = 40, int height = 60}) {
  final rgba = Uint8List(width * height * 4);
  final argb = color.toARGB32();
  for (var i = 0; i < width * height; i++) {
    rgba[i * 4] = argb >> 16 & 0xFF;
    rgba[i * 4 + 1] = argb >> 8 & 0xFF;
    rgba[i * 4 + 2] = argb & 0xFF;
    rgba[i * 4 + 3] = 0xFF;
  }
  return (
    source: 'flat-${color.toARGB32()}',
    pixels: (rgba: rgba, width: width, height: height),
  );
}

/// The colour of the bake's centre texel, unpremultiplied.
Color _centre(Uint8List rgba, int size) {
  final i = (size ~/ 2 * size + size ~/ 2) * 4;
  final a = rgba[i + 3] / 255;
  int c(int k) => (rgba[i + k] / a).round().clamp(0, 255);
  return Color.fromARGB(255, c(0), c(1), c(2));
}

double _linear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// The relative luminance of [art] laid over [ground] as the top of the room
/// lays it: at the picture's opacity, under the lightest scrim.
double _litTop(Color art, Color ground, List<double> scrim) {
  final reach = RoomLightMetrics.opacity * (1 - scrim.first);
  double at(double a, double g) => _linear(g * (1 - reach) + a * reach);
  return 0.2126 * at(art.r, ground.r) +
      0.7152 * at(art.g, ground.g) +
      0.0722 * at(art.b, ground.b);
}

void main() {
  group('bakeRoomArt', () {
    test('crops to the middle square and blurs past its edge', () {
      final art = bakeRoomArt(_flat(const Color(0xFF3366CC)))!;
      // 40 wide: a 40 square, the blur's three sigmas each side.
      final sigma = 40 * RoomLightMetrics.blurFraction;
      expect(art.inset, (sigma * 3).ceil());
      expect(art.size, 40 + 2 * art.inset);
      expect(art.dark, hasLength(art.size * art.size * 4));
      // Whole in the middle, gone at the corner.
      expect(art.dark[(art.size ~/ 2 * art.size + art.size ~/ 2) * 4 + 3], 255);
      expect(art.dark[3], lessThan(8));
    });

    test('nothing to light with a picture smaller than four texels', () {
      expect(bakeRoomArt(_flat(Colors.red, width: 3, height: 3)), isNull);
    });

    // Secondary text sits on the top of a lit room: a white poster may not
    // light it past the ceiling.
    test('the dark room keeps a white poster under the ceiling', () {
      final art = bakeRoomArt(_flat(Colors.white))!;
      final lit = _litTop(
        _centre(art.dark, art.size),
        DesignTokensDark.colorRoomGround,
        RoomLightMetrics.darkScrimAlphas,
      );
      expect(lit, lessThanOrEqualTo(RoomLightMetrics.darkCeiling + 0.01));
      expect(lit, greaterThan(RoomLightMetrics.darkCeiling - 0.03));
    });

    // On paper a dark poster tints the page instead of darkening it.
    test('the day room lifts a black poster to the floor', () {
      final art = bakeRoomArt(_flat(const Color(0xFF101010)))!;
      final lit = _litTop(
        _centre(art.day, art.size),
        DesignTokensLight.colorRoomGround,
        RoomLightMetrics.dayScrimAlphas,
      );
      expect(lit, greaterThanOrEqualTo(RoomLightMetrics.dayFloor - 0.01));
    });

    test('a coloured poster keeps its hue, more saturated', () {
      const teal = Color(0xFF2E7D7A);
      final art = bakeRoomArt(_flat(teal))!;
      final lit = HSVColor.fromColor(_centre(art.dark, art.size));
      final source = HSVColor.fromColor(teal);
      expect((lit.hue - source.hue).abs(), lessThan(8));
      expect(lit.saturation, greaterThan(source.saturation));
    });

    test('the title light carries its picture, and a grey poster has '
        'neither', () async {
      final teal = await titleLightOf(_flat(const Color(0xFF2E7D7A)));
      expect(teal, isNotNull);
      expect(teal!.art, isNotNull);
      expect(teal.art!.source, 'flat-${const Color(0xFF2E7D7A).toARGB32()}');
      expect(await titleLightOf(_flat(const Color(0xFF808080))), isNull);
    });

    test('two bakes of one picture are one light', () {
      final a = bakeRoomArt(_flat(Colors.indigo))!;
      final b = bakeRoomArt(_flat(Colors.indigo))!;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('AmbientBackground with a picture', () {
    Future<void> pump(
      WidgetTester tester,
      RoomArt? art, {
      bool reduceMotion = false,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: AmbientBackground(art: art, child: const SizedBox.expand()),
        ),
      ),
    );

    AmbientRoom room(WidgetTester tester) =>
        tester.widget<AmbientRoom>(find.byType(AmbientRoom));

    testWidgets('comes up over the lamp once decoded', (tester) async {
      final art = bakeRoomArt(_flat(const Color(0xFF8E44AD)))!;
      await pump(tester, null);
      expect(room(tester).picture, isNull);

      await pump(tester, art);
      // The decode is the engine's, outside the test's clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(room(tester).picture, isNotNull);
      expect(room(tester).presence, lessThan(1), reason: 'still coming up');

      await tester.pumpAndSettle();
      expect(room(tester).presence, 1);
    });

    testWidgets('Reduce Motion seats the picture at once', (tester) async {
      final art = bakeRoomArt(_flat(const Color(0xFF27AE60)))!;
      await pump(tester, art, reduceMotion: true);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(room(tester).picture, isNotNull);
      expect(room(tester).presence, 1);
      expect(room(tester).leaving, isNull);
    });

    testWidgets('goes back to the lamp when the title leaves', (tester) async {
      final art = bakeRoomArt(_flat(const Color(0xFFC0392B)))!;
      await pump(tester, art);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(room(tester).picture, isNotNull);

      await pump(tester, null);
      await tester.pump();
      expect(room(tester).picture, isNull);
      expect(room(tester).leaving, isNotNull, reason: 'it fades, not cuts');
      await tester.pumpAndSettle();
      expect(room(tester).leaving, isNull);
    });
  });
}
