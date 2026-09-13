import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
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
import 'package:cupola/features/activity/presentation/widgets/activity_tab_helpers.dart';
import 'package:cupola/features/activity/presentation/widgets/detail_sheets.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
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
                        FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) _SubtitleText(text: subtitle),
                    const SizedBox(height: AppSpacing.sm),
                    // The badge carries the label, the state icon and the
                    // percentage in tabular figures — the percentage used to be
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
                        text: episodeCode,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.weight(
                        FontWeight.w700,
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

class BlocklistItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final ServiceType serviceType;

  const BlocklistItemTile({
    super.key,
    required this.item,
    required this.serviceType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subtitle = blocklistSubtitle(item, serviceType);
    final chips = _buildBlocklistChips(item, colorScheme);
    final status = resolveBlocklistStatus(item);
    final reason = status.detail;

    return _TileShell(
      onTap: () => DetailSheets.showBlocklistDetail(context, item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleRow(
            title: blocklistTitle(item, serviceType),
            titleStyle: theme.textTheme.titleSmall?.weight(FontWeight.w700),
            trailing: StatusBadge(info: status),
          ),
          if (subtitle != null) _SubtitleText(text: subtitle),
          _ChipRow(chips: chips),
          if (reason != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            formatRelativeActivityDate(stringOrNull(item['date'])),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
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
            titleStyle: theme.textTheme.titleSmall?.weight(FontWeight.w700),
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
          if (statusText != null)
            _SubtitleText(text: statusText, color: colorScheme.error),
          _ChipRow(chips: chips),
        ],
      ),
    );
  }
}

class GlobalActivityItemTile extends ConsumerWidget {
  final GlobalActivityItem item;

  const GlobalActivityItemTile({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = item.service.accent;
    final raw = item.raw;
    // One colour for the whole row's state — badge, warning text and progress
    // bar all read from the resolved tone rather than from the row's category.
    final toneColor = statusToneColor(colorScheme, item.status.tone);
    final canSearch =
        raw != null &&
        (item.kind == GlobalActivityKind.missing ||
            item.kind == GlobalActivityKind.cutoff) &&
        extractWantedItemId(item.serviceType, raw) != null;
    // Resolved here rather than inside [_writeActions] because it is the one
    // decision on this row that needs a `ref`. Short-circuited so only a queue
    // row that would actually offer the hand-off subscribes to the lens — the
    // History list builds thousands of these.
    final canManualImport =
        item.kind == GlobalActivityKind.queue &&
        item.service.supportsManualImport &&
        _manualImportFolder != null &&
        (item.instanceId.isEmpty ||
            item.instanceId ==
                ref.watch(activeInstanceProvider(item.service))?.id);
    final writeActions = _writeActions(canManualImport: canManualImport);
    final icon = switch (item.kind) {
      GlobalActivityKind.request => Icons.person_add_alt_1_rounded,
      GlobalActivityKind.queue => Icons.downloading_rounded,
      GlobalActivityKind.history => Icons.history_rounded,
      GlobalActivityKind.blocklist => Icons.block_rounded,
      GlobalActivityKind.missing => Icons.warning_amber_rounded,
      GlobalActivityKind.cutoff => Icons.trending_up_rounded,
    };

    // Same row, two shapes. A phone gets a card, because a card is what a finger
    // aims at; a window gets a table row, because a pointer is precise and a
    // 1140pt column of 96pt cards wastes the one thing a window has. Everything
    // else — the actions, the tap target, the badges, the tones — is computed
    // above and shared, so the table can never drift into being a second,
    // poorer row with its own bugs.
    final onOpen = switch (item.kind) {
      GlobalActivityKind.request => () => context.push(
        _requestsLocation(item.instanceId),
      ),
      _ =>
        item.raw == null
            ? null
            : () => _showDetails(context, ref, writeActions),
    };
    final trailing = raw != null && canSearch
        ? MediaSearchPopupMenu(
            onAutoSearch: () => _runAutoSearch(context, ref, raw),
            onInteractiveSearch: () =>
                _showInteractiveSearch(context, ref, raw),
            iconSize: 18,
          )
        : (writeActions.isEmpty
              ? null
              : _RowActionsMenu(item: item, actions: writeActions));

    if (AppBreakpoints.isDesktopShell &&
        MediaQuery.sizeOf(context).width >= AppBreakpoints.desktopCompact) {
      return _DesktopActivityRow(
        item: item,
        icon: icon,
        accent: accent,
        toneColor: toneColor,
        onOpen: onOpen,
        trailing: trailing,
        actions: writeActions,
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
        // Request rows used to be styled exactly like every other card and then
        // swallow the tap — `raw` is never set for them, so `onTap` resolved to
        // null while the affordance stayed. They now go where requests are
        // actually managed instead of promising a detail that does not exist.
        //
        // `push`, emphatically not `go`. `/activity/:type` is a root-navigator
        // route *outside* the ShellRoute, so it carries no bottom nav bar of its
        // own — and `go` replaces the stack rather than pushing onto it, so
        // `Navigator.canPop()` was false and the app bar had no back entry to
        // imply a leading button from. The result was a dead end: no nav bar, no
        // back, nothing but the requests list. `push` keeps the return path.
        onTap: switch (item.kind) {
          GlobalActivityKind.request => () => context.push(
            _requestsLocation(item.instanceId),
          ),
          _ =>
            item.raw == null
                ? null
                : () => _showDetails(context, ref, writeActions),
        },
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
              child: Icon(icon, color: accent, size: 20),
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
                    ).textTheme.bodyMedium?.weight(FontWeight.w700),
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
                      // service, and when it is filtered the user chose it — so
                      // the chip was restating known information on every row,
                      // in the same 11pt weight as the status it competed with.
                      // The accent-tinted icon well still carries the identity.
                      StatusBadge(info: item.status),
                      // Which server this row came off. On the row rather than
                      // on the group header, because the header groups by
                      // *service* and two connections interleave inside it —
                      // the one place the search sections do not have to say
                      // it, since one leg there is one server. Empty, and so
                      // absent, whenever the service has a single connection.
                      ConnectionBadge(
                        label: item.instanceLabel,
                        accent: accent,
                      ),
                      // When each event happened. `sortDate` was already being
                      // parsed to order the feed but never shown, which left the
                      // History list unable to answer its own question — several
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
            if (raw != null && canSearch) ...[
              const SizedBox(width: AppSpacing.xs),
              MediaSearchPopupMenu(
                onAutoSearch: () => _runAutoSearch(context, ref, raw),
                onInteractiveSearch: () =>
                    _showInteractiveSearch(context, ref, raw),
                iconSize: 18,
              ),
            ] else if (writeActions.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs),
              _RowActionsMenu(item: item, actions: writeActions),
            ],
          ],
        ),
      ),
    );
  }

  /// The write actions this row supports.
  ///
  /// Empty for history (nothing to change about something that happened) and
  /// whenever the record has no id to act on.
  ///
  /// [canManualImport] gates the manual-import fast path — see the switch.
  List<_RowAction> _writeActions({required bool canManualImport}) {
    // Requests are checked before the `recordId` guard, not after: they are the
    // one kind that carries no \*arr record at all, so that guard would drop them
    // before they were ever considered.
    if (item.kind == GlobalActivityKind.request) {
      final request = item.request;
      // Gate on the request's **own** status, never on `displayStatus`. That
      // getter is overridden by media availability, so a request that is still
      // waiting for approval reports "Available" the moment the media exists
      // anywhere — and would silently lose the only action it needs.
      if (request == null || request.status != RequestStatus.pendingApproval) {
        return const [];
      }
      return const [_RowAction.approveRequest, _RowAction.declineRequest];
    }

    if (item.recordId == null) return const [];
    if (!item.serviceType.supportsArrActivity) return const [];
    return switch (item.kind) {
      GlobalActivityKind.queue => [
        // The rescue fast-path: a stuck download's row can jump straight into
        // manual import with the download's own output folder pre-seeded.
        // Offered only for the connection the lens is on, which is a gap
        // rather than a rule: `manualImportLocation` carries a service and no
        // connection, and every screen in the import flow resolves through the
        // lens. Sending a row from the other Radarr there would browse the
        // wrong server's filesystem and import into it — so the affordance is
        // withheld rather than made to lie. Restoring it needs `?i=` on the
        // import routes, which is that feature's work, not this one's.
        if (canManualImport) _RowAction.manualImport,
        _RowAction.blocklistAndRetry,
        _RowAction.removeFromQueue,
      ],
      GlobalActivityKind.blocklist => const [_RowAction.removeFromBlocklist],
      _ => const [],
    };
  }

  String? get _manualImportFolder => manualImportFolderFromOutputPath(
    dynamic_utils.stringOrNull(item.raw?['outputPath']),
  );

  void _showDetails(
    BuildContext context,
    WidgetRef ref,
    List<_RowAction> writeActions,
  ) {
    final raw = item.raw;
    if (raw == null) return;
    switch (item.kind) {
      case GlobalActivityKind.queue:
        DetailSheets.showQueueDetail(
          context,
          raw,
          actions: writeActions.isEmpty
              ? null
              : _SheetActions(
                  actions: writeActions,
                  // The tile's own context and ref, deliberately: the sheet
                  // closes before the action runs, so anything captured from
                  // *inside* it is disposed by the time the confirmation
                  // dialog returns. See [_SheetActions].
                  onSelected: (action) =>
                      _runRowAction(context, ref, item, action),
                ),
        );
        break;
      case GlobalActivityKind.history:
        DetailSheets.showHistoryDetail(context, raw);
        break;
      case GlobalActivityKind.blocklist:
        DetailSheets.showBlocklistDetail(context, raw);
        break;
      case GlobalActivityKind.missing:
      case GlobalActivityKind.cutoff:
        DetailSheets.showWantedDetail(context, raw, item.serviceType);
        break;
      case GlobalActivityKind.request:
        break;
    }
  }

  void _runAutoSearch(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> raw,
  ) {
    runWantedAutoSearch(
      context,
      ref.read(
        connectionArrServiceProvider((item.serviceType, item.instanceId)),
      ),
      item.serviceType,
      raw,
    );
  }

  void _showInteractiveSearch(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> raw,
  ) {
    showWantedInteractiveSearch(
      context,
      ref,
      item.serviceType,
      raw,
      // The subject alone: the sheet's own heading already says "Releases", and
      // `showWantedInteractiveSearch` caps whatever it is handed.
      title: item.title,
      // A release search runs on the server that listed the row. Stamped here
      // rather than left to `showReleaseSearch`, which falls back to the lens —
      // right for a screen that shows one connection, wrong for a feed that
      // merges several.
      instanceId: item.instanceId,
    );
  }
}

