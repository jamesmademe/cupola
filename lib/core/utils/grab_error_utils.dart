import 'package:dio/dio.dart';

import 'package:cupola/core/network/connection_failure.dart';

/// Translates a grab-release error into a user-friendly message.
///
/// Three causes an arr reports in its own words keep a sentence of their own
/// — an indexer that timed out behind the arr (a 504), a release already in
/// the library or queue, a full disk — and a 500, which the arrs answer for a
/// release that is already downloading. Everything else reads the
/// classification, so a refused key is a refusal and only silence says the
/// server did not answer. Never a status code, never the exception's text.
String translateGrabError(Object error) {
  final status = error is DioException ? error.response?.statusCode : null;
  final said = failureServiceMessage(error);
  // The arr's words when Dio kept them, and the exception's own text for the
  // app-authored exceptions that carry the arr's sentence inside it.
  final haystack = [
    ?said,
    if (error is! DioException) error.toString(),
  ].join(' ').toLowerCase();

  if (status == 504 ||
      haystack.contains('504') ||
      haystack.contains('gateway timeout')) {
    return 'The indexer took too long to answer, so nothing was grabbed.';
  }

  if (status == 500 ||
      haystack.contains('500') ||
      haystack.contains('server error')) {
    return 'The server answered with an error. This release may already be '
        'downloading or available, so check the download queue.';
  }

  if (haystack.contains('already')) {
    return 'This item is already in your library or download queue.';
  }

  if (haystack.contains('disk space') || haystack.contains('space')) {
    return 'Not enough disk space for this download.';
  }

  if (haystack.contains('timeout')) {
    return 'The request timed out, so nothing was grabbed. Retry when the '
        'indexer is back.';
  }

  return 'Nothing was grabbed. ${said ?? connectionFailureSentence(error)}';
}
