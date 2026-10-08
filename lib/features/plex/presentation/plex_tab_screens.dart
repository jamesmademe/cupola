import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/plex/presentation/plex_capability.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/presentation/stream_overview_provider.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_now_playing_section.dart';

/// The token owner's part-watched titles from Plex's continue-watching hub.
class PlexOnDeckScreen extends ConsumerWidget {
  const PlexOnDeckScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref)) return _notConfigured();
    return _PlexOnDeckBody(topPadding: topPadding);
  }
}

/// Current Plex playback activity.
///
/// The client has no `/activities` contract. Live sessions are the real,
/// operable activity it does expose, so this tab reuses the Stream session
/// shell instead of fabricating a server-job feed.
class PlexActivitiesScreen extends ConsumerWidget {
  const PlexActivitiesScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref)) return _notConfigured();
    return _PlexActivitiesBody(topPadding: topPadding);
  }
}

class PlexDevicesScreen extends ConsumerWidget {
  const PlexDevicesScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref)) return _notConfigured();
    return ServiceListPage<PlexDevice>(
      service: ServiceKey.plex,
      topPadding: topPadding,
      value: ref.watch(plexDevicesProvider),
      serviceName: 'Plex devices',
      emptyIcon: Icons.devices_other_rounded,
      emptyTitle: 'No devices',
      emptyMessage: 'Plex returned no authorized devices.',
      onRetry: () => ref.invalidate(plexDevicesProvider),
      summary: (devices) => countLabel(devices.length, 'device'),
      rowBuilder: (device) => _DeviceRow(device: device),
    );
  }
}

class PlexPlaylistsScreen extends ConsumerWidget {
  const PlexPlaylistsScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref)) return _notConfigured();
    return ServiceListPage<PlexPlaylist>(
      service: ServiceKey.plex,
      topPadding: topPadding,
      value: ref.watch(plexPlaylistsProvider),
      serviceName: 'Plex playlists',
      emptyIcon: Icons.playlist_play_rounded,
      emptyTitle: 'No playlists',
      emptyMessage: 'Create a Plex playlist to see it here.',
      onRetry: () => ref.invalidate(plexPlaylistsProvider),
      summary: (playlists) => countLabel(playlists.length, 'playlist'),
      rowBuilder: (playlist) => _PlaylistRow(playlist: playlist),
    );
  }
}

bool _isConfigured(WidgetRef ref) =>
    ref.watch(currentSettingsProvider).isServiceConfigured(ServiceKey.plex);

Widget _notConfigured() => NotConfiguredPlaceholder.forService(ServiceKey.plex);

class _PlexOnDeckBody extends ConsumerWidget {
  const _PlexOnDeckBody({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(plexOnDeckTabProvider);
    // The host's two bands and the status bar the upper one consumes: this
    // page has no `SafeArea` and no app bar to take the inset off first.
    final top = topPadding + MediaQuery.paddingOf(context).top;
    // The tab is this one read, so a cold failure is the server's leaf.
    if (items.hasError && !items.hasValue) {
      return AmbientScaffold(
        accent: ServiceKey.plex.accent,
        body: Padding(
          padding: EdgeInsets.only(top: top),
          child: ServiceOfflineState.failure(
            service: ServiceKey.plex,
            error: items.error!,
            onRetry: () => ref.invalidate(plexOnDeckTabProvider),
          ),
        ),
      );
    }
    return AmbientScaffold(
      accent: ServiceKey.plex.accent,
      body: Padding(
        padding: EdgeInsets.only(top: top),
        child: AsyncValueWidget<List<StreamItem>>(
          value: items,
          serviceName: 'Plex on deck',
          loadingLabel: 'Loading what is on deck',
          onRetry: () => ref.invalidate(plexOnDeckTabProvider),
          isEmpty: (list) => list.isEmpty,
          emptyBuilder: AppEmptyStatePage(
            emptyState: AppEmptyState(
              icon: Icons.play_circle_outline_rounded,
              title: 'Nothing part-watched',
              message: 'Titles appear here after the owner starts watching.',
              accentColor: ServiceKey.plex.accent,
            ),
          ),
          skeleton: AppSkeleton.posterGrid(count: 9),
          data: (list) => _OnDeckGrid(items: list),
        ),
      ),
    );
  }
}

class _PlexActivitiesBody extends ConsumerWidget {
  const _PlexActivitiesBody({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(plexSessionsProvider);
    // The host's two bands and the status bar the upper one consumes: this
    // page has no `SafeArea` and no app bar to take the inset off first.
    final top = topPadding + MediaQuery.paddingOf(context).top;
    // A refusal that turns out to be a shared account's token is Now
    // playing's to say, in blue, and so is the moment before the probe has
    // said: the page is not offline.
    if (sessions.hasError &&
        !sessions.hasValue &&
        plexSessionsRefusal(
              ref,
              capabilityConnectionId(ref, ServiceKey.plex),
              sessions.error,
            ) ==
            PlexSessionsRefusal.failure) {
      return AmbientScaffold(
        accent: ServiceKey.plex.accent,
        body: Padding(
          padding: EdgeInsets.only(top: top),
          child: ServiceOfflineState.failure(
            service: ServiceKey.plex,
            error: sessions.error!,
            onRetry: () => ref.invalidate(plexSessionsProvider),
          ),
        ),
      );
    }
    return AmbientScaffold(
      accent: ServiceKey.plex.accent,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(plexSessionsProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            0,
            top + AppSpacing.md,
            0,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            StreamNowPlayingSection(
              service: ServiceKey.plex,
              sessions: sessions,
            ),
          ],
        ),
      ),
    );
  }
}

