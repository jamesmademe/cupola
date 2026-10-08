import 'package:flutter/widgets.dart';

import 'package:cupola/core/app_breakpoints.dart';

/// Centres a screen's content in a reading-width well on a desktop window, and
/// gets out of the way everywhere else.
///
/// A dashboard stretched across a 27-inch display is not more information — it
/// is the same information with the reading line broken and the eye travelling
/// twice as far between a label and its figure. So the content stops growing at
/// a measured width and centres in whatever the rail and the inspector leave.
///
/// Deliberately a *wrapper around the body* rather than something the shell
/// imposes. Two reasons: an app bar, an ambient gradient and a sticky filter bar
/// must stay full-bleed, and the width can be the archetype's own. Most pages
/// take [AppBreakpoints.contentWell], the widest the main well grows on any
/// shell; a page read as one column (an artist's shelf, a search's rows, the
/// calendar's agenda) stops at [AppBreakpoints.readingWell], because its rows
/// stretched wider are a line too long to follow.
class DesktopContentWell extends StatelessWidget {
  const DesktopContentWell({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.contentWell,
    this.topPadding = 0,
  });

  final Widget child;

  /// Widest the content may grow. See the class doc for why this is per-screen.
  final double maxWidth;

  /// Air between the deck and the first thing on the page.
  ///
  /// Zero by default because most bodies already carry their own leading
  /// padding, and doubling it is how a page ends up starting an inch down.
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    if (!AppBreakpoints.isDesktopShell(context)) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// The width the page's well holds its body to, for a bar above the body.
///
/// The bar stays full-bleed, the room's, but what sits on it lines up with
/// the well under it: on a wide window a title at the window's edge over a
/// body centred 200pt in reads as two pages. `AmbientScaffold` puts one
/// around every page, with no width where the page owns the whole window.
class ContentWellScope extends InheritedWidget {
  const ContentWellScope({
    super.key,
    required this.width,
    required super.child,
  });

  /// The well's width, or null where the body is not welled.
  final double? width;

  /// How far a bar [barWidth] wide insets its contents to line them up with
  /// the well: nothing on a touch build, nothing without a well, nothing on a
  /// window no wider than the well.
  static double insetOf(BuildContext context, double barWidth) {
    final width = context
        .dependOnInheritedWidgetOfExactType<ContentWellScope>()
        ?.width;
    if (width == null || !AppBreakpoints.isDesktopShell(context)) return 0;
    return ((barWidth - width) / 2).clamp(0, double.infinity);
  }

  /// Whether a bar here may line up with a well at all, before its width is
  /// known.
  static bool welled(BuildContext context) =>
      AppBreakpoints.isDesktopShell(context) &&
      context.dependOnInheritedWidgetOfExactType<ContentWellScope>()?.width !=
          null;

  @override
  bool updateShouldNotify(ContentWellScope oldWidget) =>
      width != oldWidget.width;
}
