import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// A skeleton is a page still loading, and must never look like a page that
/// loaded empty: the block shows on whatever it is drawn on, and the band that
/// sweeps it is light passing over it.
///
/// It was two opaque surface roles: the dark room's highlight was darker than
/// its base, so a shadow swept the block, and the day room's base measured
/// 1.01:1 on the ground.
void main() {
  for (final (name, room) in [
    ('dark', CupolaRoom.dark),
    ('day', CupolaRoom.light),
  ]) {
    group('the $name room', () {
      for (final (ground, under) in [
        ('ground', room.ground),
        ('slab', room.slab),
      ]) {
        test('a block shows on the $ground', () {
          final block = Color.alphaBlend(room.fillSkeleton, under);
          expect(_contrast(block, under), greaterThanOrEqualTo(1.15));
        });

        test('the band is brighter than the block on the $ground', () {
          final block = Color.alphaBlend(room.fillSkeleton, under);
          final band = Color.alphaBlend(room.fillSkeletonGlint, under);
          expect(
            band.computeLuminance(),
            greaterThan(block.computeLuminance()),
          );
        });
      }
    });
  }

  testWidgets('the block paints the room\'s skeleton fills', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const Scaffold(body: ShimmerPlaceholder(height: 20)),
      ),
    );
    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(ShimmerPlaceholder),
        matching: find.byType(Container),
      ),
    );
    final gradient = (box.decoration! as BoxDecoration).gradient!;
    expect(gradient.colors, [
      CupolaRoom.light.fillSkeleton,
      CupolaRoom.light.fillSkeletonGlint,
      CupolaRoom.light.fillSkeleton,
    ]);
  });
}
