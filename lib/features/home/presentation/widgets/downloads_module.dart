/// Downloads: what is moving, how fast, and the one that is stuck with its
/// remedy in reach of the thumb.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/features/activity/domain/download_page.dart'
    show downloadPageKey;
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/data/acted_faults.dart';
import 'package:cupola/features/activity/domain/stuck_download_fault.dart';
import 'package:cupola/features/activity/presentation/widgets/fault_card.dart'
    show FaultNoteLine;
import 'package:cupola/features/activity/presentation/widgets/stuck_action_taker.dart';
import 'package:cupola/features/home/domain/downloads.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/kept_waiting_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// The four download clients: where speeds come from.
const _clients = [
  ServiceKey.qbittorrent,
  ServiceKey.transmission,
  ServiceKey.sabnzbd,
  ServiceKey.nzbget,
];

/// Downloads: the transfers that move and the ones that stopped, four rows,
/// then the way to Activity.
///
/// Absent only when no queue is set up. Nothing moving is a calm line with
/// the last time a download finished, not an absence: the queue was read and
/// is quiet. A client that did not answer makes the speed `—`; the rows keep
/// what the arrs know.
class HomeDownloadsModule extends ConsumerWidget {
  const HomeDownloadsModule({super.key});

  static const _title = 'Downloads';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    if (!HomeModule.downloads.services.any(settings.isServiceConfigured)) {
      return const SizedBox.shrink();
    }

    final inFlight = ref.watch(servicesInFlightProvider);
    // The last answer stands while the next one is read: the poll must not
    // put the skeleton back every thirty seconds.
    final data = inFlight.value;
    if (data == null) {
      if (inFlight.hasError) {
        return HomeModuleFrame.silent(
          title: _title,
          coverage: SourceCoverage.merge([
            for (final service in HomeModule.downloads.services)
              if (settings.isServiceConfigured(service))
                SourceCoverage.failure(service, inFlight.error),
          ]),
          onRetry: () => ref.invalidate(servicesQueueProvider),
        );
      }
      return const HomeModuleFrame.loading(title: _title);
    }
    final coverage = data.coverage;
    if (coverage.everySourceFailed) {
      return HomeModuleFrame.silent(
        title: _title,
        coverage: coverage,
        onRetry: () => retryDashboardServices(ref, coverage.failedServices),
      );
    }

    final stuck = [
      for (final item in data.faults)
        if (isDownloadFault(item.fault)) item,
    ];
    // A download acted on leaves the queue as it is read again; its row stays
    // with its note until the Home is read again, as its card does in Needs
    // you.
    final present = {
      for (final item in [...data.preview, ...stuck]) keptWaitingKey(item),
    };
    final acted = [
      for (final MapEntry(:key, :value)
          in ref.watch(actedFaultsProvider).entries)
        if (!present.contains(key)) value.item,
    ];
    final rows = downloadRowsOf(data.preview, [...stuck, ...acted]);
    final clientSetUp = _clients.any(settings.isServiceConfigured);
    final subtitle = downloadsSubtitle(
      moving: data.movingCount,
      stuck: stuck.length,
      queued: data.queued.length,
      clientSetUp: clientSetUp,
      clientSilent: coverage.failedServices.any(_clients.contains),
      rateBytesPerSecond: data.rateBytesPerSecond,
      coverage: coverage,
    );
    final note = coverageNote(coverage);
    // A finished download the arr will not import is no download any more:
    // Needs you leads with it, and the module says so once.
    final footnote = inFlightFaultFootnote(
      needsImport: data.faults
          .where((item) => item.fault == InFlightFault.needsImport)
          .length,
      coverage: coverage,
    );
    final room = CupolaRoom.of(context);

