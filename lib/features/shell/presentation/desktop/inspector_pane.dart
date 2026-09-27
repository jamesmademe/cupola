import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/inspector_state.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';

/// The inspector: what is happening, without leaving what you are doing.
///
/// The pane exists because a desktop window is wide enough to hold two thoughts
/// at once, and the second thought is almost always the same one — "is my
/// transfer moving". On the phone that is a whole tab you have to travel to and
/// come back from; here it is a column.
///
/// Everything in it also exists in `/activity`. That is the rule for the whole
/// desktop layer: the inspector is an accelerator, so nothing may live only
/// here, or a phone user would be missing a feature rather than a shortcut.
class InspectorPane extends ConsumerWidget {
  const InspectorPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final queue = ref.watch(globalNowItemsProvider);
    // The same fold the Dashboard header counts: this card names a service
    // only when every connection of it is dark.
    final offline = ref.watch(unreachableServicesProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.72),
        border: Border(
          left: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _InspectorHeader(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ...switch (queue) {
                  AsyncData(:final value) when value.items.isEmpty => const [
                    _InspectorNote('Nothing downloading right now.'),
                  ],
                  AsyncData(:final value) => [
                    for (final item in value.items.take(8))
                      _QueueRow(item: item),
                  ],
                  AsyncError() => const [
                    _InspectorNote(
                      'The queue could not be read. Open Activity to retry.',
                    ),
                  ],
                  _ => const [_InspectorNote('Reading the queue…')],
                },
                if (offline.isNotEmpty) _UnreachableCard(services: offline),
                const _FinishedToday(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The ground every tone and accent in this pane is measured against.
///
/// Not `colorScheme.surface`: the pane paints its own fill, so a tone walked
/// against the default would be walked against a surface it never lands on. The
/// alpha is dropped because a translucent fill composited over the shell's
/// surface sits within a hair of the opaque container, and the walk needs an
/// opaque colour to measure.
Color _paneSurface(ColorScheme colorScheme) =>
    colorScheme.surfaceContainerLowest;

/// 44pt, matching the window strip above it, so the two read as one bar.
class _InspectorHeader extends ConsumerWidget {
  const _InspectorHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Row(
        children: [
          // The tab's own accent, walked against the pane's ground rather than
          // painted raw. `AppColors.navActivity` is a palette constant tuned for
          // the dark canvas — it measures 2.20:1 on paper — so a literal here
          // rendered the dark palette on the Light theme and the one glyph that
          // names the pane went nearly invisible in daylight.
          Icon(
            Icons.insights_rounded,
            size: 16,
            color: ServiceTheme.onTint(
              NavTab.activity.accentColor,
              surface: _paneSurface(colorScheme),
              tintAlpha: 0,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Activity',
              style: AppTheme.chrome(
                context,
                size: 13,
                weight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          IconButton(
            onPressed: () => GoRouter.of(context).go(NavTab.activity.routePath),
            icon: const Icon(Icons.open_in_full_rounded, size: 15),
            iconSize: 15,
            visualDensity: VisualDensity.compact,
            tooltip: 'Open the full Activity screen',
          ),
          IconButton(
            onPressed: () =>
                ref.read(inspectorStateProvider.notifier).setOpen(false),
            icon: const Icon(Icons.close_rounded, size: 16),
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            tooltip: 'Close inspector  ${ShellShortcuts.inspector}',
          ),
        ],
      ),
    );
  }
}

/// One transfer: name, a 3pt bar, and the figures in tabular mono.
///
/// The bar is 3pt because it is a *readout*, not a control — nothing here can be
/// dragged — and the row is the same 48pt-ish height as a list row elsewhere so
/// the pane does not become its own typographic world.
class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.item});

  final GlobalActivityItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = item.progress;
    final warning = item.status.hasWarning;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md + 2,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.surfaceContainerLow.withValues(alpha: 0.9),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Seven of the seventeen service accents are under 3:1 on paper, so
          // the glyph that says *which* service a row belongs to is walked
          // against the pane's ground rather than painted at its palette value.
          Icon(
            item.service.icon,
            size: 17,
            color: ServiceTheme.onTint(
              item.service.accent,
              surface: _paneSurface(colorScheme),
              tintAlpha: 0,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.chrome(
                    context,
                    size: 12,
                    weight: FontWeight.w500,
                    color: colorScheme.onSurface,
                    height: 1.22,
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0, 1),
                      minHeight: 3,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      // `AppColors.warning` raw was a dark-palette literal at
                      // 1.39:1 on paper — a bar that says "this one is in
                      // trouble" and cannot be seen saying it. The row already
                      // carries a resolved tone; the bar spends that instead of
                      // re-deciding, through the same walk every other status
                      // colour in the app goes through.
                      valueColor: AlwaysStoppedAnimation(
                        warning
                            ? statusToneColor(
                                colorScheme,
                                item.status.tone,
                                surface: _paneSurface(colorScheme),
                              )
                            : colorScheme.primary,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 5),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.chrome(
                    context,
                    size: 11,
                    color: CupolaThemeColors.of(context).dimText,
                  ).mono.tabular,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The incomplete-list warning, in the pane that would otherwise imply a whole
/// queue. A queue that silently omits a service is worse than no queue.
class _UnreachableCard extends ConsumerWidget {
  const _UnreachableCard({required this.services});

  final List<ServiceKey> services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel('Unreachable'),
          const SizedBox(height: AppSpacing.sm + 2),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 11,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              color: colorScheme.error.withValues(alpha: 0.07),
              border: Border.all(
                color: colorScheme.error.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Red here is *correct* under the tone rule — these are
                    // connections that did not answer, which is the one thing
                    // red means — but as ink on its own 7% tint it still has to
                    // clear the composite, which raw `colorScheme.error` does
                    // not on paper (3.42:1).
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 15,
                      color: statusToneColor(
                        colorScheme,
                        StatusTone.error,
                        surface: _paneSurface(colorScheme),
                        tintAlpha: 0.07,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        services.map((s) => s.title).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.chrome(
                          context,
                          size: 12,
                          weight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  'No response. Anything they hold is missing from this list.',
                  style: AppTheme.chrome(
                    context,
                    size: 11,
                    weight: FontWeight.w500,
                    color: CupolaThemeColors.of(context).dimText,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        for (final service in services) {
                          // Per connection: `serviceSummaryProvider` delegates
                          // to these, so invalidating the delegate alone
                          // re-awaited the cached verdict and probed nothing.
                          for (final id in ref.read(
                            serviceInstanceIdsProvider(service),
                          )) {
                            ref.invalidate(
                              instanceSummaryProvider((
                                service: service,
                                instanceId: id,
                              )),
                            );
                          }
                          ref.invalidate(serviceSummaryProvider(service));
                        }
                        ref.invalidate(globalNowItemsProvider);
                      },
                      child: const Text('Retry'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    TextButton(
                      onPressed: () => GoRouter.of(
                        context,
                      ).go('${NavTab.settings.routePath}/connections'),
                      child: const Text('Settings'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What landed today, from the history feed the Activity screen already pages.
///
/// Reading it here does start that feed's first page, which is why the pane is
/// closed by default and this section renders nothing until the feed has
/// something: an inspector nobody opened must not cost a round of history
/// requests per service.
class _FinishedToday extends ConsumerWidget {
  const _FinishedToday();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(globalHistoryFeedProvider);
    final feed = state.feed;
    if (feed == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final today = feed.items
        .where((item) {
          final date = item.sortDate;
          return date != null &&
              date.year == now.year &&
              date.month == now.month &&
              date.day == now.day;
        })
        .take(6)
        .toList(growable: false);
    if (today.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md + 2,
        0,
        AppSpacing.md + 2,
        AppSpacing.md + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel('Finished today'),
          for (final item in today)
            SizedBox(
              height: 30,
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Two defects in one expression, both now gone.
                      //
                      // It painted **red** for a failed import. Under the tone
                      // rule red means one thing and only one: a connection that
                      // did not answer. An import the service reported as failed
                      // is the opposite — the server answered, and told us what
                      // went wrong — so it is a fault, and faults are amber.
                      // `historyEventTone` has said exactly that since the
                      // Activity pass; this row was re-deciding from a boolean
                      // instead of spending the answer, and getting it wrong.
                      //
                      // And the calm half was `AppColors.success` raw, a dark
                      // palette constant at 2.07:1 on paper — a green dot that
                      // is legible at night and a pale smudge in daylight.
                      color: statusToneColor(
                        colorScheme,
                        item.status.tone,
                        surface: _paneSurface(colorScheme),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.chrome(
                        context,
                        size: 11,
                        weight: FontWeight.w500,
                        color: CupolaThemeColors.of(context).dimText,
                        height: 1.22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Text(
      text.toUpperCase(),
      style: AppTheme.chrome(
        context,
        size: 11,
        weight: FontWeight.w600,
        color: CupolaThemeColors.of(context).dimText,
        height: 1.2,
        letterSpacing: 1.4,
      ),
    ),
  );
}

class _InspectorNote extends StatelessWidget {
  const _InspectorNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Text(
      text,
      style: AppTheme.chrome(
        context,
        size: 12,
        color: CupolaThemeColors.of(context).dimText,
        height: 1.4,
      ),
    ),
  );
}

/// The split handle: a 3pt line in a 9pt hit area.
///
/// Nine because a 3pt target is a miss with a mouse and impossible with a
/// trackpad, and the visual has to stay 3 or the window grows a seam. Double
/// click restores the drawn width — the one gesture that makes an experiment
/// with the width free.
class InspectorSplitHandle extends ConsumerWidget {
  const InspectorSplitHandle({super.key});

  static const double width = 9;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final notifier = ref.read(inspectorStateProvider.notifier);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) =>
            notifier.resizeBy(details.delta.dx),
        onDoubleTap: notifier.resetWidth,
        child: SizedBox(
          width: width,
          child: Center(
            child: Container(width: 3, color: colorScheme.surfaceContainerLow),
          ),
        ),
      ),
    );
  }
}
