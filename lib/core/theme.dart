import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';

/// Builds a [TextStyle] backed by the bundled Inter variable font.
///
/// Every style goes through here so three things are impossible to forget:
/// the `wght` axis (see [AppTheme.interVariations] — a bare [FontWeight] does
/// not reach it), the optical size, and Inter's own tracking.
TextStyle _inter({
  Color? color,
  required double fontSize,
  required FontWeight fontWeight,
  required double height,
  required Brightness brightness,
  double? letterSpacing,
  List<FontFeature>? fontFeatures,
}) {
  return TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontVariations: AppTheme.interVariations(fontWeight, fontSize),
    height: height,
    letterSpacing:
        letterSpacing ?? AppTheme.interTracking(fontSize, brightness),
    fontFeatures: fontFeatures,
  );
}

/// Type-level helpers that have to reach Inter's variable axes.
///
/// These exist because [TextStyle.copyWith] is a trap on a variable font: it
/// will happily change [TextStyle.fontWeight] and leave `fontVariations`
/// pointing at the old weight, so the text keeps rendering at the weight it
/// had. Re-weight through [weight] instead.
extension CupolaTextStyle on TextStyle {
  /// Re-weights this style so the change actually reaches Inter's `wght` axis.
  ///
  /// The bundled Inter is a single variable face registered at weight 400.
  /// Flutter resolves `fontWeight: FontWeight.w800` against that one face,
  /// finds it, and never touches the axis — so the glyphs stay Regular and the
  /// only difference is whatever synthetic emboldening Skia decides to add.
  /// Measured: `w400` through `w900` all lay out to the identical advance
  /// width, while an explicit `wght` variation does not.
  ///
  /// The optical size is carried over rather than recomputed, so re-weighting a
  /// display style does not quietly hand it back the text-size drawing.
  TextStyle weight(FontWeight weight) {
    double? opticalSize;
    final variations = fontVariations;
    if (variations != null) {
      for (final variation in variations) {
        if (variation.axis == 'opsz') {
          opticalSize = variation.value;
          break;
        }
      }
    }
    return copyWith(
      fontWeight: weight,
      fontVariations: [
        FontVariation('wght', weight.value.toDouble()),
        FontVariation(
          'opsz',
          opticalSize ?? AppTheme.opticalSize(fontSize ?? 14),
        ),
      ],
    );
  }

  /// Locks digits to a single advance width.
  ///
  /// The Tabular Rule: anything that updates in place — a transfer rate, a
  /// percentage, a queue count — jitters as it counts with proportional digits.
  TextStyle get tabular =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// Switches a style onto the monospaced family, for code, logs and data.
  ///
  /// Keeps the size, colour and line height it already had — a fingerprint or a
  /// log line still belongs to the role it was set in, it just needs columns
  /// that line up. See [AppTheme.monoFontFamily] for why this is not a literal.
  TextStyle get mono => copyWith(
    fontFamily: AppTheme.monoFontFamily,
    fontFamilyFallback: AppTheme.monoFontFamilyFallback,
    // Inter's axes mean nothing to the platform mono face, and a mono face is
    // already spaced on a fixed advance — tracking it fights the grid.
    fontVariations: const [],
    letterSpacing: 0,
    fontFeatures: const [FontFeature.slashedZero()],
  );
}

/// Seerr-inspired color palette for Cupola
///
/// Colors extracted from Seerr source code (Tailwind config)
/// Provides both dark and light theme variants while maintaining
/// the signature indigo accent color.
class AppColors {
  AppColors._();

  // === SERVICE ACCENTS ===
  static const Color seerr = DesignTokens.colorServiceSeerr;
  static const Color radarr = DesignTokens.colorServiceRadarr;
  static const Color sonarr = DesignTokens.colorServiceSonarr;
  static const Color lidarr = DesignTokens.colorServiceLidarr;
  static const Color qbittorrent = DesignTokens.colorServiceQbittorrent;
  static const Color bazarr = DesignTokens.colorServiceBazarr;
  static const Color truenas = DesignTokens.colorServiceTruenas; // TrueNAS blue
  static const Color dockge = DesignTokens.colorServiceDockge; // Dockge teal
  static const Color prowlarr =
      DesignTokens.colorServiceProwlarr; // Prowlarr orange
  static const Color readarr = DesignTokens.colorServiceReadarr; // Readarr red
  static const Color sabnzbd =
      DesignTokens.colorServiceSabnzbd; // SABnzbd amber/gold
  static const Color nzbget = DesignTokens.colorServiceNzbget; // NZBGet green
  static const Color unraid = DesignTokens.colorServiceUnraid; // Unraid orange
  static const Color jellyfin =
      DesignTokens.colorServiceJellyfin; // Jellyfin purple

  /// Transmission crimson — the brand's red family, walked off its own hex for
  /// the same reason [plex] is walked off Plex gold.
  ///
  /// Transmission's mark is a plain red that lands ΔE 5.3 from [readarr] and
  /// 6.1 from [error]: three near-identical reds, one of which is the alarm
  /// tone. At the 8pt source dot on the merged Recently Added rail, and at the
  /// 18pt glyph on a folded matrix cell, that is not a distinguishable colour —
  /// it is a red smear that could be a book, a torrent, or a failure. Rotating
  /// toward crimson keeps it unmistakably Transmission red while clearing
  /// ΔE 8.8 from the alarm tone and 10.8 from Readarr. For reference, the
  /// tightest pair already shipping is [radarr]/[sabnzbd] at ΔE 4.8.
  static const Color transmission = DesignTokens.colorServiceTransmission;

