import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Which film one Radarr's own id names: its TMDB id, null when that Radarr
/// answered that it has none. A failure travels.
final radarrMovieTmdbProvider = FutureProvider.autoDispose
    .family<int?, ({String connectionId, int movieId})>((ref, movie) async {
      final record = await ref
          .watch(radarrServiceForProvider(movie.connectionId))
          .getMovieOrThrow(movie.movieId);
      final tmdbId = record?.tmdbId ?? 0;
      return tmdbId > 0 ? tmdbId : null;
    }, retry: noProviderRetry);

/// The way from a link that names a film by one Radarr's own id (every link
/// the app made before a title had one page, and a queue row that does not
/// carry the film) to that film's page: it asks that Radarr which film it is,
/// then takes its place, under the same tab.
///
/// While Radarr has not answered, the room; when it did not answer, why, with
/// the remedy its cause names; when it has no such film, it says so.
class RadarrMovieOpener extends ConsumerWidget {
  const RadarrMovieOpener({
    super.key,
    required this.movieId,
    this.instanceId,
    this.heroTag,
  });

  /// The film's id on that Radarr.
  final int movieId;

  /// The Radarr the id belongs to; null for the one Radarr is read through.
  final String? instanceId;
  final String? heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final connectionId =
        instanceId ?? ref.watch(activeInstanceProvider(ServiceKey.radarr))?.id;
    // Checked before the provider: a Radarr that is not set up is not a
    // failure that waiting mends.
    if (connectionId == null ||
        !ref
            .watch(currentSettingsProvider)
            .isServiceConfigured(ServiceKey.radarr)) {
      return Scaffold(
        backgroundColor: room.ground,
        body: NotConfiguredPlaceholder.forService(ServiceKey.radarr),
      );
    }
    final target = (connectionId: connectionId, movieId: movieId);
    final answer = ref.watch(radarrMovieTmdbProvider(target));
    if (answer case AsyncData(value: final tmdbId?)) {
      // After this frame: a navigation inside a build rebuilds the tree that
      // is being built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.replace(
          ServiceRoutes.media(
            MediaKey.movie(tmdbId),
            from: GoRouterState.of(context).uri.path,
            focus: instanceId,
            heroTag: heroTag,
          ),
        );
      });
    }
    return Scaffold(
      backgroundColor: room.ground,
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: switch (answer) {
        AsyncError(:final error) => AppErrorState(
          error: error,
          service: ServiceKey.radarr,
          instanceId: connectionId,
          onRetry: () => ref.invalidate(radarrMovieTmdbProvider(target)),
        ),
        AsyncData(value: null) => const AppEmptyState(
          icon: Icons.movie_outlined,
          title: 'Not in Radarr any more',
          message:
              'Radarr has no movie by this link. It may have been removed.',
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
