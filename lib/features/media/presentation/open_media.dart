import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/media/domain/media_key.dart';

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
  }) => push(
    ServiceRoutes.media(
      key,
      from: _here,
      focus: focus,
      heroTag: heroTag,
      posterUrl: posterUrl,
    ),
  );

  /// Opens a title Seerr names: a movie's own page under the tab the user is
  /// on; a series, until it has one, Seerr's page.
  Future<void> openSeerrTitle({
    required String mediaType,
    required int id,
    String? heroTag,
    String? posterUrl,
  }) => mediaType == 'tv'
      ? push(
          ServiceRoutes.seerrDetail(
            mediaType: 'tv',
            id: id,
            heroTag: heroTag,
            posterUrl: posterUrl,
          ),
        )
      : openMedia(MediaKey.movie(id), heroTag: heroTag, posterUrl: posterUrl);

  /// Pushes [location], a title's page in root form moved under the tab the
  /// user is on (`ServiceRoutes.mounted`); any other location as it is.
  Future<void> pushMounted(String location, {Object? extra}) =>
      push(ServiceRoutes.mounted(location, from: _here), extra: extra);
}