class _OnDeckGrid extends ConsumerWidget {
  const _OnDeckGrid({required this.items});

  final List<StreamItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(plexServerProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(plexOnDeckTabProvider),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = MediaGrid.columnsFor(
            constraints.maxWidth - (AppSpacing.lg * 2),
            3,
          );
          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              FloatingNavBarMetrics.getScrollViewBottomPadding(context),
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: AppSpacing.gridGap,
              mainAxisSpacing: AppSpacing.gridGap,
              childAspectRatio: TextScaleMetrics.aspectRatio(
                context,
                base: 0.58,
              ),
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
              child: StaggeredEntrance(
                index: index,
                wrapCount: columns * 4,
                child: _OnDeckTile(
                  item: items[index],
                  index: index,
                  poster: items[index].posterPath == null
                      ? null
                      : client.imageFor(items[index].posterPath!, width: 260),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OnDeckTile extends StatelessWidget {
  const _OnDeckTile({
    required this.item,
    required this.index,
    required this.poster,
  });

  final StreamItem item;
  final int index;
  final StreamImageSource? poster;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = streamOnDeckCaption(item);
    return PressableScale(
      onTap: () => context.openStreamItem(ServiceKey.plex, item),
      semanticLabel: item.title,
      semanticValue: caption.isEmpty ? null : spokenFromDotted(caption),
      semanticHint: 'Open this title',
      excludeChildSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: MediaPosterCard(
              heroTag: 'stream_tab_ondeck_plex_${item.id}_$index',
              imageUrl: poster?.url,
              imageHeaders: poster?.headers,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall
                ?.weight(FontWeight.w600)
                .copyWith(color: theme.colorScheme.onSurface),
          ),
          if (caption.isNotEmpty)
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: CupolaThemeColors.of(context).dimText,
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device});

  final PlexDevice device;

  @override
  Widget build(BuildContext context) {
    final name = device.name.trim().isEmpty ? 'Unnamed device' : device.name;
    final product = device.product.trim().isEmpty
        ? 'Client unavailable'
        : device.product.trim();
    final platform = device.platform.trim().isEmpty
        ? 'Platform unavailable'
        : device.platform.trim();
    final lastSeen = device.lastSeenAt == null
        ? 'Last seen unavailable'
        : 'Last seen ${formatRelativeDateTime(device.lastSeenAt!)}';
    final provides = device.provides.isEmpty
        ? 'Capabilities unavailable'
        : device.provides.join(', ');
    return ServiceRecordRow(
      icon: Icons.devices_other_rounded,
      tone: StatusTone.neutral,
      title: name,
      detail: '$product · $platform · $lastSeen',
      trailing: device.provides.isEmpty ? '—' : device.provides.join(' · '),
      semanticLabel: '$name, $product, $platform, $provides, $lastSeen',
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist});

  final PlexPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final title = playlist.title.trim().isEmpty
        ? 'Untitled playlist'
        : playlist.title.trim();
    final kind = playlist.smart ? 'Smart playlist' : 'Playlist';
    final media = playlist.playlistType.trim().isEmpty
        ? 'Media type unavailable'
        : playlist.playlistType.trim();
    final duration = _durationLabel(playlist.durationMs);
    final updated = playlist.updatedAt == null
        ? 'Updated unavailable'
        : 'Updated ${formatRelativeDateTime(playlist.updatedAt!)}';
    final itemCount = playlist.itemCount;
    final itemLabel = itemCount == null
        ? 'Items unavailable'
        : countLabel(itemCount, 'item');
    final detail = [media, ?duration, updated].join(' · ');
    return ServiceRecordRow(
      icon: playlist.smart
          ? Icons.auto_awesome_rounded
          : Icons.playlist_play_rounded,
      tone: playlist.smart ? StatusTone.info : StatusTone.neutral,
      title: title,
      detail: detail,
      trailing: itemCount == null ? '—' : '$itemCount',
      semanticLabel: '$title, $kind, $itemLabel, ${spokenFromDotted(detail)}',
    );
  }
}

String? _durationLabel(int? milliseconds) {
  if (milliseconds == null || milliseconds < 0) return null;
  final duration = Duration(milliseconds: milliseconds);
  return formatTimeSpan(duration);
}
