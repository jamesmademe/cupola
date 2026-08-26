import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/movies/presentation/movie_detail_provider.dart'
    show ArrItemRef;
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One series, from one named connection. See [movieDetailForProvider] for why
/// the connection is part of the key rather than something resolved inside.
final seriesDetailForProvider = FutureProvider.autoDispose
    .family<SonarrSeries?, ArrItemRef>((ref, item) async {
      if (item.id <= 0) return null;
      return _sonarr(ref, item.instanceId).getSeriesById(item.id);
    });

final seriesEpisodesForProvider = FutureProvider.autoDispose
    .family<List<SonarrEpisode>, ArrItemRef>((ref, item) async {
      if (item.id <= 0) return const [];
      return _sonarr(ref, item.instanceId).getEpisodes(item.id);
    });

SonarrService _sonarr(Ref ref, String instanceId) => instanceId.isEmpty
    ? ref.watch(sonarrServiceProvider)
    : ref.watch(sonarrServiceForProvider(instanceId));

ArrItemRef _throughLens(Ref ref, int id) => (
  instanceId: ref.watch(activeInstanceProvider(ServiceKey.sonarr))?.id ?? '',
  id: id,
);

final seriesDetailProvider = FutureProvider.autoDispose
    .family<SonarrSeries?, int>(
      (ref, seriesId) => ref.watch(
        seriesDetailForProvider(_throughLens(ref, seriesId)).future,
      ),
    );

final seriesEpisodesProvider = FutureProvider.autoDispose
    .family<List<SonarrEpisode>, int>(
      (ref, seriesId) => ref.watch(
        seriesEpisodesForProvider(_throughLens(ref, seriesId)).future,
      ),
    );
