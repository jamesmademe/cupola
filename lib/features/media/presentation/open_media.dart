import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/side_pane_route.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_split.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

/// Opening a title's page from the page the user is on: under that page's
/// tab, so the poster flies and the tab keeps it (`ServiceRoutes.media`).
extension OpenMedia on BuildContext {
  /// Where the user is: the location the router is showing.
  String get _here => GoRouter.of(this).state.uri.path;

  /// Pushes [key]'s page under the tab the user is on.
  Future<void> openMedia(
    MediaKey key, {
    String? focus,
    String? heroTag,
    String? posterUrl,
  }) => _openTitle(
    ServiceRoutes.media(
      key,
      from: _here,
      focus: focus,
      heroTag: heroTag,
      posterUrl: posterUrl,
    ),
  );

  /// Pushes a title's [location]. On a tablet with a title open beside the
  /// list (`MediaSplit`), one chosen from the list takes that title's place,
  /// with the pane's own history; one opened from inside the pane is pushed
  /// on it, so Back in the pane returns to the title before.
  Future<void> _openTitle(String location, {Object? extra}) {
    final router = GoRouter.of(this);
    if (MediaPane.maybeOf(this) == null &&
        SidePaneScope.selectedOf(this) != null) {
      while (MediaSplit.targetOf(router.state.uri) != null && router.canPop()) {
        router.pop();
      }
    }
    return router.push(location, extra: extra);
  }

  /// Opens a title Seerr names on its own page, under the tab the user is
  /// on: [mediaType] is Seerr's `movie` or `tv`, [id] TMDB's.
  Future<void> openSeerrTitle({
    required String mediaType,
    required int id,
    String? heroTag,
    String? posterUrl,
  }) => openMedia(
    mediaType == 'tv' ? MediaKey.tv(id) : MediaKey.movie(id),
    heroTag: heroTag,
    posterUrl: posterUrl,
  );

  /// Opens an item a media server listed: a movie or a series on its own
  /// page, with the copy of the connection that listed it leading (the
  /// service's lens); anything else on the server's own page.
  Future<void> openStreamItem(ServiceKey service, StreamItem item) =>
      switch (MediaKey.ofStreamItem(item)) {
        final key? => openMedia(
          key,
          focus: ProviderScope.containerOf(
            this,
            listen: false,
          ).read(activeInstanceProvider(service))?.id,
        ),
        null => push(ServiceRoutes.streamItem(service, item.id)),
      };

  /// Pushes a person's page under the tab the user is on, as a title opened
  /// here would be (`ServiceRoutes.person`).
  Future<void> openPerson(int id, {String? heroTag, String? posterUrl}) => push(
    ServiceRoutes.person(
      id,
      from: _here,
      heroTag: heroTag,
      posterUrl: posterUrl,
    ),
  );

  /// Pushes a collection's page under the tab the user is on.
  Future<void> openCollection(int id, {String? heroTag}) =>
      push(ServiceRoutes.collection(id, from: _here, heroTag: heroTag));

  /// Pushes [location], a title's page in root form moved under the tab the
  /// user is on (`ServiceRoutes.mounted`); any other location as it is.
  Future<void> pushMounted(String location, {Object? extra}) {
    final mounted = ServiceRoutes.mounted(location, from: _here);
    return MediaSplit.targetOf(Uri.parse(mounted)) == null
        ? push(mounted, extra: extra)
        : _openTitle(mounted, extra: extra);
  }
}
