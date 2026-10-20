import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/theme.dart';

/// A row of posters that a pointer can move: it owns the row's
/// [ScrollController] and hands its heading back and forward ([arrows], for
/// `SectionHeader.rail`).
///
/// A finger swipes a row; a mouse cannot. So where there is a pointer (a
/// desktop, or a tablet with a trackpad or mouse attached) the heading carries
/// ‹ and ›: always there while the row runs past the window, the first one off
/// at the start and the second at the end, never over the posters. A row that
/// fits has none, and neither has a touch screen with nothing pointing at it.
///
/// [builder] lays out the heading and the row: put [controller] on the row's
/// horizontal scroll view and [arrows] (null when there are none) in its
/// heading.
class RailArrows extends StatefulWidget {
  const RailArrows({super.key, required this.builder});

  final Widget Function(
    BuildContext context,
    ScrollController controller,
    Widget? arrows,
  )
  builder;

  /// The scroll of the row whose heading carries the arrows, for a row built
  /// below a heading it does not own (`ServiceOverviewSection.bleed`); null
  /// outside one.
  static ScrollController? controllerOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RailScope>()?.controller;

  /// How much of the visible row one step moves: most of it, so the last
  /// poster cut at the edge comes back whole as the first of the next view.
  static const double step = 0.85;

  @override
  State<RailArrows> createState() => _RailArrowsState();
}

class _RailArrowsState extends State<RailArrows> {
  final _controller = ScrollController();
  final _mouse = RendererBinding.instance.mouseTracker;

  /// Where the row stands: whether it runs past the window, and whether it
  /// is at either end. Null until it first lays out.
  ({bool overflows, bool atStart, bool atEnd})? _place;

  @override
  void initState() {
    super.initState();
    _mouse.addListener(_mouseChanged);
  }

  @override
  void dispose() {
    _mouse.removeListener(_mouseChanged);
    _controller.dispose();
    super.dispose();
  }

  void _mouseChanged() {
    if (mounted) setState(() {});
  }

  bool _read(ScrollMetrics metrics) {
    // Within a pixel of an end counts as there: the last step lands on the
    // extent, a fling settles a fraction off it.
    final place = (
      overflows: metrics.maxScrollExtent > metrics.minScrollExtent,
      atStart: metrics.pixels <= metrics.minScrollExtent + 1,
      atEnd: metrics.pixels >= metrics.maxScrollExtent - 1,
    );
    if (place != _place) setState(() => _place = place);
    return false;
  }

  void _move(int direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target =
        (position.pixels +
                direction * position.viewportDimension * RailArrows.step)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpTo(target);
    } else {
      _controller.animateTo(
        target,
        duration: AppAnimation.standard,
        curve: AppAnimation.standardCurve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pointer = AppBreakpoints.isDesktopPlatform || _mouse.mouseIsConnected;
    final place = _place;
    if (place == null) {
      // The first layout: read where the row stands once it has one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        final position = _controller.position;
        if (position.hasContentDimensions) _read(position);
      });
    }
    final arrows = pointer && place != null && place.overflows
        ? _Arrows(
            back: place.atStart ? null : () => _move(-1),
            forward: place.atEnd ? null : () => _move(1),
          )
        : null;
    // Only the row's own scrolling: a poster inside never scrolls, but a
    // nested list in a builder's heading might.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => n.depth == 0 && _read(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => n.depth == 0 && _read(n.metrics),
        child: _RailScope(
          controller: _controller,
          child: widget.builder(context, _controller, arrows),
        ),
      ),
    );
  }
}

class _RailScope extends InheritedWidget {
  const _RailScope({required this.controller, required super.child});

  final ScrollController controller;

  @override
  bool updateShouldNotify(_RailScope oldWidget) =>
      controller != oldWidget.controller;
}

class _Arrows extends StatelessWidget {
  const _Arrows({required this.back, required this.forward});

  final VoidCallback? back;
  final VoidCallback? forward;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The pointer's alone: Tab walks the posters themselves.
    Widget arrow(IconData icon, VoidCallback? onPressed, String key) =>
        ExcludeFocus(
          child: IconButton(
            key: ValueKey('rail-arrow-$key'),
            onPressed: onPressed,
            icon: Icon(icon),
            iconSize: 22,
            color: colorScheme.onSurface,
            disabledColor: CupolaThemeColors.of(context).dimText,
            style: IconButton.styleFrom(
              minimumSize: const Size.square(44),
              visualDensity: VisualDensity.standard,
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        arrow(Icons.chevron_left_rounded, back, 'back'),
        arrow(Icons.chevron_right_rounded, forward, 'forward'),
      ],
    );
  }
}
