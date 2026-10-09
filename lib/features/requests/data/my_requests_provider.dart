/// Her requests, read for the Home and for her page, and the one failure
/// the requester's Home says.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/requests/domain/my_requests.dart';

/// Her requests as the last read left them, and whether that read was the
/// last to answer.
///
/// The list is her Seerr's (the lens: the only Seerr she has), every page of
/// it, which Seerr limits to her own. While a read after it fails the list
/// stays, [stale]: what she last knew, never figures that stopped moving
/// presented as current.
typedef MyRequestsRead = ({MyRequests? requests, Object? error, bool stale});

final myRequestsProvider = Provider.autoDispose<MyRequestsRead>((ref) {
  final read = ref.watch(requestsProvider);
  final list = read.value;
  if (list == null) return (requests: null, error: read.error, stale: false);
  final now = ref.watch(calendarClockProvider)();
  final stale = read.hasError;
  return (
    requests: myRequestsOf(list, now: now, stale: stale),
    error: read.error,
    stale: stale,
  );
});

/// The requester's Home says one failure, above everything, whatever the
/// cause and whichever of her reads it came from: her requests, the shelf of
/// the week, what comes out soon. Null while each answered or is still
/// asking; kept while a Retry asks again, so the line keeps its time.
final requesterHomeFailureProvider = Provider.autoDispose<Object?>((ref) {
  for (final read in [
    ref.watch(requestsProvider),
    ref.watch(atriumTrendingProvider),
    ref.watch(comingSoonProvider),
  ]) {
    if (read.hasError) return read.error;
  }
  return null;
});

/// Asks her Seerr again for everything her Home reads.
void retryRequesterHome(WidgetRef ref) {
  ref.invalidate(requestsProvider);
  ref.invalidate(atriumTrendingProvider);
  ref.invalidate(comingSoonProvider);
}
