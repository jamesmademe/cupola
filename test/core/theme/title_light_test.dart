/// The title light: derived from the artwork, never picked, and the lamp for
/// artwork with too little chroma (brand book, *The title light*).
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'package:cupola/core/title_light.dart';

/// A 64 × 64 picture: [share] of it in [colour], the rest the black ground.
List<int> _picture(int colour, {double share = 0.6}) {
  const total = 64 * 64;
  final lit = (total * share).round();
  return [for (var i = 0; i < total; i++) i < lit ? colour : 0xFF0A0A0D];
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test(
    'a blue picture lights a blue room, at the tones the brand book names',
    () async {
      final light = await titleLightFromPixels(_picture(0xFF2E6FD8));

      expect(light, isNotNull);
      final hue = Hct.fromInt(0xFF2E6FD8).hue;
      for (final (colour, tone) in [
        (light!.light, 68.0),
        (light.actionFill, 82.0),
        (light.actionInk, 12.0),
        (light.dayPrimary, 40.0),
      ]) {
        final hct = Hct.fromInt(colour.toARGB32());
        expect(hct.tone, closeTo(tone, 1.5));
        expect(hct.hue, closeTo(hue, 6));
      }
      expect(
        Hct.fromInt(light.light.toARGB32()).chroma,
        lessThanOrEqualTo(48.5),
      );
    },
  );

  test('grey artwork has too little chroma: the lamp', () async {
    expect(await titleLightFromPixels(_picture(0xFF777777)), isNull);
  });

  test('only the black ground and white lettering: the lamp', () async {
    final pixels = [
      ..._picture(0xFFFFFFFF, share: 0.3),
      ..._picture(0xFF000000),
    ];
    expect(await titleLightFromPixels(pixels), isNull);
  });

  test(
    'the ink on the tinted fill reads at 7:1 or better, on every hue',
    () async {
      for (var hue = 0.0; hue < 360; hue += 30) {
        final colour = Hct.from(hue, 60, 50).toInt();
        final light = await titleLightFromPixels(_picture(colour));
        expect(light, isNotNull, reason: 'hue $hue');
        expect(
          _contrast(light!.actionFill, light.actionInk),
          greaterThanOrEqualTo(7),
          reason: 'hue $hue',
        );
        expect(
          _contrast(light.dayPrimary, const Color(0xFFFFFFFF)),
          greaterThanOrEqualTo(4.5),
          reason: 'hue $hue',
        );
      }
    },
  );
}
