import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/activity/data/selected_download.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/download_page.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/inspector_state.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';

/// The inspector: what is happening, without leaving what you are doing.
///
/// The pane exists because a desktop window is wide enough to hold two thoughts
/// at once, and the second thought is almost always the same one: "is my
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
    // A download chosen in Activity's table: the pane is its page.
    final selected = ref.watch(selectedDownloadProvider);

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
          _InspectorHeader(selected: selected),
          if (selected != null)
            Expanded(
              child: DownloadPage.inspector(
                key: ValueKey(selected),
                instanceId: selected.instanceId,
                downloadKey: selected.key,
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ...switch (queue) {
                    // The feed carries each connection's failure rather than
                    // throwing, so "could not be read" is decided here, from the
                    // connections, and not only by an `AsyncError` that a load
                    // with per-connection errors never produces. Without this,
                    // three \*arrs that all failed read "Nothing downloading".
                    AsyncData(:final value) => [
                      if (value.noArrAnswered)
                        const _InspectorNote(_queueUnreadNote)
                      else if (value.items.isEmpty)
                        _InspectorNote(_emptyQueueNote(value)),
                      for (final item in value.items.take(8))
                        _QueueRow(item: item),
                    ],
                    AsyncError() => const [_InspectorNote(_queueUnreadNote)],
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

const _queueUnreadNote = 'The queue could not be read. Open Activity to retry.';

/// The empty queue's note, and the connections it could not hear from.
///
/// "Nothing downloading" is a claim about every \*arr, so with one of them
/// silent or refusing it is only true of the others, and the note names the
/// ones it leaves out, the way Activity's own readout does.
String _emptyQueueNote(ActivityFeed feed) {
  final notCounted = feed.arrConnections
      .where((r) => r.failed)
      .toList(growable: false);
  if (notCounted.isEmpty) return 'Nothing downloading right now.';
  return 'Nothing downloading right now. ${notCountedClause(notCounted)}.';
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
///
/// Its buttons keep the theme's standard density, 40pt in the 44pt bar:
/// `VisualDensity.compact` took them to 32, under the pointer floor every
/// other desktop control keeps.
///
/// Over a chosen download it reads `Selected download`: its first button
/// opens the download's page, its second goes back to the queue.
class _InspectorHeader extends ConsumerWidget {
  const _InspectorHeader({this.selected});

  final DownloadSelection? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.slabY),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Row(
        children: [
          // The secondary ink, like every mark in the chrome: the pane is
          // named by its title beside the glyph, and a section colour here once
          // measured 2.20:1 on paper.
          Icon(
            selected == null ? Icons.insights_rounded : Icons.download_rounded,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                selected == null ? 'Activity' : 'Selected download',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.chrome(
                  context,
                  size: 13,
                  weight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
          if (selected case final download?) ...[
            IconButton(
              onPressed: () => GoRouter.of(context).go(
                ServiceRoutes.activityDownload(
                  instanceId: download.instanceId,
                  key: download.key,
                ),
              ),
              icon: const Icon(Icons.open_in_full_rounded, size: 15),
              iconSize: 15,
              tooltip: "Open the download's page",
            ),
            IconButton(
              onPressed: () =>
                  ref.read(selectedDownloadProvider.notifier).clear(),
              icon: const Icon(Icons.close_rounded, size: 16),
              iconSize: 16,
              tooltip: 'Back to the queue',
            ),
          ] else ...[
            IconButton(
              onPressed: () =>
                  GoRouter.of(context).go(NavTab.activity.routePath),
              icon: const Icon(Icons.open_in_full_rounded, size: 15),
              iconSize: 15,
              tooltip: 'Open the full Activity screen',
            ),
            IconButton(
              onPressed: () =>
                  ref.read(inspectorStateProvider.notifier).setOpen(false),
              icon: const Icon(Icons.close_rounded, size: 16),
              iconSize: 16,
              tooltip: 'Close inspector  ${ShellShortcuts.inspector}',
            ),
          ],
        ],
      ),
    );
  }
}

/// One transfer: name, a 3pt bar, and the line under it in the text face.
///
/// The bar is 3pt because it is a *readout*, not a control: nothing here can be
/// dragged, and the row is the same 48pt-ish height as a list row elsewhere so
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
        horizontal: AppSpacing.slabY,
        vertical: AppSpacing.row,
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
          // The service's mark, monochrome: which service a row belongs to is
          // said by the mark's shape and the name under it, never by a hue.
          Icon(
            item.service.icon,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.row),
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
                  const SizedBox(height: AppSpacing.xs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0, 1),
                      minHeight: 3,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      // `AppColors.warning` raw was a dark-palette literal at
                      // 1.39:1 on paper: a bar that says "this one is in
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
                const SizedBox(height: AppSpacing.xs),
                // The episode, its title and the release it came as: a line of
                // prose with a name in it, the same line the Activity table
                // sets in the text face. Not a figure, and not a machine string
                // on its own.
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.chrome(
                    context,
                    size: 11,
                    color: CupolaThemeColors.of(context).dimText,
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

/// The incomplete-list warning, in the pane that would otherwise imply a whole
/// queue. A queue that silently omits a service is worse than no queue.
///
/// A quiet line (glyph, sentence, remedy), not a card: the Presence
/// Rule keeps the red on the glyph and the title. It used to be a card in the
/// error tone at 7% under a 30% border, with an amber-shaped warning glyph,
/// and "No response." for words.
class _UnreachableCard extends ConsumerWidget {
  const _UnreachableCard({required this.services});

  final List<ServiceKey> services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // Walked against the pane it is drawn on: there is no wash behind it any
    // more, and the glyph and the title carry the whole tone.
    final red = statusToneColor(
      colorScheme,
      StatusTone.error,
      surface: _paneSurface(colorScheme),
    );
    final title = services.length == 1
        ? failureHeadline(
            ServiceFailureReason.unreachable,
            subject: services.single.title,
          )
        : '${Lexicon.names(services.map((s) => s.title))} did not answer';
    final body = services.length == 1
        ? 'Anything it holds is missing from this list.'
        : 'Anything they hold is missing from this list.';

    return Padding(
      key: const ValueKey('inspector-did-not-answer'),
      padding: const EdgeInsets.all(AppSpacing.slabY),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: '$title. $body',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  failureIcon(ServiceFailureReason.unreachable),
                  size: 15,
                  color: red,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      title,
                      style: AppTheme.chrome(
                        context,
                        size: 12,
                        weight: FontWeight.w600,
                        color: red,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ExcludeSemantics(
                    child: Text(
                      body,
                      style: AppTheme.chrome(
                        context,
                        size: 11,
                        weight: FontWeight.w500,
                        color: CupolaThemeColors.of(context).dimText,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      // Both verbs in ink, never red: a red cure looks like
                      // the disease.
                      TextButton(
                        onPressed: () {
                          for (final service in services) {
                            // Per connection: `serviceSummaryProvider`
                            // delegates to these, so invalidating the delegate
                            // alone re-awaited the cached verdict and probed
                            // nothing.
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
      ),
    );
  }
}

/// What landed today, from the history feed the Activity screen already pages.
///
/// Reading it does start that feed's first page, which is why the pane is
/// closed by default and this section renders nothing until the feed has
/// something: an inspector nobody opened must not cost a round of history
/// requests per service.
///
/// The day is `finishedTodayProvider`'s, the one the Activity band reads. This
/// section kept a copy of its own that compared each record's UTC date with
/// the local day, so after midnight the two disagreed about what "today" held.
class _FinishedToday extends ConsumerWidget {
  const _FinishedToday();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(finishedTodayProvider).rows;
    if (today.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.slabY,
        0,
        AppSpacing.slabY,
        AppSpacing.slabY,
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
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Two defects in one expression, both now gone.
                      //
                      // It painted **red** for a failed import. Under the tone
                      // rule red means one thing and only one: a connection that
                      // did not answer. An import the service reported as failed
                      // is the opposite: the server answered, and told us what
                      // went wrong, so it is a fault, and faults are amber.
                      // `historyEventTone` has said exactly that since the
                      // Activity pass; this row was re-deciding from a boolean
                      // instead of spending the answer, and getting it wrong.
                      //
                      // And the calm half was `AppColors.success` raw, a dark
                      // palette constant at 2.07:1 on paper: a green dot that
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
    // A section label in the micro role, sentence case for the eye and the
    // ear alike.
    child: Text(
      text,
      semanticsLabel: text,
      style: AppTheme.chrome(
        context,
        color: CupolaThemeColors.of(context).dimText,
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
/// click restores the drawn width: the one gesture that makes an experiment
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
