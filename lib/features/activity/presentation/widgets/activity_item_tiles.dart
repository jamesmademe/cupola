import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart' as dynamic_utils;
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/connection_badge.dart';
import 'package:cupola/core/widgets/media_search_popup_menu.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/widgets/tag_chip.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_actions.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:cupola/features/activity/presentation/widgets/detail_sheets.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class QueueItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final ServiceType serviceType;

  const QueueItemTile({
    super.key,
    required this.item,
    required this.serviceType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final resolvedStatus = resolveQueueDisplayStatus(item);
    final title = queueTitle(item, serviceType);
    final subtitle = queueSubtitle(item, serviceType);
    final progress = dynamic_utils.queueProgress(
      item,
      parseStrings: false,
      includeSizeLeftAlias: false,
    );
    final chips = _buildQueueChips(item, colorScheme);
    // Gated on the status vocabulary rather than on `downloading` alone, so a
    // stalled transfer keeps its bar: "stuck at 43%" is how the user decides
    // between waiting and blocklisting, and the bar is tinted by tone, so it
    // reads as a frozen amber rather than as healthy progress.
    final showInlineProgress = progress != null && resolvedStatus.showsProgress;
    final toneColor = statusToneColor(colorScheme, resolvedStatus.tone);

    return _TileShell(
      onTap: () => DetailSheets.showQueueDetail(context, item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.weight(
                        FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) _SubtitleText(text: subtitle),
                    const SizedBox(height: AppSpacing.sm),
                    // The badge carries the label, the state icon and the
                    // percentage in tabular figures. The percentage used to be
                    // concatenated into a subtitle string, so it re-flowed the
                    // line every time it ticked.
                    StatusBadge(info: resolvedStatus),
                    if (resolvedStatus.detail != null)
                      _SubtitleText(
                        text: resolvedStatus.detail!,
                        color: toneColor,
                      ),
                    if (showInlineProgress)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: SizedBox(
                          width: 96,
                          child: ClipRRect(
                            borderRadius: AppRadius.borderRadiusFull,
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              color: toneColor,
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          _ChipRow(chips: chips),
        ],
      ),
    );
  }
}

class HistoryItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final ServiceType serviceType;

  const HistoryItemTile({
    super.key,
    required this.item,
    required this.serviceType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = historyTitle(item, serviceType);
    final subtitle = historySubtitle(item, serviceType);
    final metadata = joinActivityParts([
      formatDateOnly(stringOrNull(item['date'])),
      historySizeLabel(item),
    ]);
    final episodeCode = serviceType == ServiceType.series
        ? historyEpisodeCode(item)
        : null;
    final chips = _buildHistoryChips(item, colorScheme);

    return _TileShell(
      onTap: () => DetailSheets.showHistoryDetail(context, item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (episodeCode != null)
                      TagChip(
                        surface: colorScheme.surfaceContainer,
                        text: episodeCode,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.weight(
                        FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Same resolver and same renderer as the global feed. These were
              // two independent switches before, and they disagreed: a
              // `downloadFailed` event was red here and green there.
              StatusBadge(info: resolveHistoryStatus(item)),
            ],
          ),
          if (subtitle != null) _SubtitleText(text: subtitle),
          if (metadata.isNotEmpty)
            _SubtitleText(text: metadata, topSpacing: AppSpacing.sm),
          _ChipRow(chips: chips),
        ],
      ),
    );
  }
}

class WantedItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final ServiceType serviceType;
  final VoidCallback? onAutoSearch;
  final VoidCallback? onInteractiveSearch;
  final bool isCutoff;
  final String? qualityProfileName;

  const WantedItemTile({
    super.key,
    required this.item,
    required this.serviceType,
    this.onAutoSearch,
    this.onInteractiveSearch,
    this.isCutoff = false,
    this.qualityProfileName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = wantedTitle(item, serviceType);
    final subtitle = isCutoff && serviceType == ServiceType.movies
        ? null
        : wantedSubtitle(item, serviceType);
    final statusText = isCutoff
        ? formatCutoffSize(item, serviceType)
        : wantedStatusText(item, serviceType);
    final chips = _buildWantedChips(
      item,
      serviceType,
      colorScheme,
      isCutoff: isCutoff,
      qualityProfileName: qualityProfileName,
    );
    final canSearch = onAutoSearch != null && onInteractiveSearch != null;

    return _TileShell(
      onTap: () => DetailSheets.showWantedDetail(context, item, serviceType),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleRow(
            title: title,
            titleStyle: theme.textTheme.titleSmall?.weight(FontWeight.w600),
            maxLines: isCutoff ? 1 : null,
            trailing: canSearch
                ? MediaSearchPopupMenu(
                    onAutoSearch: onAutoSearch!,
                    onInteractiveSearch: onInteractiveSearch!,
                    iconSize: 18,
                  )
                : null,
          ),
          if (subtitle != null) _SubtitleText(text: subtitle),
          // Backlog, so neutral: "missing from disk" is the list of things to
          // fetch, the resting state of a wanted row, not damage.
          if (statusText != null) _SubtitleText(text: statusText),
          _ChipRow(chips: chips),
        ],
      ),
    );
  }
}

