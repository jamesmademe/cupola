import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_animation.dart';

/// Wraps a tappable child with a subtle press-down scale + optional haptic,
/// giving the app a tactile, "alive" feel on touch.
///
/// Use around posters, cards and list rows that navigate or act on tap. Keep
/// the effect gentle ([pressedScale] 0.96, the press role) so it reads as
/// depth, not a bounce.
///
/// Because nearly every tappable card in the app funnels through here, this is
/// also where the button role and label for assistive technology are attached:
/// pass [semanticLabel] and VoiceOver/TalkBack announce the tile as a button
/// with a name instead of an unlabelled image. Set [excludeChildSemantics] when
/// the child's own text would otherwise be read out twice.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Scale applied while pressed. Defaults to the press role's 0.96.
  final double pressedScale;

  /// Whether to fire [HapticFeedback.lightImpact] on tap.
  final bool haptic;

  /// Accessible name announced for this control.
  ///
  /// Supply it whenever the child is visual-only (a poster, an artwork tile);
  /// omit it when the child already renders the text a screen reader needs.
  final String? semanticLabel;

  /// Additional context announced after the label, e.g. "Missing".
  final String? semanticValue;

  /// What activating this does, e.g. 'opens the queue item'.
  ///
  /// Exists so [AppCard] can hand its own `semanticHint` down when it delegates
  /// press feedback here: without it the hint would be dropped silently, which
  /// is the sort of gap only a screen reader notices.
  final String? semanticHint;

  /// Whether to hide the child's own semantics behind [semanticLabel].
  final bool excludeChildSemantics;

  /// Whether the control stands for what is selected beside it (the row whose
  /// page the pane shows), for a screen reader; null says nothing.
  final bool? semanticSelected;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = AppAnimation.pressScale,
    this.haptic = true,
    this.semanticLabel,
    this.semanticValue,
    this.semanticHint,
    this.excludeChildSemantics = false,
    this.semanticSelected,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    if (widget.onTap == null) return;
    if (widget.haptic) HapticFeedback.lightImpact();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    // Honour Reduce Motion: the press-down scale is decoration, so drop it
    // rather than animate it.
    final animate = !MediaQuery.disableAnimationsOf(context);

    final Widget scaled = AnimatedScale(
      scale: _pressed && animate ? widget.pressedScale : 1.0,
      duration: animate ? AppAnimation.press : Duration.zero,
      curve: AppAnimation.standardCurve,
      child: widget.child,
    );

    final Widget detector = GestureDetector(
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTap: enabled ? _handleTap : null,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: scaled,
    );

    // A hint counts as something to publish: the dimmed-but-tappable cell is
    // named by its own child text and carries only a hint, so bailing out on a
    // missing label alone would drop it.
    if (!enabled &&
        widget.semanticLabel == null &&
        widget.semanticHint == null) {
      return detector;
    }

    return Semantics(
      button: enabled,
      container: true,
      enabled: enabled,
      label: widget.semanticLabel,
      value: widget.semanticValue,
      selected: widget.semanticSelected,
      // The hint survives a control that cannot act, and that is the point of
      // it. It used to be gated on `enabled`, which meant the one state where a
      // hint is load-bearing — a control the user can see and cannot use — was
      // the one state that published nothing, and a screen reader landed on a
      // named button with no explanation of why it would not respond. "requires
      // qBittorrent" is exactly that sentence. A sighted user reads the dimming
      // for free; dropping the hint charged a screen-reader user for it.
      hint: widget.semanticHint,
      excludeSemantics: widget.excludeChildSemantics,
      onTap: enabled ? _handleTap : null,
      onLongPress: widget.onLongPress,
      child: detector,
    );
  }
}
