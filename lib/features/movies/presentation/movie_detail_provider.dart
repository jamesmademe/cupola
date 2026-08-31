import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One movie, from one named connection.
///
/// Keyed on the pair, because `movieId 42` is a different film on each Radarr:
/// a family keyed on the int alone would serve the 4K server's answer to a page
/// that asked the HD one, and — worse — would not refetch, because from the
/// cache's point of view nothing about the question had changed.
///
/// An empty [ArrItemRef.instanceId] means the lens, which is what
/// [movieDetailProvider] passes.
typedef ArrItemRef = ({String instanceId, int id});

final movieDetailForProvider = FutureProvider.autoDispose
    .family<RadarrMovie?, ArrItemRef>((ref, item) async {
      if (item.id <= 0) return null;
      final service = item.instanceId.isEmpty
          ? ref.watch(radarrServiceProvider)
          : ref.watch(radarrServiceForProvider(item.instanceId));
      return service.getMovie(item.id);
    });

/// The same movie, from whichever connection Radarr is being read through.
///
/// Delegates rather than fetching, the same way `serviceSummaryProvider`
/// delegates to `instanceSummaryProvider`: the surfaces that never name a
/// connection keep the shape they always had, and there is still only one place
/// that knows how to load a movie.
final movieDetailProvider = FutureProvider.autoDispose
    .family<RadarrMovie?, int>((ref, movieId) async {
      final lens = ref.watch(activeInstanceProvider(ServiceKey.radarr))?.id;
      return ref.watch(
        movieDetailForProvider((instanceId: lens ?? '', id: movieId)).future,
      );
    });
