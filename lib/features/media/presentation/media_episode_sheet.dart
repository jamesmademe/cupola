import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/artwork_decode.dart';
import 'package:cupola/core/widgets/machine_name.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/media/domain/quality_words.dart';
import 'package:cupola/features/media/presentation/media_episode_providers.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

/// The Sonarr that tracks the series, as an episode's sheet acts on it.
typedef MediaEpisodeSonarr = ({
  ServiceInstance connection,
  String name,
  int seriesId,
  int? profileId,
});

/// The media server that holds the episodes, as an episode's sheet plays
/// them.
typedef MediaEpisodeServer = ({ServiceInstance connection, String name});

/// One episode, whole: its still, its title and when it aired, TMDB's score,
/// where to play it and how far the viewer is, its synopsis, and what Sonarr
/// holds of it (the file, a search for what is missing or below the cutoff,
/// whether it is monitored). The chevrons walk the series an episode at a
/// time.
///
/// TMDB's still, synopsis and votes come through [seerr], read when the
/// sheet opens; Sonarr's file the same way. The requester ([operator] false)
/// reads no Sonarr.
class MediaEpisodeSheet extends ConsumerStatefulWidget {
  const MediaEpisodeSheet({
    super.key,
    required this.seriesTitle,
    required this.seasons,
    required this.season,
    required this.number,
    required this.operator,
    required this.onPlay,
    required this.onChanged,
    this.sonarr,
    this.seerr,
    this.server,
    this.light,
    this.now,
  });

  final String seriesTitle;
  final List<MediaSeason> seasons;

  /// The episode the sheet opens on.
  final int season;
  final int number;

  final bool operator;
  final MediaEpisodeSonarr? sonarr;
  final ({String connectionId, int tvId})? seerr;
  final MediaEpisodeServer? server;

  /// The title's light, for Play.
  final TitleLight? light;

  /// Plays [episode] on the media server.
  final void Function(StreamItem episode) onPlay;

  /// Sonarr changed: the page reads it again.
  final VoidCallback onChanged;

  /// The clock the dates are read against; the wall clock by default.
  final DateTime? now;

  @override
  ConsumerState<MediaEpisodeSheet> createState() => _MediaEpisodeSheetState();
}

class _MediaEpisodeSheetState extends ConsumerState<MediaEpisodeSheet> {
  late final List<MediaEpisode> _episodes = [
    for (final season in widget.seasons) ...season.episodes,
  ];
  late int _index = _episodes
      .indexWhere((e) => e.season == widget.season && e.number == widget.number)
      .clamp(0, _episodes.length - 1);

  /// What the switch said last, until Sonarr is read again.
  final Map<int, bool> _monitored = {};
  bool _searching = false;

  MediaEpisode get _episode => _episodes[_index];

