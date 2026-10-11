import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/activity_download.dart';
import 'package:cupola/features/activity/domain/download_page.dart'
    show downloadPageKey;
import 'package:cupola/features/activity/domain/download_table.dart'
    show downloadProgressCell;
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/home/domain/downloads.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One download on Activity: its art, its title and the release it is, which
/// way its bytes travel, how far it got and how fast, and who asked for it;
/// a stuck one says where it stopped and since when, in amber; one stopped on
/// purpose says where, in the neutral.
///
/// The remedy of a stuck one is in Needs you, once: the row only shows it.
/// A tap opens the download's own page (`openDownload`), beside the list on
/// a tablet, where the row wears the selection.
class ActivityDownloadRow extends ConsumerWidget {
  const ActivityDownloadRow({
    super.key,
    required this.item,
    required this.now,
    this.request,
    this.divided = false,
  }) : _queued = false;

  /// A download waiting its turn, in Up next: `Queued · starts in about
  /// 6 min` in blue under the release, and which way it will travel.
  const ActivityDownloadRow.queued({
    super.key,
    required this.item,
    required this.now,
    this.request,
    this.divided = false,
  }) : _queued = true;

  final ServiceQueueItem item;

  /// The clock its `nothing for 3 h` and `ready around 21:10` are read by.
  final DateTime now;

  /// The household request that asked for it, when Seerr holds one.
  final SeerrRequest? request;

  /// Whether a hairline separates it from the row above.
  final bool divided;

  final bool _queued;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final room = CupolaRoom.of(context);
    final fault = item.fault;
    final stuck = !_queued && isDownloadFault(fault);
    // Stopped on purpose: the neutral, `Stopped at 62%`, and no speed.
    final stopped = !_queued && !stuck && item.held;
    final tone = statusToneColor(
      scheme,
      stuck
          ? StatusTone.warning
          : stopped
          ? StatusTone.neutral
          : StatusTone.info,
      surface: room.slab,
    );
    final percent = item.progress == null
        ? null
        : wholePercent(item.progress! * 100);
    final value = _queued
        ? ''
        : stuck
        ? stuckValue(fault!, percent: percent)
        : stopped
        ? downloadProgressCell(item).text
        : movingValue(percent: percent, etaSeconds: item.etaSeconds);
    final route = downloadRoute(item);
    final release = item.names.machineName;
    final showsRelease =
        release != null && release.isNotEmpty && release != item.title;
    final evidence = stuck
        ? nothingForWords(item.stalledSince, now: now)
        : null;
    final speed = _queued || stuck || stopped || item.rateBytesPerSecond == null
        ? null
        : formatBytesPerSecond(item.rateBytesPerSecond!);
    final asked = switch (request) {
      final request? => requestLine(item, request, now: now),
      null => null,
    };
    final waiting = _queued ? queuedWords(item.startsInSeconds) : null;
    final spokenValue = _queued
        ? waiting!
        : stuck || stopped
        ? spokenPercents(value)
        : spokenMovingValue(percent: percent, etaSeconds: item.etaSeconds);

    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final valueText = Text(
      value,
      style: AppType.meta.weight(FontWeight.w600).tabular.copyWith(color: tone),
    );
    final routeText = Text(
      route,
      maxLines: large ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: AppType.meta.copyWith(color: room.inkSecondary),
    );
    final secondary = AppType.meta.tabular.copyWith(color: room.inkSecondary);
    // Under the bar, at its end: how fast, or since when nothing arrived.
    final underBar = speed ?? evidence;

    return ActivityRowFrame(
      divided: divided,
      label: item.title,
      value: [
        spokenValue,
        route,
        if (speed != null) spokenBytesPerSecond(speed),
        ?evidence,
        ?asked,
      ].join(', '),
      onTap: () => context.openDownload(item),
      selected: context.paneShowsDownload(downloadPageKey(item)),
      art: HomeRowArt.large(posterUrl: item.posterUrl, icon: item.service.icon),
      children: [
        Text(
          item.title,
          maxLines: large ? 3 : 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.row.copyWith(color: room.ink),
        ),
        if (showsRelease)
          Text(
            release,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: AppType.mono.copyWith(color: room.inkSecondary),
          ),
        if (waiting != null) ...[
          _Dotted(words: waiting, color: tone),
          routeText,
        ] else if (large) ...[
          routeText,
          if (value.isNotEmpty) valueText,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: routeText),
              if (value.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                valueText,
              ],
            ],
          ),
        if (!_queued)
          if (item.progress case final progress?) ...[
            const SizedBox(height: AppSpacing.xs),
            HomeRowBar(value: progress, color: tone),
          ],
        if (underBar != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(underBar, style: secondary),
            ),
          ),
        if (asked != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              asked,
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
          ),
      ],
    );
  }
}

