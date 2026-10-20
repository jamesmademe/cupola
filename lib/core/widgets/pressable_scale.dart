import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/focus_ring.dart';
import 'package:cupola/core/theme.dart';

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
///
/// It is also where a pointer and a keyboard meet the control. A mouse gets the
/// pointing hand; Tab reaches it, Enter or Space activate it, and while it has
/// the keyboard's focus a ring ([CupolaRoom.focus]) is drawn [ringRadius]
/// around it. A finger never sees the ring: a tap does not focus. What the
/// pointer and keyboard are doing is published below as [PressFeedback], so a
/// poster inside can rise under the pointer and draw the ring on its own
/// corner instead ([PressFeedback.claimRing]).
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

  /// Custom screen-reader actions published on this control's node, for a
  /// child that is silenced by [excludeChildSemantics] and so cannot offer
  /// its own. [AppCard] hands its own down.
  final Map<CustomSemanticsAction, VoidCallback>? customSemanticsActions;

  /// Whether to hide the child's own semantics behind [semanticLabel].
  final bool excludeChildSemantics;

  /// Whether the control stands for what is selected beside it (the row whose
  /// page the pane shows), for a screen reader; null says nothing.
  final bool? semanticSelected;

  /// The corner the focus ring follows, a hair outside the control.
  final BorderRadius ringRadius;

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
    this.customSemanticsActions,
    this.excludeChildSemantics = false,
    this.semanticSelected,
    this.ringRadius = const BorderRadius.all(Radius.circular(AppRadius.md)),
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  final _claims = _RingClaims();

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
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
      child: PressFeedback._(
        hovered: _hovered,
        focused: _focused,
        claims: _claims,
        child: widget.child,
      ),
    );

    final Widget detector = GestureDetector(
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTap: enabled ? _handleTap : null,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        foregroundPainter: _focused
            ? _ControlRing(
                color: CupolaRoom.of(context).focus,
                radius: widget.ringRadius,
                claims: _claims,
              )
            : null,
        child: scaled,
      ),
    );

    // The keyboard's way in. Its own focus semantics stay out: the node
    // below already says button and carries the tap.
    final Widget focusable = FocusableActionDetector(
      enabled: widget.onTap != null,
      includeFocusSemantics: false,
      onShowFocusHighlight: _setFocused,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _handleTap();
            return null;
          },
        ),
      },
      child: detector,
    );

    // The pointer's hand, and the hover a poster rises on. Its own region
    // rather than the detector's hover highlight, which waits for a key on a
    // touch platform: a tablet with a trackpad has a pointer all the same.
    final Widget pointed = widget.onTap == null
        ? focusable
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => _setHovered(true),
            onExit: (_) => _setHovered(false),
            child: focusable,
          );

    // A hint counts as something to publish: the dimmed-but-tappable cell is
    // named by its own child text and carries only a hint, so bailing out on a
    // missing label alone would drop it.
    if (!enabled &&
        widget.semanticLabel == null &&
        widget.semanticHint == null &&
        widget.customSemanticsActions == null) {
      return pointed;
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
      // hint is load-bearing, a control the user can see and cannot use, was
      // the one state that published nothing, and a screen reader landed on a
      // named button with no explanation of why it would not respond. "requires
      // qBittorrent" is exactly that sentence. A sighted user reads the dimming
      // for free; dropping the hint charged a screen-reader user for it.
      hint: widget.semanticHint,
      customSemanticsActions: widget.customSemanticsActions,
      excludeSemantics: widget.excludeChildSemantics,
      onTap: enabled ? _handleTap : null,
      onLongPress: widget.onLongPress,
      child: pointed,
    );
  }
}

/// What the pointer and the keyboard are doing to the nearest
/// [PressableScale]: whether a mouse is over it and whether it holds the
/// keyboard's focus with the ring showing.
///
/// Both are false on a touch screen: hover needs a pointer, and the ring is
/// shown only once a key or a mouse was last used ([FocusHighlightMode]).
class PressFeedback extends InheritedWidget {
  const PressFeedback._({
    required this.hovered,
    required this.focused,
    required _RingClaims claims,
    required super.child,
  }) : _claims = claims;

  /// A mouse or a trackpad's pointer is over the control.
  final bool hovered;

  /// The control holds the keyboard's focus, and the ring should show.
  final bool focused;

  final _RingClaims _claims;

  /// The feedback of the [PressableScale] above [context], or null outside
  /// one.
  static PressFeedback? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PressFeedback>();

  /// Says that a descendant draws the focus ring itself, on its own shape (a
  /// poster, on its corner), so the control does not draw a second one around
  /// the whole tile. Hand the returned callback back when the descendant goes.
  VoidCallback claimRing() {
    _claims.count++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _claims.count--;
    };
  }

  /// Whether this and [other] are the feedback of the same control.
  bool sameControlAs(PressFeedback? other) => other?._claims == _claims;

  @override
  bool updateShouldNotify(PressFeedback oldWidget) =>
      hovered != oldWidget.hovered ||
      focused != oldWidget.focused ||
      _claims != oldWidget._claims;
}

/// How many descendants draw the ring themselves. Read at paint time, after
/// every descendant has built.
class _RingClaims {
  int count = 0;
}

/// The focus ring around the whole control, unless a descendant claimed it.
class _ControlRing extends CustomPainter {
  const _ControlRing({
    required this.color,
    required this.radius,
    required this.claims,
  });

  final Color color;
  final BorderRadius radius;
  final _RingClaims claims;

  @override
  void paint(Canvas canvas, Size size) {
    if (claims.count > 0) return;
    paintFocusRing(canvas, Offset.zero & size, radius: radius, color: color);
  }

  @override
  bool shouldRepaint(_ControlRing oldDelegate) => true;
}
