import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Sonarr library wall, with a failed fetch allowed to reach the wall.
///
/// It read `getSeries`, which swallows its own failure into `[]`, so an
/// unreachable Sonarr resolved this *successfully* and the wall read "No items
/// found". The wall is the whole library in one request — there is nothing
/// partial to show beside the failure — so it shows the failure. See
/// `moviesProvider` for why the retry policy matches the KPI rail's.
final seriesProvider = FutureProvider<List<SonarrSeries>>((ref) async {
  final service = ref.watch(sonarrServiceProvider);
  return service.getSeriesOrThrow();
}, retry: noProviderRetry);
