import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/providers/provider_retry.dart';
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
  if (query.isEmpty) return null;
  final cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  // `reportFailure`, and not through `loadNullableSearchResults`: both used to
  // turn a Seerr that did not answer into `[]`, and the page said "No results
  // found" about a search nobody ran. "No results" is only said after Seerr
  // answered; a failure reaches the page's error state in its own words.
  return ref
      .read(seerrServiceProvider)
      .search(query, cancelToken: cancelToken, reportFailure: true);
}, retry: noProviderRetry);
