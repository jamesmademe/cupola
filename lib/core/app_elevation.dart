import 'package:flutter/material.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';

/// Elevation for Cupola.
///
/// Instead of Material's flat `elevation: n` (which tints the surface), Cupola
/// uses explicit, layered [BoxShadow] stacks: a tight *contact* shadow plus a
/// wide *ambient* one, tuned per brightness. The dark room casts a shadow only
/// from what floats (the bar, sheets, menus, toasts) and from a poster, whose
/// shadow is its own light: resting cards ([level1]) are flat there and lift
/// softly on paper.
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

  /// The floating bar's elevation: the float shadow under the enamel plus a
  /// 1px top highlight that reads as light catching its leading edge.
  ///
  /// Used by the floating navigation bar and the other floating bars.
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

  /// A poster's shadow: its own light, cast down and pulled in.
  ///
  /// [light] is the title's light; until it is derived from the artwork, a
  /// poster casts the neutral lamp. A [lifted] poster, risen under the
  /// pointer, casts it stronger and the lift further down.
  static List<BoxShadow> poster(
    ColorScheme scheme, {
    Color? light,
    bool lifted = false,
  }) {
    final dark = _isDark(scheme);
    final alpha = switch ((dark, lifted)) {
      (true, false) => DesignTokensDark.elevationPosterGlow,
      (true, true) => DesignTokensDark.elevationPosterLifted,
      (false, false) => DesignTokensLight.elevationPosterGlow,
      (false, true) => DesignTokensLight.elevationPosterLifted,
    };
    return [
      BoxShadow(
        color: (light ?? DesignTokens.shadowPosterGlowColor).withValues(
          alpha: alpha,
        ),
        blurRadius: DesignTokens.shadowPosterGlowBlur,
        spreadRadius: DesignTokens.shadowPosterGlowSpread,
        offset: Offset(
          DesignTokens.shadowPosterGlowOffsetX,
          DesignTokens.shadowPosterGlowOffsetY +
              (lifted ? DesignTokens.motionHoverLift : 0),
        ),
      ),
    ];
  }

  /// The hero artwork's shadow: a wide glow of its [light] over a tight contact
  /// shadow.
  static List<BoxShadow> hero(ColorScheme scheme, {Color? light}) {
    final dark = _isDark(scheme);
    return [
      BoxShadow(
        color: (light ?? DesignTokens.shadowHeroGlowColor).withValues(
          alpha: dark
              ? DesignTokensDark.elevationHeroGlow
              : DesignTokensLight.elevationHeroGlow,
        ),
        blurRadius: DesignTokens.shadowHeroGlowBlur,
        spreadRadius: DesignTokens.shadowHeroGlowSpread,
        offset: const Offset(
          DesignTokens.shadowHeroGlowOffsetX,
          DesignTokens.shadowHeroGlowOffsetY,
        ),
      ),
      BoxShadow(
        color: DesignTokens.shadowHeroContactColor.withValues(
          alpha: dark
              ? DesignTokensDark.elevationHeroContact
              : DesignTokensLight.elevationHeroContact,
        ),
        blurRadius: DesignTokens.shadowHeroContactBlur,
        spreadRadius: DesignTokens.shadowHeroContactSpread,
        offset: const Offset(
          DesignTokens.shadowHeroContactOffsetX,
          DesignTokens.shadowHeroContactOffsetY,
        ),
      ),
    ];
  }

  /// What floats over the room: menus, toasts, a popover.
  static List<BoxShadow> float(ColorScheme scheme) {
    final dark = _isDark(scheme);
    return [
      BoxShadow(
        color: DesignTokens.shadowFloatDropColor.withValues(
          alpha: dark
              ? DesignTokensDark.elevationFloatDrop
              : DesignTokensLight.elevationFloatDrop,
        ),
        blurRadius: DesignTokens.shadowFloatDropBlur,
        spreadRadius: DesignTokens.shadowFloatDropSpread,
        offset: const Offset(
          DesignTokens.shadowFloatDropOffsetX,
          DesignTokens.shadowFloatDropOffsetY,
        ),
      ),
    ];
  }

  /// A bottom sheet, lifting off the bottom edge.
  static List<BoxShadow> sheet(ColorScheme scheme) {
    final dark = _isDark(scheme);
    return [
      BoxShadow(
        color: DesignTokens.shadowSheetDropColor.withValues(
          alpha: dark
              ? DesignTokensDark.elevationSheetDrop
              : DesignTokensLight.elevationSheetDrop,
        ),
        blurRadius: DesignTokens.shadowSheetDropBlur,
        spreadRadius: DesignTokens.shadowSheetDropSpread,
        offset: const Offset(
          DesignTokens.shadowSheetDropOffsetX,
          DesignTokens.shadowSheetDropOffsetY,
        ),
      ),
    ];
  }
}
