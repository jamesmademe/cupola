import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/media/presentation/media_episode_providers.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';

/// The seasons TMDB scores for a series, read through the Seerr
/// [connectionId] when the graph is drawn: one read a season.
MediaEpisodesGraph? watchEpisodesGraph(
  WidgetRef ref, {
  required String connectionId,
  required int tvId,
  required List<int> seasons,
}) {
  final read = <int, List<MediaEpisodeFacts>>{};
  for (final season in seasons) {
    final facts = ref
        .watch(
          mediaSeasonFactsProvider((
            connectionId: connectionId,
            tvId: tvId,
            season: season,
          )),
        )
        .value;
    // Drawn once every season has answered, so the averages hold still.
    if (facts == null) return null;
    read[season] = facts;
  }
  final graph = mediaEpisodesGraphOf(read);
  return graph.isEmpty ? null : graph;
}

/// One cell's width and the gap after it, for a row of [longest] episodes
/// across [width]: the same for every season of a series, so episode 5 sits
/// under episode 5 and a season of 24 is not drawn thinner than one of 8
/// beside it (11/10). Gaps close up to a hairline when the cells would
/// otherwise vanish between them.
({double cell, double gap}) _cellsAcross(double width, int longest) {
  if (longest <= 1) return (cell: width, gap: 0);
  double across(double gap) => (width - gap * (longest - 1)) / longest;
  final roomy = across(3);
  if (roomy >= 6) return (cell: roomy, gap: 3);
  return (cell: math.max(1, across(1)), gap: 1);
}

/// `Best · S2 E6 8.9`, the lead of a graph's summary.
String _bestOf(MediaEpisodeFacts best) =>
    '${formatEpisodeCode(best.season, best.number)} '
    '${best.voteAverage!.toStringAsFixed(1)}';

/// The graph closed, on the page: a row of cells a season, its average, and
/// the best episode; `Open` shows it whole. Nothing until the seasons have
/// answered, and nothing for a series TMDB has not scored.
class MediaEpisodesGraphPanel extends ConsumerWidget {
  const MediaEpisodesGraphPanel({
    super.key,
    required this.connectionId,
    required this.tvId,
    required this.seasons,
    required this.onOpen,
    this.light,
    this.upcoming,
  });

  final String connectionId;
  final int tvId;
  final List<int> seasons;
  final TitleLight? light;

  /// A season still to air and the day it starts: its row reads `S3 · Fri`.
  final ({int season, String day})? upcoming;

  final VoidCallback onOpen;

