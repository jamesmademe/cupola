/// Runs a section search: null for an empty query (nothing was asked), the
/// answer otherwise, and the failure, rethrown, when there was no answer.
///
/// It used to catch every failure into `[]`, so a Radarr that did not answer,
/// or refused the key, drew "No results" under a search nobody ran. "No
/// results" is said only after the service answered (the brand book's fifth
/// configuration rule); a failure reaches the page's error state in its
/// classified words. Pair [lookup] with the service's `reportFailure: true`,
/// which is what stops the service itself from degrading to `[]` first.
Future<List<T>?> loadNullableSearchResults<T>({
  required String query,
  required Future<List<T>> Function(String query) lookup,
}) async {
  if (query.isEmpty) {
    return null;
  }
  return lookup(query);
}
