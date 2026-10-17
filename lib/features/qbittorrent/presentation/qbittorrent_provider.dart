import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/gated_poll.dart'; // ignore: implementation_imports
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/read_clock.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;

import 'package:cupola/features/qbittorrent/data/qbittorrent_client_provider.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/qbittorrent/domain/torrent_list_order.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent_file.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent_properties.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent_tracker.dart';
import 'package:cupola/features/qbittorrent/domain/models/transfer_info.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

export 'package:cupola/features/qbittorrent/domain/torrent_list_order.dart'
    show TorrentFilter, TorrentSort;

final qbittorrentServiceProvider = Provider<QbittorrentService>((ref) {
  // Selected rather than watching the whole model: only this service's own
  // address and credentials, and the lens, decide which connection this is.
  final transport = watchTransport(ref, ServiceKey.qbittorrent);
  transport.ensureConfigured(ServiceKey.qbittorrent);
  // The connection's one client, which holds the WebUI SID cookie and any
  // refused sign-in, and which the Dashboard's probe and Home's reads share.
  // Owned and closed by its own provider, so moving the lens away and back
  // keeps the session instead of signing in again.
  return QbittorrentService(
    ref.watch(qbittorrentClientForProvider(transport.instanceId)),
    ref.watch(qbittorrentSyncForProvider(transport.instanceId)),
  );
});

/// The qBittorrent service for a route or background job that names a
/// connection explicitly.
///
/// Empty ids and the active id deliberately collapse onto the ordinary
/// provider, which reads the same client. A different id reads that
/// connection's own client: one client per connection, whoever asks
/// ([qbittorrentClientForProvider]).
final qbittorrentServiceForProvider =
    Provider.family<QbittorrentService, String>((ref, instanceId) {
      final activeId = ref
          .read(activeInstanceProvider(ServiceKey.qbittorrent))
          ?.id;
      if (instanceId.isEmpty || instanceId == activeId) {
        return ref.watch(qbittorrentServiceProvider);
      }

      final transport = watchTransport(
        ref,
        ServiceKey.qbittorrent,
        instanceId: instanceId,
      );
      transport.ensureConfigured(ServiceKey.qbittorrent);
      return QbittorrentService(
        ref.watch(qbittorrentClientForProvider(instanceId)),
        ref.watch(qbittorrentSyncForProvider(instanceId)),
      );
    });

/// Call first in a user's explicit Retry, or pull-to-refresh, on a qBittorrent
/// surface, before invalidating what it retries.
///
/// Forgets a sign-in refusal the lens's client is holding (see
/// `QbittorrentClient` and [qbittorrentClientForProvider]), so the one attempt
/// the person asked for is actually made: they fixed the password on the
/// server, or waited out a ban. Poll ticks invalidate directly
/// and never come through here: a timer that cleared the refusal would be the
/// loop that gets the address banned.
void clearQbittorrentLoginRefusal(WidgetRef ref) {
  // Checked rather than caught: the service provider throws when qBittorrent is
  // not configured, and every surface that offers a Retry has already gated on
  // this same question.
  if (ref
      .read(currentSettingsProvider)
      .isServiceConfigured(ServiceKey.qbittorrent)) {
    ref.read(qbittorrentServiceProvider).clearLoginRefusal();
  }
}

final torrentFilterProvider = StateProvider<TorrentFilter>(
  (ref) => TorrentFilter.all,
);

final torrentSortProvider = StateProvider<TorrentSort>(
  (ref) => TorrentSort.addedOn,
);

final torrentSortReverseProvider = StateProvider<bool>((ref) => true);

final torrentCategoryFilterProvider = StateProvider<String?>((ref) => null);

final torrentTagFilterProvider = StateProvider<String?>((ref) => null);

final torrentTrackerFilterProvider = StateProvider<String?>((ref) => null);

final torrentSearchQueryProvider = StateProvider<String>((ref) => '');

