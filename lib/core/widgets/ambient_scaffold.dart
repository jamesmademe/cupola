import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/desktop_content_well.dart';

/// A [Scaffold] pre-wired for the premium ambient look: an [AmbientBackground]
/// paints the gradient full-bleed and the Scaffold itself is transparent, so the
/// gradient runs continuously behind a transparent/glass app bar (pair with
/// [GlassAppBar]).
///
/// Because the Scaffold background is transparent and the gradient is painted by
/// an ancestor, the app bar band no longer shows a flat opaque surface strip.
/// [extendBodyBehindAppBar] is left `false` by default: the gradient is already
/// continuous behind the (transparent) app bar, so content does not need to be
/// re-padded.
///
/// **Under a bar, content fades into the room instead of being sliced.** The
/// body starts at the bar's lower edge, so a list scrolled up would be cut
/// there, a hard line across a bar that is otherwise glass. With an [appBar],
/// a vertical scroll view whose top is the body's top is covered, over
/// [_UnderBarFade.height] below its edge, by the room itself ([AmbientRoom]):
/// whole at the edge and gone below it, so what passes the edge melts into
/// the light around it with no line and no step. It appears with the first
/// points scrolled, so a list at rest is drawn whole. No blur (the
/// No-Blur-Under-Scroll Rule); the one layer is the fade's own strip, and
/// nothing is repainted while a list scrolls past its first points.
class AmbientScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Color? accent;

  /// See [AmbientBackground.accentDuration].
  final Duration accentDuration;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool resizeToAvoidBottomInset;
  final bool extendBodyBehindAppBar;
  final bool extendBody;

  /// Whether the body is centred in a reading-width well on a desktop window.
  ///
  /// True for every screen, because a dashboard stretched across a 27-inch
  /// display is the same information with the reading line broken; see
  /// [DesktopContentWell]. Pass false only for a body that genuinely owns the
  /// whole window: a full-bleed console, a map, a video surface.
  ///
  /// The app bar and the ambient gradient are never welled: they are the room,
  /// and a room with margins is a card.
  final bool contentWell;

  /// Widest the well may grow, when the archetype's own measure differs.
  ///
  /// Every page takes the default today; a page read as one column draws its
  /// own [AppBreakpoints.readingWell] inside it rather than narrowing this.
  final double contentWellWidth;

  const AmbientScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.accent,
    this.accentDuration = AppAnimation.durationMd,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset = true,
    this.extendBodyBehindAppBar = false,
    this.extendBody = true,
    this.contentWell = true,
    this.contentWellWidth = AppBreakpoints.contentWell,
  });

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      accent: accent,
      accentDuration: accentDuration,
      // The bars stay full-bleed; a `GlassAppBar` reads the well from here to
      // line its title and actions up with the body.
      child: ContentWellScope(
        width: contentWell ? contentWellWidth : null,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: extendBody,
          extendBodyBehindAppBar: extendBodyBehindAppBar,
          appBar: appBar,
          body: _underBar(
            contentWell
                ? DesktopContentWell(maxWidth: contentWellWidth, child: body)
                : body,
          ),
          floatingActionButton: floatingActionButton,
          bottomNavigationBar: bottomNavigationBar,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        ),
      ),
    );
  }

  /// [body], faded at its top edge when there is a bar for it to pass under.
  Widget _underBar(Widget body) => appBar == null || extendBodyBehindAppBar
      ? body
      : _UnderBarFade(child: body);
}

/// The fade at the top of a body under a bar; see [AmbientScaffold].
///
/// Listens to the scroll views under it and remembers, for each, how much of
/// its content lies above its top edge. Where each one is on screen is asked
/// only when the fade is painted, once layout is done.
class _UnderBarFade extends StatefulWidget {
  const _UnderBarFade({required this.child});

  final Widget child;

  /// How far below the edge the fade reaches, and how far a list scrolls
  /// before the fade is whole.
  static const double height = AppSpacing.xl;

  @override
  State<_UnderBarFade> createState() => _UnderBarFadeState();
}

class _UnderBarFadeState extends State<_UnderBarFade> {
  final _edges = _HiddenAbove();

  @override
  void dispose() {
    _edges.dispose();
    super.dispose();
  }

