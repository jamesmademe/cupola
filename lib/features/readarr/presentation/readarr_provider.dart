import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/base_arr_service.dart';
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
  return _readarrService(ref, instanceId: null);
});

/// Readarr service bound to one named connection, independent of the lens.
final readarrServiceForProvider = Provider.family<ReadarrService, String>((
  ref,
  instanceId,
) {
  final lens = ref.read(activeInstanceProvider(ServiceKey.readarr))?.id ?? '';
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(readarrServiceProvider);
  }
  return _readarrService(ref, instanceId: instanceId);
});

ReadarrService _readarrService(Ref ref, {required String? instanceId}) {
  return ReadarrService(
    watchApiClient(ref, ServiceKey.readarr, instanceId: instanceId),
  );
}

/// All authors in the library, with a failed fetch allowed to reach the caller.
///
/// It read `getAuthors`, which swallows its own failure into `[]`, so a dark
/// Readarr drew "No authors in the library yet." — and the error branch the
/// Library tab already had could never be reached. The list is the whole
/// library in one request, so there is nothing partial to show beside a
/// failure. `noProviderRetry` for the reason `moviesProvider` gives: the rail
/// above reads the same library that way, and a Retry is the user's call.
final readarrAuthorsProvider = FutureProvider<List<ReadarrAuthor>>((ref) async {
  return ref.watch(readarrServiceProvider).getAuthorsOrThrow();
}, retry: noProviderRetry);

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
///
/// The walk with its envelope, not the bare rows: the rail counted the rows
/// and stated them as the queue, so a proxy that drops `totalRecords` stopped
/// the walk on its first full page and the rail read `Queue 200` however long
/// the queue was. [ArrRecordPage.total] and [ArrRecordPage.cutShort] say
/// which figure the rows can stand for.
final readarrQueueProvider = FutureProvider<ArrRecordPage>((ref) async {
  return ref.watch(readarrServiceProvider).getQueuePage();
}, retry: noProviderRetry);