  /// Nginx Proxy Manager vermilion — the brand value, used unchanged.
  ///
  /// Unlike [transmission] and [plex] this one needed no adjustment: it sits
  /// ΔE 9.2 from [prowlarr]'s orange and 8.3 from [error], comfortably above
  /// the palette's existing floor, because it is a *red*-orange and the crowded
  /// band above it ([unraid], [plex], [radarr], [sabnzbd]) is amber.
  static const Color nginxProxyManager =
      DesignTokens.colorServiceNginxProxyManager;

  /// Plex bronze — deliberately **not** Plex's brand gold `#E5A00D`.
  ///
  /// The brand value is unusable here, and measurably so. In CIE Lab it sits
  /// ΔE 5 from [sabnzbd] and ΔE 8 from the amber-500 [warning] used to be — and
  /// that value was the same byte as [radarr] — so brand gold would have been
  /// the fourth amber in a five-way tie that included the alarm tone. The tie
  /// is two narrower now that [warning] has moved to yellow-400, but brand gold
  /// would still collide with [sabnzbd]. Two consequences,
  /// both fatal: the 8pt source dot on the merged Recently Added rail could not
  /// distinguish a Plex item from a Radarr or SABnzbd one, and the Stream
  /// dashboard's whole focal moment — a transcoding session lighting its reason
  /// in [warning] — would have been invisible against a room lit by the Plex
  /// accent itself.
  ///
  /// This value keeps the brand's hue family (34° against the brand's 41°, so it
  /// still reads as Plex gold) while clearing ΔE 18 from every existing amber
  /// and 20 from the alarm tone. It resolves to 5.05:1 as a label over its own
  /// 14% tint in dark; light theme still goes through `ServiceTheme.onTint`,
  /// which brand gold also required (it measured 1.84:1 there).
  static const Color plex = DesignTokens.colorServicePlex;

  // === NAV SECTION ACCENTS ===
  //
  // One per canonical tab, so the floating nav bar's selected pill actually
  // differs by section. The bar has always taken a per-destination accent and
  // DESIGN.md has always described the pill as carrying "that destination's
  // accent" — but every `NavTab` passed `primary`, so the mechanism existed and
  // never showed a difference.
  //
  // These are **sections, not services**, and the hues are chosen accordingly:
  //
  // - Nothing here may borrow from the status vocabulary (`success`, `warning`,
  //   `error`, `info`). Status is a closed set, and a green or amber pill in
  //   permanent chrome would read as a health signal (The Closed Tone Rule).
  // - Nothing here should be mistaken for a service's identity, so the set stays
  //   in the cool, instrument-panel end of the palette rather than reaching for
  //   the alarm hues.
  // - Services keeps `primary`: it is the app's own colour and the home tab.
  static const Color navDashboard = DesignTokens.colorNavDashboard;
  static const Color navActivity = DesignTokens.colorNavActivity; // cyan-500
  static const Color navSearch = DesignTokens.colorNavSearch; // purple-500
  static const Color navSettings = DesignTokens.colorNavSettings; // teal-500

  // === PRIMARY (Seerr Indigo) ===
  static const Color primary = seerr;
  static const Color primaryDark =
      DesignTokens.colorBrandPrimaryDark; // indigo-600
  static const Color primaryLight =
      DesignTokens.colorBrandPrimaryLight; // indigo-400
  static const Color primaryLighter =
      DesignTokens.colorBrandPrimaryLighter; // indigo-300

  // === DARK THEME SURFACES ===
  // Deep, layered near-black ladder so cards separate cleanly once elevation
  // and shadows are applied. Each step is a genuinely distinct tone.
  static const Color surfaceDark =
      DesignTokensDark.colorSurface; // scaffold base
  static const Color surfaceContainerLowestDark =
      DesignTokensDark.colorSurfaceContainerLowest;
  static const Color surfaceContainerLowDark =
      DesignTokensDark.colorSurfaceContainerLow;
  static const Color surfaceContainerDark =
      DesignTokensDark.colorSurfaceContainer;
  static const Color surfaceContainerHighDark =
      DesignTokensDark.colorSurfaceContainerHigh;
  static const Color surfaceContainerHighestDark =
      DesignTokensDark.colorSurfaceContainerHighest;

  // === LIGHT THEME SURFACES ===
  static const Color surfaceLight = DesignTokensLight.colorSurface;
  static const Color surfaceContainerLight =
      DesignTokensLight.colorSurfaceContainer;
  static const Color surfaceContainerHighLight =
      DesignTokensLight.colorSurfaceContainerHigh;
  static const Color surfaceContainerHighestLight =
      DesignTokensLight.colorSurfaceContainerHighest;

  // === PLATE (artwork stand-ins) ===
  //
  // The one region of the app that does **not** follow the theme. A plate
  // stands in for artwork — a poster that has not loaded, an album with no
  // cover, the letterboxed well a backdrop sits in — and artwork is not
  // palette. A missing poster rendered as a white rectangle on the light theme
  // does not read as "art that is not here yet", it reads as a hole in the
  // layout; and the instant the real image arrives the well flips from white to
  // a dark photograph, which is the flash the plate exists to prevent.
  //
  // So these are the dark ladder's own bytes, painted in both brightnesses.
  // They were discovered independently once already — the Dockge log panel
  // pinned itself to a near-black literal with the same reasoning written out
  // beside it — which is the argument for naming them here instead of letting
  // each surface rediscover them.
  static const Color plateSurface = DesignTokens.colorPlateSurface;
  static const Color plateWell = DesignTokens.colorPlateWell;
  static const Color plateOutline = DesignTokens.colorPlateOutline;
  static const Color plateInk = DesignTokens.colorPlateInk;

  /// The plate's secondary ink.
  ///
  /// Not [onSurfaceDimDark]: that tone is spaced against the dark *scaffold*
  /// and measures 4.20:1 on [plateSurface], which is below AA on the very
  /// surface a plate's caption sits on. This is one step brighter and clears it
  /// at 5.49:1 on [plateSurface] and 7.02:1 on [plateWell].
  static const Color plateDimInk = DesignTokens.colorPlateDimInk;