  bool _onNotification(Notification notification) {
    final (metrics, scrollable) = switch (notification) {
      ScrollNotification(:final metrics, :final context) => (metrics, context),
      ScrollMetricsNotification(:final metrics, :final context) => (
        metrics,
        context,
      ),
      _ => (null, null),
    };
    if (metrics == null || scrollable == null) return false;
    if (metrics.axis != Axis.vertical) return false;
    // A list read from the bottom (`reverse`) keeps what is above its top
    // edge at its far end.
    final above = metrics.axisDirection == AxisDirection.down
        ? metrics.extentBefore
        : metrics.extentAfter;
    _edges.record(scrollable, above);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<Notification>(
      onNotification: _onNotification,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: _FadePaint(
              edges: _edges,
              room: AmbientRoom.maybeOf(context),
              roomBox: context
                  .getElementForInheritedWidgetOfExactType<AmbientRoom>(),
              ground: CupolaRoom.of(context).ground,
            ),
          ),
        ],
      ),
    );
  }
}

/// How strongly each scroll view under a bar is faded, from 0 at rest to 1
/// once [_UnderBarFade.height] of it has gone above its edge. Says so only
/// when a strength changes, so a long scroll repaints nothing.
class _HiddenAbove extends ChangeNotifier {
  final Map<BuildContext, double> strength = {};

  void record(BuildContext scrollable, double above) {
    final next = (above / _UnderBarFade.height).clamp(0.0, 1.0);
    final previous = strength[scrollable] ?? 0;
    if (next == previous) return;
    // A list that has left the page leaves nothing behind.
    strength.removeWhere((other, _) => !other.mounted);
    if (next == 0) {
      strength.remove(scrollable);
    } else {
      strength[scrollable] = next;
    }
    notifyListeners();
  }
}

class _FadePaint extends LeafRenderObjectWidget {
  const _FadePaint({
    required this.edges,
    required this.room,
    required this.roomBox,
    required this.ground,
  });

  final _HiddenAbove edges;

  /// The room the fade paints, and where its box is: null only outside an
  /// [AmbientBackground], where the fade falls back to the flat [ground].
  final AmbientRoom? room;
  final BuildContext? roomBox;
  final Color ground;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFade(edges, room, roomBox, ground);

  @override
  void updateRenderObject(BuildContext context, _RenderFade renderObject) {
    renderObject
      ..edges = edges
      ..room = room
      ..roomBox = roomBox
      ..ground = ground;
  }
}

/// Paints, over every faded scroll view whose top is this box's top, the
/// room from whole at the edge to nothing below it, across that scroll view's
/// width. A list under a fixed field or a header has its top lower down and
/// is left alone: what covers it there is not a bar.
class _RenderFade extends RenderBox {
  _RenderFade(this._edges, this._room, this._roomBox, this._ground);

  AmbientRoom? _room;
  set room(AmbientRoom? value) {
    if (value?.accent == _room?.accent && value?.scheme == _room?.scheme) {
      _room = value;
      return;
    }
    _room = value;
    markNeedsPaint();
  }

  BuildContext? _roomBox;
  set roomBox(BuildContext? value) {
    if (identical(value, _roomBox)) return;
    _roomBox = value;
    markNeedsPaint();
  }

  _HiddenAbove _edges;
  set edges(_HiddenAbove value) {
    if (identical(value, _edges)) return;
    if (attached) _edges.removeListener(markNeedsPaint);
    _edges = value;
    if (attached) _edges.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  Color _ground;
  set ground(Color value) {
    if (value == _ground) return;
    _ground = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _edges.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _edges.removeListener(markNeedsPaint);
    super.detach();
  }

  // Its own layer: a change of strength repaints the fade, not the page.
  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_edges.strength.isEmpty) return;
    final origin = localToGlobal(Offset.zero);
    final room = _room;
    final roomBox = _roomBox?.findRenderObject();
    final roomRect = roomBox is RenderBox && roomBox.attached && roomBox.hasSize
        ? offset + (roomBox.localToGlobal(Offset.zero) - origin) & roomBox.size
        : null;
    final canvas = context.canvas;
    for (final MapEntry(key: scrollable, value: strength)
        in _edges.strength.entries) {
      if (!scrollable.mounted) continue;
      final box = scrollable.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final at = box.localToGlobal(Offset.zero) - origin;
      if (at.dy.abs() > 0.5) continue;
      final rect =
          offset + Offset(at.dx, 0) &
          Size(box.size.width, _UnderBarFade.height);
      // The strip alone is a layer: the room painted into it, then kept
      // where the fade is.
      canvas.saveLayer(rect, Paint());
      if (room != null && roomRect != null) {
        room.paint(canvas, rect, roomRect);
      } else {
        canvas.drawRect(rect, Paint()..color = _ground);
      }
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.fromRGBO(0, 0, 0, strength),
              Color.fromRGBO(0, 0, 0, 0.55 * strength),
              const Color(0x00000000),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(rect),
      );
      canvas.restore();
    }
  }
}
