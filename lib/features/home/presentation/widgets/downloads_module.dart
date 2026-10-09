/// Downloads: what is moving, how fast, and the one that is stuck with its
/// remedy in reach of the thumb.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_actions.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/home/domain/downloads.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
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
    final rows = downloadRowsOf(data.preview, stuck);
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
/// it, the bar; and when it stopped, the remedy in the row.
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

    Future<void> open() async => context.go(ServiceRoutes.activity);

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
            if (stuck)
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

/// What a stuck download offers: another download of the same title, and
/// More with its client and Remove; or its client alone, for a transfer no
/// arr asked for, where there is nothing to search again.
class _StuckRemedy extends ConsumerWidget {
  const _StuckRemedy({required this.item});

  final ServiceQueueItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = _serviceTypeOf(item.service);
    final recordId = int.tryParse(item.id);
    final client = item.clientService;
    // The client as the row names it, with its connection when there are
    // two.
    final clientTitle = client == null ? null : item.clientLabel;
    // The client moving the bytes, or the service the row came from when
    // nothing joined it to one.
    final target = client ?? item.service;
    final targetInstance = client == null
        ? item.instanceId
        : item.clientInstanceId;

    Future<void> openTarget() async {
      await bringUnderLens(ref, target, targetInstance);
      if (!context.mounted) return;
      context.go(ServiceRoutes.forService(target));
    }

    if (type == null || recordId == null || recordId <= 0) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton(
          onPressed: openTarget,
          style: remedyFillStyle(context),
          child: Text(
            'Open in ${clientTitle ?? target.title}',
            semanticsLabel:
                'Open ${item.title} in ${clientTitle ?? target.title}',
          ),
        ),
      );
    }

    Future<void> another() async {
      await ActivityActions.blocklistAndRetry(
        context,
        ref,
        serviceType: type,
        instanceId: item.instanceId,
        recordId: recordId,
        title: item.title,
      );
      _refresh(ref);
    }

    Future<void> remove() async {
      await ActivityActions.removeFromQueue(
        context,
        ref,
        serviceType: type,
        instanceId: item.instanceId,
        recordId: recordId,
        title: item.title,
      );
      _refresh(ref);
    }

    final room = CupolaRoom.of(context);
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: another,
            style: remedyFillStyle(context),
            child: Text(
              'Try another download',
              semanticsLabel: 'Try another download of ${item.title}',
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        PopupMenuButton<_More>(
          tooltip: 'More for ${item.title}',
          onSelected: (choice) => switch (choice) {
            _More.client => openTarget(),
            _More.remove => remove(),
          },
          itemBuilder: (context) => [
            if (clientTitle != null)
              PopupMenuItem(
                value: _More.client,
                child: Text('Open in $clientTitle'),
              ),
            const PopupMenuItem(value: _More.remove, child: Text('Remove')),
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
    );
  }

  /// The queue again, now that it changed: the row goes or says what it is.
  static void _refresh(WidgetRef ref) {
    for (final source in homeDownloadsSources) {
      ref.invalidate(source);
    }
  }
}

enum _More { client, remove }

/// The queue writes speak in Activity's types: the three arrs it knows.
ServiceType? _serviceTypeOf(ServiceKey service) => switch (service) {
  ServiceKey.radarr => ServiceType.movies,
  ServiceKey.sonarr => ServiceType.series,
  ServiceKey.lidarr => ServiceType.music,
  _ => null,
};

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