class GlobalActivityItemTile extends StatelessWidget {
  final GlobalActivityItem item;

  const GlobalActivityItemTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = item.service.accent;
    final raw = item.raw;
    // One colour for the whole row's state: badge, warning text and progress
    // bar all read from the resolved tone rather than from the row's category.
    final toneColor = statusToneColor(colorScheme, item.status.tone);
    final writeActions = _writeActions();
    const icon = Icons.block_rounded;

    // Same row, two shapes. A phone gets a card, because a card is what a finger
    // aims at; a window gets a table row, because a pointer is precise and a
    // 1140pt column of 96pt cards wastes the one thing a window has. Everything
    // else (the actions, the tap target, the badges, the tones) is computed
    // above and shared, so the table can never drift into being a second,
    // poorer row with its own bugs.
    final onOpen = raw == null ? null : () => _showDetails(context);
    final trailing = writeActions.isEmpty
        ? null
        : _RowActionsMenu(item: item, actions: writeActions);

    // A window gets the table at every width    // A window gets the table at every width its shell has, not only above
    // 1100: under 720 it has the phone's shell, and the phone's cards. The
    // gate used to be `isDesktopShell && width >= desktopCompact`, so dragging
    // a desktop window narrower than 1100 swapped the whole list for phone
    // cards: a different information architecture at a size the user reached
    // by moving a mouse. The size-class rule is the opposite: below the compact
    // breakpoint the shell keeps every part it had and shows fewer items in
    // each, never smaller ones. So the row stays a row and sheds cells.
    if (AppBreakpoints.isDesktopShell(context)) {
      return _DesktopActivityRow(
        item: item,
        icon: icon,
        accent: accent,
        toneColor: toneColor,
        onOpen: onOpen,
        trailing: trailing,
        actions: writeActions,
        compact:
            MediaQuery.sizeOf(context).width < AppBreakpoints.desktopCompact,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: AppCard.outlined(
        onTap: onOpen,
        backgroundColor: colorScheme.surfaceContainer,
        borderColor: colorScheme.outlineVariant,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 56,
              decoration: BoxDecoration(
                color: ServiceTheme.fromAccent(accent).softContainer,
                borderRadius: AppRadius.borderRadiusSm,
              ),
              child: Icon(
                icon,
                color: ServiceTheme.onTint(
                  accent,
                  surface: colorScheme.surfaceContainer,
                  tintAlpha: 0.14,
                ),
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.weight(FontWeight.w600),
                  ),
                  if (item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // The resolved status, rendered by the shared badge. The
                      // service is deliberately no longer a chip here: when the
                      // feed is grouped its section header already names the
                      // service, and when it is filtered the user chose it, so
                      // the chip was restating known information on every row,
                      // in the same 11pt weight as the status it competed with.
                      // The icon well, with the service's mark, still carries
                      // the identity: by shape, the well is the lamp.
                      StatusBadge(info: item.status),
                      // Which server this row came off. On the row rather than
                      // on the group header, because the header groups by
                      // *service* and two connections interleave inside it:
                      // the one place the search sections do not have to say
                      // it, since one leg there is one server. Empty, and so
                      // absent, whenever the service has a single connection.
                      ConnectionBadge(
                        label: item.instanceLabel,
                        accent: accent,
                        surface: colorScheme.surfaceContainer,
                      ),
                      // When each event happened. `sortDate` was already being
                      // parsed to order the feed but never shown, which left the
                      // History list unable to answer its own question: several
                      // rows for one title, no way to tell which came first.
                      // Plain text rather than a pill: it is context, not
                      // another label to scan.
                      if (item.sortDate != null)
                        Text(
                          formatRelativeDateTime(item.sortDate!),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                  // The service's own explanation of a problem. It was already
                  // being fetched and then thrown away behind a bare "Warning"
                  // chip, so the row announced that something was wrong while
                  // withholding what.
                  if (item.detail != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: toneColor),
                    ),
                  ],
                  if (item.progress != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ClipRRect(
                      borderRadius: AppRadius.borderRadiusFull,
                      child: LinearProgressIndicator(
                        value: item.progress,
                        minHeight: 4,
                        // Tone, not the service accent: a failed transfer's bar
                        // has to read red. Colouring it by service meant a
                        // stalled download and a healthy one were chromatically
                        // identical.
                        color: toneColor,
                        backgroundColor: colorScheme.outlineVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // No trailing percentage: StatusBadge already prints it, with
            // tabular figures, right next to the label it belongs to. Two
            // copies of one number on one row is how the old layout ended up
            // with four things at 11pt competing for the same glance.
            if (writeActions.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs),
              _RowActionsMenu(item: item, actions: writeActions),
            ],
          ],
        ),
      ),
    );
  }

