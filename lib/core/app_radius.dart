import 'package:flutter/material.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';

/// Corner radii.
///
/// Two vocabularies over one scale: the component radii the room names
/// ([thumb], [chip], [poster], [control], [button], [field], [door], [group],
/// [slab], [sheet], [pill]) and the older ladder ([xs] … [full]), whose steps
/// now resolve to the component radius each one stood for. Corners are drawn
/// continuous (`RoundedSuperellipseBorder`) wherever a shape takes an
/// `OutlinedBorder`; a `BorderRadius` on a `BoxDecoration` stays circular.
class AppRadius {
  AppRadius._();

  /// 0dp - No rounding (sharp corners)
  static const double none = DesignTokens.radiusNone;

  /// 4dp - Subtle curves; progress tracks.
  static const double xs = DesignTokens.radiusXs;

  /// 12dp - Chips, badges and small objects: the [chip] radius.
  static const double sm = DesignTokens.radiusSm;

  /// 14dp - The default for cards, controls, posters, list tiles: the
  /// [control] radius.
  static const double md = DesignTokens.radiusMd;

  /// 16dp - Buttons, fields, banners, grouped settings: the [button] radius.
  static const double lg = DesignTokens.radiusLg;

  /// Fully rounded: the selected-affordance radius (the nav indicator, segment
  /// pills, chips). Every pill is drawn at half its height, so this is larger
  /// than any pill it rounds.
  static const double pill = DesignTokens.radiusPill;

  /// 30dp - The floating navigation bar and sheet tops: the [sheet] radius.
  static const double xl = DesignTokens.radiusXl;

  /// Fully rounded: metadata pills (tags, genres, ratings). The same corner as
  /// [pill].
  static const double full = DesignTokens.radiusFull;

  // --- Component radii ---

  /// 8dp - A row thumbnail (36×54), a checkbox.
  static const double thumb = DesignTokens.radiusThumb;

  /// 12dp - A chip's plate, a tile, a fault chip, a stale band.
  static const double chip = DesignTokens.radiusChip;

  /// 14dp - A poster.
  static const double poster = DesignTokens.radiusPoster;

  /// 14dp - A medium button, a segmented track, a stepper, an icon button.
  static const double control = DesignTokens.radiusControl;

  /// 16dp - A large button, a banner, a toast.
  static const double button = DesignTokens.radiusButton;

  /// 16dp - A text field and the search field.
  static const double field = DesignTokens.radiusField;

  /// 20dp - A door: Discover's entrances, tiles.
  static const double door = DesignTokens.radiusDoor;

  /// 22dp - Grouped rows (settings, record lists).
  static const double group = DesignTokens.radiusGroup;

  /// 26dp - A slab (a section) and a dialog.
  static const double slab = DesignTokens.radiusSlab;

  /// 30dp - A bottom sheet's top corners.
  static const double sheet = DesignTokens.radiusSheet;

  // --- Pre-built BorderRadius ---

  /// BorderRadius for extra small elements
  static final BorderRadius borderRadiusXs = BorderRadius.circular(xs);

  /// BorderRadius for small elements (chips, badges)
  static final BorderRadius borderRadiusSm = BorderRadius.circular(sm);

  /// BorderRadius for medium elements (cards, controls)
  static final BorderRadius borderRadiusMd = BorderRadius.circular(md);

  /// BorderRadius for large elements (buttons, fields, banners)
  static final BorderRadius borderRadiusLg = BorderRadius.circular(lg);

  /// BorderRadius for a selected affordance (nav indicator, segment pills)
  static final BorderRadius borderRadiusPill = BorderRadius.circular(pill);

  /// BorderRadius for fully rounded elements
  static final BorderRadius borderRadiusFull = BorderRadius.circular(full);

  /// BorderRadius for a text field.
  static final BorderRadius borderRadiusField = BorderRadius.circular(field);

  /// BorderRadius for a slab.
  static final BorderRadius borderRadiusSlab = BorderRadius.circular(slab);
}
