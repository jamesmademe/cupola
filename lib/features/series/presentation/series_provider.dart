import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Sonarr library wall, with a failed fetch allowed to reach the wall.
///
/// It read `getSeries`, which swallows its own failure into `[]`, so an
/// unreachable Sonarr resolved this *successfully* and the wall read "No items
/// found". The wall is the whole library in one request — there is nothing
/// partial to show beside the failure — so it shows the failure. See
/// `moviesProvider` for why the retry policy matches the KPI rail's.
///
/// The one read of the lens's library, as `moviesProvider` is Radarr's:
/// `sonarrKpiLibraryProvider` and `sonarrOverviewSeriesProvider` are names for
/// it.
final seriesProvider = FutureProvider<List<SonarrSeries>>((ref) async {
  final service = ref.watch(sonarrServiceProvider);
  return service.getSeriesOrThrow();
}, retry: noProviderRetry);

/// [seriesProvider] for one named connection, whatever the lens is on: the library
/// a second Sonarr holds. The lens's own id, and the empty one, read [seriesProvider],
/// so a connection's library is downloaded once a session whichever surface
/// asks first. What Home's fold reads for a connection that is not the lens;
/// it used to download that library again every time Home was rebuilt.
final seriesForProvider = FutureProvider.family<List<SonarrSeries>, String>((
  ref,
  instanceId,
) {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.sonarr))?.id;
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(seriesProvider.future);
  }
  return ref.watch(sonarrServiceForProvider(instanceId)).getSeriesOrThrow();
}, retry: noProviderRetry);