/// The whole torrent list, in the order the person chose.
///
/// Read from the connection's copy ([QbittorrentService.mainData]), which asks
/// `/api/v2/sync/maindata` only for what changed since its last answer, then
/// sorted here ([sortTorrents]). Invalidating it is a read: the copy asks the
/// server again, and a write since the last read is never answered from before
/// it (`QbittorrentSync.noteWrite`).
///
/// **Every `FutureProvider` in this feature carries `retry: noProviderRetry`**,
/// and this one is why. Riverpod's default re-runs a failed build ten times
/// behind an exponential backoff, and while it does the state is an
/// `AsyncLoading` that still holds the last value *and* the error, which
/// `when` routes to `loading`. The list's three-second poll then invalidates
/// before the tenth attempt, so a qBittorrent that went down stayed a spinner
/// for as long as the page was open, and the last-known list with its fault
/// band was never reached. Failing on the first attempt lands the error at
/// once; the poll, or the user's Retry, is the retry. The providers derived
/// from this one carry the flag too, or the derivation would quietly
/// reintroduce the retry the source refused.
///
/// **Where the list is noted as read** (`ReadClock`): here, right after the
/// answer lands, for the connection this build resolved. Every filtered view
/// ([torrentsProvider]) derives from this answer, so this is the read a
/// retained list is as old as.
final allTorrentsProvider = FutureProvider<List<Torrent>>((ref) async {
  final service = ref.watch(qbittorrentServiceProvider);
  final sort = ref.watch(torrentSortProvider);
  final reverse = ref.watch(torrentSortReverseProvider);
  final noteRead = ref.queueReadNoter(ServiceKey.qbittorrent);
  final data = await service.mainData();
  noteRead();
  return sortTorrents(data.torrents, sort, reverse: reverse);
}, retry: noProviderRetry);

final availableCategoriesProvider = Provider<List<String>>((ref) {
  final torrents = ref.watch(allTorrentsProvider).asData?.value;
  if (torrents == null) return [];
  return torrents
      .where((t) => t.category.isNotEmpty)
      .map((t) => t.category)
      .toSet()
      .toList()
    ..sort();
});

final availableTagsProvider = Provider<List<String>>((ref) {
  final torrents = ref.watch(allTorrentsProvider).asData?.value;
  if (torrents == null) return [];
  final tags = <String>{};
  for (final t in torrents) {
    tags.addAll(t.tags);
  }
  return tags.toList()..sort();
});

final availableTrackersProvider = Provider<List<String>>((ref) {
  final torrents = ref.watch(allTorrentsProvider).asData?.value;
  if (torrents == null) return [];
  final trackers = <String>{};
  for (final t in torrents) {
    if (t.trackerDomain.isNotEmpty) trackers.add(t.trackerDomain);
  }
  return trackers.toList()..sort();
});

/// The list as the tab, the chips and the search narrow it, all on the phone
/// over [allTorrentsProvider]'s answer: no request of its own, so a new tab or
/// a letter typed in the search costs nothing on the wire.
final torrentsProvider = FutureProvider<List<Torrent>>((ref) async {
  final filter = ref.watch(torrentFilterProvider);
  final categoryFilter = ref.watch(torrentCategoryFilterProvider);
  final tagFilter = ref.watch(torrentTagFilterProvider);
  final trackerFilter = ref.watch(torrentTrackerFilterProvider);
  final searchQuery = ref
      .watch(torrentSearchQueryProvider)
      .trim()
      .toLowerCase();

  var torrents = [
    for (final t in await ref.watch(allTorrentsProvider.future))
      if (torrentMatches(t, filter)) t,
  ];

  if (categoryFilter != null && categoryFilter.isNotEmpty) {
    torrents = torrents.where((t) => t.category == categoryFilter).toList();
  }

  if (tagFilter != null && tagFilter.isNotEmpty) {
    torrents = torrents.where((t) => t.tags.contains(tagFilter)).toList();
  }

  if (trackerFilter != null) {
    torrents = torrents.where((t) => t.trackerDomain == trackerFilter).toList();
  }

  if (searchQuery.isNotEmpty) {
    torrents = torrents
        .where(
          (t) =>
              t.name.toLowerCase().contains(searchQuery) ||
              t.category.toLowerCase().contains(searchQuery) ||
              t.tags.any((tag) => tag.toLowerCase().contains(searchQuery)),
        )
        .toList();
  }

  return torrents;
}, retry: noProviderRetry);

// The four detail families below are polled every three seconds by
// [torrentDetailPollingProvider], so they fail fast for the reason
// [allTorrentsProvider] states.

