import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Dashboard-ready alias for the underlying Readarr service.
///
/// Throws if Readarr is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.readarr)` before reading.
final readarrServiceProvider = Provider<ReadarrService>((ref) {
  return ReadarrService(watchApiClient(ref, ServiceKey.readarr));
});

/// All authors in the library.
final readarrAuthorsProvider = FutureProvider<List<ReadarrAuthor>>((ref) async {
  return ref.watch(readarrServiceProvider).getAuthors();
});

/// Most recent activity for the dashboard.
final readarrRecentHistoryProvider = FutureProvider<List<ReadarrHistoryItem>>((
  ref,
) async {
  return ref.watch(readarrServiceProvider).getRecentHistory();
});

/// Current download queue. Degrades to an empty list on failure so a queue
/// error never hides the rest of the KPI rail.
final readarrQueueProvider = FutureProvider<List<dynamic>>((ref) async {
  try {
    return await ref.watch(readarrServiceProvider).getQueue();
  } catch (_) {
    return const <dynamic>[];
  }
});
