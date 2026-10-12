import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';

void main() {
  group('AppTheme', () {
    testWidgets('dark theme preserves special-case background colors', (
      tester,
    ) async {
      final theme = AppTheme.darkTheme();

      // The dark room: ground, slab, raised, and the inks and edge flattened
      // on the ground.
      expect(theme.colorScheme.surface, const Color(0xFF0A0A0D));
      expect(theme.colorScheme.surfaceContainer, const Color(0xFF121218));
      expect(theme.colorScheme.surfaceContainerHigh, const Color(0xFF17171D));
      expect(theme.colorScheme.outline, const Color(0xFF232326));
      expect(theme.colorScheme.onSurface, const Color(0xFFF7F6F2));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFFBBBBBC));
      // The chrome is monochrome: the interactive colour is the ink.
      expect(theme.colorScheme.primary, theme.colorScheme.onSurface);
      expect(
        theme.navigationBarTheme.backgroundColor,
        AppColors.surfaceContainerDark,
      );
      // Sheets and dialogs are raised, a step above the slab.
      expect(
        theme.bottomSheetTheme.backgroundColor,
        theme.colorScheme.surfaceContainerHigh,
      );
      expect(
        theme.dialogTheme.backgroundColor,
        theme.colorScheme.surfaceContainerHigh,
      );
    });

    testWidgets('light theme preserves special-case background colors', (
      tester,
    ) async {
      final theme = AppTheme.lightTheme();

      // The day room: paper, white slabs, and the fill and edge flattened.
      expect(theme.colorScheme.surface, const Color(0xFFF6F4EF));
      expect(theme.colorScheme.surfaceContainer, Colors.white);
      expect(theme.colorScheme.surfaceContainerHigh, const Color(0xFFF3F3F3));
      expect(theme.colorScheme.outline, const Color(0xFFDFDDD9));
      expect(theme.colorScheme.onSurface, const Color(0xFF16151A));
      expect(theme.colorScheme.primary, theme.colorScheme.onSurface);
      // `onSurfaceVariant` used to be pinned here to `#5A6273`. It moved to
      // `#4B5563`, because the old value was spaced against `surface` alone and
      // measured 4.82:1 on `surfaceContainerHighest`, which is the chip fill
      // and the input fill, both of which paint this exact token as their
      // label. The hex is no longer asserted anywhere: a byte is not the rule,
      // and pinning one here is what let the real rule go unchecked. See
      // `theme_light_contrast_test.dart`, which measures every light ink
      // against every light surface the theme actually paints.
      expect(
        theme.colorScheme.onSurfaceVariant,
        isNot(theme.colorScheme.onSurface),
      );
      expect(
        theme.navigationBarTheme.backgroundColor,
        theme.colorScheme.surface,
      );
      // Sheets and dialogs are white slabs on paper.
      expect(
        theme.bottomSheetTheme.backgroundColor,
        theme.colorScheme.surfaceContainer,
      );
      expect(
        theme.dialogTheme.backgroundColor,
        theme.colorScheme.surfaceContainer,
      );
    });

    testWidgets('dark theme attaches CupolaThemeColors defaults', (
      tester,
    ) async {
      final theme = AppTheme.darkTheme();

      final colors = theme.extension<CupolaThemeColors>();

      expect(colors, isNotNull);
      expect(
        colors!.statusBadgeBackground,
        theme.colorScheme.surface.withValues(alpha: 0.8),
      );
      expect(colors.statusBadgeForeground, theme.colorScheme.onSurface);
    });

    testWidgets('light theme attaches CupolaThemeColors defaults', (
      tester,
    ) async {
      final theme = AppTheme.lightTheme();

      final colors = theme.extension<CupolaThemeColors>();

      expect(colors, isNotNull);
      expect(
        colors!.statusBadgeBackground,
        theme.colorScheme.surface.withValues(alpha: 0.8),
      );
      expect(colors.statusBadgeForeground, theme.colorScheme.onSurface);
    });

    test('CupolaThemeColors.defaults uses surface scrim and onSurface', () {
      final colorScheme = AppTheme.lightTheme().colorScheme.copyWith(
        surface: const Color(0xFF123456),
        onSurface: const Color(0xFFABCDEF),
      );

      final colors = CupolaThemeColors.defaults(
        brightness: Brightness.light,
        colorScheme: colorScheme,
      );

      expect(
        colors.statusBadgeBackground,
        colorScheme.surface.withValues(alpha: 0.8),
      );
      expect(colors.statusBadgeForeground, colorScheme.onSurface);
    });

    test('service accent colors match the Open Design prototype', () {
      expect(AppColors.seerr, const Color(0xFF6366F1));
      expect(AppColors.radarr, const Color(0xFFF59E0B));
      expect(AppColors.sonarr, const Color(0xFF8B5CF6));
      expect(AppColors.lidarr, const Color(0xFFEC4899));
    });

    // These guard the *reason* the light secondary tones were changed, not just
    // their hex: gray-500 measured 4.39:1 and gray-400 a failing 2.36:1, so
    // secondary and tertiary text was below WCAG AA on every light screen.
    group('contrast', () {
      // `theme.dart` cannot call `ServiceTheme.foregroundOn` without importing a
      // feature file, so the four scheme inks are constants, and this is what
      // stops a constant from being the wrong answer. Every filled control in
      // the app paints its label in one of these pairs.
      test('every filled scheme pair takes the ink that measures better', () {
        for (final scheme in [
          AppTheme.darkTheme().colorScheme,
          AppTheme.lightTheme().colorScheme,
        ]) {
          final pairs = <String, (Color, Color)>{
            'onPrimary': (scheme.onPrimary, scheme.primary),
            'onSecondary': (scheme.onSecondary, scheme.secondary),
            'onTertiary': (scheme.onTertiary, scheme.tertiary),
            'onError': (scheme.onError, scheme.error),
          };
          pairs.forEach((name, pair) {
            final (ink, fill) = pair;
            expect(
              ink,
              ServiceTheme.foregroundOn(fill),
              reason: '$name on ${scheme.brightness.name}',
            );
            expect(
              _contrast(ink, fill),
              greaterThanOrEqualTo(3.0),
              reason: '$name on ${scheme.brightness.name}',
            );
          });
        }
      });

      test('the fault tone is not a service accent', () {
        // `warning` and `radarr` were the same byte, so an accent chip and a
        // fault chip were indistinguishable on every Radarr surface.
        for (final accent in [
          AppColors.radarr,
          AppColors.sabnzbd,
          AppColors.plex,
          AppColors.unraid,
        ]) {
          expect(AppColors.warning, isNot(accent));
          expect(CupolaRoom.light.toneAmber, isNot(accent));
        }
      });

      test('light secondary and tertiary text clear WCAG AA', () {
        final scheme = AppTheme.lightTheme().colorScheme;

        expect(
          _contrast(scheme.onSurfaceVariant, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(AppColors.onSurfaceDimLight, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
        // Tertiary stays visibly lighter than secondary, so the hierarchy that
        // the old values expressed through contrast is preserved.
        expect(
          _contrast(AppColors.onSurfaceDimLight, scheme.surface),
          lessThan(_contrast(scheme.onSurfaceVariant, scheme.surface)),
        );
      });

      test('dark secondary and tertiary text clear WCAG AA', () {
        final scheme = AppTheme.darkTheme().colorScheme;

        expect(
          _contrast(scheme.onSurfaceVariant, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(AppColors.onSurfaceDimDark, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('a selected segment is distinguishable from the surface', () {
        for (final scheme in [
          AppTheme.lightTheme().colorScheme,
          AppTheme.darkTheme().colorScheme,
        ]) {
          // secondaryContainer is the selected-segment fill. It was 1.03:1 from
          // surface in light mode, i.e. invisible.
          expect(
            _contrast(scheme.secondaryContainer, scheme.surface),
            greaterThan(1.1),
          );
          // And its label must be readable on it.
          expect(
            _contrast(scheme.onSecondaryContainer, scheme.secondaryContainer),
            greaterThanOrEqualTo(4.5),
          );
        }
      });
    });
  });
}

/// WCAG 2.1 relative-luminance contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
