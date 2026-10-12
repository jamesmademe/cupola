import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart'
    show HomeRowArt;
import 'package:cupola/features/import/domain/blocked_import.dart';
import 'package:cupola/features/import/domain/manual_import_display.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/presentation/manual_import_fix_sheet.dart';
import 'package:cupola/features/import/presentation/manual_import_provider.dart';
import 'package:cupola/features/import/presentation/manual_import_review_rows.dart'
    show FilenameText;
import 'package:cupola/features/media/domain/quality_words.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The poster of the title [item] was matched to, off the arr's own host.
String? _posterOf(ServiceKey service, ManualImportItem item) {
  final payload = switch (service) {
    ServiceKey.radarr => item.movie,
    ServiceKey.lidarr => item.artist,
    _ => item.series,
  };
  final images = payload?['images'];
  return images is List ? remotePosterOf(images) : null;
}

/// What the arr says, word for word, and the same in plain words: what
/// `Why?` opens on.
class BlockedImportWhy extends StatelessWidget {
  const BlockedImportWhy({
    super.key,
    required this.service,
    required this.messages,
    this.plain,
  });

  final ServiceKey service;
  final List<String> messages;
  final String? plain;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: AppRadius.borderRadiusSlab,
        border: Border.all(color: room.hair),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (messages.isNotEmpty) ...[
              Text(
                'What ${service.title} says',
                style: AppType.meta.copyWith(color: room.inkTertiary),
              ),
              for (final message in messages) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message,
                  style: AppType.mono.copyWith(color: room.inkSecondary),
                ),
              ],
            ],
            if (plain case final plain?) ...[
              if (messages.isNotEmpty) const SizedBox(height: AppSpacing.sm),
              Text(
                'In plain words: $plain',
                style: AppType.meta.copyWith(color: room.inkSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `12 clear matches`, `6 need you`: a part's title, what is on its right,
/// and the sentence under it.
class BlockedImportPartHeading extends StatelessWidget {
  const BlockedImportPartHeading({
    super.key,
    required this.title,
    this.trailing,
    this.explanation,
  });

  final String title;
  final Widget? trailing;
  final String? explanation;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // What is on the right goes under the title once both no longer
        // fit, so a large reading size never breaks the title's words.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xxs,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: AppType.section.copyWith(color: room.ink),
              ),
            ),
            ?trailing,
          ],
        ),
        if (explanation case final explanation?) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            explanation,
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
        ],
      ],
    );
  }
}

/// Whether a file is in the import: a filled circle in ink with its tick,
/// an empty one when it is not, and a dashed amber one while the file still
/// waits for a choice.
class BlockedImportMark extends StatelessWidget {
  const BlockedImportMark({
    super.key,
    required this.selected,
    this.waiting = false,
  });

  final bool selected;
  final bool waiting;

  static const double size = 24;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (waiting) {
      return CustomPaint(
        size: const Size.square(size),
        painter: _DashedCircle(
          statusToneColor(scheme, StatusTone.warning, surface: room.slab),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : null,
        border: selected ? null : Border.all(color: room.edge, width: 1.5),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
          : null,
    );
  }
}

class _DashedCircle extends CustomPainter {
  _DashedCircle(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = Offset.zero & size;
    const dashes = 10;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect.deflate(1), i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle oldDelegate) => oldDelegate.color != color;
}

/// The clear files grabbed for one title: its poster, its name and the
/// quality they bring (`1080p WEB · English · each replaces a 720p file`),
/// `Clear all` or `Select all`, then a row per file.
class BlockedImportClearGroup extends StatelessWidget {
  const BlockedImportClearGroup({
    super.key,
    required this.service,
    required this.title,
    required this.files,
    required this.selected,
    required this.onToggle,
    required this.onAll,
    this.replacing = const {},
  });

