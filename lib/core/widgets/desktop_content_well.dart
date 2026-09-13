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
/// must stay full-bleed, and the width itself is the archetype's own — the media
/// spine is 1040 because its side track is 300, the library is 1160 because
/// eight 130pt posters and their gaps come to that. One number for all of them
/// would be a number that fits none of them.
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
    if (!AppBreakpoints.isDesktopShell) return child;
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
