import 'package:flutter/material.dart';

import 'package:cupola/core/app_breakpoints.dart';
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
class AmbientScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Color? accent;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool resizeToAvoidBottomInset;
  final bool extendBodyBehindAppBar;
  final bool extendBody;

  /// Whether the body is centred in a reading-width well on a desktop window.
  ///
  /// True for every screen, because a dashboard stretched across a 27-inch
  /// display is the same information with the reading line broken — see
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
      // The bars stay full-bleed; a `GlassAppBar` reads the well from here to
      // line its title and actions up with the body.
      child: ContentWellScope(
        width: contentWell ? contentWellWidth : null,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: extendBody,
          extendBodyBehindAppBar: extendBodyBehindAppBar,
          appBar: appBar,
          body: contentWell
              ? DesktopContentWell(maxWidth: contentWellWidth, child: body)
              : body,
          floatingActionButton: floatingActionButton,
          bottomNavigationBar: bottomNavigationBar,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        ),
      ),
    );
  }
}