  /// Fill behind a selected segment/chip in light mode.
  ///
  /// Deliberately further from `surfaceLight` than the container tokens: a
  /// selected state has to be visible at a glance, and 1.03:1 was not.
  static const Color selectedContainerLight =
      DesignTokensLight.colorSecondaryContainer;

  // === TEXT COLORS - DARK ===
  static const Color onSurfaceDark = DesignTokensDark.colorOnSurface;
  static const Color onSurfaceVariantDark =
      DesignTokensDark.colorOnSurfaceVariant; // brighter secondary
  static const Color onSurfaceDimDark =
      DesignTokensDark.colorDimText; // dimmer tertiary

  // === TEXT COLORS - LIGHT ===
  //
  // Spaced against the **worst paper surface the theme actually paints text
  // on**, not against the scaffold. That distinction is the whole correction
  // here: the previous pair (`#5A6273` / `#656C7B`) was measured on
  // `surfaceLight` alone, where they read 5.56:1 and 4.79:1 and looked safe —
  // but `surfaceContainerHighest` (#E2E4EA) is the chip fill and the input
  // fill, both of which carry `onSurfaceVariant` as their label, and there the
  // dim tone measured **4.15:1**, below AA, on every chip and every text field
  // placeholder in light mode. A contrast token verified on one ground is a
  // token that is wrong on the others.
  //
  // The replacements clear AA on all four light surfaces — paper, white, high
  // and highest — with room to spare: onVariant 6.87 / 7.56 / 6.70 / 5.94, and
  // dim 5.49 / 6.04 / 5.35 / 4.75. The two-step hierarchy between them is
  // preserved, and both stay neutral grays so nothing reads as tinted.
  static const Color onSurfaceLight =
      DesignTokensLight.colorOnSurface; // gray-900
  static const Color onSurfaceVariantLight =
      DesignTokensLight.colorOnSurfaceVariant; // 5.94:1 worst
  static const Color onSurfaceDimLight =
      DesignTokensLight.colorDimText; // 4.75:1 worst

  // === OUTLINE / BORDER ===
  static const Color outlineDark = DesignTokensDark.colorOutline;
  static const Color outlineVariantDark = DesignTokensDark.colorOutlineVariant;
  static const Color outlineLight = DesignTokensLight.colorOutline;
  static const Color outlineVariantLight =
      DesignTokensLight.colorOutlineVariant;

  // === SEMANTIC COLORS ===
  static const Color success = DesignTokens.colorStatusSuccess; // green-500
  static const Color successContainer =
      DesignTokens.colorStatusSuccessContainer; // green-800
  /// The fault tone — yellow-400, and deliberately not amber-500.
  ///
  /// It used to be `#F59E0B`, which is the **same byte** as [radarr]. A fault
  /// chip and a service accent that cannot be told apart is not a near miss:
  /// the whole tone rule rests on amber meaning "something is wrong", and on a
  /// Radarr surface every accent-coloured thing on the page was already wearing
  /// the alarm colour. Moving it is the cheapest way to make the rule true.
  ///
  /// Measured in CIE Lab the new value clears ΔE 18.1 from [sabnzbd] gold — the
  /// nearest accent in the palette — and 25.7 from [radarr]; nothing else is
  /// under 40. It stays a warmer yellow than any of them, so the *word* amber
  /// in the tone vocabulary still describes what the eye sees.
  static const Color warning = DesignTokens.colorStatusWarning; // yellow-400
  static const Color error = DesignTokens.colorStatusError; // red-500
  static const Color errorContainer =
      DesignTokens.colorStatusErrorContainer; // red-800
  static const Color info = DesignTokens.colorStatusInfo; // blue-500

  /// The ink a *bright* fill takes, when white loses the measurement.
  ///
  /// gray-900, the same value [ServiceTheme.foregroundOn] returns. It is a
  /// constant here rather than a call so `theme.dart` stays a leaf — importing
  /// `service_theme.dart` would pull a feature file into the palette — and
  /// `theme_test.dart` re-measures every use of it against `foregroundOn`, so
  /// the constant cannot quietly become the wrong answer.
  ///
  /// The three schemes entries it replaces all assumed white and all lost:
  /// on the error red white is 3.76:1 against this ink's 4.71:1, on the success
  /// green 2.28 against 7.79, and on `primaryLight` 2.98 against 5.95. Those
  /// values are what every filled button, badge and checkbox paints its label
  /// in — `filledButtonTheme` reads `colorScheme.onPrimary`, and the rest read
  /// their own pair — so three of the app's filled controls were below AA
  /// everywhere they appeared.
  ///
  /// `onPrimary` is deliberately still white: on brand indigo white measures
  /// 4.47:1 and this ink 3.97:1, so white wins and the brand keeps its
  /// familiar reversed-out label.
  static const Color inkOnBright = DesignTokens.colorInkOnBright;
}

@immutable
class CupolaThemeColors extends ThemeExtension<CupolaThemeColors> {
  final Color statusBadgeBackground;
  final Color statusBadgeForeground;

  /// Dimmer tertiary text tone for editorial captions / metadata, sitting a
  /// step below [ColorScheme.onSurfaceVariant].
  final Color dimText;

  /// Translucent surface used by backdrop-blurred (glass) elements.
  final Color glassSurface;

  /// Brand gradient endpoints (indigo → violet) for accents and marks.
  final Color brandGradientStart;
  final Color brandGradientEnd;

  const CupolaThemeColors({
    required this.statusBadgeBackground,
    required this.statusBadgeForeground,
    required this.dimText,
    required this.glassSurface,
    required this.brandGradientStart,
    required this.brandGradientEnd,
  });