  /// The write actions this row supports: removing the release from the
  /// blocklist, when the record has an id to act on.
  List<_RowAction> _writeActions() {
    if (item.recordId == null) return const [];
    if (!item.serviceType.supportsArrActivity) return const [];
    return const [_RowAction.removeFromBlocklist];
  }

  void _showDetails(BuildContext context) {
    final raw = item.raw;
    if (raw == null) return;
    DetailSheets.showBlocklistDetail(context, raw);
  }
}

/// A write action available on an Activity row.
enum _RowAction {
  removeFromBlocklist(
    'Remove from blocklist',
    Icons.playlist_add_check_rounded,
  );

  const _RowAction(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The per-row action menu: the thing that turns Activity from a feed into
/// something you can operate.
class _RowActionsMenu extends ConsumerWidget {
  final GlobalActivityItem item;
  final List<_RowAction> actions;

  const _RowActionsMenu({required this.item, required this.actions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<_RowAction>(
      tooltip: 'Actions for ${item.title}',
      icon: Icon(
        Icons.more_vert_rounded,
        size: 18,
        color: colorScheme.onSurfaceVariant,
      ),
      onSelected: (action) => _runRowAction(context, ref, item, action),
      itemBuilder: (context) => _rowActionMenuItems(context, actions),
    );
  }
}

/// The row's actions as menu items, built once for both doors.
///
/// Two doors on a desktop window: the visible `⋮` button and a right-click on
/// the row, and exactly one list behind them. That is the binding rule for the
/// whole desktop layer: hover and right-click are accelerators, so every item
/// here is also reachable from a control that is simply *there*, and a phone
/// loses nothing by having no pointer.
List<PopupMenuEntry<_RowAction>> _rowActionMenuItems(
  BuildContext context,
  List<_RowAction> actions,
) {
  final colorScheme = Theme.of(context).colorScheme;
  return [
    for (final action in actions)
      PopupMenuItem<_RowAction>(
        value: action,
        child: Row(
          children: [
            Icon(action.icon, size: 18, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.md),
            // Flexible, because the longest label does not fit: a Material
            // 3 popup is capped at 280pt and "Remove from blocklist" plus
            // its glyph and gutter wants 326, so the row overflowed by 70
            // and painted the debug stripe over the menu. Wrapping rather
            // than ellipsising: a menu item that reads "Remove from
            // blockli…" is worse than one that takes two lines.
            Flexible(child: Text(action.label)),
          ],
        ),
      ),
  ];
}

/// Dispatches one [_RowAction] against [item].
///
/// Top-level rather than a method on the menu, because the detail sheet needs
/// the same dispatch driven by a context that is *not* the sheet's; see
/// [_SheetActions]. [context] and [ref] must therefore belong to something that
/// outlives any modal the action opens.
///
/// Each case reads the key it actually needs. There used to be one
/// `recordId == null` guard covering the whole method, which quietly made every
/// action \*arr-shaped: a Seerr request is keyed by its own id and has no \*arr
/// record, so it could never have reached the switch.
void _runRowAction(
  BuildContext context,
  WidgetRef ref,
  GlobalActivityItem item,
  _RowAction action,
) {
  switch (action) {
    case _RowAction.removeFromBlocklist:
      final recordId = item.recordId;
      if (recordId == null) return;
      ActivityActions.removeFromBlocklist(
        context,
        ref,
        serviceType: item.serviceType,
        // The row's own connection, never the lens: see [ActivityActions].
        instanceId: item.instanceId,
        recordId: recordId,
        title: item.title,
      );
  }
}

class _TileShell extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const _TileShell({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // One card rhythm for the whole feature. This used to be `sm` top *and*
      // bottom (16pt between cards) while `GlobalActivityItemTile` used 0/`sm`
      // for 8pt, so the same conceptual row had two different densities
      // depending on which screen you opened. 8pt is the denser of the two,
      // which is the right call for an operational list.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: AppCard.outlined(
        onTap: onTap,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        borderColor: Theme.of(context).colorScheme.outlineVariant,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: child,
      ),
    );
  }
}

class _SubtitleText extends StatelessWidget {
  final String text;
  final Color? color;
  final double topSpacing;

