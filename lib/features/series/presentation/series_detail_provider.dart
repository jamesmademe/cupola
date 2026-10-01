import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/movies/presentation/movie_detail_provider.dart'
    show ArrItemRef;
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';

/// One series, from one named connection. See [movieDetailForProvider] for why
/// the connection is part of the key rather than something resolved inside,
/// why it reads the throwing fetch, and why it does not retry on its own.
final seriesDetailForProvider = FutureProvider.autoDispose
    .family<SonarrSeries?, ArrItemRef>((ref, item) async {
      if (item.id <= 0) return null;
      return _sonarr(ref, item.instanceId).getSeriesByIdOrThrow(item.id);
    }, retry: noProviderRetry);

/// The series' episodes. `noProviderRetry` like the series beside it: the two
/// share one outage, and a page that said Sonarr did not answer at once while
/// its episode list shimmered for a minute would be telling two stories.
final seriesEpisodesForProvider = FutureProvider.autoDispose
    .family<List<SonarrEpisode>, ArrItemRef>((ref, item) async {
      if (item.id <= 0) return const [];
      return _sonarr(ref, item.instanceId).getEpisodes(item.id);
    }, retry: noProviderRetry);

SonarrService _sonarr(Ref ref, String instanceId) => instanceId.isEmpty
    ? ref.watch(sonarrServiceProvider)
    : ref.watch(sonarrServiceForProvider(instanceId));
