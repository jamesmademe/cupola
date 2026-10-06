import 'package:flutter/material.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/focus_ring.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// A shared row layout for media detail header actions.
///
/// Displays an [expanded] widget that fills remaining space, with an
/// optional [trailing] widget (typically an icon-only button) on the right.
class HeaderActionRow extends StatelessWidget {
  /// The primary widget that fills available horizontal space.
  final Widget expanded;

  /// Optional trailing widget, shown to the right of [expanded].
  final Widget? trailing;

  /// How [expanded] and [trailing] line up when they are different heights.
  ///
  /// Centred by default, because the common case is two controls of the same
  /// height. A row whose trailing carries a caption underneath it passes
  /// [CrossAxisAlignment.start] so the two controls' *tops* align and the
  /// caption hangs below, rather than the caption pushing its button up.
  final CrossAxisAlignment crossAxisAlignment;

  const HeaderActionRow({
    super.key,
    required this.expanded,
    this.trailing,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  /// Minimum touch target for every detail action control.
  ///
  /// 48, not the 42 this used to be. 42 is under *both* platform minimums, and
  /// the app already documents 44 as its floor on the detail back button
  /// (`MediaDetailBackButton.targetSize`) — so the shared constant was two
  /// points below a number the codebase writes down for itself, on a row that
  /// includes Delete. One cross-platform constant has to satisfy the larger of
  /// iOS' 44pt and Android's 48dp, which is 48; and 48 is also the height the
  /// promoted primary action takes, so an action band has one height rather
  /// than two.
  ///
  /// Adjacent targets are separated by [AppSpacing.sm] (8dp) or more.
  ///
  /// 52 now, `size.button-l`: the brand book's primary, which the promoted
  /// action is, and the band keeps one height, so its discs grow with it.
  static const double buttonHeight = DesignTokens.sizeButtonL;

  /// Shared shape for all detail header action buttons: `radius.button` (16),
  /// the large button's, continuous. These are controls, and full or
  /// near-full radius is the metadata shape in this system.
  static final _buttonShape = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(AppRadius.button),
  );

  /// [_buttonShape], ringed in `line.focus` while the keyboard holds it
  /// (`FocusRingBorder`): a style that sets its own shape replaces the
  /// theme's, ring included, so the band draws it itself.
  static WidgetStateProperty<OutlinedBorder> _ringed(BuildContext context) =>
      focusRingShape(_buttonShape, ring: CupolaRoom.of(context).focus);

  static ButtonStyle _filledButtonStyle(
    BuildContext context, {
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? fixedSize,
    Color? foregroundColor,
    Color? backgroundColor,
  }) => FilledButton.styleFrom(
    padding: padding,
    minimumSize: minimumSize,
    fixedSize: fixedSize,
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
  ).copyWith(shape: _ringed(context));

  /// Creates a [ButtonStyle] for icon-only [FilledButton] trailing widgets.
  ///
  /// Produces a [buttonHeight]×[buttonHeight] square button. Pass
  /// [backgroundColor] and [foregroundColor] for variants like error/delete.
  static ButtonStyle iconOnlyButtonStyle(
    BuildContext context, {
    Color? foregroundColor,
    Color? backgroundColor,
  }) => _filledButtonStyle(
    context,
    padding: EdgeInsets.zero,
    minimumSize: const Size(buttonHeight, buttonHeight),
    fixedSize: const Size(buttonHeight, buttonHeight),
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
  );

  /// Creates a [ButtonStyle] for expanded [FilledButton.icon] widgets.
  ///
  /// [minimumSize], never `fixedSize`: a fixed height cannot grow, so a label
  /// that no longer fits is broken *inside the word* — which is how the request
  /// button came to read "Requeste / d" at an accessibility reading size. The
  /// button grows instead.
  static ButtonStyle expandedButtonStyle(
    BuildContext context, {
    Color? foregroundColor,
    Color? backgroundColor,
    Color? disabledForegroundColor,
    Color? disabledBackgroundColor,
  }) => FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    minimumSize: const Size(double.infinity, buttonHeight),
    // Standard density on every platform: the desktop's compact density takes
    // 8 off `minimumSize`, which painted this button 40 tall beside the 48pt
    // discs (`fixedSize`, which density does not touch) — two heights in one
    // band.
    visualDensity: VisualDensity.standard,
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    disabledForegroundColor: disabledForegroundColor,
    disabledBackgroundColor: disabledBackgroundColor,
  ).copyWith(shape: _ringed(context));

