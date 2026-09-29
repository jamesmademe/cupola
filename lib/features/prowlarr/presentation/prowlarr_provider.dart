import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';

import 'package:cupola/features/prowlarr/data/prowlarr_service.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const int _defaultHistoryPageSize = 20;

/// One server-side page of the History tab.
///
/// A record key keeps page and event filter together, so switching the filter
/// cannot accidentally reuse a page fetched for another event family.
typedef ProwlarrHistoryQuery = ({int page, int pageSize, String? eventType});

/// A bounded statistics window ending at the moment the request starts.
enum ProwlarrStatsWindow {
  day('24 hours', Duration(hours: 24)),
  week('7 days', Duration(days: 7)),
  month('30 days', Duration(days: 30));

  const ProwlarrStatsWindow(this.label, this.duration);

  final String label;
  final Duration duration;
}

/// Dashboard-ready alias for the underlying Prowlarr service.
///
/// Throws if Prowlarr is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.prowlarr)` before reading.
///
/// ## Retry: none, anywhere in this file
///
/// Every provider here carries `retry: noProviderRetry`, and one added later
/// must too. Riverpod's default re-runs a failed build ten times over roughly
/// forty seconds and reports *loading* throughout, so a Prowlarr that went
/// dark was a spinner for most of a minute before any list could say so and
/// offer its Retry. A provider derived from another (`…ByIdProvider`, the
/// Overview's three regions, applications and download clients) carries it
/// as well: it cannot settle before its source does, and without the policy
/// on the source it waits out the source's retries. Retrying is the user's
/// call: a Retry must invalidate the *source* a derived provider reads, since
/// invalidating only the derivation re-reads the source's cached failure.
///
/// This build throws "not configured", which the default would retry too.
final prowlarrServiceProvider = Provider<ProwlarrService>((ref) {
  return _prowlarrService(ref, instanceId: null);
}, retry: noProviderRetry);

/// Prowlarr service bound to one named connection, independent of the lens.
///
/// Empty and active-lens ids reuse [prowlarrServiceProvider], preserving one
/// client and its overrides for the ordinary path. A different id is resolved
/// explicitly so folded surfaces cannot read the lens under another label.
final prowlarrServiceForProvider = Provider.family<ProwlarrService, String>((
  ref,
  instanceId,
) {
  final lens = ref.read(activeInstanceProvider(ServiceKey.prowlarr))?.id ?? '';
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(prowlarrServiceProvider);
  }
  return _prowlarrService(ref, instanceId: instanceId);
}, retry: noProviderRetry);

ProwlarrService _prowlarrService(Ref ref, {required String? instanceId}) {
  return ProwlarrService(
    watchApiClient(ref, ServiceKey.prowlarr, instanceId: instanceId),
  );
}

/// Configured indexers.
final prowlarrIndexersProvider = FutureProvider<List<ProwlarrIndexer>>((
  ref,
) async {
  return ref.watch(prowlarrServiceProvider).getIndexers();
}, retry: noProviderRetry);

/// How far back the indexer readout reaches.
///
/// The Overview labels its Queries / Grabs / Fails figures as the last day's
/// work, and a self-hoster reads them that way: "did anything break today".
/// This provider used to call `getIndexerStats()` with no window at all, so
/// every one of those figures was an all-time total that had been climbing
/// since the indexer was added — a number that can only go up is not a
/// readout, and a Fails count that never returns to zero is not a fault
/// signal. The client has accepted `startDate`/`endDate` all along.
const prowlarrStatsWindow = Duration(hours: 24);

/// Aggregated per-indexer usage statistics over [prowlarrStatsWindow].
///
/// The window is computed once per fetch rather than read from a clock inside
/// the widget tree: two KPIs resolved a few milliseconds apart must describe
/// the same day, or Grabs can exceed Queries.
final prowlarrIndexerStatsProvider = FutureProvider<ProwlarrIndexerStats>((
  ref,
) async {
  final now = DateTime.now().toUtc();
  return ref
      .watch(prowlarrServiceProvider)
      .getIndexerStats(
        startDate: now.subtract(prowlarrStatsWindow).toIso8601String(),
        endDate: now.toIso8601String(),
      );
}, retry: noProviderRetry);

/// Indexers currently disabled due to failures.
final prowlarrIndexerStatusProvider =
    FutureProvider<List<ProwlarrIndexerStatus>>((ref) async {
      return ref.watch(prowlarrServiceProvider).getIndexerStatus();
    }, retry: noProviderRetry);

/// Current health issues.
final prowlarrHealthProvider = FutureProvider<List<ProwlarrHealthIssue>>((
  ref,
) async {
  return ref.watch(prowlarrServiceProvider).getHealth();
}, retry: noProviderRetry);

/// Most recent indexer activity for the dashboard.
final prowlarrRecentHistoryProvider = FutureProvider<ProwlarrHistoryPage>((
  ref,
) async {
  return ref
      .watch(prowlarrServiceProvider)
      .getHistory(page: 1, pageSize: _defaultHistoryPageSize);
}, retry: noProviderRetry);

/// Paged, optionally filtered history for the full History tab.
final prowlarrHistoryPageProvider = FutureProvider.autoDispose
    .family<ProwlarrHistoryPage, ProwlarrHistoryQuery>((ref, query) async {
      return ref
          .watch(prowlarrServiceProvider)
          .getHistory(
            page: query.page,
            pageSize: query.pageSize,
            eventType: query.eventType,
          );
    }, retry: noProviderRetry);

