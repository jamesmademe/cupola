import 'package:flutter/material.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';

/// The next episode to air, in one slab: the day, which episode and when,
/// what will happen, and `Not aired`.
///
/// [operator] reads what Sonarr will do (`Sonarr looks for it once it airs`);
/// the requester reads no service's name.
class MediaNextAiringCard extends StatelessWidget {
  const MediaNextAiringCard({
    super.key,
    required this.next,
    required this.now,
    required this.operator,
  });

  final MediaNextAiring next;
  final DateTime now;
  final bool operator;

  String get _day => mediaAiringDay(next, now);

  /// `S3 E1 · premiere at 21:00`, `S2 E7 · at 21:00`, `S3 E1 · premiere`.
  String get _what {
    final when = [
      if (next.premiere) 'premiere',
      if (next.timed) 'at ${formatClockTime(next.at)}',
    ].join(' ');
    return [
      formatEpisodeCode(next.season, next.number),
      if (when.isNotEmpty) when,
    ].join(' · ');
  }

  /// What will happen: Sonarr's part for the operator, else the season TMDB
  /// announces.
  String? get _then {
    if (operator && next.timed) {
      return next.sonarrMonitors
          ? 'Sonarr looks for it once it airs'
          : 'Sonarr is not set to look for it';
    }
    final count = next.seasonEpisodes;
    if (next.premiere && count != null) {
      return 'Season ${next.season} · ${countLabel(count, 'episode')} announced';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final then = _then;
    return Semantics(
      container: true,
      label: [_day, _what, ?then, StateWord.notAired.label].join('. '),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.slabY,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: room.fillQuiet,
          borderRadius: BorderRadius.circular(AppRadius.door),
          border: Border.all(color: room.hair),
        ),
        child: Row(
          children: [
            Text(_day, style: AppType.section.copyWith(color: room.ink)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_what, style: AppType.row.copyWith(color: room.ink)),
                  if (then != null)
                    Text(
                      then,
                      style: AppType.meta
                          .weight(FontWeight.w400)
                          .copyWith(color: room.inkSecondary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            _StateWord(
              StateWord.notAired.label,
              tone: StatusTone.neutral,
              hollow: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// A series' episodes, a season at a time: the seasons as a segmented track,
/// then one row per episode (its number, its title, one word for where it
/// stands, a bar while it plays or downloads), then `Search the N missing`
/// where [onSearchMissing] can ask for them.
class MediaEpisodes extends StatefulWidget {
  const MediaEpisodes({
    super.key,
    required this.seasons,
    required this.initialSeason,
    this.onSearchMissing,
    this.onOpen,
  });

  final List<MediaSeason> seasons;

  /// The season shown first: where the viewer is, else the latest aired.
  final int initialSeason;

  /// Asks Sonarr for a season's missing episodes; null where nothing can.
  final Future<void> Function(MediaSeason season)? onSearchMissing;

  /// Opens an episode's sheet.
  final void Function(MediaEpisode episode)? onOpen;

  @override
  State<MediaEpisodes> createState() => _MediaEpisodesState();
}

class _MediaEpisodesState extends State<MediaEpisodes> {
  late int _season = widget.initialSeason;

  /// A search asked for the season, until the season changes.
  final Set<int> _asked = {};
  bool _asking = false;

  @override
  Widget build(BuildContext context) {
    final seasons = widget.seasons;
    final season =
        seasons.where((s) => s.number == _season).firstOrNull ?? seasons.first;
    final missing = season.missing;
    final onSearch = widget.onSearchMissing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (seasons.length > 1) ...[
          _SeasonTrack(
            seasons: seasons,
            selected: season.number,
            onSelected: (number) => setState(() => _season = number),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        MediaGroup(
          children: [
            for (final episode in season.episodes)
              _EpisodeRow(
                episode,
                onTap: widget.onOpen == null
                    ? null
                    : () => widget.onOpen!(episode),
              ),
          ],
        ),
        if (onSearch != null && missing.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _asking || _asked.contains(season.number)
                ? null
                : () async {
                    setState(() => _asking = true);
                    try {
                      await onSearch(season);
                      if (mounted) setState(() => _asked.add(season.number));
                    } finally {
                      if (mounted) setState(() => _asking = false);
                    }
                  },
            icon: const Icon(Icons.search_rounded, size: 18),
            label: Text(
              missing.length == 1
                  ? 'Search the missing one'
                  : 'Search the ${missing.length} missing',
            ),
          ),
        ],
      ],
    );
  }
}

/// The seasons as one track: a segment each, the chosen one in the ink. The
/// segments share the width when they fit and scroll when they do not.
class _SeasonTrack extends StatelessWidget {
  const _SeasonTrack({
    required this.seasons,
    required this.selected,
    required this.onSelected,
  });

  final List<MediaSeason> seasons;
  final int selected;
  final ValueChanged<int> onSelected;

  /// The narrowest a segment gets before the track scrolls.
  static const double _segment = 104;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    Widget segment(MediaSeason season) {
      final chosen = season.number == selected;
      return Semantics(
        container: true,
        button: true,
        selected: chosen,
        label: season.label,
        onTap: () => onSelected(season.number),
        child: ExcludeSemantics(
          child: PressableScale(
            onTap: () => onSelected(season.number),
            child: AnimatedContainer(
              duration: AppAnimation.emphasized,
              curve: AppAnimation.standardCurve,
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: chosen ? room.ink : null,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                season.label,
                maxLines: 1,
                style: AppType.label.copyWith(
                  color: chosen ? room.onInk : room.inkSecondary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.door),
        border: Border.all(color: room.hair),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth / seasons.length >= _segment) {
            return Row(
              children: [
                for (final season in seasons) Expanded(child: segment(season)),
              ],
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final season in seasons)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: _segment),
                    child: segment(season),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One episode: its number, its title, its word, and a bar while it plays
/// or downloads. One sentence for a screen reader.
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow(this.episode, {this.onTap});

  final MediaEpisode episode;

  /// Opens the episode's sheet.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final progress = episode.progress;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              episode.code,
              style: AppType.meta
                  .weight(FontWeight.w400)
                  .copyWith(color: room.inkTertiary),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        episode.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.row.copyWith(color: room.ink),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 170),
                      child: _StateWord(
                        episode.state,
                        tone: episode.tone,
                        hollow: episode.tone == StatusTone.neutral,
                      ),
                    ),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: room.fillTrack,
                      color: episode.downloading
                          ? statusToneColor(
                              scheme,
                              StatusTone.info,
                              surface: room.ground,
                            )
                          : room.inkSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    final onTap = this.onTap;
    if (onTap == null) {
      return Semantics(
        container: true,
        label: episode.spoken,
        excludeSemantics: true,
        child: row,
      );
    }
    return PressableScale(
      onTap: onTap,
      semanticLabel: episode.spoken,
      excludeChildSemantics: true,
      child: row,
    );
  }
}

/// A state's word after its 7 dot, in its tone; the backlog's ring when
/// [hollow].
class _StateWord extends StatelessWidget {
  const _StateWord(this.word, {required this.tone, required this.hollow});

  final String word;
  final StatusTone tone;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = statusToneColor(scheme, tone, surface: room.ground);
    // The info tone colours its word too, as the rows do with a download.
    final ink = tone == StatusTone.info || tone == StatusTone.warning
        ? color
        : room.inkSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hollow ? null : color,
            border: hollow
                ? Border.all(color: room.inkSecondary, width: 1.5)
                : null,
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Flexible(
          child: Text(
            word,
            style: AppType.meta.weight(FontWeight.w600).copyWith(color: ink),
          ),
        ),
      ],
    );
  }
}

/// The day [next] airs, as a card or a graph row says it: `Today`,
/// `Tomorrow`, `Fri` within the week, else `9 Oct`.
String mediaAiringDay(MediaNextAiring next, DateTime now) {
  final at = next.timed ? next.at.toLocal() : next.at;
  final today = DateTime(now.year, now.month, now.day);
  final days = DateTime(at.year, at.month, at.day).difference(today).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  final short = formatShortDate(
    '${at.year.toString().padLeft(4, '0')}-'
    '${at.month.toString().padLeft(2, '0')}-'
    '${at.day.toString().padLeft(2, '0')}',
    now: now,
  );
  // `Fri 9 Oct`: the weekday alone within the week, the date beyond it.
  return days < 7 ? short.split(' ').first : short.substring(4);
}
