import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/media/domain/quality_words.dart';

/// The parts Manage is built from, for a movie and a series alike: a closed
/// section, a section open on the copies it acts on, and one event of a
/// history.

/// A closed operator section: its title and what it holds in one line,
/// opening on [body] when there is one. Its content is built when it opens:
/// a section nobody opens reads nothing.
class MediaManageRow extends StatefulWidget {
  const MediaManageRow({
    super.key,
    required this.title,
    required this.summary,
    this.body,
    this.onTap,
  }) : assert(body == null || onTap == null, 'a section opens or acts');

  final String title;
  final String summary;
  final WidgetBuilder? body;

  /// What the row does instead of opening, when it leads straight there.
  final VoidCallback? onTap;

  @override
  State<MediaManageRow> createState() => _MediaManageRowState();
}

class _MediaManageRowState extends State<MediaManageRow> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final body = widget.body;
    final header = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: AppType.row.copyWith(color: room.ink),
                ),
                if (widget.summary.isNotEmpty)
                  Text(
                    widget.summary,
                    style: AppType.meta
                        .weight(FontWeight.w400)
                        .copyWith(color: room.inkTertiary),
                  ),
              ],
            ),
          ),
          if (widget.onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: room.inkTertiary,
            ),
          if (body != null)
            AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: room.inkTertiary,
              ),
            ),
        ],
      ),
    );
    if (widget.onTap case final onTap?) {
      return Semantics(
        button: true,
        child: InkWell(onTap: onTap, child: header),
      );
    }
    if (body == null) return header;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: header,
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.slabY),
            child: body(context),
          ),
      ],
    );
  }
}

/// A section open on the copies it can act on: one row per copy, each named
/// for what it does there (`Search releases on Radarr 4K`).
class MediaCopyChoices<T> extends StatelessWidget {
  const MediaCopyChoices({
    super.key,
    required this.verb,
    required this.copies,
    required this.onChoose,
  });

  /// What a row does, before the connection's name: `Search releases on`.
  final String verb;
  final List<({String name, T target})> copies;
  final ValueChanged<T> onChoose;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final copy in copies)
          Semantics(
            button: true,
            label: '$verb ${copy.name}',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => onChoose(copy.target),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: DesignTokens.sizeTouch,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        copy.name,
                        style: AppType.label.copyWith(color: room.inkSecondary),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: room.inkTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One event: its word in its tone, the episode it concerns for a series,
/// the release's quality, the day.
class MediaHistoryLine extends StatelessWidget {
  const MediaHistoryLine({
    super.key,
    required this.record,
    required this.scheme,
  });

  final Map<String, dynamic> record;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final event = '${record['eventType'] ?? ''}';
    final quality = mapOrNull(
      mapOrNull(record['quality'])?['quality'],
    )?['name'];
    final date = '${record['date'] ?? ''}';
    final episode = mapOrNull(record['episode']);
    final season = intOrNull(episode?['seasonNumber']);
    final number = intOrNull(episode?['episodeNumber']);
    final words = [
      historyEventLabel(event),
      if ((season, number) case (final season?, final number?))
        formatArrEpisodeCode(season, number),
      if (quality is String && quality.isNotEmpty) qualityWords(quality),
      if (date.isNotEmpty) formatShortDate(date),
    ];
    return Semantics(
      container: true,
      label: words.join('. '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusToneColor(
                  scheme,
                  historyEventTone(event),
                  surface: room.ground,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                words.join(' · '),
                style: AppType.meta
                    .weight(FontWeight.w400)
                    .copyWith(color: room.inkSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