  /// The bundle for [context]'s theme, falling back to [defaults] when the
  /// extension is absent — which happens in any widget test that pumps a bare
  /// `MaterialApp`.
  ///
  /// The fallback is why this is worth a helper: without it every call site
  /// writes `theme.extension<CupolaThemeColors>()?.dimText ?? <something>`, and
  /// the `<something>` is where a dark-theme literal gets in. Eleven files were
  /// skipping the lookup entirely and painting `AppColors.onSurfaceDimDark` in
  /// both themes.
  static CupolaThemeColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<CupolaThemeColors>() ??
        CupolaThemeColors.defaults(
          brightness: theme.brightness,
          colorScheme: theme.colorScheme,
        );
  }

  factory CupolaThemeColors.defaults({
    required Brightness brightness,
    required ColorScheme colorScheme,
  }) {
    final isDark = brightness == Brightness.dark;
    return CupolaThemeColors(
      statusBadgeBackground: colorScheme.surface.withValues(
        alpha: DesignTokens.opacityStatusBadge,
      ),
      statusBadgeForeground: colorScheme.onSurface,
      dimText: isDark
          ? AppColors.onSurfaceDimDark
          : AppColors.onSurfaceDimLight,
      glassSurface: colorScheme.surfaceContainer.withValues(
        alpha: isDark
            ? DesignTokensDark.opacityGlassSurface
            : DesignTokensLight.opacityGlassSurface,
      ),
      brandGradientStart: AppColors.seerr,
      brandGradientEnd: AppColors.sonarr,
    );
  }

  @override
  CupolaThemeColors copyWith({
    Color? statusBadgeBackground,
    Color? statusBadgeForeground,
    Color? dimText,
    Color? glassSurface,
    Color? brandGradientStart,
    Color? brandGradientEnd,
  }) {
    return CupolaThemeColors(
      statusBadgeBackground:
          statusBadgeBackground ?? this.statusBadgeBackground,
      statusBadgeForeground:
          statusBadgeForeground ?? this.statusBadgeForeground,
      dimText: dimText ?? this.dimText,
      glassSurface: glassSurface ?? this.glassSurface,
      brandGradientStart: brandGradientStart ?? this.brandGradientStart,
      brandGradientEnd: brandGradientEnd ?? this.brandGradientEnd,
    );
  }

  @override
  CupolaThemeColors lerp(
    covariant ThemeExtension<CupolaThemeColors>? other,
    double t,
  ) {
    if (other is! CupolaThemeColors) {
      return this;
    }

    return CupolaThemeColors(
      statusBadgeBackground:
          Color.lerp(statusBadgeBackground, other.statusBadgeBackground, t) ??
          statusBadgeBackground,
      statusBadgeForeground:
          Color.lerp(statusBadgeForeground, other.statusBadgeForeground, t) ??
          statusBadgeForeground,
      dimText: Color.lerp(dimText, other.dimText, t) ?? dimText,
      glassSurface:
          Color.lerp(glassSurface, other.glassSurface, t) ?? glassSurface,
      brandGradientStart:
          Color.lerp(brandGradientStart, other.brandGradientStart, t) ??
          brandGradientStart,
      brandGradientEnd:
          Color.lerp(brandGradientEnd, other.brandGradientEnd, t) ??
          brandGradientEnd,
    );
  }
}

/// Material Design 3 Theme configuration for Cupola
class AppTheme {
  AppTheme._();

  /// Bundled app font family declared in pubspec.yaml.
  static const String fontFamily = DesignTokens.typeFamilySans;

  /// Family for code, logs, hashes and anything read in columns.
  ///
  /// **Not** the string `'monospace'`, which is the mistake this token exists to
  /// stop repeating. `'monospace'` is an Android family alias; CoreText has no
  /// family by that name, so on iOS and macOS Flutter finds nothing and falls
  /// back to the proportional system face. That silently rendered Dockge's YAML
  /// editor, its container logs, TrueNAS' JSON diagnostics and — worst — the
  /// certificate fingerprint a user is asked to *compare by eye* in a
  /// proportional font on two of the three targets, which is also a per-OS
  /// divergence the brand explicitly forbids.
  ///
  /// Menlo leads because it is the mono face reliably present on both Apple
  /// platforms; the fallbacks pick the job up everywhere else, ending at the
  /// Android alias.
  static const String monoFontFamily = DesignTokens.typeFamilyMono;

  /// Fallbacks for [monoFontFamily], in resolution order.
  static const List<String> monoFontFamilyFallback =
      DesignTokens.typeFamilyMonoFallback;

  // === VARIABLE AXES ===
  //
  // The bundled Inter.ttf is a variable font exposing `wght` (100–900) and
  // `opsz` (14–32). Both are addressed explicitly: Flutter drives neither from
  // a plain `TextStyle`.

  /// Lower bound of Inter's optical-size axis — the text-reading drawing.
  static const double _opticalSizeMin = 14;

  /// Upper bound of Inter's optical-size axis — the display drawing.
  static const double _opticalSizeMax = 32;

  /// The optical size Inter should be *drawn* at for text rendered at [fontSize].
  ///
  /// Inter's `opsz` axis is not a size, it is a drawing: at 14 the letterforms
  /// are opened up and lightly contrasted for small text, at 32 they tighten and
  /// gain contrast for headlines. The app bundles the axis and, until now, spent
  /// every string on the 14pt drawing — so a 57pt title was set in a face
  /// designed to survive being 14pt. Tracking the authored size is the whole
  /// point of the axis.
  static double opticalSize(double fontSize) =>
      fontSize.clamp(_opticalSizeMin, _opticalSizeMax);

  /// The `wght` + `opsz` pair for Inter at a given weight and size.
  static List<FontVariation> interVariations(
    FontWeight weight,
    double fontSize,
  ) => <FontVariation>[
    FontVariation('wght', weight.value.toDouble()),
    FontVariation('opsz', opticalSize(fontSize)),
  ];