  const _SubtitleText({
    required this.text,
    this.color,
    this.topSpacing = AppSpacing.xs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: topSpacing),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color ?? colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  final List<Widget> chips;

  const _ChipRow({required this.chips});

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: chips,
        ),
      ],
    );
  }
}

class _TitleRow extends StatelessWidget {
  final String title;
  final TextStyle? titleStyle;
  final Widget? trailing;
  final int? maxLines;

  const _TitleRow({
    required this.title,
    this.titleStyle,
    this.trailing,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            style: titleStyle,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ],
      ],
    );
  }
}

List<Widget> _buildQueueChips(
  Map<String, dynamic> item,
  ColorScheme colorScheme,
) {
  final quality = extractQualityName(item);
  final protocol = stringOrNull(item['protocol']);
  final downloadClient = stringOrNull(item['downloadClient']);
  final hasWarning = arrQueueHasWarning(item);

  return [
    // A record the service flagged is a fault, so amber. Red would say the
    // service did not answer, and it did: it answered with this warning.
    if (hasWarning)
      TagChip(
        surface: colorScheme.surfaceContainer,
        text: 'Warning',
        color: statusToneFill(colorScheme, StatusTone.warning),
        icon: Icons.warning_amber_rounded,
      ),
    if (quality != null)
      TagChip(surface: colorScheme.surfaceContainer, text: quality),
    // A protocol states no status, so it wears no tone: the plain chip, like
    // the quality beside it.
    if (protocol != null)
      TagChip(surface: colorScheme.surfaceContainer, text: protocol),
    if (downloadClient != null)
      TagChip(surface: colorScheme.surfaceContainer, text: downloadClient),
  ];
}

List<Widget> _buildHistoryChips(
  Map<String, dynamic> item,
  ColorScheme colorScheme,
) {
  final quality = extractQualityName(item);
  final indexer = stringOrNull(asActivityMap(item['data'])?['indexer']);

  return [
    if (quality != null)
      TagChip(surface: colorScheme.surfaceContainer, text: quality),
    if (indexer != null)
      TagChip(surface: colorScheme.surfaceContainer, text: indexer),
  ];
}

List<Widget> _buildWantedChips(
  Map<String, dynamic> item,
  ServiceType serviceType,
  ColorScheme colorScheme, {
  bool isCutoff = false,
  String? qualityProfileName,
}) {
  // Neutral: an unmonitored item is one the user chose to stop tracking, which
  // is the backlog arm of the tone rule, not a fault and not unreachable.
  final monitored = item['monitored'] == false
      ? TagChip(
          surface: colorScheme.surfaceContainer,
          text: 'Unmonitored',
          color: statusToneFill(colorScheme, StatusTone.neutral),
        )
      : null;
  final quality = switch (serviceType) {
    ServiceType.movies =>
      qualityProfileName ??
          extractQualityName(item, fileKey: 'movieFile') ??
          extractQualityName(item),
    ServiceType.music =>
      extractQualityName(item, fileKey: 'albumFile') ??
          extractQualityName(item),
    _ => extractQualityName(item),
  };
  final date = switch (serviceType) {
    ServiceType.movies => stringOrNull(
      item['airDateUtc'] ?? item['digitalRelease'] ?? item['inCinemas'],
    ),
    ServiceType.music => stringOrNull(item['releaseDate']),
    _ => stringOrNull(item['airDateUtc']),
  };
  final showDateChip = !(isCutoff && serviceType == ServiceType.movies);

  return [
    ?monitored,
    if (quality != null)
      TagChip(surface: colorScheme.surfaceContainer, text: quality),
    if (showDateChip && date != null)
      TagChip(
        surface: colorScheme.surfaceContainer,
        text: formatShortDate(date),
      ),
  ];
}

