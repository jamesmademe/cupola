import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/status/read_age.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';
import 'package:cupola/core/widgets/service_kpi_peek.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/widgets/torrent_list_controls.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/widgets/torrent_selection_bar.dart';
import 'package:cupola/features/qbittorrent/presentation/widgets/torrent_tile.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class QbittorrentScreen extends ConsumerStatefulWidget {
  final double topPadding;

  const QbittorrentScreen({super.key, this.topPadding = 0});

  @override
  ConsumerState<QbittorrentScreen> createState() => _QbittorrentScreenState();
}

class _QbittorrentScreenState extends ConsumerState<QbittorrentScreen> {
  @override
  Widget build(BuildContext context) {
    // The not-configured gate comes FIRST, and before anything is watched.
    //
    // Its three sibling download clients have had it since they shipped; this
    // one reached the providers regardless and let `AsyncValueWidget` recognise
    // the `qBittorrent not configured` exception on the way out. The rendering
    // was right and the work was not: a `FutureProvider` that throws is a
    // provider that failed, so Riverpod's default retry scheduled a backoff for
    // a condition no amount of waiting changes: a connection is configured in
    // Settings or it is not. Reaching the placeholder without asking is the
    // same screen for none of the timers.
    final settings = ref.watch(currentSettingsProvider);
    if (!settings.isServiceConfigured(ServiceKey.qbittorrent)) {
      return AmbientScaffold(
        accent: ServiceKey.qbittorrent.accent,
        body: SafeArea(
          child: NotConfiguredPlaceholder.forService(ServiceKey.qbittorrent),
        ),
      );
    }

    // Poll only while this page is the page on screen. Replaces an observer of
    // its own that paused on app background: that covered one of the four ways
    // this list stops being read, and missed the three the shell now reports:
    // another tab showing, a torrent's detail pushed on top, the Portal open
    // over it.
    ref.watchWhileLive(context, torrentPollingProvider);
    final torrentsAsync = ref.watch(torrentsProvider);
    final selectedHashes = ref.watch(selectedTorrentHashesProvider);
    // How old the rows are, only while they are the last list read under a
    // fault band: their ETAs are the one figure that is certainly false then.
    final sampleAge = ref.watchQueueReadAge(
      context,
      ServiceKey.qbittorrent,
      underBand: showsLastReadUnderBand(torrentsAsync),
    );

    return AmbientScaffold(
      accent: ServiceKey.qbittorrent.accent,
      body: Column(
        children: [
          // Stats + search + filter/sort rows scroll away with the torrent
          // list; the selection action bar stays pinned at the bottom.
          Expanded(
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                if (widget.topPadding > 0)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height:
                          widget.topPadding + MediaQuery.paddingOf(context).top,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: ServiceKpiPeek(
                    kpis: ref.watch(serviceKpiProvider(ServiceKey.qbittorrent)),
                    accent: ServiceKey.qbittorrent.accent,
                  ),
                ),
                SliverToBoxAdapter(
                  child: SearchBarHeader(
                    hintText: 'Search torrents',
                    onQueryChanged: (query) {
                      ref.read(torrentSearchQueryProvider.notifier).state =
                          query;
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: TorrentFilterChipsRow()),
                const SliverToBoxAdapter(child: TorrentFilterPillsRow()),
                const SliverToBoxAdapter(child: TorrentSortRow()),
              ],
              body: _buildTorrentList(
                context,
                torrentsAsync,
                selectedHashes,
                sampleAge,
              ),
            ),
          ),
          TorrentSelectionBar(
            onConfirmDelete: () =>
                confirmDeleteTorrents(context, ref, selectedHashes),
          ),
        ],
      ),
    );
  }

  Widget _buildTorrentList(
    BuildContext context,
    AsyncValue<List<Torrent>> torrentsAsync,
    Set<String> selectedHashes,
    Duration? sampleAge,
  ) {
    return AsyncValueWidget<List<Torrent>>(
      value: torrentsAsync,
      serviceName: 'qBittorrent',
      silentService: ServiceKey.qbittorrent,
      onRetry: () {
        clearQbittorrentLoginRefusal(ref);
        ref.invalidate(allTorrentsProvider);
        ref.invalidate(torrentsProvider);
        ref.invalidate(transferInfoProvider);
      },
      data: (torrents) {
        if (torrents.isEmpty) {
          return const _EmptyTorrents();
        }

        return RefreshIndicator(
          onRefresh: () async {
            clearQbittorrentLoginRefusal(ref);
            ref.invalidate(allTorrentsProvider);
            ref.invalidate(torrentsProvider);
            ref.invalidate(transferInfoProvider);
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              top: 4,
              bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
            ),
            itemCount: torrents.length,
            itemBuilder: (context, index) {
              final torrent = torrents[index];
              return TorrentTile(
                torrent: torrent,
                selected: selectedHashes.contains(torrent.hash),
                sampleAge: sampleAge,
                onTap: () {
                  if (selectedHashes.isNotEmpty) {
                    _toggleSelection(ref, torrent.hash);
                  } else {
                    context.push(
                      ServiceRoutes.qbittorrentTorrent(torrent.hash),
                    );
                  }
                },
                onLongPress: () => _toggleSelection(ref, torrent.hash),
              );
            },
          ),
        );
      },
    );
  }

  void _toggleSelection(WidgetRef ref, String hash) {
    final notifier = ref.read(selectedTorrentHashesProvider.notifier);
    final current = Set<String>.from(notifier.state);
    if (current.contains(hash)) {
      current.remove(hash);
    } else {
      current.add(hash);
    }
    notifier.state = current;
  }
}

/// No torrent to draw: one line where the rows would start, on their edge, as
/// every other client's empty queue reads. A filter that hides everything says
/// so rather than claiming the client holds nothing.
class _EmptyTorrents extends ConsumerWidget {
  const _EmptyTorrents();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered =
        ref.watch(torrentFilterProvider) != TorrentFilter.all ||
        (ref.watch(torrentCategoryFilterProvider)?.isNotEmpty ?? false) ||
        (ref.watch(torrentTagFilterProvider)?.isNotEmpty ?? false) ||
        (ref.watch(torrentTrackerFilterProvider)?.isNotEmpty ?? false) ||
        ref.watch(torrentSearchQueryProvider).trim().isNotEmpty;
    // Scrollable, so the pull to refresh and the header slivers above it
    // behave as they do over rows.
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        filtered
            ? const AppEmptyState.inline(
                icon: Icons.filter_alt_off_rounded,
                title: 'No matching torrents',
              )
            : const AppEmptyState.inline(
                icon: Icons.download_done_rounded,
                title: 'No torrents',
              ),
      ],
    );
  }
}
