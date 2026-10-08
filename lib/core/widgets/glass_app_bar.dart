import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/desktop_content_well.dart';

/// A near-transparent app-bar surface that lets the page's ambient gradient
/// read continuously behind it — no opaque strip and no hairline border that
/// would visually "cut" the gradient.
///
/// Instead of a flat translucent fill it paints a soft top-anchored scrim that
/// fades to fully transparent: just enough tint under the status bar / title to
/// keep icons and text legible where list content scrolls beneath, while the
/// lower edge blends seamlessly into the background.
///
/// Deliberately does NOT use a [BackdropFilter] blur — a real backdrop blur
/// re-rasterises everything behind it every frame, which visibly janks scroll
/// on screens whose content scrolls under the app bar. The gradient scrim gives
/// the same legibility protection at zero per-frame cost.
class GlassSurface extends StatelessWidget {
  final Widget? child;

  const GlassSurface({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final scrim = colorScheme.surface;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scrim.withValues(alpha: isDark ? 0.55 : 0.6),
            scrim.withValues(alpha: isDark ? 0.28 : 0.32),
            scrim.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: child,
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
    final ground = CupolaRoom.of(context).ground;
    final height = top + AppSpacing.lg;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                ground.withValues(alpha: 0.92),
                ground.withValues(alpha: 0.72),
                ground.withValues(alpha: 0),
              ],
              stops: [0, top / height, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// A transparent [AppBar] with a [GlassSurface] behind it. Drop-in replacement
/// for `AppBar` on screens that sit over an [AmbientBackground], so the app bar
/// frosts the gradient/content instead of painting an opaque strip over it.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
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
  });

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

  Widget _bar({required bool glass}) => AppBar(
    backgroundColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    title: title,
    leading: leading,
    actions: actions,
    centerTitle: centerTitle,
    bottom: bottom,
    toolbarHeight: toolbarHeight,
    automaticallyImplyLeading: automaticallyImplyLeading,
    flexibleSpace: glass ? const GlassSurface() : null,
  );
}