/// A write action available on an Activity row.
enum _RowAction {
  approveRequest(
    'Approve request',
    Icons.check_circle_outline_rounded,
    destructive: false,
  ),
  declineRequest('Decline request', Icons.cancel_outlined, destructive: true),
  manualImport(
    'Manual import',
    Icons.drive_file_move_rounded,
    destructive: false,
  ),
  blocklistAndRetry(
    'Blocklist and search',
    Icons.refresh_rounded,
    destructive: false,
  ),
  removeFromQueue(
    'Remove from queue',
    Icons.delete_outline_rounded,
    destructive: true,
  ),
  removeFromBlocklist(
    'Remove from blocklist',
    Icons.playlist_add_check_rounded,
    destructive: false,
  );

  const _RowAction(this.label, this.icon, {required this.destructive});

  final String label;
  final IconData icon;
  final bool destructive;
}

/// The same actions as buttons, for the detail sheet.
///
/// A row can only afford an overflow glyph; a sheet the user deliberately opened
/// on a stalled download can afford to name the actions outright.
///
/// Deliberately dumb: it closes the sheet and hands the choice back to whoever
/// opened it, rather than running the mutation itself. Running it here was the
/// bug — the button popped the sheet and then called the action with the
/// *sheet's own* context. `showAppConfirmDialog` still opened (its navigator is
/// captured synchronously), but by the time the user confirmed, the sheet route
/// was disposed, so every `if (!context.mounted) return;` guard in
/// [ActivityActions] short-circuited and the request was never sent — no
/// mutation, no snackbar, no error. Remove, blocklist-and-retry, un-blocklist
/// and approve/decline were all silently inert from this surface, while the row
/// overflow menu — which passes the tile's context — kept working and hid it.
class _SheetActions extends StatelessWidget {
  final List<_RowAction> actions;