/// The one torrent the detail screen shows, from the connection's copy: a
/// read of what changed, not a request of its own. Empty when the server no
/// longer holds it (deleted from elsewhere).
final qbittorrentTorrentsProvider =
    FutureProvider.family<List<Torrent>, String>((ref, hash) async {
      final service = ref.watch(qbittorrentServiceProvider);
      final torrent = (await service.mainData()).torrent(hash);
      return [?torrent];
    }, retry: noProviderRetry);

final torrentFilesProvider = FutureProvider.family<List<TorrentFile>, String>((
  ref,
  hash,
) async {
  final service = ref.watch(qbittorrentServiceProvider);
  return service.getTorrentFiles(hash);
}, retry: noProviderRetry);

final torrentTrackersProvider =
    FutureProvider.family<List<TorrentTracker>, String>((ref, hash) async {
      final service = ref.watch(qbittorrentServiceProvider);
      return service.getTorrentTrackers(hash);
    }, retry: noProviderRetry);

final torrentPropertiesProvider =
    FutureProvider.family<TorrentProperties, String>((ref, hash) async {
      final service = ref.watch(qbittorrentServiceProvider);
      return service.getTorrentProperties(hash);
    }, retry: noProviderRetry);

/// The session's figures, from the same answer as the list: the poll ticks
/// both together, and the connection's copy asks once for the two
/// (`QbittorrentSync`).
final transferInfoProvider = FutureProvider<TransferInfo>((ref) async {
  final service = ref.watch(qbittorrentServiceProvider);
  return (await service.mainData()).transfer;
}, retry: noProviderRetry);

final selectedTorrentHashesProvider = StateProvider.autoDispose<Set<String>>(
  (ref) => {},
);

/// The torrent list's live refresh, for as long as the list is what the user is
/// looking at.
///
/// Watched through `WidgetRef.watchWhileLive`, so this provider's own lifetime is
/// the gate: the moment the page is not the page on screen the watch is dropped,
/// the last listener goes, and the timer with it.
final torrentPollingProvider = Provider.autoDispose<void>((ref) {
  ref.gatedPoll(
    id: 'qbittorrent.list',
    interval: _pollInterval,
    onTick: () => _refreshUnlessInFlight(ref, [
      allTorrentsProvider,
      torrentsProvider,
      transferInfoProvider,
    ]),
  );
});

/// Invalidates [providers] for a poll tick, except any whose last request
/// has not answered yet.
///
/// The tick is three seconds and the transport's connect timeout is ten, so
/// against a host that drops packets instead of refusing them, invalidating on
/// every tick threw each request away before it could fail: the provider never
/// left `loading`, the cold open was a spinner for as long as the page stayed
/// open, and no error (hence no fault band) ever landed. A request still in
/// flight is left to finish; the tick after it answers refreshes as usual.
///
/// All of them are inspected **before** any is invalidated: reading a provider
/// whose dependency this tick has just invalidated would force it to rebuild
/// on the spot, inside the tick. And only a provider that already exists is
/// inspected, so a tick never creates one just to ask about it. The same
/// no-op `invalidate` is for a provider nothing has read.
void _refreshUnlessInFlight(
  Ref ref,
  List<ProviderBase<AsyncValue<Object?>>> providers,
) {
  final idle = [
    for (final provider in providers)
      if (!ref.exists(provider) || !ref.read(provider).isLoading) provider,
  ];
  for (final provider in idle) {
    ref.invalidate(provider);
  }
}

/// One torrent's own live refresh.
///
/// Invalidates only what the detail screen displays, and it is the only poll
/// running while the detail is open: the list it was pushed from is covered, so
/// that gate is shut. The torrent itself comes from the connection's copy, so
/// its tick is one read of what changed, plus the files, trackers and
/// properties only this screen shows.
///
/// Popping back gives the list a catch-up tick, so what it shows is a frame
/// behind the return rather than up to three seconds stale.
final torrentDetailPollingProvider = Provider.autoDispose.family<void, String>((
  ref,
  hash,
) {
  ref.gatedPoll(
    id: 'qbittorrent.detail.$hash',
    interval: _pollInterval,
    onTick: () => _refreshUnlessInFlight(ref, [
      qbittorrentTorrentsProvider(hash),
      torrentFilesProvider(hash),
      torrentTrackersProvider(hash),
      torrentPropertiesProvider(hash),
    ]),
  );
});

/// The cadence both qBittorrent polls run at.
const _pollInterval = Duration(seconds: 3);