  // === TRACKING ===

  /// Inter's own tracking, in logical pixels, for text at [fontSize].
  ///
  /// The ramp used to carry Material's Baseline tracking table — `+0.5` on
  /// `bodyLarge`, `+0.25` on `bodyMedium`, `+0.5` on the labels. Those values
  /// are specified for Roboto, a narrower face with tighter default fit; on
  /// Inter they read spacey, and the display end of the same ramp had already
  /// been hand-tuned negative, so the ladder was half-designed and half
  /// inherited.
  ///
  /// This is instead Inter's published dynamic-metrics curve — tracking in em as
  /// `-0.0223 + 0.185·e^(-0.1745·size)` — which lands near zero at reading sizes
  /// and around -0.022em at display sizes. It replaces fifteen literals with the
  /// curve they were approximating.
  ///
  /// [brightness] adds a hair of positive tracking on the dark theme only.
  /// Light-on-dark type blooms optically and its counters close up; the standard
  /// compensation is a little more air, tapering away by the headline sizes where
  /// the effect stops mattering. Both themes still end up tighter than the
  /// Roboto values they replace, so nothing gets wider than it was.
  static double interTracking(double fontSize, Brightness brightness) {
    final double em =
        -0.0223 +
        0.185 * math.exp(-0.1745 * fontSize) +
        (brightness == Brightness.dark ? _darkTrackingDelta(fontSize) : 0);
    return em * fontSize;
  }

  /// Dark-theme optical compensation, in em: +0.006 up to 16pt, gone by 24pt.
  static double _darkTrackingDelta(double fontSize) {
    const double maxDelta = 0.006;
    final double taper = ((24 - fontSize) / 8).clamp(0.0, 1.0);
    return maxDelta * taper;
  }

  /// Standardised "eyebrow" / overline style: small, uppercase-tracked label
  /// used above section titles and on onboarding steps. Pair with
  /// `Text(label.toUpperCase(), style: AppTheme.eyebrow(...))`.
  ///
  /// The one style whose tracking is authored rather than derived: it is meant
  /// to be a distinct voice, and +1.4 is what uppercasing at 11pt needs to stop
  /// reading as a cramped acronym. Kept off [interTracking] deliberately.
  static TextStyle eyebrow(Color color) => _inter(
    color: color,
    fontSize: DesignTokens.typeLabelEyebrowFontSize,
    fontWeight: DesignTokens.typeLabelEyebrowFontWeight,
    height: DesignTokens.typeLabelEyebrowLineHeight,
    letterSpacing: DesignTokens.typeLabelEyebrowLetterSpacing,
    brightness: Brightness.dark,
  );

  /// The four roles DESIGN.md's Hierarchy names that the Material ramp has no
  /// slot for.
  ///
  /// They exist because the alternative is what the codebase actually had:
  /// thirty-nine bare `TextStyle(fontSize: …)` literals, mostly across the
  /// desktop shell. A bare `TextStyle` is not a smaller version of a ramp role,
  /// it is a *different* style — it never reaches Inter's `wght` axis, so every
  /// one of those weights rendered as Regular, and it never reaches
  /// [interTracking], so its letter spacing is whatever the face ships with.
  ///
  /// Each takes a [brightness] because Inter's tracking is walked per theme:
  /// the dark delta is why a dark surface traced from light tracking is wrong.
  ///
  /// **Subtitle** (600, 20, -0.3 tracking) — a service's own name in its app
  /// bar. One step under Title because it names the surface the app bar already
  /// put you on, not the surface itself.
  static TextStyle subtitle(Brightness brightness) => _inter(
    fontSize: DesignTokens.typeTitleSubtitleFontSize,
    fontWeight: DesignTokens.typeTitleSubtitleFontWeight,
    height: DesignTokens.typeTitleSubtitleLineHeight,
    letterSpacing: DesignTokens.typeTitleSubtitleLetterSpacing,
    brightness: brightness,
  );

  /// **Panel header** (600, 18) — an `h2` inside a page: a Dockge stack, an NPM
  /// host, a TrueNAS console section. It heads a region, not the whole screen.
  static TextStyle panelHeader(Brightness brightness) => _inter(
    fontSize: DesignTokens.typeTitlePanelHeaderFontSize,
    fontWeight: DesignTokens.typeTitlePanelHeaderFontWeight,
    height: DesignTokens.typeTitlePanelHeaderLineHeight,
    brightness: brightness,
  );

  /// **Row title** (600, 15) — the primary line of a list row that is a *name*
  /// rather than a sentence: a device, a now-playing session, a proxy host.
  static TextStyle rowTitle(Brightness brightness) => _inter(
    fontSize: DesignTokens.typeTitleRowTitleFontSize,
    fontWeight: DesignTokens.typeTitleRowTitleFontWeight,
    height: DesignTokens.typeTitleRowTitleLineHeight,
    brightness: brightness,
  );

  /// **Data** (500, 13, 1.30) — the answer in a row: the title of an attention
  /// item, a queue entry, a table cell.
  ///
  /// It sits *above* Label on purpose. The thing that needs a human must never
  /// be smaller than the word describing it.
  static TextStyle data(Brightness brightness) => _inter(
    fontSize: DesignTokens.typeLabelDataFontSize,
    fontWeight: DesignTokens.typeLabelDataFontWeight,
    height: DesignTokens.typeLabelDataLineHeight,
    brightness: brightness,
  );

