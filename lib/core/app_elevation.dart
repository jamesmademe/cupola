import 'package:flutter/material.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';

/// Premium elevation tokens for Cupola.
///
/// Instead of Material's flat `elevation: n` (which tints the surface), Cupola
/// uses explicit, layered [BoxShadow] stacks that read as soft, physical depth:
/// a tight *contact* shadow plus a wide, low-opacity *ambient* shadow. Shadows
/// are tuned per brightness — deeper and darker on dark surfaces, softer on
/// light ones — so cards separate cleanly from the background at every level.
///
/// Usage:
/// ```dart
/// Container(
///   decoration: BoxDecoration(
///     color: colorScheme.surfaceContainer,
///     borderRadius: AppRadius.borderRadiusMd,
///     boxShadow: AppElevation.level2(colorScheme),
///   ),
/// );
/// ```
class AppElevation {
  AppElevation._();

  static bool _isDark(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark;

  /// Subtle lift for resting cards and list rows.
  static List<BoxShadow> level1(ColorScheme scheme) {
    final dark = _isDark(scheme);
    return [
      BoxShadow(
        color: scheme.shadow.withValues(
          alpha: dark
              ? DesignTokensDark.elevationLevel1Contact
              : DesignTokensLight.elevationLevel1Contact,
        ),
        blurRadius: DesignTokens.shadowLevel1ContactBlur,
        spreadRadius: DesignTokens.shadowLevel1ContactSpread,
        offset: const Offset(
          DesignTokens.shadowLevel1ContactOffsetX,
          DesignTokens.shadowLevel1ContactOffsetY,
        ),
      ),
      BoxShadow(
        color: scheme.shadow.withValues(
          alpha: dark
              ? DesignTokensDark.elevationLevel1Ambient
              : DesignTokensLight.elevationLevel1Ambient,
        ),
        blurRadius: DesignTokens.shadowLevel1AmbientBlur,
        spreadRadius: DesignTokens.shadowLevel1AmbientSpread,
        offset: const Offset(
          DesignTokens.shadowLevel1AmbientOffsetX,
          DesignTokens.shadowLevel1AmbientOffsetY,
        ),
      ),
    ];
  }

  /// Standard elevation for posters, feature cards and elevated surfaces.
  static List<BoxShadow> level2(ColorScheme scheme) {
    final dark = _isDark(scheme);
    return [
      BoxShadow(
        color: scheme.shadow.withValues(
          alpha: dark
              ? DesignTokensDark.elevationLevel2Contact
              : DesignTokensLight.elevationLevel2Contact,
        ),
        blurRadius: DesignTokens.shadowLevel2ContactBlur,
        spreadRadius: DesignTokens.shadowLevel2ContactSpread,
        offset: const Offset(
          DesignTokens.shadowLevel2ContactOffsetX,
          DesignTokens.shadowLevel2ContactOffsetY,
        ),
      ),
      BoxShadow(
        color: scheme.shadow.withValues(
          alpha: dark
              ? DesignTokensDark.elevationLevel2Ambient
              : DesignTokensLight.elevationLevel2Ambient,
        ),
        blurRadius: DesignTokens.shadowLevel2AmbientBlur,
        spreadRadius: DesignTokens.shadowLevel2AmbientSpread,
        offset: const Offset(
          DesignTokens.shadowLevel2AmbientOffsetX,
          DesignTokens.shadowLevel2AmbientOffsetY,
        ),
      ),
    ];
  }

  /// Prominent elevation for sheets, popovers and hero surfaces.
  static List<BoxShadow> level3(ColorScheme scheme) {
    final dark = _isDark(scheme);
    return [
      BoxShadow(
        color: scheme.shadow.withValues(
          alpha: dark
              ? DesignTokensDark.elevationLevel3Contact
              : DesignTokensLight.elevationLevel3Contact,
        ),
        blurRadius: DesignTokens.shadowLevel3ContactBlur,
        spreadRadius: DesignTokens.shadowLevel3ContactSpread,
        offset: const Offset(
          DesignTokens.shadowLevel3ContactOffsetX,
          DesignTokens.shadowLevel3ContactOffsetY,
        ),
      ),
      BoxShadow(
        color: scheme.shadow.withValues(
          alpha: dark
              ? DesignTokensDark.elevationLevel3Ambient
              : DesignTokensLight.elevationLevel3Ambient,
        ),
        blurRadius: DesignTokens.shadowLevel3AmbientBlur,
        spreadRadius: DesignTokens.shadowLevel3AmbientSpread,
        offset: const Offset(
          DesignTokens.shadowLevel3AmbientOffsetX,
          DesignTokens.shadowLevel3AmbientOffsetY,
        ),
      ),
    ];
  }

  /// Floating-glass elevation: a deep ambient shadow plus a 1px top highlight
  /// that reads as light catching the leading edge of a blurred surface.
  ///
  /// Used by the floating navigation bar and other backdrop-blurred surfaces.
  static List<BoxShadow> glass(ColorScheme scheme) {
    final dark = _isDark(scheme);
    return [
      BoxShadow(
        color: DesignTokens.shadowGlassAmbientColor.withValues(
          alpha: dark
              ? DesignTokensDark.elevationGlassAmbient
              : DesignTokensLight.elevationGlassAmbient,
        ),
        blurRadius: DesignTokens.shadowGlassAmbientBlur,
        spreadRadius: DesignTokens.shadowGlassAmbientSpread,
        offset: const Offset(
          DesignTokens.shadowGlassAmbientOffsetX,
          DesignTokens.shadowGlassAmbientOffsetY,
        ),
      ),
      BoxShadow(
        color: DesignTokens.shadowGlassHighlightColor.withValues(
          alpha: dark
              ? DesignTokensDark.elevationGlassHighlight
              : DesignTokensLight.elevationGlassHighlight,
        ),
        blurRadius: DesignTokens.shadowGlassHighlightBlur,
        spreadRadius: DesignTokens.shadowGlassHighlightSpread,
        offset: const Offset(
          DesignTokens.shadowGlassHighlightOffsetX,
          DesignTokens.shadowGlassHighlightOffsetY,
        ),
      ),
    ];
  }
}