  /// Invoked after the sheet is closed, with a context that outlives it.
  final ValueChanged<_RowAction> onSelected;

  const _SheetActions({required this.actions, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    void select(_RowAction action) {
      // Close the sheet first: the confirmation dialog is the thing that should
      // hold focus, and leaving the sheet up behind it stacks two modals over
      // the row being removed.
      Navigator.of(context).pop();
      onSelected(action);
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final action in actions)
          action.destructive
              ? OutlinedButton.icon(
                  onPressed: () => select(action),
                  icon: Icon(action.icon, size: 18),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    side: BorderSide(
                      color: colorScheme.error.withValues(alpha: 0.5),
                    ),
                  ),
                  label: Text(action.label),
                )
              : FilledButton.icon(
                  onPressed: () => select(action),
                  icon: Icon(action.icon, size: 18),
                  label: Text(action.label),
                ),
      ],
    );
  }
}

/// The per-row action menu — the thing that turns Activity from a feed into
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
/// Two doors on a desktop window — the visible `⋮` button and a right-click on
/// the row — and exactly one list behind them. That is the binding rule for the
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
            Icon(
              action.icon,
              size: 18,
              color: action.destructive
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            // Flexible, because the longest label does not fit: a Material
            // 3 popup is capped at 280pt and "Remove from blocklist" plus
            // its glyph and gutter wants 326, so the row overflowed by 70
            // and painted the debug stripe over the menu. Wrapping rather
            // than ellipsising — a menu item that reads "Remove from
            // blockli…" is worse than one that takes two lines.
            Flexible(
              child: Text(
                action.label,
                // Recoloured from the ambient row style, not built from
                // scratch: a bare `TextStyle(color:)` only happened to keep
                // the family and size because `Text` merges an inheriting
                // style, which makes the base invisible at the call site.
                style: action.destructive
                    ? DefaultTextStyle.of(
                        context,
                      ).style.copyWith(color: colorScheme.error)
                    : null,
              ),
            ),
          ],
        ),
      ),
  ];
}

