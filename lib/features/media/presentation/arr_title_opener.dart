import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// A title by one arr's own id: Radarr's movie or Sonarr's series id, on the
/// connection [connectionId].
typedef ArrTitleRef = ({ServiceKey arr, String connectionId, int id});

/// Which title one arr's own id names: its page's key, null when that arr
/// answered that it has none. A failure travels.
///
/// A movie by its TMDB id. A series by TMDB's too, the one every source
/// opens it by: Sonarr v4 records it; for a v3 record a Seerr names it from
/// TVDB's (`SeerrService.findTvByTvdbId`), and only when none can does the
/// series open by TVDB's id.
final arrTitleKeyProvider = FutureProvider.autoDispose
    .family<MediaKey?, ArrTitleRef>((ref, title) async {
      if (title.arr == ServiceKey.radarr) {
        final record = await ref
            .watch(radarrServiceForProvider(title.connectionId))
            .getMovieOrThrow(title.id);
        final tmdbId = record?.tmdbId ?? 0;
        return tmdbId > 0 ? MediaKey.movie(tmdbId) : null;
      }
      final series = await ref
          .watch(sonarrServiceForProvider(title.connectionId))
          .getSeriesByIdOrThrow(title.id);
      if (series == null) return null;
      if (series.tmdbId <= 0 && series.tvdbId > 0) {
        final seerrs = ref
            .watch(currentSettingsProvider)
            .instancesOf(ServiceKey.seerr)
            .where((instance) => instance.isConfigured);
        for (final seerr in seerrs) {
          try {
            final tmdbId = await ref
                .watch(seerrServiceForProvider(seerr.id))
                .findTvByTvdbId(series.tvdbId);
            if (tmdbId != null) return MediaKey.tv(tmdbId);
          } catch (_) {
            // That Seerr is on the page's own row; another may still say.
          }
        }
      }
      return MediaKey.ofSeries(tmdbId: series.tmdbId, tvdbId: series.tvdbId);
    }, retry: noProviderRetry);

/// The way from a link that names a title by one arr's own id (every link
/// the app made before a title had one page, and a row that does not carry
/// the title's ids) to that title's page: it asks that arr which title it is,
/// then takes its place, under the same tab.
///
/// While the arr has not answered, the room; when it did not answer, why,
/// with the remedy its cause names; when it has no such title, it says so.
class ArrTitleOpener extends ConsumerWidget {
  /// A movie by Radarr's id.
  const ArrTitleOpener.radarr({
    super.key,
    required int movieId,
    this.instanceId,
    this.heroTag,
  }) : arr = ServiceKey.radarr,
       id = movieId;

  /// A series by Sonarr's id.
  const ArrTitleOpener.sonarr({
    super.key,
    required int seriesId,
    this.instanceId,
    this.heroTag,
  }) : arr = ServiceKey.sonarr,
       id = seriesId;

  /// Radarr or Sonarr.
  final ServiceKey arr;

  /// The title's id on that arr.
  final int id;

  /// The connection the id belongs to; null for the one [arr] is read
  /// through.
  final String? instanceId;
  final String? heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final connectionId =
        instanceId ?? ref.watch(activeInstanceProvider(arr))?.id;
    // Checked before the provider: an arr that is not set up is not a
    // failure that waiting mends.
    if (connectionId == null ||
        !ref.watch(currentSettingsProvider).isServiceConfigured(arr)) {
      return Scaffold(
        backgroundColor: room.ground,
        body: NotConfiguredPlaceholder.forService(arr),
      );
    }
    final target = (arr: arr, connectionId: connectionId, id: id);
    final answer = ref.watch(arrTitleKeyProvider(target));
    if (answer case AsyncData(value: final key?)) {
      // After this frame: a navigation inside a build rebuilds the tree that
      // is being built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.replace(
          ServiceRoutes.media(
            key,
            from: GoRouterState.of(context).uri.path,
            focus: instanceId,
            heroTag: heroTag,
          ),
        );
      });
    }
    final movie = arr == ServiceKey.radarr;
    return Scaffold(
      backgroundColor: room.ground,
      appBar: const GlassAppBar(),
      body: switch (answer) {
        AsyncError(:final error) => AppErrorState(
          error: error,
          service: arr,
          instanceId: connectionId,
          onRetry: () => ref.invalidate(arrTitleKeyProvider(target)),
        ),
        AsyncData(value: null) => AppEmptyState(
          icon: movie ? Icons.movie_outlined : Icons.tv_outlined,
          title: 'Not in ${arr.title} any more',
          message:
              '${arr.title} has no ${movie ? 'movie' : 'series'} by this '
              'link. It may have been removed.',
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
