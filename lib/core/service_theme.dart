import 'package:flutter/material.dart';

import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The full colour bundle for a single service, derived from its accent.
///
/// Single source of truth for service theming. Screens should read
/// [serviceThemeFor] (or [ServiceTheme.fromAccent]) instead of re-deriving
/// accent containers, gradients and glows locally: a pattern that previously
/// diverged (e.g. the onboarding screen tinted Seerr green instead of indigo).
///
/// **Monochrome.** A service's accent is the neutral lamp now
/// ([ServiceKey.accent]), so the bundle a service gets is the lamp's: a glow
/// that is the room's own light, a soft container that is a neutral wash, and
/// through [onTint], the room's ink wherever a label sits on it. The brand
/// colour is registry data ([ServiceKey.brandAccent]) and is not painted.
@immutable
class ServiceTheme {
  /// The saturated brand accent.
  final Color accent;

  /// Foreground colour that reads legibly on top of [accent].
  final Color onAccent;

  /// Low-alpha accent fill for soft containers (icon backgrounds, chips).
  final Color softContainer;

  const ServiceTheme({
    required this.accent,
    required this.onAccent,
    required this.softContainer,
  });

  /// Builds a [ServiceTheme] from any accent colour.
  factory ServiceTheme.fromAccent(Color accent) {
    return ServiceTheme(
      accent: accent,
      onAccent: foregroundOn(accent),
      softContainer: accent.withValues(
        alpha: DesignTokens.opacityServiceSoftContainer,
      ),
    );
  }

  /// The legible foreground for text or icons sitting on [background].
  ///
  /// Hard-coding white was wrong for the bright accents in this palette: white
  /// on the amber used by Radarr and SABnzbd measures 2.15:1 and on the success
  /// green 2.28:1, both far below WCAG AA, while black on the same fills clears
  /// 9:1. So the two candidate inks are *measured* against the fill and the
  /// winner is returned. A plain luminance threshold is not enough: the
  /// contrast crossover sits near 0.18 relative luminance, so a mid-luminance
  /// accent (Radarr's 0.44 amber, the 0.41 success green) passes any intuitive
  /// cutoff while white on it still fails; which is exactly how a 0.45
  /// threshold shipped white-on-amber buttons at 2.15:1.
  ///
  /// Both candidates go through the same symmetric WCAG ratio. The dark-ink arm
  /// used to hard-code the background as the lighter of the pair, which is a
  /// value the caller can falsify: on a background darker than [_darkInk]
  /// (relative luminance under ~0.013) it yielded a number below 1 rather than
  /// the real ratio. It never picked the wrong ink: white clears ~17:1 down
  /// there and wins either way, but a contrast function that can report a
  /// ratio below 1 is one someone will later read as a measurement.
  static Color foregroundOn(Color background) {
    final luminance = background.computeLuminance();
    final whiteContrast = _contrastBetween(_whiteLuminance, luminance);
    final darkContrast = _contrastBetween(_darkInkLuminance, luminance);
    return darkContrast >= whiteContrast ? _darkInk : Colors.white;
  }

  /// gray-900, softer than pure black.
  static const Color _darkInk = DesignTokens.colorInkOnBright;

  /// [_darkInk] never changes, so its luminance is resolved once instead of on
  /// every [foregroundOn] call, each `computeLuminance` is three `pow`s.
  static final double _darkInkLuminance = _darkInk.computeLuminance();

  /// White's relative luminance is 1.0 by definition; named so [foregroundOn]
  /// reads as one comparison between two measured inks.
  static const double _whiteLuminance = 1.0;

