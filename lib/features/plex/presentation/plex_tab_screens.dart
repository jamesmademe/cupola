import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/plex/presentation/plex_capability.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';
import 'package:cupola/features/stream/presentation/stream_overview_provider.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_now_playing_section.dart';

/// The token owner's part-watched titles from Plex's continue-watching hub.
///
/// [instanceId] is the `?i=` of the location the tab was built for. A tab's
/// root reads the connection the visit has in view first (`streamInstanceOf`,
/// not pinned) and this where the visit has none; null reads the lens. The same
/// on every tab below.
class PlexOnDeckScreen extends ConsumerWidget {
  const PlexOnDeckScreen({super.key, this.topPadding = 0, this.instanceId});

  final double topPadding;
  final String? instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref)) return _notConfigured();
    return _PlexOnDeckBody(
      topPadding: topPadding,
      instanceId: streamInstanceOf(
        ref,
        ServiceKey.plex,
        instanceId,
        pinned: false,
      ),
    );
  }
}

/// Current Plex playback activity.
///
/// The client has no `/activities` contract. Live sessions are the real,
/// operable activity it does expose, so this tab reuses the Stream session
/// shell instead of fabricating a server-job feed.
///
/// [instanceId] is the connection to read (`?i=`); null, or one that is not a
/// Plex connection, reads the active one.
class PlexActivitiesScreen extends ConsumerWidget {
  const PlexActivitiesScreen({super.key, this.topPadding = 0, this.instanceId});

  final double topPadding;
  final String? instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref)) return _notConfigured();
    return _PlexActivitiesBody(
      topPadding: topPadding,
      instanceId: streamInstanceOf(
        ref,
        ServiceKey.plex,
        instanceId,
        pinned: false,
      ),
    );
  }
}

class PlexDevicesScreen extends ConsumerWidget {
  const PlexDevicesScreen({super.key, this.topPadding = 0, this.instanceId});

  final double topPadding;
  final String? instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref)) return _notConfigured();
    final connection = streamInstanceOf(
      ref,
      ServiceKey.plex,
      instanceId,
      pinned: false,
    );
    return ServiceListPage<PlexDevice>(
      service: ServiceKey.plex,
      instanceId: connection,
      topPadding: topPadding,
      value: ref.watch(plexDevicesForProvider(connection)),
      serviceName: 'Plex devices',
      emptyIcon: Icons.devices_other_rounded,
      emptyTitle: 'No devices',
      emptyMessage: 'Plex returned no authorized devices.',
      onRetry: () {
        ref.invalidate(plexDevicesForProvider(connection));
        ref.invalidate(plexDevicesProvider);
      },
      summary: (devices) => countLabel(devices.length, 'device'),
      rowBuilder: (device) => _DeviceRow(device: device),
    );
  }
}

class PlexPlaylistsScreen extends ConsumerWidget {
  const PlexPlaylistsScreen({super.key, this.topPadding = 0, this.instanceId});

  final double topPadding;
  final String? instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref)) return _notConfigured();
    final connection = streamInstanceOf(
      ref,
      ServiceKey.plex,
      instanceId,
      pinned: false,
    );
    return ServiceListPage<PlexPlaylist>(
      service: ServiceKey.plex,
      instanceId: connection,
      topPadding: topPadding,
      value: ref.watch(plexPlaylistsForProvider(connection)),
      serviceName: 'Plex playlists',
      emptyIcon: Icons.playlist_play_rounded,
      emptyTitle: 'No playlists',
      emptyMessage: 'Create a Plex playlist to see it here.',
      onRetry: () {
        ref.invalidate(plexPlaylistsForProvider(connection));
        ref.invalidate(plexPlaylistsProvider);
      },
      summary: (playlists) => countLabel(playlists.length, 'playlist'),
      rowBuilder: (playlist) => _PlaylistRow(playlist: playlist),
    );
  }
}

bool _isConfigured(WidgetRef ref) =>
    ref.watch(currentSettingsProvider).isServiceConfigured(ServiceKey.plex);

Widget _notConfigured() => NotConfiguredPlaceholder.forService(ServiceKey.plex);

class _PlexOnDeckBody extends ConsumerWidget {
  const _PlexOnDeckBody({required this.topPadding, required this.instanceId});

  final double topPadding;

  /// The connection whose deck this is; empty is the lens.
  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(plexOnDeckTabForProvider(instanceId));
    void reload() {
      ref.invalidate(plexOnDeckTabForProvider(instanceId));
      ref.invalidate(plexOnDeckTabProvider);
    }

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
            instanceId: instanceId,
            error: items.error!,
            onRetry: reload,
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
          instanceId: instanceId,
          loadingLabel: 'Loading what is on deck',
          onRetry: reload,
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
          data: (list) => _OnDeckGrid(
            items: list,
            instanceId: instanceId,
            onReload: reload,
          ),
        ),
      ),
    );
  }
}

class _PlexActivitiesBody extends ConsumerWidget {
  const _PlexActivitiesBody({
    required this.topPadding,
    required this.instanceId,
  });

  final double topPadding;
  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = (service: ServiceKey.plex, instanceId: instanceId);
    ref.watchWhileLive(context, streamSessionsPollProvider(connection));
    final sessions = ref.watch(streamSessionsForProvider(connection));
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
              instanceId.isEmpty
                  ? capabilityConnectionId(ref, ServiceKey.plex)
                  : instanceId,
              sessions.error,
            ) ==
            PlexSessionsRefusal.failure) {
      return AmbientScaffold(
        accent: ServiceKey.plex.accent,
        body: Padding(
          padding: EdgeInsets.only(top: top),
          child: ServiceOfflineState.failure(
            service: ServiceKey.plex,
            instanceId: instanceId,
            error: sessions.error!,
            onRetry: () =>
                refreshStreamSessions(ref, ServiceKey.plex, instanceId),
          ),
        ),
      );
    }
    return AmbientScaffold(
      accent: ServiceKey.plex.accent,
      body: RefreshIndicator(
        onRefresh: () async =>
            refreshStreamSessions(ref, ServiceKey.plex, instanceId),
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
              instanceId: instanceId,
              sessions: sessions,
            ),
          ],
        ),
      ),
    );
  }
}

class _OnDeckGrid extends ConsumerWidget {
  const _OnDeckGrid({
    required this.items,
    required this.instanceId,
    required this.onReload,
  });

  final List<StreamItem> items;
  final String instanceId;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(
      streamClientForProvider((
        service: ServiceKey.plex,
        instanceId: instanceId,
      )),
    );
    return RefreshIndicator(
      onRefresh: () async => onReload(),
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
                  instanceId: instanceId,
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
    required this.instanceId,
    required this.index,
    required this.poster,
  });

  final StreamItem item;

  /// The connection the deck was read from, which the title opens on.
  final String instanceId;
  final int index;
  final StreamImageSource? poster;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = streamOnDeckCaption(item);
    return PressableScale(
      onTap: () =>
          context.openStreamItem(ServiceKey.plex, item, instanceId: instanceId),
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
      detail: '$product\u00A0· $platform\u00A0· $lastSeen',
      trailing: device.provides.isEmpty
          ? '—'
          : device.provides.join(dotSeparator),
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
    final detail = [media, ?duration, updated].join(dotSeparator);
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
