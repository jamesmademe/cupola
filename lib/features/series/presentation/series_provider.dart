import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Sonarr library, for callers that would rather show nothing than a
/// dialog.
///
/// `getSeries` swallows its own failure into `[]`, so this provider resolves
/// *successfully* for an unreachable Sonarr. That is survivable for the browse
/// grid it was written for and a lie for anything that counts: see
/// `sonarrOverviewSeriesProvider`, which reads the same library through
/// `getSeriesOrThrow` precisely so a figure nobody fetched can read an em dash.
final seriesProvider = FutureProvider<List<SonarrSeries>>((ref) async {
  final service = ref.watch(sonarrServiceProvider);
  return service.getSeries();
});