    return HomeModuleFrame(
      title: _title,
      subtitle: subtitle,
      semanticLabel: joinSpokenParts([
        _title,
        spokenDownloadsSubtitle(subtitle),
        if (note != null) spokenFromDotted(note),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null) HomeCoverageNote(note: note, coverage: coverage),
          // Nothing is downloading only where every queue answered; over a
          // silent one the note above says what is not known.
          if (rows.isEmpty && coverage.isWhole) const _NothingDownloading(),
          if (rows.isNotEmpty)
            for (final (index, item) in rows.indexed)
              DownloadRow(
                // With the connection: two Radarr both number their queues
                // from one.
                key: ValueKey('${item.service}-${item.instanceId}-${item.id}'),
                item: item,
                divided: index > 0,
              ),
          if (rows.isNotEmpty && !clientSetUp) const _SpeedsComeFromAClient(),
          if (footnote != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                footnote,
                semanticsLabel: spokenFaultFootnote(footnote),
                style: AppType.meta.copyWith(color: room.inkSecondary),
              ),
            ),
          HomeModuleLink(
            label: rows.isEmpty ? 'Activity' : 'See all in Activity',
            onTap: () => context.go(ServiceRoutes.activity),
          ),
        ],
      ),
    );
  }
}

/// One download: its art, its title and how far it got, the release under
/// it, the bar; and when it stopped, the remedy in the row. A tap opens the
/// download's own page in Activity.
class DownloadRow extends ConsumerWidget {
  const DownloadRow({super.key, required this.item, this.divided = false});

  final ServiceQueueItem item;

  /// Whether a hairline separates it from the row above.
  final bool divided;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final room = CupolaRoom.of(context);
    final fault = item.fault;
    final stuck = isDownloadFault(fault);
    // The remedy Needs you offers, or the note once one was taken there or
    // here; a stall kept waiting offers none until its day is up.
    final acted = ref.watch(
      actedFaultsProvider.select((acted) => acted[keptWaitingKey(item)]),
    );
    final kept =
        fault == InFlightFault.stalled &&
        isKeptWaiting(
          item,
          ref.watch(keptWaitingProvider),
          ref.watch(stallClockProvider)(),
        );
    final remedy = acted != null || (stuck && !kept);
    final tone = statusToneColor(
      scheme,
      stuck ? StatusTone.warning : StatusTone.info,
      surface: room.slab,
    );
    final percent = item.progress == null
        ? null
        : wholePercent(item.progress! * 100);
    final value = stuck
        ? stuckValue(fault!, percent: percent)
        : movingValue(percent: percent, etaSeconds: item.etaSeconds);
    final spokenValue = stuck
        ? spokenPercents(value)
        : spokenMovingValue(percent: percent, etaSeconds: item.etaSeconds);
    // Which Radarr, once there are two: the glyph says Radarr, and only the
    // words can say which. A client's own row is named by its client.
    final title =
        item.connectionName == null || item.clientService == item.service
        ? item.title
        : '${item.title} · ${serviceWithConnection(item.service, item.connectionName, joiner: ' ')}';
    final release = item.names.machineName;
    final showsRelease =
        release != null && release.isNotEmpty && release != item.title;

    // Its own page, in Activity, with Activity behind it.
    Future<void> open() async => context.go(
      ServiceRoutes.activityDownload(
        instanceId: item.instanceId,
        key: downloadPageKey(item),
      ),
    );