/// Dispatches one [_RowAction] against [item].
///
/// Top-level rather than a method on the menu, because the detail sheet needs
/// the same dispatch driven by a context that is *not* the sheet's — see
/// [_SheetActions]. [context] and [ref] must therefore belong to something that
/// outlives any modal the action opens.
///
/// Each case reads the key it actually needs. There used to be one
/// `recordId == null` guard covering the whole method, which quietly made every
/// action \*arr-shaped: a Seerr request is keyed by its own id and has no \*arr
/// record, so it could never have reached the switch.
/// Where a request row goes: the requests list **of its own connection**.
///
/// The `?i=` is the navigation half of the per-connection routing. /activity
/// merges every configured Seerr, so a row can belong to a server the lens is
/// not on — and the destination resolves its list, and every write on it, from
/// the lens unless it is told otherwise. Without this, tapping a row from the
/// second Seerr opened the first Seerr's requests: the defect moved rather than
/// closed.
///
/// This route carried an `?i=` once before and it was removed in review,
/// correctly, because nothing read it. `ActivityScreen` reads it now.
///
/// Omitted when the row names no connection — a single-Seerr stack, or a
/// fixture predating the merge — so the ordinary link stays the ordinary link.
String _requestsLocation(String instanceId) {
  final path = '/activity/${ServiceType.discover.name}';
  if (instanceId.isEmpty) return path;
  return Uri(path: path, queryParameters: {'i': instanceId}).toString();
}

void _runRowAction(
  BuildContext context,
  WidgetRef ref,
  GlobalActivityItem item,
  _RowAction action,
) {
  switch (action) {
    case _RowAction.approveRequest:
      final requestId = item.request?.id;
      if (requestId == null) return;
      ActivityActions.approveRequest(
        context,
        ref,
        // The row's own connection, never the lens: a request id is per Seerr.
        instanceId: item.instanceId,
        requestId: requestId,
        title: item.title,
      );
    case _RowAction.declineRequest:
      final requestId = item.request?.id;
      if (requestId == null) return;
      ActivityActions.declineRequest(
        context,
        ref,
        instanceId: item.instanceId,
        requestId: requestId,
        title: item.title,
      );
    case _RowAction.manualImport:
      final folder = manualImportFolderFromOutputPath(
        dynamic_utils.stringOrNull(item.raw?['outputPath']),
      );
      if (folder == null || !item.service.supportsManualImport) return;
      context.push(
        manualImportLocation(
          manualImportBrowsePath,
          item.service,
          folderPath: folder,
        ),
      );
    case _RowAction.blocklistAndRetry:
      final recordId = item.recordId;
      if (recordId == null) return;
      ActivityActions.blocklistAndRetry(
        context,
        ref,
        serviceType: item.serviceType,
        // The row's own connection, never the lens: see [ActivityActions].
        instanceId: item.instanceId,
        recordId: recordId,
        title: item.title,
      );
    case _RowAction.removeFromQueue:
      final recordId = item.recordId;
      if (recordId == null) return;
      ActivityActions.removeFromQueue(
        context,
        ref,
        serviceType: item.serviceType,
        // The row's own connection, never the lens: see [ActivityActions].
        instanceId: item.instanceId,
        recordId: recordId,
        title: item.title,
      );
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
      // bottom — 16pt between cards — while `GlobalActivityItemTile` used 0/`sm`
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
    if (hasWarning)
      TagChip(
        text: 'Warning',
        color: colorScheme.error,
        icon: Icons.warning_amber_rounded,
      ),
    if (quality != null) TagChip(text: quality),
    if (protocol != null) TagChip(text: protocol, color: AppColors.info),
    if (downloadClient != null)
      TagChip(text: downloadClient, color: colorScheme.tertiary),
  ];
}

