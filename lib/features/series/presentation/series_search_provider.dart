import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/utils/search_results_loader.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';

/// Provider for the current search query in Series section.
final seriesSearchQueryProvider = StateProvider<String>((ref) => '');

/// Provider for search results in Series section.
///
/// Returns null when query is empty, otherwise returns lookup results.
///
/// The lookup carries a [CancelToken] cancelled on dispose: see
/// `moviesSearchResultsProvider` for why the superseded round has to stop.
final seriesSearchResultsProvider = FutureProvider<List<SonarrSeries>?>((
  ref,
) async {
  final query = ref.watch(seriesSearchQueryProvider);
  // `watch`, not `read`: see `moviesSearchResultsProvider`.
  final service = ref.watch(sonarrServiceProvider);
  final cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  return loadNullableSearchResults(
    query: query,
    // `reportFailure`: a Sonarr that did not answer is not "No results".
    lookup: (term) => service.lookupSeries(
      term,
      cancelToken: cancelToken,
      reportFailure: true,
    ),
  );
}, retry: noProviderRetry);
