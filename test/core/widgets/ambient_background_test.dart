import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_background.dart';

/// The lamp's current colour, read off the room the widget actually hands
/// its children (and paints) rather than off anything it was handed.
Color _paintedAccent(WidgetTester tester) =>
    tester.widget<AmbientRoom>(find.byType(AmbientRoom)).accent;

Future<void> _pump(
  WidgetTester tester, {
  required Color? accent,
  bool reduceMotion = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: AmbientBackground(accent: accent, child: const SizedBox()),
      ),
    ),
  );
}

void main() {
  group('AmbientBackground', () {
    // The room is one of three instruments that answer a change of subject:
    // the page slides, the ring rotates, the glow becomes the new colour, and
    // cutting the glow while the other two travel is what made the change read
    // as a repaint instead of a move.
    testWidgets('drifts to a new accent instead of cutting to it', (
      tester,
    ) async {
      const from = Color(0xFFF59E0B); // Radarr amber
      const to = Color(0xFF8B5CF6); // Sonarr violet

      await _pump(tester, accent: from);
      await tester.pumpAndSettle();
      expect(_paintedAccent(tester), from);

      await _pump(tester, accent: to);
      await tester.pump(AppAnimation.durationMd ~/ 2);

      final midway = _paintedAccent(tester);
      expect(midway, isNot(from));
      expect(midway, isNot(to), reason: 'it should still be travelling');

      await tester.pumpAndSettle();
      expect(_paintedAccent(tester), to);
    });

    // Reduce Motion **removes** the animator rather than shortening it, which
    // is the rule the rest of the app keeps: with the tween gone the room is
    // simply already the new colour, and every flow stays completable without a
    // single frame of interpolation.
    testWidgets('Reduce Motion arrives seated, not quickly', (tester) async {
      const from = Color(0xFFF59E0B);
      const to = Color(0xFF8B5CF6);

      await _pump(tester, accent: from, reduceMotion: true);
      await tester.pump();
      expect(_paintedAccent(tester), from);

      await _pump(tester, accent: to, reduceMotion: true);
      await tester.pump();
      expect(_paintedAccent(tester), to);

      expect(
        find.byType(TweenAnimationBuilder<Color?>),
        findsNothing,
        reason: 'the animator is removed, not given a shorter duration',
      );
    });

    // The trap this fix had to step around: `accent` is nullable and
    // `ColorTween` asserts on a null `end`, so the brand fallback has to be
    // resolved *before* the tween rather than inside it. A null accent must
    // still paint: it is the default on three of the four onboarding beats and
    // on every screen that has no service of its own.
    testWidgets('a null accent falls back to the neutral lamp', (tester) async {
      // Never the primary: that is the ink now, near-white in the dark room,
      // and a white wash reads as fog, which is what the Portal's bare
      // `AmbientBackground()` painted until the fallback moved to the lamp.
      await _pump(tester, accent: null);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_paintedAccent(tester), AppColors.lamp);
      expect(
        _paintedAccent(tester),
        isNot(AppTheme.darkTheme().colorScheme.primary),
      );
    });

    // Drifting out of and back into the lamp, rather than cutting at the
    // edges of a lit stretch: the same fallback, on the way back.
    testWidgets('drifts back out to the lamp when the accent clears', (
      tester,
    ) async {
      const brand = AppColors.lamp;

      await _pump(tester, accent: const Color(0xFFF59E0B));
      await tester.pumpAndSettle();

      await _pump(tester, accent: null);
      await tester.pump(AppAnimation.durationMd ~/ 2);
      expect(_paintedAccent(tester), isNot(brand));

      await tester.pumpAndSettle();
      expect(_paintedAccent(tester), brand);
    });
  });
}
