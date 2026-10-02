import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Radarr library wall, with a failed fetch allowed to reach the wall.
///
/// It read `getMovies`, which swallows every failure into `[]`, so a Radarr
/// that was down resolved this *successfully* and the wall said "No items
/// found" — a library that exists and is empty, the opposite of what happened.
/// The wall is the whole library in one request: there is no partial answer
/// to show beside a failed one, so the failure is what it has to show.
///
/// `retry: noProviderRetry` because the KPI peek above the wall reads the same
/// library with that policy: under the default one the rail said "—" at once
/// while the wall sat on a spinner for the better part of a minute. Retry and
/// pull-to-refresh are the user's call. See `lib/core/providers/provider_retry.dart`.
///
/// **The one read of the lens's library.** The KPI rail, Home's card and the
/// Overview read this same provider (`radarrKpiLibraryProvider` and
/// `radarrOverviewMoviesProvider` are names for it), so the heaviest answer
/// the app asks for is downloaded once a session, not three times.
final moviesProvider = FutureProvider<List<RadarrMovie>>((ref) async {
  final service = ref.watch(radarrServiceProvider);
  return service.getMoviesOrThrow();
}, retry: noProviderRetry);

/// [moviesProvider] for one named connection, whatever the lens is on: the library
/// a second Radarr holds. The lens's own id, and the empty one, read [moviesProvider],
/// so a connection's library is downloaded once a session whichever surface
/// asks first. What Home's fold reads for a connection that is not the lens;
/// it used to download that library again every time Home was rebuilt.
final moviesForProvider = FutureProvider.family<List<RadarrMovie>, String>((
  ref,
  instanceId,
) {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.radarr))?.id;
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(moviesProvider.future);
  }
  return ref.watch(radarrServiceForProvider(instanceId)).getMoviesOrThrow();
}, retry: noProviderRetry);