  final ServiceKey service;
  final String title;
  final List<ManualImportItem> files;
  final Set<String> selected;
  final Map<String, String> replacing;
  final void Function(ManualImportItem file, bool selected) onToggle;
  final void Function(List<ManualImportItem> files, bool selected) onAll;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final all = files.every((file) => selected.contains(file.path));
    final line = clearQualityLine(files, replacing: replacing);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: room.slab,
        borderRadius: AppRadius.borderRadiusSlab,
        border: Border.all(color: room.hair),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Builder(
                builder: (context) {
                  final words = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.row.copyWith(color: room.ink),
                      ),
                      if (line != null)
                        Text(
                          line,
                          style: AppType.meta.copyWith(
                            color: room.inkSecondary,
                          ),
                        ),
                    ],
                  );
                  final toggle = OutlinedButton(
                    onPressed: () => onAll(files, !all),
                    child: Text(
                      all ? 'Clear all' : 'Select all',
                      semanticsLabel: all
                          ? 'Clear all of $title'
                          : 'Select all of $title',
                    ),
                  );
                  final art = HomeRowArt(
                    posterUrl: _posterOf(service, files.first),
                    icon: service.icon,
                  );
                  // At a large reading size the button leaves the title
                  // the row and stands under it.
                  if (MediaQuery.textScalerOf(context).scale(10) > 15) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            art,
                            const SizedBox(width: AppSpacing.md),
                            Expanded(child: words),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        toggle,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      art,
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: words),
                      const SizedBox(width: AppSpacing.sm),
                      toggle,
                    ],
                  );
                },
              ),
            ),
            for (final file in files)
              _ClearRow(
                service: service,
                file: file,
                selected: selected.contains(file.path),
                onToggle: () => onToggle(file, !selected.contains(file.path)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ClearRow extends StatelessWidget {
  const _ClearRow({
    required this.service,
    required this.file,
    required this.selected,
    required this.onToggle,
  });

  final ServiceKey service;
  final ManualImportItem file;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final label = clearRowLabel(service, file);
    return Semantics(
      container: true,
      checked: selected,
      label: '$label, ${file.fileName}',
      onTap: onToggle,
      excludeSemantics: true,
      child: InkWell(
        onTap: onToggle,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: room.hair)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  BlockedImportMark(selected: selected),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: AppType.row.copyWith(color: room.ink),
                        ),
                        FilenameText(
                          filename: fileStem(file),
                          style: AppType.mono.copyWith(
                            color: room.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A file that needs the user, closed: its name and what it waits for
/// (`Which episode?`), or once placed, where it goes (`Added · Cosmos
/// Laundromat S1 E3`). Open, the choice it needs: the season and episode on
/// the row for a series Sonarr knows, the match sheet for a title it does
/// not, and for a file the arr refused, its reason and `Add it anyway`.
class BlockedImportNeedYouRow extends ConsumerStatefulWidget {
  const BlockedImportNeedYouRow({
    super.key,
    required this.service,
    required this.item,
    required this.kind,
    required this.selected,
    required this.open,
    required this.onOpen,
    required this.onPlaced,
    this.divided = false,
  });

  final ServiceKey service;
  final ManualImportItem item;
  final NeedYouKind kind;
  final bool selected;
  final bool open;
  final VoidCallback onOpen;
  final VoidCallback onPlaced;
  final bool divided;

  @override
  ConsumerState<BlockedImportNeedYouRow> createState() =>
      _BlockedImportNeedYouRowState();
}

class _BlockedImportNeedYouRowState
    extends ConsumerState<BlockedImportNeedYouRow> {
  int? _season;
  late int _episode = episodeNumberInName(widget.item.fileName) ?? 1;

  /// Whether the stepper is still on its own guess: the file's name says no
  /// episode and nobody has stepped it yet.
  late bool _guessing = episodeNumberInName(widget.item.fileName) == null;

  /// Each season's episode numbers, as Sonarr lists them.
  final _numbers = <int, List<int>>{};
  bool _busy = false;
  String? _error;

  List<int> get _seasons => seasonsOfSeries(widget.item.series);

  @override
  void initState() {
    super.initState();
    final seasons = _seasons;
    if (widget.kind == NeedYouKind.episode) {
      // One season: nothing to pick. More: the one every other file of the
      // series in this Review sits in, when they agree; otherwise a choice.
      _season = seasons.length == 1 ? seasons.single : _soleSeason();
      _followPlaced();
    }
  }

  /// The season every other file of the same series in this Review is on,
  /// or null when they are on none or on several.
  int? _soleSeason() {
    final seriesId = intOrNull(widget.item.series?['id']);
    final seasons = <int>{
      for (final other in ref.read(manualImportFlowProvider).items)
        if (other.path != widget.item.path &&
            intOrNull(other.series?['id']) == seriesId)
          for (final episode in other.episodes)
            ?intOrNull(episode['seasonNumber']),
    };
    return seasons.length == 1 ? seasons.single : null;
  }

  /// A run of files whose names say no episode is a run of episodes: the
  /// guess is the one after the last this Review placed in the season.
  void _followPlaced() {
    final season = _season;
    if (!_guessing || season == null) return;
    final seriesId = intOrNull(widget.item.series?['id']);
    var last = 0;
    for (final other in ref.read(manualImportFlowProvider).items) {
      if (other.path == widget.item.path) continue;
      if (intOrNull(other.series?['id']) != seriesId) continue;
      for (final episode in other.episodes) {
        if (intOrNull(episode['seasonNumber']) != season) continue;
        final number = intOrNull(episode['episodeNumber']) ?? 0;
        if (number > last) last = number;
      }
    }
    if (last > 0) _episode = last + 1;
  }

  /// The other file of this Review already on [episode] of [season], if any.
  String? _placedOn(int season, int episode) {
    final seriesId = intOrNull(widget.item.series?['id']);
    for (final other in ref.read(manualImportFlowProvider).items) {
      if (other.path == widget.item.path) continue;
      if (intOrNull(other.series?['id']) != seriesId) continue;
      final taken = other.episodes.any(
        (each) =>
            intOrNull(each['seasonNumber']) == season &&
            intOrNull(each['episodeNumber']) == episode,
      );
      if (taken) return fileStem(other);
    }
    return null;
  }

  @override
  void didUpdateWidget(BlockedImportNeedYouRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && !oldWidget.open && _season != null) {
      // Opened after a sibling was placed: follow it.
      setState(_followPlaced);
      _load(_season!);
    }
  }

  Future<void> _load(int season) async {
    if (_numbers.containsKey(season)) return;
    final seriesId = intOrNull(widget.item.series?['id']) ?? 0;
    if (seriesId <= 0) return;
    try {
      final episodes = await ref
          .read(manualImportFlowProvider.notifier)
          .getEpisodes(seriesId: seriesId, seasonNumber: season);
      if (!mounted) return;
      final numbers = [
        for (final episode in episodes)
          if (episode.seasonNumber == season) episode.episodeNumber,
      ]..sort();
      setState(() => _numbers[season] = numbers);
    } catch (_) {
      // The stepper stays free; Add says so if the episode is not there.
    }
  }

  void _pickSeason(int season) {
    setState(() {
      _season = season;
      _error = null;
      _followPlaced();
    });
    _load(season);
  }

  void _step(int delta) {
    final numbers = _numbers[_season];
    final low = numbers == null || numbers.isEmpty ? 1 : numbers.first;
    final high = numbers == null || numbers.isEmpty ? 999 : numbers.last;
    setState(() {
      _episode = (_episode + delta).clamp(low, high);
      _guessing = false;
      _error = null;
    });
  }

  Future<void> _place() async {
    final season = _season;
    if (season == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref
        .read(manualImportFlowProvider.notifier)
        .placeEpisode(widget.item, season: season, episode: _episode);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) widget.onPlaced();
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final amber = statusToneColor(
      scheme,
      StatusTone.warning,
      surface: room.slab,
    );
    final service = widget.service;
    final item = widget.item;
    final ready = item.isSubmittableFor(service);
    final waiting =
        !ready || (widget.kind == NeedYouKind.refused && !widget.selected);
    final title = manualImportGroupTitle(service, item);
    final code = manualImportIdentityFor(service, item).code;
    final where = [if (title != 'Unmatched') title, ?code].join(' ');
    final reason = item.rejections.isEmpty
        ? null
        : item.rejections.first.reason;

    final (String status, Color statusColor, bool strong) = switch (true) {
      _ when ready && widget.selected => (
        'Added · $where',
        room.inkSecondary,
        false,
      ),
      _ when ready && widget.kind != NeedYouKind.refused => (
        '$where · left out',
        room.inkTertiary,
        false,
      ),
      _ => switch (widget.kind) {
        NeedYouKind.episode => ('Which episode?', amber, true),
        NeedYouKind.identity => (
          switch (service) {
            ServiceKey.radarr => 'Which movie?',
            ServiceKey.lidarr => 'Which album?',
            _ => 'Which series?',
          },
          amber,
          true,
        ),
        NeedYouKind.refused => (reason ?? 'Refused', amber, true),
      },
    };

    final header = Semantics(
      container: true,
      button: true,
      expanded: widget.open,
      label: '${item.fileName}, $status',
      onTap: widget.onOpen,
      excludeSemantics: true,
      child: InkWell(
        onTap: widget.onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: ready
                      ? () => ref
                            .read(manualImportFlowProvider.notifier)
                            .toggleItem(item, !widget.selected)
                      : widget.onOpen,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: BlockedImportMark(
                        selected: ready && widget.selected,
                        waiting: waiting,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FilenameText(
                        filename: fileStem(item),
                        style: AppType.mono.copyWith(color: room.ink),
                      ),
                      Text(
                        status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: strong
                            ? AppType.meta
                                  .weight(FontWeight.w600)
                                  .copyWith(color: statusColor)
                            : AppType.meta.copyWith(color: statusColor),
                      ),
                    ],
                  ),
                ),
                Icon(
                  widget.open
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: room.inkSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: widget.divided
            ? Border(top: BorderSide(color: room.hair))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (widget.open)
            Padding(
              padding: const EdgeInsets.only(
                left: 44 + AppSpacing.xs,
                bottom: AppSpacing.md,
              ),
              child: switch (widget.kind) {
                NeedYouKind.episode => _episodeChoice(context),
                NeedYouKind.identity => _matchChoice(context, reason),
                NeedYouKind.refused => _refusedChoice(context, reason),
              },
            ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
    child: Text(
      text,
      style: AppType.meta.copyWith(color: CupolaRoom.of(context).inkSecondary),
    ),
  );

  Widget _episodeChoice(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final service = widget.service;
    final item = widget.item;
    final title = manualImportGroupTitle(service, item);
    final quality = item.qualityLabel == 'Unknown'
        ? null
        : qualityWords(item.qualityLabel);
    final language = item.languageLabel == 'Original'
        ? null
        : item.languageLabel;
    final season = _season;
    final numbers = season == null ? null : _numbers[season];
    final missing =
        numbers != null && numbers.isNotEmpty && !numbers.contains(_episode);
    final placedOn = season == null ? null : _placedOn(season, _episode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, 'Series'),
        _TitleTile(
          posterUrl: _posterOf(service, item),
          icon: service.icon,
          title: title,
          from: "from ${service.title}'s grab",
          onChange: () => showManualImportFixSheet(
            context: context,
            service: service,
            item: item,
          ),
        ),
        _label(context, 'Season'),
        _Seasons(seasons: _seasons, selected: season, onPick: _pickSeason),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(context, 'Episode'),
                  _Stepper(
                    value: formatEpisodeOrdinal(_episode),
                    onLess: () => _step(-1),
                    onMore: () => _step(1),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (quality != null || language != null)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(context, 'From the file name'),
                    Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.borderRadiusMd,
                        border: Border.all(color: room.hair),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (quality != null)
                            Text(
                              quality,
                              style: AppType.label.copyWith(color: room.ink),
                            ),
                          if (language != null)
                            Text(
                              language,
                              style: AppType.meta.copyWith(
                                color: room.inkSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              const Spacer(),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: season == null || _busy ? null : _place,
          child: Text(
            season == null ? 'Pick a season to add it' : 'Add to the import',
          ),
        ),
        // In the secondary ink, not amber: a better copy of an episode
        // already placed is a choice the user may mean. Said, so it is one.
        if (placedOn != null && _error == null && !missing) ...[
          const SizedBox(height: AppSpacing.xs),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      '${formatEpisodeCode(season!, _episode)} is already on ',
                ),
                TextSpan(
                  text: placedOn,
                  style: AppType.mono.copyWith(color: room.inkSecondary),
                ),
              ],
            ),
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
        ],
        if (_error ?? (missing ? _missingWords(season!) : null)
            case final error?) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            error,
            style: AppType.meta.copyWith(
              color: statusToneColor(
                scheme,
                StatusTone.warning,
                surface: room.slab,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _missingWords(int season) =>
      '${seasonChipLabel(season)} has no ${formatEpisodeOrdinal(_episode)}.';

  Widget _matchChoice(BuildContext context, String? reason) {
    final room = CupolaRoom.of(context);
    final service = widget.service;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reason != null) ...[
          _label(context, 'What ${service.title} says'),
          Text(reason, style: AppType.mono.copyWith(color: room.inkSecondary)),
        ],
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: () => showManualImportFixSheet(
            context: context,
            service: service,
            item: widget.item,
          ),
          child: Text(switch (service) {
            ServiceKey.radarr => 'Pick the movie',
            ServiceKey.lidarr => 'Pick the album',
            _ => 'Pick the series',
          }),
        ),
      ],
    );
  }

  Widget _refusedChoice(BuildContext context, String? reason) {
    final room = CupolaRoom.of(context);
    final service = widget.service;
    final item = widget.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, 'What ${service.title} says'),
        for (final rejection in item.rejections)
          Text(
            rejection.reason,
            style: AppType.mono.copyWith(color: room.inkSecondary),
          ),
        const SizedBox(height: AppSpacing.md),
        if (widget.selected)
          OutlinedButton(
            onPressed: () => ref
                .read(manualImportFlowProvider.notifier)
                .toggleItem(item, false),
            child: const Text('Leave it out'),
          )
        else
          FilledButton(
            onPressed: () => ref
                .read(manualImportFlowProvider.notifier)
                .toggleItem(item, true),
            child: const Text('Add it anyway'),
          ),
      ],
    );
  }
}

/// The seasons a file can go in, one choice: four or fewer share the row
/// equally, as J draws them; more wrap at their own width.
class _Seasons extends StatelessWidget {
  const _Seasons({
    required this.seasons,
    required this.selected,
    required this.onPick,
  });

  final List<int> seasons;
  final int? selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    Widget chip(int season) => _SeasonChip(
      label: seasonChipLabel(season),
      selected: season == selected,
      onTap: () => onPick(season),
    );
    if (seasons.length <= 4) {
      return Row(
        children: [
          for (final (index, season) in seasons.indexed) ...[
            if (index > 0) const SizedBox(width: AppSpacing.xs),
            Expanded(flex: season == 0 ? 2 : 1, child: chip(season)),
          ],
        ],
      );
    }
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [for (final season in seasons) chip(season)],
    );
  }
}

