import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/utils/search_results_loader.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';

/// Provider for the current search query in Discover section.
final discoverSearchQueryProvider = StateProvider<String>((ref) => '');

/// Provider for search results in Discover section.
///
/// Returns null when query is empty, otherwise returns search results.
///
/// The lookup carries a [CancelToken] cancelled on dispose. Riverpod tears the
/// previous build down before it starts the next one, so the request a
/// keystroke supersedes is aborted rather than left to run to completion
/// against a Seerr instance that may take seconds to answer a query nobody is
/// asking any more. This is CONTEXT.md rule 8, and this provider was the only
/// one of the four search providers not honouring it.
final discoverSearchResultsProvider = FutureProvider<List<MediaPreview>?>((
  ref,
) async {
  final query = ref.watch(discoverSearchQueryProvider);
  final cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  return loadNullableSearchResults(
    query: query,
    // Read inside the lookup, not above it: the loader only calls this when the
    // query is non-empty, and it runs inside the try. That keeps the original
    // behaviour where an unconfigured Seerr yields `[]` — and an empty query
    // still yields `null` without touching the provider at all.
    lookup: (term) =>
        ref.read(seerrServiceProvider).search(term, cancelToken: cancelToken),
  );
});