  /// The dense chrome styles the desktop shell needs, off the ramp and through
  /// Inter's axes.
  ///
  /// Every one of these used to be a bare `TextStyle(fontSize: …)`, which is a
  /// different thing from a smaller ramp role in two ways that both show. It
  /// never reaches `fontVariations`, so the bundled variable Inter resolves the
  /// requested weight against its single registered face and renders Regular —
  /// the whole shell was asking for w500 and w700 and getting neither. And it
  /// never reaches [interTracking], so its letter spacing is the face default
  /// rather than the walked per-theme value.
  ///
  /// [size] is clamped to 11, which is how DESIGN.md's floor stays *enforced*
  /// rather than asserted: ten runs in the shell were at 9 and 10, including a
  /// nav badge numeral on a badge that had already been grown from 15 to 18dp
  /// specifically so it would not need one.
  static TextStyle chrome(
    BuildContext context, {
    double size = DesignTokens.typeLabelChromeFontSize,
    FontWeight weight = DesignTokens.typeLabelChromeFontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => _inter(
    color: color,
    fontSize: size < DesignTokens.typeLabelChromeFontSize
        ? DesignTokens.typeLabelChromeFontSize
        : size,
    fontWeight: weight,
    height: height ?? DesignTokens.typeLabelChromeLineHeight,
    letterSpacing: letterSpacing,
    brightness: Theme.of(context).brightness,
  );

  // === DARK THEME (Primary) ===
  //
  // Both themes are deliberately fixed. Cupola's palette is part of its
  // identity — per-service accents have to stay recognisable, and the
  // experience is meant to be identical on every OS — so platform dynamic
  // color (Material You) is not harmonised in. The previous signature took a
  // `dynamicColorScheme` it silently ignored, which read as a wiring bug.
  static ThemeData darkTheme() {
    return _buildTheme(
      brightness: Brightness.dark,
      colorScheme: _darkColorScheme,
      navigationBarBackground: AppColors.surfaceContainerDark,
      bottomSheetBackground: _darkColorScheme.surfaceContainer,
      dialogBackground: _darkColorScheme.surfaceContainer,
    );
  }

  // === LIGHT THEME ===
  static ThemeData lightTheme() {
    return _buildTheme(
      brightness: Brightness.light,
      colorScheme: _lightColorScheme,
      navigationBarBackground: _lightColorScheme.surface,
      bottomSheetBackground: _lightColorScheme.surface,
      dialogBackground: _lightColorScheme.surface,
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required ColorScheme colorScheme,
    required Color navigationBarBackground,
    required Color bottomSheetBackground,
    required Color dialogBackground,
  }) {
    final TextTheme textTheme = _buildTextTheme(
      brightness == Brightness.dark
          ? ThemeData.dark().textTheme
          : ThemeData.light().textTheme,
      brightness,
    );
    // Component text comes off the ramp rather than re-declaring sizes: the
    // app-bar title *is* titleLarge at a heavier weight, a button label *is*
    // labelLarge. Restating `fontSize: 22` here is how a component drifts out of
    // the ladder it is supposed to belong to.
    final TextStyle labelLarge = textTheme.labelLarge!;
    final TextStyle labelMedium = textTheme.labelMedium!;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      extensions: [
        CupolaThemeColors.defaults(
          brightness: brightness,
          colorScheme: colorScheme,
        ),
      ],
      textTheme: textTheme,
      scaffoldBackgroundColor: colorScheme.surface,

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge!
            .weight(FontWeight.w700)
            .copyWith(color: colorScheme.onSurface),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),

      // NavigationBar
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navigationBarBackground,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return labelMedium
                .weight(FontWeight.w600)
                .copyWith(color: colorScheme.primary);
          }
          return labelMedium.copyWith(color: colorScheme.onSurfaceVariant);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.primary);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
      ),

      // Card
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusMd),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        labelStyle: labelMedium.copyWith(color: colorScheme.onSurfaceVariant),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusSm),
      ),

      // Buttons keep standard density on every platform. The theme leaves
      // `visualDensity` to Flutter, which picks compact (-2, -2) on the
      // desktop: that took 8 off every button's height and painted Material
      // buttons 32pt tall there, under the 38pt floor for pointer-only
      // controls. The rest of the desktop keeps its compact density.
      //
      // FilledButton
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.standard,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: labelLarge.weight(FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusMd),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceXl,
            vertical: DesignTokens.spaceMd,
          ),
        ),
      ),

      // OutlinedButton
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.standard,
          foregroundColor: colorScheme.primary,
          textStyle: labelLarge.weight(FontWeight.w600),
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusMd),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceXl,
            vertical: DesignTokens.spaceMd,
          ),
        ),
      ),

      // TextButton
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.standard,
          foregroundColor: colorScheme.primary,
          textStyle: labelLarge.weight(FontWeight.w600),
        ),
      ),

      // IconButton: the same floor. Compact density shrank a bare icon button
      // to 32pt on the desktop.
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(visualDensity: VisualDensity.standard),
      ),

      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusMd,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusMd,
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusMd,
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusMd,
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceLg,
          vertical: DesignTokens.spaceMd,
        ),
        hintStyle: textTheme.bodyMedium!.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),

      // BottomSheet
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bottomSheetBackground,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusLg),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium!.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusMd),
      ),

      // ListTile
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceLg,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusMd),
      ),

      // TabBar
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
        labelStyle: labelLarge.weight(FontWeight.w600),
        unselectedLabelStyle: labelLarge,
      ),

      // ProgressIndicator
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),
    );
  }

  // === COLOR SCHEMES ===

  static final ColorScheme _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    // Primary
    primary: DesignTokensDark.colorPrimary,
    onPrimary: DesignTokensDark.colorOnPrimary,
    primaryContainer: DesignTokensDark.colorPrimaryContainer,
    onPrimaryContainer: DesignTokensDark.colorOnPrimaryContainer,
    // Secondary (same as primary for unified look)
    secondary: DesignTokensDark.colorSecondary,
    onSecondary: DesignTokensDark.colorOnSecondary,
    secondaryContainer: DesignTokensDark.colorSecondaryContainer,
    onSecondaryContainer: DesignTokensDark.colorOnSecondaryContainer,
    // Tertiary
    tertiary: DesignTokensDark.colorTertiary,
    onTertiary: DesignTokensDark.colorOnTertiary,
    tertiaryContainer: DesignTokensDark.colorTertiaryContainer,
    onTertiaryContainer: DesignTokensDark.colorOnTertiaryContainer,
    // Error
    error: DesignTokensDark.colorError,
    onError: DesignTokensDark.colorOnError,
    errorContainer: DesignTokensDark.colorErrorContainer,
    onErrorContainer: DesignTokensDark.colorOnErrorContainer,
    // Surface
    surface: DesignTokensDark.colorSurface,
    onSurface: DesignTokensDark.colorOnSurface,
    surfaceContainerLowest: DesignTokensDark.colorSurfaceContainerLowest,
    surfaceContainerLow: DesignTokensDark.colorSurfaceContainerLow,
    surfaceContainer: DesignTokensDark.colorSurfaceContainer,
    surfaceContainerHigh: DesignTokensDark.colorSurfaceContainerHigh,
    surfaceContainerHighest: DesignTokensDark.colorSurfaceContainerHighest,
    onSurfaceVariant: DesignTokensDark.colorOnSurfaceVariant,
    // Outline
    outline: DesignTokensDark.colorOutline,
    outlineVariant: DesignTokensDark.colorOutlineVariant,
    // Other
    shadow: DesignTokensDark.colorShadow,
    scrim: DesignTokensDark.colorScrim,
    inverseSurface: DesignTokensDark.colorInverseSurface,
    onInverseSurface: DesignTokensDark.colorOnInverseSurface,
    inversePrimary: DesignTokensDark.colorInversePrimary,
  );

  static final ColorScheme _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    // Primary
    //
    // Indigo-600 on paper, not the indigo-500 the dark scheme uses, and this is
    // the one place the brand shifts a byte between themes. The reason is that
    // `primary` is overwhelmingly an **ink** here — every `TextButton` and
    // `OutlinedButton` label, the selected navigation glyph, the recovery verb
    // on a fault band, `StatusTone.primary`, and thirty-odd `color:
    // colorScheme.primary` sites — and indigo-500 measures **4.06:1** on the
    // `#F3F4F6` scaffold and 4.47:1 on white. Below AA on the ground it is most
    // often drawn on, on the most-painted ink in the app after `onSurface`.
    //
    // Indigo-600 clears it everywhere on paper: 5.71:1 on the scaffold, 6.29:1
    // on white, 4.95:1 on `surfaceContainerHighest`. As a *fill* it improves
    // too — reversed-out white goes from 4.47:1 to 6.29:1 — so the filled
    // controls follow without a second token. Dark keeps indigo-500, where it
    // already measures comfortably.
    //
    // This is not the tone walk: `statusToneColor` deliberately refuses to walk
    // the brand, because a walked indigo is a repainted brand. Choosing the
    // adjacent step of the brand's own ramp per theme is the design's own
    // answer instead.
    primary: DesignTokensLight.colorPrimary,
    onPrimary: DesignTokensLight.colorOnPrimary,
    primaryContainer: DesignTokensLight.colorPrimaryContainer,
    onPrimaryContainer: DesignTokensLight.colorOnPrimaryContainer,
    // Secondary
    //
    // `secondaryContainer` is what Material paints behind a selected
    // SegmentedButton segment. It used to be surfaceContainerHigh (#F0F1F5),
    // which sits 1.03:1 from `surface` — the selected segment had no visible
    // fill at all, and with onSurfaceVariant as its foreground it read as
    // *less* prominent than the unselected ones. A distinctly tinted container
    // plus full-strength text makes the selected state unmistakable.
    secondary: DesignTokensLight.colorSecondary,
    onSecondary: DesignTokensLight.colorOnSecondary,
    secondaryContainer: DesignTokensLight.colorSecondaryContainer,
    onSecondaryContainer: DesignTokensLight.colorOnSecondaryContainer,
    // Tertiary
    tertiary: DesignTokensLight.colorTertiary,
    onTertiary: DesignTokensLight.colorOnTertiary,
    tertiaryContainer: DesignTokensLight.colorTertiaryContainer,
    onTertiaryContainer: DesignTokensLight.colorOnTertiaryContainer,
    // Error
    error: DesignTokensLight.colorError,
    onError: DesignTokensLight.colorOnError,
    errorContainer: DesignTokensLight.colorErrorContainer,
    onErrorContainer: DesignTokensLight.colorOnErrorContainer,
    // Surface
    surface: DesignTokensLight.colorSurface,
    onSurface: DesignTokensLight.colorOnSurface,
    surfaceContainerLowest: DesignTokensLight.colorSurfaceContainerLowest,
    surfaceContainerLow: DesignTokensLight.colorSurfaceContainerLow,
    surfaceContainer: DesignTokensLight.colorSurfaceContainer,
    surfaceContainerHigh: DesignTokensLight.colorSurfaceContainerHigh,
    surfaceContainerHighest: DesignTokensLight.colorSurfaceContainerHighest,
    onSurfaceVariant: DesignTokensLight.colorOnSurfaceVariant,
    // Outline
    outline: DesignTokensLight.colorOutline,
    outlineVariant: DesignTokensLight.colorOutlineVariant,
    // Other
    //
    // Ink, not black. Every `AppElevation` level paints `scheme.shadow`, and on
    // paper a pure-black drop shadow reads as grime under a card rather than as
    // depth — the light ladder is drawn as `rgba(17,24,39, …)` at all three
    // levels. `AppElevation.glass()` is the deliberate exception and hardcodes
    // its own black, so it is unaffected by this line.
    shadow: DesignTokensLight.colorShadow,
    scrim: DesignTokensLight.colorScrim,
    inverseSurface: DesignTokensLight.colorInverseSurface,
    onInverseSurface: DesignTokensLight.colorOnInverseSurface,
    inversePrimary: DesignTokensLight.colorInversePrimary,
  );

  // === TEXT THEME ===

  /// The type ramp.
  ///
  /// Sizes and weights are unchanged; what is new is that the weights actually
  /// render (see [CupolaTextStyle.weight]), that tracking comes from Inter's
  /// own curve rather than Roboto's table ([interTracking]), and that line
  /// height is a decision per role instead of the font file's default.
  ///
  /// On that last point: every style in the app used to inherit Inter's own
  /// 1.21 (ascender 1984 + descender 494 over a 2048 em), from the 57pt display
  /// down to 12pt metadata. One ratio across a 5:1 size range cannot be right at
  /// both ends — it is loose for a headline and cramped for a paragraph. So the
  /// ladder now tightens as it climbs and opens as it falls:
  ///
  /// - **Display and headline** tighten toward the 1.10 floor. Large type needs
  ///   less leading, not proportionally more. The floor is not taste: an
  ///   accented capital reaches ~0.89em above its baseline and a descender
  ///   ~0.21em below, so below 1.10 the acute on one line starts touching the
  ///   `y` on the line above. Media titles arrive from TMDB in every language,
  ///   so that case is real; 1.06 was tried and the collision is visible.
  /// - **Body** opens to 1.45–1.55. This is where prose lives — overviews,
  ///   descriptions, empty-state copy — and light-on-dark text at a wide measure
  ///   wants the most air of anything here. `bodyLarge` is the widest measure and
  ///   gets the most.
  /// - **Labels stay at ~1.22**, near the old default, because labels are chrome:
  ///   they sit in fixed-height pills, badges and cells where extra leading buys
  ///   nothing and costs layout.
  static TextTheme _buildTextTheme(TextTheme base, Brightness brightness) {
    TextStyle style({
      required double size,
      required FontWeight weight,
      required double height,
    }) => _inter(
      fontSize: size,
      fontWeight: weight,
      height: height,
      brightness: brightness,
    );

    return base
        .apply(fontFamily: fontFamily)
        .copyWith(
          // Display — editorial: heaviest weights, tightest leading.
          displayLarge: style(
            size: DesignTokens.typeDisplayLargeFontSize,
            weight: DesignTokens.typeDisplayLargeFontWeight,
            height: DesignTokens.typeDisplayLargeLineHeight,
          ),
          displayMedium: style(
            size: DesignTokens.typeDisplayMediumFontSize,
            weight: DesignTokens.typeDisplayMediumFontWeight,
            height: DesignTokens.typeDisplayMediumLineHeight,
          ),
          displaySmall: style(
            size: DesignTokens.typeDisplaySmallFontSize,
            weight: DesignTokens.typeDisplaySmallFontWeight,
            height: DesignTokens.typeDisplaySmallLineHeight,
          ),
          // Headline — screen-level headings.
          headlineLarge: style(
            size: DesignTokens.typeHeadlineLargeFontSize,
            weight: DesignTokens.typeHeadlineLargeFontWeight,
            height: DesignTokens.typeHeadlineLargeLineHeight,
          ),
          headlineMedium: style(
            size: DesignTokens.typeHeadlineMediumFontSize,
            weight: DesignTokens.typeHeadlineMediumFontWeight,
            height: DesignTokens.typeHeadlineMediumLineHeight,
          ),
          headlineSmall: style(
            size: DesignTokens.typeHeadlineSmallFontSize,
            weight: DesignTokens.typeHeadlineSmallFontWeight,
            height: DesignTokens.typeHeadlineSmallLineHeight,
          ),
          // Title — section headers, card titles, row primaries, KPI values.
          titleLarge: style(
            size: DesignTokens.typeTitleLargeFontSize,
            weight: DesignTokens.typeTitleLargeFontWeight,
            height: DesignTokens.typeTitleLargeLineHeight,
          ),
          titleMedium: style(
            size: DesignTokens.typeTitleMediumFontSize,
            weight: DesignTokens.typeTitleMediumFontWeight,
            height: DesignTokens.typeTitleMediumLineHeight,
          ),
          titleSmall: style(
            size: DesignTokens.typeTitleSmallFontSize,
            weight: DesignTokens.typeTitleSmallFontWeight,
            height: DesignTokens.typeTitleSmallLineHeight,
          ),
          // Body — running text. The only roles set for reading, not for chrome.
          bodyLarge: style(
            size: DesignTokens.typeBodyLargeFontSize,
            weight: DesignTokens.typeBodyLargeFontWeight,
            height: DesignTokens.typeBodyLargeLineHeight,
          ),
          bodyMedium: style(
            size: DesignTokens.typeBodyMediumFontSize,
            weight: DesignTokens.typeBodyMediumFontWeight,
            height: DesignTokens.typeBodyMediumLineHeight,
          ),
          bodySmall: style(
            size: DesignTokens.typeBodySmallFontSize,
            weight: DesignTokens.typeBodySmallFontWeight,
            height: DesignTokens.typeBodySmallLineHeight,
          ),
          // Label — chips, badges, nav, dense metadata. Chrome: leading stays put.
          labelLarge: style(
            size: DesignTokens.typeLabelLargeFontSize,
            weight: DesignTokens.typeLabelLargeFontWeight,
            height: DesignTokens.typeLabelLargeLineHeight,
          ),
          labelMedium: style(
            size: DesignTokens.typeLabelMediumFontSize,
            weight: DesignTokens.typeLabelMediumFontWeight,
            height: DesignTokens.typeLabelMediumLineHeight,
          ),
          labelSmall: style(
            size: DesignTokens.typeLabelSmallFontSize,
            weight: DesignTokens.typeLabelSmallFontWeight,
            height: DesignTokens.typeLabelSmallLineHeight,
          ),
        );
  }
}
