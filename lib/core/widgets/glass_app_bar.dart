import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/desktop_content_well.dart';
import 'package:cupola/core/widgets/page_title.dart';

/// A near-transparent app-bar surface that lets the page's ambient gradient
/// read continuously behind it: no opaque strip and no hairline border that
/// would visually "cut" the gradient.
///
/// Instead of a flat translucent fill it paints a soft top-anchored scrim that
/// fades to fully transparent: just enough tint under the status bar / title to
/// keep icons and text legible where list content scrolls beneath, while the
/// lower edge blends seamlessly into the background.
///
/// Deliberately does NOT use a [BackdropFilter] blur: a real backdrop blur
/// re-rasterises everything behind it every frame, which visibly janks scroll
/// on screens whose content scrolls under the app bar. The gradient scrim gives
/// the same legibility protection at zero per-frame cost.
class GlassSurface extends StatelessWidget {
  final Widget? child;

  const GlassSurface({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The room painted again under the bar, not its flat ground: at rest the
    // glass cannot be seen and a lit room keeps its light up to the top edge.
    final veil = _ScrimPaint(
      alphas: isDark ? const [0.55, 0.28, 0] : const [0.6, 0.32, 0],
      stops: const [0, 0.55, 1],
      room: AmbientRoom.maybeOf(context),
      roomBox: context.getElementForInheritedWidgetOfExactType<AmbientRoom>(),
      ground: CupolaRoom.of(context).ground,
    );
    if (child == null) return IgnorePointer(child: veil);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: IgnorePointer(child: veil)),
        child!,
      ],
    );
  }
}

/// The glass under the status bar, on a page that scrolls beneath it with no
/// bar of its own (the media page, a person's page): a heading passing under
/// the clock fades into the room instead of colliding with it. The room's
/// ground, nearly opaque behind the clock and gone a little below it; no
/// blur, for the reason [GlassSurface] gives. Ignores touches, and draws
/// nothing where there is no top inset.
class StatusBarScrim extends StatelessWidget {
  const StatusBarScrim({super.key});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    if (top <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox(
        height: top + AppSpacing.lg,
        child: _ScrimPaint(
          alphas: const [0.92, 0.72, 0],
          inset: top,
          room: AmbientRoom.maybeOf(context),
          roomBox: context
              .getElementForInheritedWidgetOfExactType<AmbientRoom>(),
          ground: CupolaRoom.of(context).ground,
        ),
      ),
    );
  }
}

/// The scrim itself: the room painted again over what passes under the clock,
/// light and all, so at rest it cannot be seen and a lit room keeps its light
/// up to the top edge. Outside an [AmbientBackground] it is the flat ground.
class _ScrimPaint extends LeafRenderObjectWidget {
  const _ScrimPaint({
    required this.alphas,
    this.stops,
    this.inset,
    required this.room,
    required this.roomBox,
    required this.ground,
  });

  /// How much of the room is painted at each stop, top to bottom.
  final List<double> alphas;

  /// Where the stops are, or null for the scrim under the clock: whole to
  /// [inset], then gone a little below it.
  final List<double>? stops;
  final double? inset;
  final AmbientRoom? room;
  final BuildContext? roomBox;
  final Color ground;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrim(alphas, stops, inset, room, roomBox, ground);

  @override
  void updateRenderObject(BuildContext context, _RenderScrim renderObject) {
    renderObject
      ..alphas = alphas
      ..stops = stops
      ..inset = inset
      ..room = room
      ..roomBox = roomBox
      ..ground = ground;
  }
}

class _RenderScrim extends RenderBox {
  _RenderScrim(
    this._alphas,
    this._stops,
    this._inset,
    this._room,
    this._roomBox,
    this._ground,
  );

  List<double> _alphas;
  set alphas(List<double> value) {
    if (listEquals(value, _alphas)) return;
    _alphas = value;
    markNeedsPaint();
  }

  List<double>? _stops;
  set stops(List<double>? value) {
    if (listEquals(value, _stops)) return;
    _stops = value;
    markNeedsPaint();
  }

  double? _inset;
  set inset(double? value) {
    if (value == _inset) return;
    _inset = value;
    markNeedsPaint();
  }

  AmbientRoom? _room;
  set room(AmbientRoom? value) {
    final same = value != null && _room != null
        ? !value.updateShouldNotify(_room!)
        : identical(value, _room);
    _room = value;
    if (!same) markNeedsPaint();
  }

