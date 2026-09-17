import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
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

/// Current download queue, with a failed fetch allowed to reach the caller.
///
/// It used to catch everything and answer `const []`, so a Readarr whose queue
/// endpoint was down read **`Queue 0`** on the rail — an idle downloader rather
/// than an unread one, and indistinguishable from a queue that had just
/// drained. The reason given for swallowing was that a queue error must not
/// hide the rest of the KPI rail, which was true and is now answered properly:
/// its one reader catches the throw into `ServiceKpi.unavailable`, so the other
/// three figures survive *and* the fourth reads an em dash instead of a number
/// nobody fetched.
///
/// `retry: noProviderRetry` comes with the throw and is not optional: its
/// reader awaits `.future` inside a `catch`, and Riverpod's default retry would
/// hold that `catch` for ten backed-off attempts before letting it run — the
/// rail stuck in its skeleton for some forty seconds instead of printing the em
/// dash. See `lib/core/providers/provider_retry.dart`.
final readarrQueueProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.watch(readarrServiceProvider).getQueue();
}, retry: noProviderRetry);