class _SeasonChip extends StatelessWidget {
  const _SeasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label == 'Specials' ? label : 'Season ${label.substring(1)}',
      excludeSemantics: true,
      child: Material(
        color: selected ? scheme.primary : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusMd,
          side: selected ? BorderSide.none : BorderSide(color: room.edge),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  label,
                  maxLines: 1,
                  style: AppType.label.copyWith(
                    color: selected ? scheme.onPrimary : room.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The title a file was grabbed for, with the way to choose another.
class _TitleTile extends StatelessWidget {
  const _TitleTile({
    required this.posterUrl,
    required this.icon,
    required this.title,
    required this.from,
    required this.onChange,
  });

  final String? posterUrl;
  final IconData icon;
  final String title;
  final String from;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: room.hair),
      ),
      child: Row(
        children: [
          HomeRowArt(posterUrl: posterUrl, icon: icon),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label.copyWith(color: room.ink),
                ),
                Text(
                  from,
                  style: AppType.meta.copyWith(color: room.inkSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
            child: Text('Change', semanticsLabel: 'Change $title'),
          ),
        ],
      ),
    );
  }
}

/// `− E3 +`.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.onLess,
    required this.onMore,
  });

  final String value;
  final VoidCallback onLess;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: room.hair),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous episode',
            onPressed: onLess,
            icon: const Icon(Icons.remove_rounded),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: AppType.row.tabular.copyWith(color: room.ink),
            ),
          ),
          IconButton(
            tooltip: 'Next episode',
            onPressed: onMore,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

/// The bar under the Review: what stays for later, that an import cannot be
/// undone, and the import itself in the amber fill, the fault's remedy.
class BlockedImportBar extends StatelessWidget {
  const BlockedImportBar({
    super.key,
    required this.label,
    required this.onImport,
    this.line,
    this.error,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onImport;
  final String? line;
  final String? error;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: room.slab,
        border: Border(top: BorderSide(color: room.hair)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error case final error?) ...[
              Text(
                error,
                style: AppType.meta.copyWith(
                  color: statusToneColor(
                    scheme,
                    StatusTone.warning,
                    surface: room.slab,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            Row(
              children: [
                if (line case final line?)
                  Expanded(
                    child: Text(
                      line,
                      style: AppType.meta.copyWith(color: room.inkSecondary),
                    ),
                  )
                else
                  const Spacer(),
                Text(
                  "Imports can't be undone",
                  style: AppType.meta.copyWith(color: room.inkTertiary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              style: remedyFillStyle(context),
              onPressed: onImport,
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
