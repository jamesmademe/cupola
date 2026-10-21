import 'package:flutter/material.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/network/route_poster.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/side_pane_route.dart';
import 'package:cupola/features/activity/presentation/download_page.dart';
import 'package:cupola/features/discover/presentation/collection_page.dart';
import 'package:cupola/features/discover/presentation/person_page.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_page.dart';

/// The title a pane shows: who it is, the connection it was opened from, the
/// season its episodes open on when it was opened from one, the poster that
/// stands in until the page reads its own, and the tile it was opened from
/// (its hero tag), which the list rings.
typedef MediaPaneTarget = ({
  MediaKey key,
  String? focus,
  int? season,
  String? posterUrl,
  String? heroTag,
});

/// What the pane draws, read from the location: a title, or one of the two
/// pages a title links to, a person's and a collection's.
sealed class MediaPanePage {
  const MediaPanePage();

  /// The tag of the tile it was opened from, which the list rings.
  String? get heroTag;

  /// What the pane shows, in the shell's own terms (`SidePaneScope.selected`).
  Object get selected;

  /// Which page this is: another one is drawn fresh, and arrives as a page
  /// does.
  Object get identity;

  /// The page as the pane draws it. With no hero tag: the tile it was opened
  /// from is in another navigator, and a flight never crosses one. The
  /// picture it drew still stands in.
  Widget build();
}

/// A title in the pane.
final class MediaPaneTitle extends MediaPanePage {
  const MediaPaneTitle(this.target);

  final MediaPaneTarget target;

  @override
  String? get heroTag => target.heroTag;

  @override
  Object get selected => target.key;

  // The season is part of which page this is: another season of the series
  // the pane shows is drawn fresh, on its own season.
  @override
  Object get identity => (target.key, target.focus, target.season);

  @override
  Widget build() => MediaPage(
    mediaKey: target.key,
    focus: target.focus,
    season: target.season,
    posterUrl: target.posterUrl,
  );
}

/// A person in the pane, opened from a list or from a title in it.
final class MediaPanePerson extends MediaPanePage {
  const MediaPanePerson({required this.id, this.posterUrl, this.heroTag});

  /// TMDB's id for them.
  final int id;

  /// The face the list drew, standing in while the page reads its own.
  final String? posterUrl;

  @override
  final String? heroTag;

  @override
  Object get selected => identity;

  @override
  Object get identity => (person: id);

  @override
  Widget build() => PersonPage(personId: id, initialProfileUrl: posterUrl);
}

/// A collection in the pane, opened from a list or from a title in it.
final class MediaPaneCollection extends MediaPanePage {
  const MediaPaneCollection({required this.id, this.heroTag});

  /// TMDB's id for it.
  final int id;

  @override
  final String? heroTag;

  @override
  Object get selected => identity;

  @override
  Object get identity => (collection: id);

  @override
  Widget build() => CollectionPage(collectionId: id);
}

/// A download in the pane, opened from Activity's lists
/// (`/activity/download?i=&id=`).
final class MediaPaneDownload extends MediaPanePage {
  const MediaPaneDownload({required this.instanceId, required this.key});

  /// The connection it was read from.
  final String instanceId;

  /// The client's id for the transfer (`downloadPageKey`).
  final String key;

  /// What the pane shows while it shows the download [key]: what a row
  /// compares itself with to wear the selection.
  static Object selectedFor(String key) => (download: key.trim().toLowerCase());

  @override
  String? get heroTag => null;

  @override
  Object get selected => selectedFor(key);

  @override
  Object get identity => (download: key.trim().toLowerCase(), i: instanceId);

  @override
  Widget build() => DownloadPage(instanceId: instanceId, downloadKey: key);
}

/// A title opened on a tablet: beside the page it was opened from, not over
/// it. A person or a collection opened from a list goes beside it the same
/// way, and one opened from a title in the pane stays in the pane.
///
/// The location is the phone's, `…/media/movie/133701` under the tab it was
/// opened from (`…/media/person/90001`, `…/media/collection/90101`), so a
/// link, Back and a rotation mean what they mean on a phone. Only the
/// drawing differs: the navigator keeps the page in the phone's column
/// ([AppBreakpoints.splitList]) with an empty slot over it
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
      season: ServiceRoutes.mediaSeasonOf(uri),
      posterUrl: RoutePoster.accept(uri.queryParameters['posterUrl']),
      heroTag: uri.queryParameters['heroTag'],
    );
  }

  /// The page [uri] puts in the pane: a title's ([targetOf]), a person's or
  /// a collection's location under a mount, or a download's, else null.
  static MediaPanePage? pageOf(Uri uri) {
    if (targetOf(uri) case final target?) return MediaPaneTitle(target);
    final segments = uri.pathSegments;
    if (uri.path == ServiceRoutes.activityDownloadPath) {
      final key = uri.queryParameters['id']?.trim() ?? '';
      return key.isEmpty
          ? null
          : MediaPaneDownload(
              instanceId: uri.queryParameters['i'] ?? '',
              key: key,
            );
    }
    final at = segments.lastIndexOf('media');
    if (at < 1 || segments.length != at + 3) return null;
    // Read as the route reads it (`RouteUtils.safeIntParam`): a slot the
    // pane could not fill would be an empty pane.
    final id = int.tryParse(segments[at + 2]);
    if (id == null) return null;
    final query = uri.queryParameters;
    return switch (segments[at + 1]) {
      'person' => MediaPanePerson(
        id: id,
        posterUrl: RoutePoster.accept(query['posterUrl']),
        heroTag: query['heroTag'],
      ),
      'collection' => MediaPaneCollection(id: id, heroTag: query['heroTag']),
      _ => null,
    };
  }
}

/// The pane a page is drawn in, as the page inside it sees it: its back
/// control goes back in the pane, or closes it.
class MediaPane extends InheritedWidget {
  const MediaPane({
    super.key,
    required this.canGoBack,
    required this.onBack,
    required super.child,
  });

  /// Whether Back returns to a page opened before this one in the pane;
  /// otherwise it closes the pane.
  final bool canGoBack;

  final VoidCallback onBack;

  static MediaPane? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaPane>();

  @override
  bool updateShouldNotify(MediaPane oldWidget) =>
      canGoBack != oldWidget.canGoBack;
}

/// The navigator, and beside it the page its location opens: a title, a
/// person or a collection ([MediaSplit.pageOf]).
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
        ? MediaSplit.pageOf(location)
        : null;
    final instant = MediaQuery.disableAnimationsOf(context);
    return SidePaneScope(
      selected: target?.selected,
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
                        key: ValueKey(target.identity),
                        page: target,
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

/// One page in the pane.
class _Pane extends StatelessWidget {
  const _Pane({super.key, required this.page, required this.location});

  final MediaPanePage page;

  /// The slot's name: the location it was pushed at.
  final String location;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: SidePaneSlots.instance,
    builder: (context, child) => MediaPane(
      canGoBack: SidePaneSlots.instance.hasHistory(location),
      onBack: () => SidePaneSlots.instance.popShown(location),
      child: child!,
    ),
    child: page.build(),
  );
}