  /// Past this many seasons the panel reads nothing until it is opened: a
  /// read a season is too many to spend on a closed panel.
  static const eagerSeasons = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    if (seasons.length > eagerSeasons) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.section),
        child: MediaGroup(
          children: [
            MediaLinkRow(
              label: 'Episodes graph',
              detail: 'TMDB votes, ${countLabel(seasons.length, 'season')}',
              onTap: onOpen,
            ),
          ],
        ),
      );
    }
    final graph = watchEpisodesGraph(
      ref,
      connectionId: connectionId,
      tvId: tvId,
      seasons: seasons,
    );
    if (graph == null) return const SizedBox.shrink();
    final best = graph.best.first;
    // Every season's cells measured on the longest one.
    final longest = graph.seasons
        .map((season) => season.episodes.length)
        .reduce(math.max);
    final stronger = graph.stronger;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.section),
      child: PressableScale(
        onTap: onOpen,
        semanticLabel: [
          'Episodes graph',
          'Best: ${formatEpisodeCode(best.season, best.number)}, '
              '${best.voteAverage!.toStringAsFixed(1)}',
          if (stronger != null) 'Season ${stronger.season} is the stronger one',
        ].join('. '),
        semanticHint: 'Opens the graph',
        excludeChildSemantics: true,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.slabY),
          decoration: BoxDecoration(
            color: room.door,
            borderRadius: BorderRadius.circular(AppRadius.slab),
            border: Border.all(color: room.hair),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Episodes graph',
                      style: AppType.section.copyWith(color: room.ink),
                    ),
                  ),
                  Text(
                    'Open',
                    style: AppType.label.copyWith(color: room.inkSecondary),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: room.inkSecondary,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              for (final season in graph.seasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          [
                            formatSeasonCode(season.number),
                            if (season.average case final average?)
                              average.toStringAsFixed(1)
                            else if (upcoming case (
                              season: final int starting,
                              :final String day,
                            ) when starting == season.number)
                              day,
                          ].join(dotSeparator),
                          style: AppType.meta
                              .weight(FontWeight.w600)
                              .copyWith(color: room.inkSecondary),
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final (:cell, :gap) = _cellsAcross(
                              box.maxWidth,
                              longest,
                            );
                            return Row(
                              children: [
                                for (final (index, episode)
                                    in season.episodes.indexed) ...[
                                  if (index > 0) SizedBox(width: gap),
                                  SizedBox(
                                    width: cell,
                                    height: 16,
                                    child: _Cell(
                                      episode: episode,
                                      light: light,
                                      radius: math.min(5, cell / 2),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Best\u00A0· ${_bestOf(best)}',
                      style: AppType.label.copyWith(color: room.ink),
                    ),
                    if (stronger != null)
                      TextSpan(
                        text:
                            '\u00A0· season ${stronger.season} is the stronger one',
                        style: AppType.label
                            .weight(FontWeight.w400)
                            .copyWith(color: room.inkSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The graph open: the best episode (it opens), every episode's score a
/// season to a column, the scale, and what the votes say.
class MediaEpisodesGraphSheet extends ConsumerWidget {
  const MediaEpisodesGraphSheet({
    super.key,
    required this.connectionId,
    required this.tvId,
    required this.seasonNumbers,
    required this.seasons,
    required this.onOpenEpisode,
    this.light,
  });

  /// The Seerr the votes are read through, the series, and its seasons.
  final String connectionId;
  final int tvId;
  final List<int> seasonNumbers;

  /// The series' episodes as the page reads them, for the best one's word.
  final List<MediaSeason> seasons;
  final TitleLight? light;
  final void Function(int season, int number) onOpenEpisode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final graph = watchEpisodesGraph(
      ref,
      connectionId: connectionId,
      tvId: tvId,
      seasons: seasonNumbers,
    );
    if (graph == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: ShimmerPlaceholder(height: 320),
      );
    }
    final best = graph.best.first;
    final bestState = [
      for (final season in seasons)
        for (final episode in season.episodes)
          if (episode.season == best.season && episode.number == best.number)
            episode.state,
    ].firstOrNull;
    final stronger = graph.stronger;
    final rows = graph.seasons
        .map((season) => season.episodes.length)
        .fold(0, math.max);
    final secondary = AppType.meta
        .weight(FontWeight.w400)
        .copyWith(color: room.inkSecondary);

    Widget column(
      ({int number, double? average, List<MediaEpisodeFacts> episodes}) season,
    ) => Column(
      children: [
        SizedBox(
          height: 28,
          child: Center(
            child: Text(
              [
                formatSeasonCode(season.number),
                if (season.average case final average?)
                  average.toStringAsFixed(1),
              ].join(dotSeparator),
              style: AppType.meta
                  .weight(FontWeight.w600)
                  .copyWith(color: room.inkSecondary),
            ),
          ),
        ),
        for (var index = 0; index < rows; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s),
            child: SizedBox(
              height: 36,
              child: index < season.episodes.length
                  ? _Cell(
                      episode: season.episodes[index],
                      light: light,
                      radius: AppRadius.thumb,
                      labelled: true,
                      best: season.episodes[index] == best,
                    )
                  : null,
            ),
          ),
      ],
    );

    final grid = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 36,
          child: Column(
            children: [
              const SizedBox(height: 28),
              for (var index = 0; index < rows; index++)
                SizedBox(
                  height: 36 + AppSpacing.s,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatEpisodeOrdinal(index + 1),
                      style: AppType.meta
                          .weight(FontWeight.w400)
                          .copyWith(color: room.inkTertiary),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (graph.seasons.length <= 3)
          for (final season in graph.seasons) ...[
            const SizedBox(width: AppSpacing.s),
            Expanded(child: column(season)),
          ]
        else
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final season in graph.seasons) ...[
                    const SizedBox(width: AppSpacing.s),
                    SizedBox(width: 96, child: column(season)),
                  ],
                ],
              ),
            ),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PressableScale(
          onTap: () => onOpenEpisode(best.season, best.number),
          semanticLabel: [
            'Best, ${formatEpisodeCode(best.season, best.number)}',
            ?best.name,
            best.voteAverage!.toStringAsFixed(1),
            countLabel(best.voteCount, 'vote'),
            ?bestState,
          ].join('. '),
          excludeChildSemantics: true,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: room.door,
              borderRadius: BorderRadius.circular(AppRadius.door),
              border: Border.all(color: room.hair),
            ),
            child: Row(
              children: [
                Text(
                  best.voteAverage!.toStringAsFixed(1),
                  style: AppType.figure.copyWith(color: room.ink),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          formatEpisodeCode(best.season, best.number),
                          ?best.name,
                        ].join(dotSeparator),
                        style: AppType.row.copyWith(color: room.ink),
                      ),
                      Text(
                        [
                          countLabel(best.voteCount, 'vote'),
                          ?bestState,
                        ].join(dotSeparator),
                        style: secondary,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: room.inkSecondary),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ExcludeSemantics(child: grid),
        const SizedBox(height: AppSpacing.md),
        ExcludeSemantics(
          child: Row(
            children: [
              Text('under ${MediaEpisodesGraph.steps.first}', style: secondary),
              const SizedBox(width: AppSpacing.sm),
              for (
                var step = 0;
                step <= MediaEpisodesGraph.steps.length;
                step++
              )
                Padding(
                  // Between the swatches only, so both ends of the strip sit
                  // a whole step from their words.
                  padding: EdgeInsets.only(
                    right: step < MediaEpisodesGraph.steps.length ? 3 : 0,
                  ),
                  child: SizedBox(
                    width: 22,
                    height: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _fillOf(room, light, step),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: AppSpacing.sm),
              Text('${MediaEpisodesGraph.steps.last}+', style: secondary),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ExcludeSemantics(
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 14,
                child: CustomPaint(
                  painter: _DashedBorder(
                    color: room.inkSecondary,
                    radius: 4,
                    dash: 4,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'fewer than ${MediaEpisodesGraph.fewVotes} votes',
                style: secondary,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Divider(height: 1, color: room.hair),
        const SizedBox(height: AppSpacing.lg),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Best',
                style: AppType.label.copyWith(color: room.ink),
              ),
              TextSpan(
                text: [
                  '',
                  for (final episode in graph.best) _bestOf(episode),
                ].join(dotSeparator),
                style: secondary,
              ),
            ],
          ),
        ),
        if (stronger != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Season ${stronger.season} is the stronger one',
                  style: AppType.label.copyWith(color: room.ink),
                ),
                TextSpan(
                  text: [
                    '',
                    '${stronger.average.toStringAsFixed(1)} against '
                        '${stronger.other.toStringAsFixed(1)}',
                    if (stronger.fewVotes > 0)
                      '${stronger.fewVotes} of its episodes have few votes',
                  ].join(dotSeparator),
                  style: secondary,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'Votes from TMDB, per episode.',
          style: AppType.caption
              .weight(FontWeight.w400)
              .copyWith(color: room.inkTertiary),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// The scale's fill at [step]: the title's light from faint to whole, or
/// the ink without one.
Color _fillOf(CupolaRoom room, TitleLight? light, int step) {
  final dark =
      ThemeData.estimateBrightnessForColor(room.ground) == Brightness.dark;
  final hue = light == null
      ? room.ink
      : dark
      ? light.light
      : light.dayPrimary;
  final t = 0.2 + 0.8 * step / MediaEpisodesGraph.steps.length;
  return Color.lerp(room.raised, hue, t)!;
}

/// One episode's cell: its score's step of the scale, dashed when few have
/// voted, dotted and empty when nobody has.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.episode,
    required this.light,
    required this.radius,
    this.labelled = false,
    this.best = false,
  });

  final MediaEpisodeFacts episode;
  final TitleLight? light;
  final double radius;
  final bool labelled;
  final bool best;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final vote = episode.voteAverage;
    if (vote == null) {
      return CustomPaint(
        painter: _DashedBorder(
          color: room.inkTertiary,
          radius: radius,
          dash: 2,
        ),
        child: labelled
            ? Center(
                child: Text(
                  '—',
                  style: AppType.meta.copyWith(color: room.inkTertiary),
                ),
              )
            : null,
      );
    }
    final fill = _fillOf(room, light, MediaEpisodesGraph.stepOf(vote));
    // The ink that reads best on the fill, by contrast ratio: the room's
    // ink or the ink's own.
    final onFill = _contrast(fill, room.ink) >= _contrast(fill, room.onInk)
        ? room.ink
        : room.onInk;
    final few = episode.voteCount < MediaEpisodesGraph.fewVotes;
    final cell = CustomPaint(
      foregroundPainter: few
          ? _DashedBorder(color: onFill, radius: radius, dash: 4)
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(radius),
        ),
        alignment: Alignment.center,
        child: labelled
            ? Text(
                vote.toStringAsFixed(1),
                style: AppType.label.copyWith(color: onFill),
              )
            : null,
      ),
    );
    if (!best) return cell;
    // The best, ringed in the ink a step away from its fill, so the ring
    // shows on the lightest step too.
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + 3),
        border: Border.all(color: room.ink, width: 2),
      ),
      child: cell,
    );
  }
}

/// WCAG's contrast ratio between [a] and [b].
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// A rounded rectangle's outline in dashes of [dash].
class _DashedBorder extends CustomPainter {
  const _DashedBorder({
    required this.color,
    required this.radius,
    required this.dash,
  });

  final Color color;
  final double radius;
  final double dash;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.6),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash * 2;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius || old.dash != dash;
}