  void _go(int delta) => setState(() {
    _index = (_index + delta).clamp(0, _episodes.length - 1);
    _searching = false;
  });

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final episode = _episode;
    final now = widget.now ?? DateTime.now();
    final seerr = widget.seerr;
    final facts = seerr == null
        ? null
        : ref
              .watch(
                mediaSeasonFactsProvider((
                  connectionId: seerr.connectionId,
                  tvId: seerr.tvId,
                  season: episode.season,
                )),
              )
              .value
              ?.where((f) => f.number == episode.number)
              .firstOrNull;
    final previous = _index > 0 ? _episodes[_index - 1] : null;
    final next = _index < _episodes.length - 1 ? _episodes[_index + 1] : null;
    final title = facts?.name ?? episode.title;
    final overview =
        facts?.overview ??
        episode.fromSonarr?.overview ??
        episode.onServer?.overview;
    final still = facts?.stillUrl();
    final aired = _aired(episode, facts, now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.seriesTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label.copyWith(color: room.inkSecondary),
              ),
            ),
            IconButton(
              tooltip: previous == null
                  ? null
                  : 'Previous episode, ${_codeOf(previous, episode)}',
              onPressed: previous == null ? null : () => _go(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              tooltip: next == null
                  ? null
                  : 'Next episode, ${_codeOf(next, episode)}',
              onPressed: next == null ? null : () => _go(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        if (still != null) ...[
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.door),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ArtworkDecodeBox(
                builder: (context, decode) => CachedNetworkImage(
                  imageUrl: still,
                  cacheManager: pinnedImageCacheFor(still),
                  memCacheWidth: decode.width,
                  memCacheHeight: decode.height,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      const ShimmerPlaceholder(height: double.infinity),
                  errorWidget: (context, url, error) =>
                      ColoredBox(color: room.raised),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(title, style: AppType.feature.copyWith(color: room.ink)),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          [
            'Season ${episode.season}',
            'Episode ${episode.number}',
            ?aired,
          ].join(' · '),
          style: AppType.meta
              .weight(FontWeight.w400)
              .copyWith(color: room.inkSecondary),
        ),
        if (facts?.voteAverage case final vote?) ...[
          const SizedBox(height: AppSpacing.md),
          Semantics(
            label:
                'TMDB ${vote.toStringAsFixed(1)} from '
                '${countLabel(facts!.voteCount, 'vote')}',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  vote.toStringAsFixed(1),
                  style: AppType.figure.copyWith(color: room.ink),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'TMDB · ${countLabel(facts.voteCount, 'vote')}',
                  style: AppType.meta
                      .weight(FontWeight.w400)
                      .copyWith(color: room.inkTertiary),
                ),
              ],
            ),
          ),
        ],
        if ((episode.onServer, widget.server) case (
          final item?,
          final server?,
        )) ...[
          const SizedBox(height: AppSpacing.lg),
          _ServerCard(
            item: item,
            serverName: server.name,
            light: widget.light,
            onPlay: () => widget.onPlay(item),
          ),
        ],
        if ((overview ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(overview!, style: AppType.body.copyWith(color: room.ink)),
        ],
        if (widget.operator)
          if ((widget.sonarr, episode.fromSonarr) case (
            final sonarr?,
            final record?,
          )) ...[
            const SizedBox(height: AppSpacing.section),
            Semantics(
              header: true,
              child: Text(
                'In ${sonarr.name}',
                style: AppType.section.copyWith(color: room.ink),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            MediaGroup(
              children: [
                if (record.episodeFileId case final fileId?)
                  _FileRow(sonarr: sonarr, fileId: fileId, now: now),
                if (_searchFor(sonarr, episode, now) case final label?)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.row,
                    ),
                    child: OutlinedButton.icon(
                      onPressed: _searching
                          ? null
                          : () => _search(sonarr, record.id),
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: Text(label),
                    ),
                  ),
                // Sonarr's own pick passed over: the releases its indexers
                // have, for this episode alone.
                if (!record.isUnairedAt(now))
                  MediaLinkRow(
                    label: 'Choose a release',
                    detail: 'Pick one from your indexers',
                    onTap: () => showReleaseSearch(
                      context,
                      ref,
                      ReleaseSearchTarget.episode(
                        episodeId: record.id,
                        seriesId: sonarr.seriesId,
                        seasonNumber: record.seasonNumber,
                        label:
                            '${truncateTitle(widget.seriesTitle)} · '
                            '${formatArrEpisodeCode(record.seasonNumber, record.episodeNumber)}',
                      ).stampedWith(sonarr.connection.id),
                    ),
                  ),
                MediaSwitchRow(
                  label: 'Monitored',
                  detail: (_monitored[record.id] ?? record.monitored)
                      ? '${sonarr.name} looks for upgrades and missing files'
                      : '${sonarr.name} leaves it as it is',
                  value: _monitored[record.id] ?? record.monitored,
                  onChanged: (value) => _monitor(sonarr, record.id, value),
                ),
              ],
            ),
          ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  /// `E4`, or `S3 E1` across a season.
  String _codeOf(MediaEpisode other, MediaEpisode from) =>
      other.season == from.season
      ? other.code
      : 'Season ${other.season} ${other.code}';

  /// `aired Fri 7 Aug`, `airs Fri 9 Oct at 21:00`; null without a date.
  String? _aired(MediaEpisode episode, MediaEpisodeFacts? facts, DateTime now) {
    final at = episode.airsAt;
    if (at != null) {
      final local = at.toLocal();
      final day = formatShortDate(local.toIso8601String(), now: now);
      return local.isAfter(now)
          ? 'airs $day at ${formatClockTime(at)}'
          : 'aired $day';
    }
    final date = facts?.airDate;
    if (date == null) return null;
    final day = DateTime.tryParse(date);
    if (day == null) return null;
    return '${day.isAfter(now) ? 'airs' : 'aired'} '
        '${formatShortDate(date, now: now)}';
  }

  /// What a search would look for: a file above the cutoff, or the episode
  /// that aired and is missing; null when there is nothing to look for.
  String? _searchFor(
    MediaEpisodeSonarr sonarr,
    MediaEpisode episode,
    DateTime now,
  ) {
    final record = episode.fromSonarr!;
    if (record.isUnairedAt(now)) return null;
    if (!record.hasFile) return 'Search for it';
    final fileId = record.episodeFileId;
    if (fileId == null) return null;
    final file = ref
        .watch(
          mediaEpisodeFilesProvider((
            connectionId: sonarr.connection.id,
            seriesId: sonarr.seriesId,
          )),
        )
        .value?[fileId];
    if (file == null || !file.cutoffNotMet) return null;
    final cutoff = switch (sonarr.profileId) {
      final profile? =>
        ref
            .watch(
              mediaSonarrCutoffProvider((
                connectionId: sonarr.connection.id,
                profileId: profile,
              )),
            )
            .value,
      null => null,
    };
    return cutoff == null
        ? 'Search for a better version'
        : 'Search for $cutoff';
  }

  Future<void> _search(MediaEpisodeSonarr sonarr, int episodeId) async {
    setState(() => _searching = true);
    try {
      await ref
          .read(sonarrServiceForProvider(sonarr.connection.id))
          .searchEpisodes([episodeId]);
      if (mounted) {
        SnackBarHelper.success(context, '${sonarr.name} is searching for it');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _searching = false);
        SnackBarHelper.error(
          context,
          'Could not ask ${sonarr.name} to search',
          detail: error,
        );
      }
    }
  }

  Future<void> _monitor(
    MediaEpisodeSonarr sonarr,
    int episodeId,
    bool monitored,
  ) async {
    final before = _monitored[episodeId];
    setState(() => _monitored[episodeId] = monitored);
    try {
      await ref
          .read(sonarrServiceForProvider(sonarr.connection.id))
          .setEpisodesMonitored([episodeId], monitored: monitored);
      widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      // Put back: the switch says what Sonarr holds.
      setState(() {
        if (before == null) {
          _monitored.remove(episodeId);
        } else {
          _monitored[episodeId] = before;
        }
      });
      SnackBarHelper.error(
        context,
        'Could not change it in ${sonarr.name}',
        detail: error,
      );
    }
  }
}

/// Where the episode plays: the server, the picture, how far the viewer is,
/// and Resume or Play, lit by the title.
class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.item,
    required this.serverName,
    required this.onPlay,
    this.light,
  });

  final StreamItem item;
  final String serverName;
  final TitleLight? light;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final picture = item.video?.resolution;
    final where = ['On $serverName', ?picture].join(' · ');
    final state = item.isPlayed
        ? 'Watched'
        : item.isInProgress
        ? mediaTimeLeft(item)
        : null;
    final progress = item.isInProgress ? item.resumeProgress : null;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.door),
        border: Border.all(color: room.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: [where, ?state].join('. '),
            excludeSemantics: true,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    where,
                    style: AppType.row.copyWith(color: room.ink),
                  ),
                ),
                if (state != null)
                  Text(
                    state,
                    style: AppType.meta
                        .weight(FontWeight.w600)
                        .copyWith(color: room.inkSecondary),
                  ),
              ],
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: room.fillTrack,
                color: room.inkSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: onPlay,
            style: mediaLeadStyle(context, light),
            child: Row(
              children: [
                Expanded(child: Text(item.isInProgress ? 'Resume' : 'Play')),
                const Icon(Icons.play_arrow_rounded, size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The file Sonarr holds: its quality, its name whole, and whether it meets
/// the profile, read when the sheet opens.
class _FileRow extends ConsumerWidget {
  const _FileRow({
    required this.sonarr,
    required this.fileId,
    required this.now,
  });

  final MediaEpisodeSonarr sonarr;
  final int fileId;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final files = ref.watch(
      mediaEpisodeFilesProvider((
        connectionId: sonarr.connection.id,
        seriesId: sonarr.seriesId,
      )),
    );
    final file = files.value?[fileId];
    final cutoff = switch (sonarr.profileId) {
      final profile? =>
        ref
            .watch(
              mediaSonarrCutoffProvider((
                connectionId: sonarr.connection.id,
                profileId: profile,
              )),
            )
            .value,
      null => null,
    };
    if (file == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
        child: files.hasError
            ? Text(
                'Could not read the file',
                style: AppType.meta.copyWith(color: room.inkSecondary),
              )
            : const ShimmerPlaceholder(width: 180, height: 14),
      );
    }
    final added = file.dateAdded;
    final imported = added == null
        ? null
        : _sameDay(added.toLocal(), now)
        ? 'imported today ${formatClockTime(added)}'
        : 'imported ${formatShortDate(added.toLocal().toIso8601String(), now: now)}';
    final line = [
      if (file.cutoffNotMet)
        cutoff == null ? 'Below the cutoff' : 'Below the $cutoff cutoff',
      ?imported,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: room.fillControl,
              borderRadius: BorderRadius.circular(AppRadius.thumb),
            ),
            child: Icon(
              Icons.folder_outlined,
              size: 19,
              color: room.inkSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  qualityWords(file.qualityName ?? ''),
                  style: AppType.row.copyWith(color: room.ink),
                ),
                const SizedBox(height: 2),
                MachineName.fileInFull(file.relativePath),
                if (line.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    line,
                    style: AppType.meta
                        .weight(FontWeight.w500)
                        .copyWith(color: room.inkSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