/// A state with its dot before it: `• Queued · starts in about 6 min`.
class _Dotted extends StatelessWidget {
  const _Dotted({required this.words, required this.color});

  final String words;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = AppType.meta.weight(FontWeight.w600).copyWith(color: color);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(child: Text(words, style: style)),
      ],
    );
  }
}

/// The frame every row of Activity shares: the art at its start, the lines
/// beside it, one sentence to a screen reader, the whole row a target.
class ActivityRowFrame extends StatelessWidget {
  const ActivityRowFrame({
    super.key,
    required this.divided,
    required this.label,
    required this.value,
    required this.onTap,
    required this.art,
    required this.children,
    this.actions = const [],
    this.selected = false,
  });

  final bool divided;

  /// Whether the pane beside the list shows this row's page, on a tablet:
  /// the row sits on the room's strong fill, the mark of what is selected,
  /// and says so to a screen reader.
  final bool selected;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Widget art;
  final List<Widget> children;

  /// What the row offers beside opening it, on a long press, a secondary
  /// click and among a screen reader's actions: nothing drawn on the row.
  final List<RowAction> actions;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    // Where the finger went down, for the menu to open under it.
    Offset? pressedAt;
    void menu() => showRowActions(context, pressedAt, actions);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: room.hair)) : null,
      ),
      child: Semantics(
        container: true,
        button: true,
        selected: selected ? true : null,
        label: label,
        value: value,
        onTap: onTap,
        customSemanticsActions: actions.isEmpty
            ? null
            : {
                for (final action in actions)
                  CustomSemanticsAction(label: action.label): action.onSelected,
              },
        child: InkWell(
          onTap: onTap,
          onTapDown: actions.isEmpty
              ? null
              : (details) => pressedAt = details.globalPosition,
          onLongPress: actions.isEmpty ? null : menu,
          onSecondaryTapDown: actions.isEmpty
              ? null
              : (details) => pressedAt = details.globalPosition,
          onSecondaryTap: actions.isEmpty ? null : menu,
          excludeFromSemantics: true,
          child: ExcludeSemantics(
            // The fill reaches into the slab's inset, so nothing in the row
            // moves when it is selected.
            child: CustomPaint(
              painter: selected ? SelectedRowPainter(room.fillStrong) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    art,
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The room's strong fill behind a selected row, reaching into the slab's
/// inset on either side, as a selected search row's does.
class SelectedRowPainter extends CustomPainter {
  const SelectedRowPainter(this.color);

  final Color color;

  static const double _reach = AppSpacing.sm;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(-_reach, 0, size.width + _reach, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(AppRadius.md)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(SelectedRowPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// One thing a row offers beside opening it: `Delete request`.
typedef RowAction = ({String label, IconData icon, VoidCallback onSelected});

/// The menu of [actions] under [at] (the row's own corner when the press
/// left no point), the theme's menu as every ⋯ draws it.
Future<void> showRowActions(
  BuildContext context,
  Offset? at,
  List<RowAction> actions,
) async {
  if (actions.isEmpty) return;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final row = context.findRenderObject() as RenderBox?;
  final point =
      at ?? row?.localToGlobal(row.size.centerLeft(Offset.zero)) ?? Offset.zero;
  final local = overlay.globalToLocal(point);
  final chosen = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(
      local & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      for (final (index, action) in actions.indexed)
        PopupMenuItem(
          value: index,
          child: Row(
            children: [
              Icon(action.icon, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: Text(action.label)),
            ],
          ),
        ),
    ],
  );
  if (chosen != null) actions[chosen].onSelected();
}

/// Opens the page of [mediaId] in [service], on the connection
/// [instanceId]. False when the arr names no title to open.
Future<bool> openArrTitle(
  BuildContext context, {
  required ServiceKey service,
  required int? mediaId,
  required String instanceId,
}) async {
  final id = mediaId;
  final instance = instanceId.isEmpty ? null : instanceId;
  final location = id == null || id <= 0
      ? null
      : switch (service) {
          ServiceKey.radarr => ServiceRoutes.radarrMovie(
            id,
            instanceId: instance,
          ),
          ServiceKey.sonarr => ServiceRoutes.sonarrSeries(
            id,
            instanceId: instance,
          ),
          ServiceKey.lidarr => ServiceRoutes.lidarrArtist(
            id,
            instanceId: instance,
          ),
          ServiceKey.readarr => ServiceRoutes.readarrAuthor(
            id,
            instanceId: instance,
          ),
          _ => null,
        };
  if (location == null) return false;
  await context.push(location);
  return true;
}
