import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Daylight legibility, measured rather than assumed.
///
/// The light theme did not fail because anyone chose a bad colour; it failed
/// because every check in the suite measured against `colorScheme.surface` and
/// the app paints text on four different light surfaces. A token verified on
/// one ground says nothing about the other three, and the two that were below
/// AA were below it on exactly the grounds nobody measured — the chip fill and
/// the input fill.
///
/// So every assertion here is a cross product: each ink against **all** the
/// surfaces, each tone at **all** the tint alphas the app uses. And none of
/// them names a hex, deliberately: a byte is not the rule, and the previous
/// test pinned bytes while the rule went unchecked.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// WCAG AA for body text.
const _aa = 4.5;

/// WCAG AA for a graphical object — a glyph, a pip, a bar — with no text of the
/// same colour beside it.
const _aaNonText = 3.0;

void main() {
  final light = AppTheme.lightTheme().colorScheme;
  final dark = AppTheme.darkTheme().colorScheme;

  /// Every light surface the theme paints text on, worst last.
  Map<String, Color> surfacesOf(ColorScheme scheme) => {
    'surface': scheme.surface,
    'surfaceContainerLowest': scheme.surfaceContainerLowest,
    'surfaceContainerLow': scheme.surfaceContainerLow,
    'surfaceContainer': scheme.surfaceContainer,
    'surfaceContainerHigh': scheme.surfaceContainerHigh,
    // The one the old test could not see, and the one both failures were on:
    // `chipTheme.backgroundColor` and `inputDecorationTheme.fillColor` both
    // resolve here, and both label themselves in `onSurfaceVariant`.
    'surfaceContainerHighest': scheme.surfaceContainerHighest,
  };

  group('light ink clears AA on every surface it can land on', () {
    for (final entry in surfacesOf(light).entries) {
      test('onSurfaceVariant on ${entry.key}', () {
        expect(
          _contrast(light.onSurfaceVariant, entry.value),
          greaterThanOrEqualTo(_aa),
        );
      });

      test('dimText on ${entry.key}', () {
        // `CupolaThemeColors.dimText` is handed to every caption in the app
        // with no idea what it lands on, which is precisely why it has to clear
        // the worst case rather than the average one.
        final dim = CupolaThemeColors.defaults(
          brightness: Brightness.light,
          colorScheme: light,
        ).dimText;
        expect(_contrast(dim, entry.value), greaterThanOrEqualTo(_aa));
      });
    }
  });

  group('status tones are legible as ink, in both themes', () {
    // The alphas the app actually draws a tone's own wash at: 0 for a bare
    // glyph or word, and the two badge/pill tints.
    const alphas = [0.0, 0.10, 0.16];

    for (final scheme in [light, dark]) {
      final themeName = scheme.brightness.name;
      for (final tone in StatusTone.values) {
        for (final surfaceEntry in surfacesOf(scheme).entries) {
          for (final alpha in alphas) {
            test(
              '${tone.name} on ${surfaceEntry.key} at $alpha ($themeName)',
              () {
                final ink = statusToneColor(
                  scheme,
                  tone,
                  surface: surfaceEntry.value,
                  tintAlpha: alpha,
                );
                // The ground is the composite the label is really drawn on —
                // the tone's own wash over the surface — not the surface alone.
                // Measuring against the surface is what passed combinations
                // that failed on screen.
                final ground = Color.alphaBlend(
                  statusToneFill(scheme, tone).withValues(alpha: alpha),
                  surfaceEntry.value,
                );
                expect(
                  _contrast(ink, ground),
                  greaterThanOrEqualTo(_aa),
                  reason: '${tone.name} ink on ${surfaceEntry.key} @$alpha',
                );
              },
            );
          }
        }
      }
    }
  });

  test('a tone fill keeps its own byte and is never walked', () {
    // The other half of the rule, and the one that stops the fix from draining
    // the colour out of the app: only ink walks. A fill is a surface and owes
    // nothing on its own — what it owes is measured by whatever sits on it,
    // which the group above checks.
    expect(statusToneFill(light, StatusTone.warning), AppColors.warning);
    expect(statusToneFill(light, StatusTone.success), AppColors.success);
    expect(statusToneFill(light, StatusTone.info), AppColors.info);
    expect(statusToneFill(light, StatusTone.error), light.error);
    expect(statusToneFill(dark, StatusTone.warning), AppColors.warning);
  });

  group('every service accent survives as ink on paper', () {
    for (final service in ServiceKey.values) {
      test('${service.name} through onTint on the hardest light ground', () {
        // `surfaceContainerHigh` is the ground the design walks against in both
        // themes — the lightest card on light, the lightest card on dark.
        final ground = light.surfaceContainerHigh;
        final ink = ServiceTheme.onTint(
          service.accent,
          surface: ground,
          tintAlpha: 0,
        );
        expect(_contrast(ink, ground), greaterThanOrEqualTo(_aa));
      });
    }

    test(
      'most of the palette genuinely needs the walk, so it is not a no-op',
      () {
        // Measured, not assumed: 15 of the 17 accents are under AA as raw ink on
        // the lightest light card, and 6 are under even the 3:1 a bare glyph
        // owes. That is the scale of the problem the walk exists for, and it is
        // why "it looks fine on my machine" was never evidence — every one of
        // these passes comfortably in dark mode.
        //
        // If this ever collapses toward zero, either the palette moved or the
        // walk stopped walking, and a walk that returns its input is
        // indistinguishable from no walk at all until someone opens the app in
        // daylight.
        final ground = light.surfaceContainerHigh;
        final underAa = ServiceKey.values
            .where((service) => _contrast(service.accent, ground) < _aa)
            .length;
        final underGraphical = ServiceKey.values
            .where((service) => _contrast(service.accent, ground) < _aaNonText)
            .length;
        expect(underAa, greaterThanOrEqualTo(12));
        expect(underGraphical, greaterThanOrEqualTo(4));
      },
    );
  });

  test('the light brand ink clears AA on paper', () {
    // `colorScheme.primary` is the most-painted ink in the app after
    // `onSurface`: every text button, every outlined button, the selected nav
    // glyph, `StatusTone.primary`, and the recovery verb on every fault band.
    // Indigo-500 measured 4.06:1 on the scaffold, which is why light takes the
    // next step of the brand's own ramp instead.
    for (final surface in surfacesOf(light).values) {
      expect(_contrast(light.primary, surface), greaterThanOrEqualTo(_aa));
    }
  });

  test('a recovery verb is never painted in the fault tone', () {
    // Rule 2 of the failure grammar, as a token fact: the colour the bands hand
    // their buttons must not be the colour they hand their glyphs. Stated here
    // rather than in a widget test because it is a property of the palette —
    // if these two ever converge, every band in the app breaks the rule at
    // once and no rendering test would obviously catch it.
    expect(
      light.primary,
      isNot(statusToneColor(light, StatusTone.error, surface: light.surface)),
    );
    expect(
      dark.primary,
      isNot(statusToneColor(dark, StatusTone.error, surface: dark.surface)),
    );
  });

  test('the plate palette is the same in both themes', () {
    // Artwork is not palette. A poster stand-in that follows the theme flips
    // from a white rectangle to a dark photograph the instant the image lands,
    // which is the flash the plate tokens exist to prevent — so they are
    // constants, and a brightness-dependent plate is the regression.
    expect(AppColors.plateSurface, AppColors.surfaceContainerHighDark);
    expect(AppColors.plateWell, AppColors.surfaceContainerLowestDark);
    expect(
      _contrast(AppColors.plateInk, AppColors.plateSurface),
      greaterThanOrEqualTo(_aa),
    );
    expect(
      _contrast(AppColors.plateDimInk, AppColors.plateSurface),
      greaterThanOrEqualTo(_aa),
    );
    expect(
      _contrast(AppColors.plateDimInk, AppColors.plateWell),
      greaterThanOrEqualTo(_aa),
    );
    // The dark scaffold's own dim tone is *not* good enough here — 4.20:1 on
    // the plate — which is the whole reason `plateDimInk` is its own token.
    expect(
      _contrast(AppColors.onSurfaceDimDark, AppColors.plateSurface),
      lessThan(_aa),
    );
  });
}
