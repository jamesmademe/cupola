import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/gated_poll.dart'; // ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent_file.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent_properties.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent_tracker.dart';
import 'package:cupola/features/qbittorrent/domain/models/transfer_info.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

final qbittorrentServiceProvider = Provider<QbittorrentService>((ref) {
  // Selected rather than watching the whole model, and here that matters twice
  // over: the client holds the WebUI SID cookie, so rebuilding it throws away
  // an authenticated session. Only this service's own address and credentials
  // should do that.
  final transport = ref.watch(
    currentSettingsProvider.select(
      (s) => (
        configured: s.isServiceConfigured(ServiceKey.qbittorrent),
        url: s.qbittorrentUrl,
        username: s.qbittorrentUsername,
        password: s.qbittorrentPassword,
        pin: s.pinForUrl(s.qbittorrentUrl),
      ),
    ),
  );
  if (!transport.configured) {
    throw Exception('qBittorrent not configured');
  }
  final client = QbittorrentClient(
    url: transport.url,
    username: transport.username.isNotEmpty ? transport.username : null,
    password: transport.password.isNotEmpty ? transport.password : null,
    certFingerprint: transport.pin,
  );
  // The outgoing client owns a Dio and a cookie jar; close it so neither leaks.
  ref.onDispose(() => client.close());
  return QbittorrentService(client);
});

enum TorrentFilter { all, downloading, seeding, completed, paused, queued }

enum TorrentSort {
  name,
  size,
  progress,
  dlSpeed,
  upSpeed,
  eta,
  addedOn,
  state;

  String get apiValue {
    switch (this) {
      case TorrentSort.name:
        return 'name';
      case TorrentSort.size:
        return 'size';
      case TorrentSort.progress:
        return 'progress';
      case TorrentSort.dlSpeed:
        return 'dlspeed';
      case TorrentSort.upSpeed:
        return 'upspeed';
      case TorrentSort.eta:
        return 'eta';
      case TorrentSort.addedOn:
        return 'added_on';
      case TorrentSort.state:
        return 'state';
    }
  }

  String get label {
    switch (this) {
      case TorrentSort.name:
        return 'Name';
      case TorrentSort.size:
        return 'Size';
      case TorrentSort.progress:
        return 'Progress';
      case TorrentSort.dlSpeed:
        return '↓ Speed';
      case TorrentSort.upSpeed:
        return '↑ Speed';
      case TorrentSort.eta:
        return 'ETA';
      case TorrentSort.addedOn:
        return 'Added';
      case TorrentSort.state:
        return 'State';
    }
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

final allTorrentsProvider = FutureProvider<List<Torrent>>((ref) async {
  final service = ref.watch(qbittorrentServiceProvider);
  final sort = ref.watch(torrentSortProvider);
  final reverse = ref.watch(torrentSortReverseProvider);
  return service.getTorrents(sort: sort.apiValue, reverse: reverse);
});

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

final torrentsProvider = FutureProvider<List<Torrent>>((ref) async {
  final service = ref.watch(qbittorrentServiceProvider);
  final filter = ref.watch(torrentFilterProvider);
  final sort = ref.watch(torrentSortProvider);
  final reverse = ref.watch(torrentSortReverseProvider);
  final categoryFilter = ref.watch(torrentCategoryFilterProvider);
  final tagFilter = ref.watch(torrentTagFilterProvider);
  final trackerFilter = ref.watch(torrentTrackerFilterProvider);
  final searchQuery = ref
      .watch(torrentSearchQueryProvider)
      .trim()
      .toLowerCase();

  final apiFilter = switch (filter) {
    TorrentFilter.downloading => 'downloading',
    TorrentFilter.seeding => 'seeding',
    TorrentFilter.completed => 'completed',
    TorrentFilter.paused => 'stopped',
    _ => 'all',
  };

  // Whenever the server-side filter resolves to "all", reuse
  // allTorrentsProvider — it requests the very same /torrents/info payload
  // (no `filter` param, which qB's WebUI v2 defaults to `all`) with the same
  // sort and direction, and it is already alive on this screen. Fetching
  // separately here would download and parse the identical body twice on
  // every 3s poll tick. Sub-filters and the search query are applied
  // client-side below, so they do not need their own request.
  var torrents = apiFilter == 'all'
      ? await ref.watch(allTorrentsProvider.future)
      : await service.getTorrents(
          filter: apiFilter,
          sort: sort.apiValue,
          reverse: reverse,
        );

  if (filter == TorrentFilter.queued) {
    torrents = torrents.where((t) => t.parsedState.isQueued).toList();
  }

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
});

final qbittorrentTorrentsProvider =
    FutureProvider.family<List<Torrent>, String>((ref, hash) async {
      final service = ref.watch(qbittorrentServiceProvider);
      return service.getTorrents(hashes: hash);
    });

final torrentFilesProvider = FutureProvider.family<List<TorrentFile>, String>((
  ref,
  hash,
) async {
  final service = ref.watch(qbittorrentServiceProvider);
  return service.getTorrentFiles(hash);
});

final torrentTrackersProvider =
    FutureProvider.family<List<TorrentTracker>, String>((ref, hash) async {
      final service = ref.watch(qbittorrentServiceProvider);
      return service.getTorrentTrackers(hash);
    });

final torrentPropertiesProvider =
    FutureProvider.family<TorrentProperties, String>((ref, hash) async {
      final service = ref.watch(qbittorrentServiceProvider);
      return service.getTorrentProperties(hash);
    });

final transferInfoProvider = FutureProvider<TransferInfo>((ref) async {
  final service = ref.watch(qbittorrentServiceProvider);
  return service.getTransferInfo();
});

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
    onTick: () {
      ref.invalidate(allTorrentsProvider);
      ref.invalidate(torrentsProvider);
      ref.invalidate(transferInfoProvider);
    },
  );
});

/// One torrent's own live refresh.
///
/// Invalidates only what the detail screen displays, and it is the only poll
/// running while the detail is open: the list it was pushed from is covered, so
/// that gate is shut. The saving is the list's whole tick — an unfiltered
/// `/torrents/info` plus `/transfer/info` — not this screen's own filtered
/// `/torrents/info`, which is a different request to the same endpoint and is
/// what this page actually reads.
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
    onTick: () {
      ref.invalidate(qbittorrentTorrentsProvider(hash));
      ref.invalidate(torrentFilesProvider(hash));
      ref.invalidate(torrentTrackersProvider(hash));
      ref.invalidate(torrentPropertiesProvider(hash));
    },
  );
});

/// The cadence both qBittorrent polls run at.
const _pollInterval = Duration(seconds: 3);