/// The desktop table's geometry, shared by the header row and every data row.
///
/// One place, because a header that does not line up with its columns is worse
/// than no header: the two used to be able to drift because only one of them
/// existed.
abstract final class _ActivityTableMetrics {
  /// The figures cell, wide enough for `99.9 GB · 12h 12m left`.
  static const double figures = 210;

  /// The relative-time cell.
  static const double time = 104;

  /// The trailing `⋮` plate's slot. 40, not 48: the plate is the drawn object
  /// and the 48dp target extends past it, which is what `IconButton` already
  /// reserves.
  static const double actions = 40;

  /// The leading glyph, and the gutter after it.
  static const double glyph = 18;
}

/// One activity row as a table row: what it is, what it is doing, and the
/// controls, on one line.
///
/// The columns are the ones the data actually has. The design sheet draws
/// separate `size`, `done`, `speed` and `left` columns; `GlobalActivityItem`
/// has no such fields and \*arr reports no transfer rate on a queue record at
/// all, so the measurements arrive pre-formatted in [GlobalActivityItem.figures]
/// and stay in one tabular cell, in the text face. Still a column that lines
/// up down the page. That cell used to be fed `subtitle`, which is prose: the table was
/// right-aligning a release filename in a numeric column.
class _DesktopActivityRow extends ConsumerStatefulWidget {
  const _DesktopActivityRow({
    required this.item,
    required this.icon,
    required this.accent,
    required this.toneColor,
    required this.onOpen,
    required this.trailing,
    required this.actions,
    required this.compact,
  });

  final GlobalActivityItem item;
  final IconData icon;
  final Color accent;
  final Color toneColor;
  final VoidCallback? onOpen;

  /// The row's own actions. Always shown, never revealed only on hover: the
  /// phone has no hover, so nothing may be reachable that way alone. Hover
  /// here brightens the row and lifts one action out of the menu it is already
  /// in, which is an accelerator rather than a door.
  final Widget? trailing;

  /// Offered again on a right-click. The same list the `⋮` button shows, from
  /// the same place; see [_rowActionMenuItems].
  final List<_RowAction> actions;

  /// A desktop window below 1100.
  ///
  /// The row keeps its identity, its title, its status, its connection and
  /// its controls, and sheds the two cells that only pay for themselves when
  /// there is room: the figures and the relative time. Fewer parts, not
  /// smaller ones, and emphatically not the phone card, which is a different
  /// shape for a different input device. The connection badge is not one of
  /// them: two connections of a service interleave in one group, and a row
  /// that drops its name cannot say which server it is about.
  final bool compact;

  @override
  ConsumerState<_DesktopActivityRow> createState() =>
      _DesktopActivityRowState();
}

class _DesktopActivityRowState extends ConsumerState<_DesktopActivityRow> {
  bool _hovered = false;
  bool _focused = false;