  /// A legible label colour for text drawn **on a low-alpha tint of its own
  /// accent**: a selected nav pill, an accent chip, a segment pill.
  ///
  /// This is the second half of DESIGN.md's Luminance Rule, and it is a different
  /// problem from [foregroundOn]. There the accent is an opaque *fill* and the
  /// question is which foreground survives on top of it. Here the accent is the
  /// *text* and the background is a translucent tint of that same accent, so the
  /// surface underneath is part of the contrast calculation: the composite, not
  /// the accent, is what the label is measured against.
  ///
  /// Getting this wrong is invisible in development. Measured against
  /// `surface-light`, Radarr's amber on its own 12% tint comes out around 1.80:1
  /// and the success green around 1.88:1, against a 4.5:1 requirement, while the
  /// identical chips in dark theme measure about 7.7:1 and pass comfortably. A
  /// pill that reads perfectly at night can be effectively invisible in daylight,
  /// which is why checking the dark theme proves nothing about the light one.
  ///
  /// So: keep the accent's hue, and walk its lightness away from the composite
  /// until it clears AA. One code path covers both themes, and it has to:
  /// measured over their own pill tints, the Seerr indigo lands at 3.48:1 in light
  /// **and 3.80:1 in dark**, and the section purple at 3.08:1 and 4.26:1. Dark
  /// theme is more forgiving, not safe: a mid-luminance accent fails there too,
  /// so a "light theme only" fix would have left half the palette failing.
  ///
  /// Bright accents (Radarr's amber, the section cyan) do pass on the first check
  /// in dark and are returned untouched.
  ///
  /// **The lamp is a light, not an ink.** Every service paints the lamp now
  /// ([ServiceKey.accent]), and walking the lamp's grey to 4.6:1 would set every
  /// label that used to be a service's colour in a dim cool grey: below the
  /// room's own tertiary ink in the dark room. A label asked of the lamp is the
  /// room's primary ink instead, the one of the two rooms' inks that measures
  /// higher on the composite: the brand book's rule that a selected or emphasised label is
  /// ink, never a hue. Every other colour (the five tones above all) is walked
  /// exactly as before.
  static Color onTint(
    Color accent, {
    required Color surface,
    required double tintAlpha,
  }) {
    final background = Color.alphaBlend(
      accent.withValues(alpha: tintAlpha),
      surface,
    );

    // The composite is fixed for the whole walk below, so its luminance is
    // measured once and every candidate is compared against that number.
    // Re-deriving it per step cost 24 redundant `pow` triples for a value that
    // cannot change.
    final backgroundLuminance = background.computeLuminance();

    if (accent == lamp) return _roomInkOn(backgroundLuminance);

    if (_contrastAgainst(accent, backgroundLuminance) >= _minBodyContrast) {
      return accent;
    }

    // Direction is derived, not assumed: the same accent has to escape a
    // near-white composite in light theme and a near-black one in dark.
    final darken = backgroundLuminance > 0.5;
    final hsl = HSLColor.fromColor(accent);

    for (var step = 1; step <= _lightnessSteps; step++) {
      final progress = step / _lightnessSteps;
      final lightness = darken
          ? hsl.lightness * (1 - progress)
          : hsl.lightness + (1 - hsl.lightness) * progress;
      final candidate = hsl.withLightness(lightness.clamp(0.0, 1.0)).toColor();

      if (_contrastAgainst(candidate, backgroundLuminance) >=
          _minBodyContrast) {
        return candidate;
      }
    }

    // No point on this hue clears it: a very light tint under a very light
    // accent. Better a legible neutral than a brand-coloured smudge.
    return foregroundOn(background);
  }

  /// The neutral lamp: what every service paints (see [ServiceKey.accent]).
  static const Color lamp = DesignTokens.colorTitleLightFallback;

  /// The dark room's primary ink and the day room's, opaque.
  static const Color _darkRoomInk = DesignTokensDark.colorOnSurface;
  static const Color _dayRoomInk = DesignTokensLight.colorOnSurface;
  static final double _darkRoomInkLuminance = _darkRoomInk.computeLuminance();
  static final double _dayRoomInkLuminance = _dayRoomInk.computeLuminance();

  /// The room's primary ink that reads on a background of
  /// [backgroundLuminance]: whichever of the two rooms' inks measures higher,
  /// which is the dark room's on a dark composite and the day room's on paper.
  static Color _roomInkOn(double backgroundLuminance) {
    final onDark = _contrastBetween(_darkRoomInkLuminance, backgroundLuminance);
    final onDay = _contrastBetween(_dayRoomInkLuminance, backgroundLuminance);
    return onDark >= onDay ? _darkRoomInk : _dayRoomInk;
  }

  /// WCAG AA for body-sized text, with a tenth of a point of headroom.
  ///
  /// 4.6 rather than 4.5 on purpose. The walk steps in 24 increments and stops
  /// at the first candidate that clears the bar, so a hair over the line is the
  /// *expected* result, not the rare one, and every consumer then composites
  /// that answer over something the walk was not told about (a hairline, a
  /// hover wash, a shadow bleeding under a chip). A run that lands at 4.52 is a
  /// run that ships believing it passed and measures 4.4 on the device. The
  /// extra tenth costs at most one more step on the ramp.
  static const double _minBodyContrast = 4.6;

  /// Granularity of the lightness walk. Fine enough to keep the result close to
  /// the original accent, coarse enough to stay cheap in a build method.
  static const int _lightnessSteps = 24;

  /// WCAG contrast of [foreground] against an already-measured background
  /// luminance. Taking the luminance rather than the `Color` lets callers that
  /// compare many foregrounds to one background pay for it once.
  static double _contrastAgainst(
    Color foreground,
    double backgroundLuminance,
  ) => _contrastBetween(foreground.computeLuminance(), backgroundLuminance);

  /// The WCAG ratio itself, over two luminances that are already measured.
  ///
  /// Split out so [foregroundOn] can compare two *constant* inks without paying
  /// `computeLuminance`, three `pow`s each, on every call.
  static double _contrastBetween(double a, double b) {
    final lighter = a > b ? a : b;
    final darker = a > b ? b : a;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Radial glow for a card lit from one corner: the room's light, which for
  /// a service is the neutral lamp.
  RadialGradient get glow => AppGradients.serviceGlow(accent);
}

/// Resolves the [ServiceTheme] for a given service, from [ServiceKey.accent]:
/// the lamp, for every service.
ServiceTheme serviceThemeFor(ServiceKey service) {
  return ServiceTheme.fromAccent(service.accent);
}