  static ButtonStyle tonalIconButtonStyle(
    BuildContext context, {
    required Color foregroundColor,
    required Color backgroundColor,
    required Color borderColor,
  }) => OutlinedButton.styleFrom(
    padding: EdgeInsets.zero,
    minimumSize: const Size(buttonHeight, buttonHeight),
    fixedSize: const Size(buttonHeight, buttonHeight),
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    side: BorderSide(color: borderColor),
  ).copyWith(shape: _ringed(context));

  static ButtonStyle tonalExpandedButtonStyle(
    BuildContext context, {
    required Color foregroundColor,
    required Color backgroundColor,
    required Color borderColor,
  }) => OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    minimumSize: const Size(double.infinity, buttonHeight),
    // See [expandedButtonStyle]: the band keeps one height on the desktop.
    visualDensity: VisualDensity.standard,
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    side: BorderSide(color: borderColor),
  ).copyWith(shape: _ringed(context));

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Expanded(child: expanded),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ],
      ],
    );
  }
}

/// The idle → busy → held-confirmation glyph for a detail action control.
///
/// One implementation, so the morph cannot drift between the promoted primary
/// action and the discs beside it. The confirmation is the best interaction
/// on this surface and it has three moving parts that are easy to lose
/// separately: the spinner has to spin for *this* control's work only, the
/// check has to be held long enough to be seen after the eye comes back from
/// the snackbar ([AppAnimation.confirmationHold], owned by the host's timer),
/// and the check has to say "complete" out loud rather than just being green.
class ActionStateGlyph extends StatelessWidget {
  /// The resting glyph.
  final IconData icon;

  /// Accessible name of the control this glyph fronts. The confirmed state
  /// announces '<label> complete'.
  final String label;

  /// Work for this control is in flight: the glyph becomes a spinner.
  final bool isBusy;

  /// The work just landed: the glyph holds a success check.
  final bool isConfirmed;

  /// Foreground for the idle glyph and the spinner.
  ///
  /// Null inherits the enclosing button's `IconTheme`, which is what keeps a
  /// disabled control's glyph dimmed by Material instead of painted at full
  /// strength.
  final Color? color;

  /// The colour this glyph is drawn *on top of*.
  ///
  /// Only the confirmed state needs it. A success green that reads cleanly on
  /// the near-black surface measures around 1.3:1 on Radarr's amber, so on a
  /// filled accent control the check is resolved through [statusToneColor]
  /// — which keeps the green's hue and walks its lightness until it clears AA
  /// — rather than shipping a tone that is invisible on a third of the
  /// palette. Defaults to `colorScheme.surface`.
  final Color? fill;

  const ActionStateGlyph({
    super.key,
    required this.icon,
    required this.label,
    this.isBusy = false,
    this.isConfirmed = false,
    this.color,
    this.fill,
  });

  /// Glyph size shared by every detail action control.
  static const double glyphSize = 18;

  /// Spinner diameter, two points under [glyphSize] so the stroke's outer edge
  /// lands roughly where the icon's box did and the control does not jump.
  static const double spinnerSize = 16;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final spinnerColor =
        color ?? IconTheme.of(context).color ?? colorScheme.onSurfaceVariant;

    Widget face;
    if (isBusy) {
      face = Semantics(
        key: const ValueKey('busy'),
        label: label,
        child: SizedBox.square(
          dimension: spinnerSize,
          child: CircularProgressIndicator(strokeWidth: 2, color: spinnerColor),
        ),
      );
    } else if (isConfirmed) {
      face = Icon(
        Icons.check_rounded,
        key: const ValueKey('confirmed'),
        size: glyphSize,
        color: statusToneColor(
          colorScheme,
          StatusTone.success,
          surface: fill ?? colorScheme.surface,
        ),
        semanticLabel: '$label complete',
      );
    } else {
      face = Icon(
        icon,
        key: const ValueKey('idle'),
        size: glyphSize,
        color: color,
        semanticLabel: label,
      );
    }

    if (reduceMotion) return face;

    return AnimatedSwitcher(
      duration: AppAnimation.durationSm,
      switchInCurve: AppAnimation.emphasizedCurve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.7, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: face,
    );
  }
}