    // At a large reading size the value goes under the title: beside it the
    // title kept three letters.
    final stacked = MediaQuery.textScalerOf(context).scale(10) >= 13;
    Widget titleText({required int maxLines}) => Text(
      title,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: AppType.row.weight(FontWeight.w600).copyWith(color: room.ink),
    );
    final valueText = Text(
      value,
      style: AppType.meta.weight(FontWeight.w600).tabular.copyWith(color: tone),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: room.hair)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              button: true,
              label: title,
              value: spokenValue,
              onTap: open,
              child: InkWell(
                onTap: open,
                excludeFromSemantics: true,
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      HomeRowArt(
                        posterUrl: item.posterUrl,
                        icon: item.service.icon,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (stacked) ...[
                              titleText(maxLines: 2),
                              if (value.isNotEmpty) valueText,
                            ] else
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Expanded(child: titleText(maxLines: 1)),
                                  if (value.isNotEmpty) ...[
                                    const SizedBox(width: AppSpacing.sm),
                                    valueText,
                                  ],
                                ],
                              ),
                            if (showsRelease)
                              Text(
                                release,
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: AppType.mono.copyWith(
                                  color: room.inkSecondary,
                                ),
                              ),
                            if (item.progress case final progress?) ...[
                              const SizedBox(height: 7),
                              HomeRowBar(value: progress, color: tone),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (remedy)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.sm,
                  left: HomeRowArt.width + AppSpacing.sm,
                ),
                child: _StuckRemedy(item: item),
              ),
          ],
        ),
      ),
    );
  }
}

/// What a stuck download offers, as Needs you offers it ([stuckActionsFor]):
/// the one amber fill, the quieter ways out behind ⋯, and once one was taken
/// the note its card says, with Undo for Keep waiting.
class _StuckRemedy extends ConsumerStatefulWidget {
  const _StuckRemedy({required this.item});

  final ServiceQueueItem item;

  @override
  ConsumerState<_StuckRemedy> createState() => _StuckRemedyState();
}

class _StuckRemedyState extends ConsumerState<_StuckRemedy>
    with StuckActionTaker {
  @override
  String get stuckDownloadKey => keptWaitingKey(widget.item);

  @override
  Widget build(BuildContext context) {
    final acted = ref.watch(
      actedFaultsProvider.select((acted) => acted[stuckDownloadKey]),
    );
    final item = acted?.item ?? widget.item;
    if (acted != null) {
      return FaultNoteLine(
        note: (
          text: acted.note,
          onUndo: acted.action == StuckAction.keepWaiting
              ? () => undoKeepWaiting(item)
              : null,
        ),
      );
    }
    final actions = stuckActionsFor(item);
    final label = stuckActionLabel(actions.primary, item);
    final busy = takingAction != null;
    final room = CupolaRoom.of(context);
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: busy
                ? null
                : () => takeStuckAction(actions.primary, item),
            style: remedyFillStyle(context),
            child: takingAction == actions.primary
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(label, semanticsLabel: '$label, ${item.sentenceTitle}'),
          ),
        ),
        if (actions.secondary.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sm),
          PopupMenuButton<StuckAction>(
            enabled: !busy,
            tooltip: 'More for ${item.sentenceTitle}',
            onSelected: (action) => takeStuckAction(action, item),
            itemBuilder: (context) => [
              for (final action in actions.secondary)
                PopupMenuItem(
                  value: action,
                  child: Text(stuckActionLabel(action, item)),
                ),
            ],
            child: SizedBox.square(
              dimension: 44,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: room.fillControl,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: room.edge),
                ),
                child: Icon(Icons.more_horiz_rounded, color: room.ink),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Nothing moving: a calm line, and when the last download finished.
class _NothingDownloading extends ConsumerWidget {
  const _NothingDownloading();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    DateTime? last;
    for (final entry
        in ref.watch(servicesArrHistoryProvider).value?.entries ??
            const <ArrHistoryEntry>[]) {
      if (entry.outcome != ArrImportOutcome.imported) continue;
      final at = entry.at;
      if (at != null && (last == null || at.isAfter(last))) last = at;
    }
    final line = lastFinishedLine(last, now: DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nothing is downloading',
            style: AppType.row.copyWith(color: room.ink),
          ),
          if (line != null)
            Text(line, style: AppType.meta.copyWith(color: room.inkSecondary)),
        ],
      ),
    );
  }
}

/// Under the rows when no download client is set up: the arrs know how far
/// a download got, not how fast.
class _SpeedsComeFromAClient extends StatelessWidget {
  const _SpeedsComeFromAClient();

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: room.inkSecondary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Speeds come from your download client',
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
