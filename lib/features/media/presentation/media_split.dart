import 'package:flutter/material.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/utils/side_pane_route.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_page.dart';

/// The title a pane shows: who it is, the connection it was opened from, the
/// poster that stands in until the page reads its own, and the tile it was
/// opened from (its hero tag), which the list rings.
typedef MediaPaneTarget = ({
  MediaKey key,
  String? focus,
  String? posterUrl,
  String? heroTag,
});

/// A title opened on a tablet: beside the page it was opened from, not over
/// it.
///
/// The location is the phone's, `…/media/movie/133701` under the tab it was
/// opened from, so a link, Back and a rotation mean what they mean on a
/// phone. Only the drawing differs: the navigator keeps the page in the
/// phone's column ([AppBreakpoints.splitList]) with an empty slot over it
/// (`SidePaneSlotRoute`), and the shell draws the title beside it
/// ([MediaSplitLayout]).
abstract final class MediaSplit {
  /// Whether this window opens a title beside the page: a touch build at
  /// [AppBreakpoints.touchSplit] or wider. The desktop keeps the full page,
  /// whose two tracks are drawn for it.
  static bool splits(BuildContext context) =>
      !AppBreakpoints.isDesktopShell(context) &&
      MediaQuery.sizeOf(context).width >= AppBreakpoints.touchSplit;

  /// The title [uri] shows when it is a title's location under a mount, else
  /// null. The root mount (`/media/…`) is outside the shell and has no pane.
  static MediaPaneTarget? targetOf(Uri uri) {
    final segments = uri.pathSegments;
    final at = segments.lastIndexOf('media');
    if (at < 1) return null;
    final key = switch (segments.sublist(at + 1)) {
      ['movie', final id] => MediaKey.parse('movie', id),
      ['tv', 'tvdb', final id] => MediaKey.parse('tv', id, byTvdb: true),
      ['tv', final id] => MediaKey.parse('tv', id),
      _ => null,
    };
    if (key == null) return null;
    return (
      key: key,
      focus: uri.queryParameters['i'],
      posterUrl: uri.queryParameters['posterUrl'],
      heroTag: uri.queryParameters['heroTag'],
    );
  }
}

/// The pane a title is drawn in, as the page inside it sees it: its back
/// control goes back in the pane, or closes it.
class MediaPane extends InheritedWidget {
  const MediaPane({
    super.key,
    required this.canGoBack,
    required this.onBack,
    required super.child,
  });

  /// Whether Back returns to a title opened before this one in the pane;
  /// otherwise it closes the pane.
  final bool canGoBack;

  final VoidCallback onBack;

  static MediaPane? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaPane>();

  @override
  bool updateShouldNotify(MediaPane oldWidget) =>
      canGoBack != oldWidget.canGoBack;
}

/// The navigator, and beside it the title its location opens.
///
/// Built by the touch shell around the branches. Without a title, or below
/// [AppBreakpoints.touchSplit], the navigator takes the whole width; with one
/// it keeps [AppBreakpoints.splitList] and the title takes the rest. The
/// navigator stays the first child either way, so the pages in it keep their
/// state, their scroll and their place when the pane opens and closes.
class MediaSplitLayout extends StatelessWidget {
  const MediaSplitLayout({
    super.key,
    required this.location,
    required this.child,
  });

  /// The router's location: the title in it, if any, is the pane's.
  final Uri location;

  /// The navigator.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final target = MediaSplit.splits(context)
        ? MediaSplit.targetOf(location)
        : null;
    final instant = MediaQuery.disableAnimationsOf(context);
    return SidePaneScope(
      selected: target?.key,
      selectedTag: target?.heroTag,
      location: location.toString(),
      child: LayoutBuilder(
        builder: (context, box) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: target == null ? box.maxWidth : AppBreakpoints.splitList,
              child: child,
            ),
            Expanded(
              child: target == null
                  ? const SizedBox.shrink()
                  : AnimatedSwitcher(
                      duration: instant ? Duration.zero : AppAnimation.standard,
                      switchInCurve: AppAnimation.standardCurve,
                      switchOutCurve: AppAnimation.standardCurve,
                      // The title arrives from the list's side and settles;
                      // the one it replaces fades where it stands.
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0.03, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: _Pane(
                        key: ValueKey((target.key, target.focus)),
                        target: target,
                        location: location.toString(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One title in the pane.
class _Pane extends StatelessWidget {
  const _Pane({super.key, required this.target, required this.location});

  final MediaPaneTarget target;

  /// The slot's name: the location it was pushed at.
  final String location;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: SidePaneSlots.instance,
    builder: (context, page) => MediaPane(
      canGoBack: SidePaneSlots.instance.hasHistory(location),
      onBack: () => SidePaneSlots.instance.popShown(location),
      child: page!,
    ),
    // No hero tag: the tile the title was opened from is in another
    // navigator, and a flight never crosses one. The poster it drew still
    // stands in.
    child: MediaPage(
      mediaKey: target.key,
      focus: target.focus,
      posterUrl: target.posterUrl,
    ),
  );
}