  BuildContext? _roomBox;
  set roomBox(BuildContext? value) {
    if (identical(value, _roomBox)) return;
    _roomBox = value;
    markNeedsPaint();
  }

  Color _ground;
  set ground(Color value) {
    if (value == _ground) return;
    _ground = value;
    markNeedsPaint();
  }

  // Its own layer: what scrolls under it repaints the page, not the scrim.
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
    final rect = offset & size;
    final canvas = context.canvas;
    final room = _room;
    final roomBox = _roomBox?.findRenderObject();
    canvas.saveLayer(rect, Paint());
    if (room != null &&
        roomBox is RenderBox &&
        roomBox.attached &&
        roomBox.hasSize) {
      final at =
          roomBox.localToGlobal(Offset.zero) - localToGlobal(Offset.zero);
      room.paint(canvas, rect, offset + at & roomBox.size);
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
          colors: [for (final alpha in _alphas) Color.fromRGBO(0, 0, 0, alpha)],
          stops: _stops ?? [0, (_inset ?? 0) / size.height, 1],
        ).createShader(rect),
    );
    canvas.restore();
  }
}

/// A transparent [AppBar] with a [GlassSurface] behind it. Drop-in replacement
/// for `AppBar` on screens that sit over an [AmbientBackground], so the app bar
/// frosts the gradient/content instead of painting an opaque strip over it.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;

  /// The name of a page that says it in the page ([PageTitle]); see
  /// [GlassAppBar.inPage].
  final String? pageTitle;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final PreferredSizeWidget? bottom;
  final double toolbarHeight;
  final bool automaticallyImplyLeading;

  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.centerTitle = false,
    this.bottom,
    this.toolbarHeight = kToolbarHeight,
    this.automaticallyImplyLeading = true,
  }) : pageTitle = null;

  /// The bar of a page that says its name in the page ([PageTitle]), as every
  /// page pushed over a tab does (brand book, *A page's name is in the
  /// page*): at rest only the way back and the page's actions. [pageTitle] comes into it, small, once the page's
  /// heading has scrolled under it, so a long page never loses its name.
  const GlassAppBar.inPage({
    super.key,
    required String this.pageTitle,
    this.leading,
    this.actions,
    this.bottom,
    this.toolbarHeight = kToolbarHeight,
    this.automaticallyImplyLeading = true,
  }) : title = null,
       centerTitle = false;

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    if (!ContentWellScope.welled(context)) return _bar(glass: true);
    // On a desktop window over a welled body the glass stays the room's,
    // full-bleed, and what sits on it moves in to line up with the well.
    return LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          const Positioned.fill(child: GlassSurface()),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ContentWellScope.insetOf(context, box.maxWidth),
            ),
            child: _bar(glass: false),
          ),
        ],
      ),
    );
  }

  Widget _bar({required bool glass}) => Builder(
    builder: (context) => AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      // A pushed room's title in the room's face, as a service room names
      // itself in its band.
      titleTextStyle: AppType.feature.copyWith(
        color: CupolaRoom.of(context).ink,
      ),
      title: switch (pageTitle) {
        final name? => _ScrolledUnderTitle(name: name),
        null => title,
      },
      leading: leading,
      actions: actions,
      centerTitle: centerTitle,
      bottom: bottom,
      toolbarHeight: toolbarHeight,
      automaticallyImplyLeading: automaticallyImplyLeading,
      flexibleSpace: glass ? const GlassSurface() : null,
    ),
  );
}

/// A page's name in its bar once its heading has scrolled under it
/// ([GlassAppBar.inPage]): absent at rest, so the name is said once.
class _ScrolledUnderTitle extends StatelessWidget {
  const _ScrolledUnderTitle({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final under = PageScrollScope.maybeOf(context);
    if (under == null) return const SizedBox.shrink();
    final style = AppType.section.copyWith(color: CupolaRoom.of(context).ink);
    return ValueListenableBuilder<bool>(
      valueListenable: under,
      builder: (context, shown, _) => AnimatedSwitcher(
        duration: AppAnimation.durationSm,
        child: shown
            ? Text(
                name,
                key: const ValueKey('page-title-in-bar'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              )
            // The page's heading names it: the bar says nothing twice.
            : const SizedBox.shrink(),
      ),
    );
  }
}