List<Widget> _buildHistoryChips(
  Map<String, dynamic> item,
  ColorScheme colorScheme,
) {
  final quality = extractQualityName(item);
  final indexer = stringOrNull(asActivityMap(item['data'])?['indexer']);

  return [
    if (quality != null) TagChip(text: quality),
    if (indexer != null) TagChip(text: indexer, color: colorScheme.tertiary),
  ];
}

List<Widget> _buildBlocklistChips(
  Map<String, dynamic> item,
  ColorScheme colorScheme,
) {
  final protocol = stringOrNull(item['protocol']);
  final indexer = stringOrNull(item['indexer']);

  return [
    if (protocol != null) TagChip(text: protocol, color: AppColors.info),
    if (indexer != null) TagChip(text: indexer, color: colorScheme.tertiary),
  ];
}

List<Widget> _buildWantedChips(
  Map<String, dynamic> item,
  ServiceType serviceType,
  ColorScheme colorScheme, {
  bool isCutoff = false,
  String? qualityProfileName,
}) {
  final monitored = item['monitored'] == false
      ? TagChip(text: 'Unmonitored', color: colorScheme.error)
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
    if (quality != null) TagChip(text: quality),
    if (showDateChip && date != null)
      TagChip(text: formatIsoDate(date), color: AppColors.info),
  ];
}

/// One activity row as a table row: what it is, what it is doing, and the
/// controls, on one line.
///
/// The columns are the ones the data actually has. The design sheet draws
/// separate `size`, `done`, `speed` and `left` columns, and the app does not
/// have those as fields — the service hands them over pre-formatted in one
/// subtitle string, so splitting them into columns would mean parsing English
/// back into numbers and being wrong the first time a service words it
/// differently. The figures therefore stay in one tabular-mono cell, which is
/// still a column that lines up down the page.
class _DesktopActivityRow extends ConsumerStatefulWidget {
  const _DesktopActivityRow({
    required this.item,
    required this.icon,
    required this.accent,
    required this.toneColor,
    required this.onOpen,
    required this.trailing,
    required this.actions,
  });

  final GlobalActivityItem item;
  final IconData icon;
  final Color accent;
  final Color toneColor;
  final VoidCallback? onOpen;

  /// The row's own actions. Always shown, never revealed only on hover: the
  /// phone has no hover, so nothing may be reachable that way alone — hover
  /// here brightens the row, and that is all it does.
  final Widget? trailing;

  /// Offered again on a right-click. The same list the `⋮` button shows, from
  /// the same place — see [_rowActionMenuItems].
  final List<_RowAction> actions;

  @override
  ConsumerState<_DesktopActivityRow> createState() =>
      _DesktopActivityRowState();
}

class _DesktopActivityRowState extends ConsumerState<_DesktopActivityRow> {
  bool _hovered = false;

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = widget.item;
    final progress = item.progress;

    return MouseRegion(
      cursor: widget.onOpen == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
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
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: widget.accent),
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
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          color: widget.toneColor,
                          backgroundColor: colorScheme.outlineVariant,
                        ),
                      ),
                    ],
                    if (item.detail != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: widget.toneColor),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // The figures, in one tabular column so they line up down the page
              // even though the words in them differ per service.
              SizedBox(
                width: 210,
                child: Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.onSurfaceDimDark,
                  ).mono.tabular,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              StatusBadge(info: item.status),
              if (item.instanceLabel.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                ConnectionBadge(
                  label: item.instanceLabel,
                  accent: widget.accent,
                ),
              ],
              SizedBox(
                width: 104,
                child: Text(
                  item.sortDate == null
                      ? ''
                      : formatRelativeDateTime(item.sortDate!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.onSurfaceDimDark,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
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