/// Per-indexer statistics for a user-selected bounded window.
final prowlarrIndexerStatsForWindowProvider = FutureProvider.autoDispose
    .family<ProwlarrIndexerStats, ProwlarrStatsWindow>((ref, window) async {
      final now = DateTime.now().toUtc();
      return ref
          .watch(prowlarrServiceProvider)
          .getIndexerStats(
            startDate: now.subtract(window.duration).toIso8601String(),
            endDate: now.toIso8601String(),
          );
    }, retry: noProviderRetry);

/// A single indexer resolved from [prowlarrIndexersProvider], or null if the id
/// is unknown. Reuses the list fetch so the detail screen adds no extra call.
final prowlarrIndexerByIdProvider =
    FutureProvider.family<ProwlarrIndexer?, int>((ref, id) async {
      final indexers = await ref.watch(prowlarrIndexersProvider.future);
      for (final indexer in indexers) {
        if (indexer.id == id) return indexer;
      }
      return null;
    }, retry: noProviderRetry);

/// Per-indexer usage statistics resolved from [prowlarrIndexerStatsProvider].
final prowlarrIndexerStatByIdProvider =
    FutureProvider.family<ProwlarrIndexerStat?, int>((ref, id) async {
      final stats = await ref.watch(prowlarrIndexerStatsProvider.future);
      for (final stat in stats.indexers) {
        if (stat.indexerId == id) return stat;
      }
      return null;
    }, retry: noProviderRetry);

/// Failure state for a single indexer, or null when it is healthy.
final prowlarrIndexerStatusByIdProvider =
    FutureProvider.family<ProwlarrIndexerStatus?, int>((ref, id) async {
      final statuses = await ref.watch(prowlarrIndexerStatusProvider.future);
      for (final status in statuses) {
        if (status.indexerId == id) return status;
      }
      return null;
    }, retry: noProviderRetry);

/// Recent history for a single indexer, filtered server-side.
final prowlarrIndexerHistoryProvider =
    FutureProvider.family<List<ProwlarrHistoryItem>, int>((ref, id) async {
      return ref.watch(prowlarrServiceProvider).getIndexerHistory(id);
    }, retry: noProviderRetry);

/// Configured providers of one kind (apps, download clients, notifications,
/// indexer proxies).
final prowlarrProvidersProvider =
    FutureProvider.family<List<ProwlarrProviderResource>, ProwlarrProviderKind>(
      (ref, kind) async {
        return ref.watch(prowlarrServiceProvider).getProviders(kind);
      },
      retry: noProviderRetry,
    );

/// Implementations that can be added for one kind.
///
/// `autoDispose` because it is only read while a picker is open.
final prowlarrProviderSchemaProvider = FutureProvider.autoDispose
    .family<List<ProwlarrProviderResource>, ProwlarrProviderKind>((
      ref,
      kind,
    ) async {
      return ref.watch(prowlarrServiceProvider).getProviderSchema(kind);
    }, retry: noProviderRetry);

/// Applications Prowlarr syncs its indexers to.
final prowlarrApplicationsProvider =
    FutureProvider<List<ProwlarrProviderResource>>((ref) async {
      return ref.watch(
        prowlarrProvidersProvider(ProwlarrProviderKind.application).future,
      );
    }, retry: noProviderRetry);

/// Download clients, offered per indexer in the edit form.
final prowlarrDownloadClientsProvider =
    FutureProvider<List<ProwlarrProviderResource>>((ref) async {
      return ref.watch(
        prowlarrProvidersProvider(ProwlarrProviderKind.downloadClient).future,
      );
    }, retry: noProviderRetry);

/// Newznab categories, for the indexer category filter.
final prowlarrCategoriesProvider = FutureProvider<List<ProwlarrCategory>>((
  ref,
) async {
  return ref.watch(prowlarrServiceProvider).getIndexerCategories();
}, retry: noProviderRetry);

/// Tags with their usage, for the tag manager.
final prowlarrTagDetailsProvider = FutureProvider<List<ProwlarrTagDetail>>((
  ref,
) async {
  return ref.watch(prowlarrServiceProvider).getTagDetails();
}, retry: noProviderRetry);

/// Tags, used by the indexer filters and the edit form.
final prowlarrTagsProvider = FutureProvider<List<ProwlarrTag>>((ref) async {
  return ref.watch(prowlarrServiceProvider).getTags();
}, retry: noProviderRetry);

/// Tag labels by id, so a tile can render names instead of numbers.
final prowlarrTagLabelsProvider = Provider<Map<int, String>>((ref) {
  final tags = ref.watch(prowlarrTagsProvider);
  return tags.maybeWhen(
    data: (tags) => {for (final tag in tags) tag.id: tag.label},
    orElse: () => const <int, String>{},
  );
});

/// Sync profiles offered by the indexer edit form.
final prowlarrAppProfilesProvider = FutureProvider<List<ProwlarrAppProfile>>((
  ref,
) async {
  return ref.watch(prowlarrServiceProvider).getAppProfiles();
}, retry: noProviderRetry);

/// Every definition Prowlarr can add.
///
/// `autoDispose` on purpose: the payload is thousands of definitions and it is
/// only needed while the add-indexer picker is open.
final prowlarrIndexerSchemaProvider =
    FutureProvider.autoDispose<List<ProwlarrIndexer>>((ref) async {
      return ref.watch(prowlarrServiceProvider).getIndexerSchema();
    }, retry: noProviderRetry);
