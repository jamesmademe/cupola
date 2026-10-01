import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';

/// One movie, from one named connection.
///
/// Keyed on the pair, because `movieId 42` is a different film on each Radarr:
/// a family keyed on the int alone would serve the 4K server's answer to a page
/// that asked the HD one, and — worse — would not refetch, because from the
/// cache's point of view nothing about the question had changed.
///
/// An empty [ArrItemRef.instanceId] means the lens.
typedef ArrItemRef = ({String instanceId, int id});

/// Reads [RadarrService.getMovieOrThrow], so a Radarr that did not answer is a
/// failure the page can name rather than a `null` it reads as "not found".
///
/// `retry: noProviderRetry`, the policy of the library wall the page is pushed
/// from: under the default one a cold open sat on its skeleton for the better
/// part of a minute before it said Radarr did not answer, and the page already
/// offers Retry and pull-to-refresh. See `lib/core/providers/provider_retry.dart`.
final movieDetailForProvider = FutureProvider.autoDispose
    .family<RadarrMovie?, ArrItemRef>((ref, item) async {
      if (item.id <= 0) return null;
      final service = item.instanceId.isEmpty
          ? ref.watch(radarrServiceProvider)
          : ref.watch(radarrServiceForProvider(item.instanceId));
      return service.getMovieOrThrow(item.id);
    }, retry: noProviderRetry);