  /// Right-click, at the pointer. Nothing new lives here: every item is also in
  /// the row's own button, which is why a phone can go without.
  Future<void> _showContextMenu(Offset globalPosition) async {
    if (widget.actions.isEmpty) return;
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final action = await showMenu<_RowAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: _rowActionMenuItems(context, widget.actions),
    );
    if (action == null || !mounted) return;
    _runRowAction(context, ref, widget.item, action);
  }

  /// The one action the hovered row lifts out of its own menu.
  ///
  /// The first non-destructive item, which is the rescue verb on every kind
  /// that has one: `Manual import` on a stuck download, `Blocklist and search`
  /// on a failed grab. Destructive actions are never promoted: a Remove that
  /// appears under the pointer on hover is a control the user did not ask to
  /// have within reach.
  _RowAction? get _primaryAction =>
      widget.actions.isEmpty ? null : widget.actions.first;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = widget.item;
    final progress = item.progress;
    final dim = CupolaThemeColors.of(context).dimText;
    // The release name, the episode code, the artist: prose, and the one thing
    // the desktop row lost when the figures cell stopped carrying it. It is the
    // fallback rather than a second line: a row with a fault has one thing to
    // say and the fault is it.
    final secondary =
        item.detail ?? (item.subtitle.isEmpty ? null : item.subtitle);
    final promoted = _hovered ? _primaryAction : null;

    return FocusableActionDetector(
      // The row was a bare `GestureDetector`: no focus node, so it was off the
      // keyboard's path entirely and could not draw the 2px ring the Components
      // sheet declares and calls never-removed. Enabled only when the row opens
      // something: a focus stop that does nothing on Enter is a dead step in
      // the tab order.
      //
      // The semantics stay on the `GestureDetector` below, which contributes
      // its own tap node, and the trailing `⋮` keeps its own: wrapping the row
      // in one label would have taken the menu off the screen reader's path.
      enabled: widget.onOpen != null,
      mouseCursor: widget.onOpen == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onOpen?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onOpen,
        onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: _hovered
                ? colorScheme.onSurface.withValues(alpha: 0.045)
                : null,
            border: _focused
                ? Border.all(color: colorScheme.primary, width: 2)
                : Border(
                    bottom: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: _ActivityTableMetrics.glyph,
                color: ServiceTheme.onTint(
                  widget.accent,
                  surface: colorScheme.surface,
                  tintAlpha: 0,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // 14, not 13: 13 is off the Components type ramp
                      // (32/22/16/14/12/11), and an off-ramp size does not
                      // scale with the rest of the row under Dynamic Type.
                      style: AppTheme.chrome(
                        context,
                        size: 14,
                        weight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      ClipRRect(
                        borderRadius: AppRadius.borderRadiusXs,
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          color: widget.toneColor,
                          backgroundColor: colorScheme.outlineVariant,
                        ),
                      ),
                    ],
                    if (secondary != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        secondary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.chrome(
                          context,
                          size: 11,
                          color: item.detail != null ? widget.toneColor : dim,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (promoted != null) ...[
                const SizedBox(width: AppSpacing.md),
                _PromotedRowAction(item: item, action: promoted),
              ],
              // The badges sit between the title and the fixed cells, not
              // inside them. A `StatusBadge` is as wide as its longest word, so
              // anything to its left was pushed a different distance on every
              // row, which is how a column that exists to line up down the
              // page ended up ragged. Everything right of here is fixed-width,
              // so the figures, the time and the `⋮` are the same three
              // vertical rules on every row and under the header.
              const SizedBox(width: AppSpacing.md),
              StatusBadge(info: item.status),
              if (item.instanceLabel.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                ConnectionBadge(
                  label: item.instanceLabel,
                  accent: widget.accent,
                ),
              ],
              if (!widget.compact) ...[
                const SizedBox(width: AppSpacing.md),
                // The measurements, in one tabular cell, never four sortable
                // columns, which would need four fields the record does not
                // have and a comparator each. Figures, so the text face.
                SizedBox(
                  width: _ActivityTableMetrics.figures,
                  child: Text(
                    item.figures,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppTheme.chrome(
                      context,
                      size: 11,
                      color: dim,
                    ).tabular,
                  ),
                ),
                SizedBox(
                  width: _ActivityTableMetrics.time,
                  child: Text(
                    item.sortDate == null
                        ? ''
                        : formatRelativeDateTime(item.sortDate!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppTheme.chrome(context, size: 11, color: dim),
                  ),
                ),
              ],
              SizedBox(
                width: _ActivityTableMetrics.actions,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: widget.trailing ?? const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row action, lifted out of the `⋮` menu onto the hovered row.
///
/// A 28pt plate inside a 44pt target, the Components sheet's row-action
/// geometry. It duplicates a menu item rather than replacing one: the phone has
/// no hover, so nothing may be reachable this way alone.
class _PromotedRowAction extends ConsumerWidget {
  const _PromotedRowAction({required this.item, required this.action});

  final GlobalActivityItem item;
  final _RowAction action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    void onTap() => _runRowAction(context, ref, item, action);
    return Semantics(
      container: true,
      button: true,
      label: action.label,
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            excludeFromSemantics: true,
            borderRadius: AppRadius.borderRadiusXs,
            child: Center(
              child: ExcludeSemantics(
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.borderRadiusXs,
                      side: BorderSide(color: colorScheme.outline),
                    ),
                  ),
                  child: SizedBox(
                    height: 28,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            action.icon,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            action.label,
                            style: AppTheme.chrome(
                              context,
                              size: 11,
                              weight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
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
