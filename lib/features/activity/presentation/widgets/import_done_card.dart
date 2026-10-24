import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/sample_age.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/presentation/widgets/fault_card.dart';
import 'package:cupola/features/import/domain/blocked_import.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/presentation/manual_import_provider.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// How long a finished import keeps its card in Needs you.
const importReportLingers = Duration(minutes: 10);

/// An import the Review of blocked imports sent, while Needs you reports it:
/// running, failed, or finished less than [importReportLingers] ago.
typedef ImportReport = ({
  ServiceKey service,
  String instanceId,
  ManualImportCommandStatus command,
  DateTime? endedAt,
  List<ManualImportItem> files,
  Map<String, String> replacing,
});

/// The report Needs you draws first, or null. It lives in the import flow,
/// so a new import, or any other run of the wizard, takes its place.
final importReportProvider = Provider<ImportReport?>((ref) {
  final flow = ref.watch(manualImportFlowProvider);
  final service = flow.service;
  final command = flow.command;
  final review = flow.blocked;
  if (service == null ||
      command == null ||
      review == null ||
      flow.submittedItems.isEmpty) {
    return null;
  }
  final ended = flow.commandEndedAt;
  if (command.isCompleted && ended != null) {
    final now = ref.read(stallClockProvider)();
    if (now.difference(ended) > importReportLingers) return null;
  }
  return (
    service: service,
    instanceId: flow.instanceId,
    command: command,
    endedAt: ended,
    files: flow.submittedItems,
    replacing: review.replacing,
  );
});

/// The import a Review sent, where the Review was opened, in Needs you.
///
/// While the arr moves the files, a blue line, read again every two seconds
/// while the card is on screen.
/// Once done, green: `12 episodes imported`, what they are now (`Cosmos
/// Laundromat S1 E1–E10 and S2 E1–E2 are now 1080p.`), the episodes on a grid,
/// the step in quality, and `Open in library`; Activity is read again, so the
/// downloads that went in leave the faults. A failed import is a fault, with
/// the arr's words under `Why?` and `Retry`.
class ImportDoneCard extends ConsumerStatefulWidget {
  const ImportDoneCard({
    super.key,
    required this.report,
    this.divided = false,
    this.whole = false,
  });

  final ImportReport report;
  final bool divided;

  /// The Needs you page's card: a slab of its own.
  final bool whole;

  @override
  ConsumerState<ImportDoneCard> createState() => _ImportDoneCardState();
}

class _ImportDoneCardState extends ConsumerState<ImportDoneCard> {
  @override
  void didUpdateWidget(ImportDoneCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = oldWidget.report.command;
    final now = widget.report.command;
    if (was.isActive && !now.isActive && now.isCompleted) {
      // The downloads that went in leave the queue: read it again. Not here,
      // though: `didUpdateWidget` runs while the tree builds, and invalidating
      // a provider then asks the provider scope to rebuild in the middle of
      // that build. Riverpod 3.3.1 let it pass; later versions assert.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) invalidateActivity(ref, ActivityTab.all);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final command = report.command;
    if (command.isFailure) {
      final words = command.exception ?? command.message;
      final retry = FilledButton(
        style: remedyFillStyle(context),
        onPressed: () =>
            ref.read(manualImportFlowProvider.notifier).retryImport(),
        child: const Text('Retry'),
      );
      const headline = "The import didn't finish";
      final explanation =
          '${report.service.title} stopped before the files went in. They '
          'are where they were.';
      return widget.whole
          ? FaultCard.whole(
              headline: headline,
              explanation: explanation,
              source: report.service.title,
              why: words,
              primary: retry,
            )
          : FaultCard(
              headline: headline,
              explanation: explanation,
              source: report.service.title,
              why: words,
              primary: retry,
              divided: widget.divided,
            );
    }
    return VisibilityPoller(
      id: 'import.report',
      interval: const Duration(seconds: 2),
      enabled: command.isActive,
      onTick: () => ref.read(manualImportFlowProvider.notifier).pollCommand(),
      child: _Report(
        report: report,
        divided: widget.divided,
        whole: widget.whole,
      ),
    );
  }
}

class _Report extends ConsumerWidget {
  const _Report({
    required this.report,
    required this.divided,
    required this.whole,
  });

  final ImportReport report;
  final bool divided;
  final bool whole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final service = report.service;
    final files = report.files;
    final done = report.command.isCompleted;
    final tone = done ? StatusTone.success : StatusTone.info;
    final color = statusToneColor(scheme, tone, surface: room.slab);
    final ended = report.endedAt;
    final now = ref.read(stallClockProvider)();
    final when = done
        ? 'Imported ${ended == null ? 'just now' : formatSampleAge(ended, now: now)}'
        : '${service.title} is moving the files';
    final headline = importHeadline(service, files, done: done);
    final sentence = done
        ? importedSentence(service, files, report.replacing)
        : null;
    final step = done ? importedStep(files, report.replacing) : null;
    final grid = done && service == ServiceKey.sonarr
        ? episodesBySeason(files)
        : const <int, List<int>>{};
    final episodes = grid.values.fold<int>(0, (sum, each) => sum + each.length);
    final open = done ? _opener(context) : null;

    final facts = Semantics(
      container: true,
      liveRegion: true,
      label: [headline, when, ?sentence].join('. '),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: whole ? 40 : 32,
                height: whole ? 40 : 32,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                child: done
                    ? Icon(
                        Icons.check_rounded,
                        size: whole ? 24 : 20,
                        color: room.ground,
                      )
                    : Padding(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: room.ground,
                        ),
                      ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsetsDirectional.only(end: 6),
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              Expanded(
                child: Text(
                  when,
                  style: AppType.label.copyWith(
                    color: done ? room.inkSecondary : color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            headline,
            style: (whole ? AppType.section : AppType.row).copyWith(
              color: room.ink,
            ),
          ),
          if (sentence != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              sentence,
              style: AppType.body.copyWith(color: room.inkSecondary),
            ),
          ],
        ],
      ),
    );

    final content = Padding(
      padding: EdgeInsets.symmetric(
        vertical: whole ? AppSpacing.lg : AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          facts,
          if (episodes > 0 && episodes <= 40) ...[
            const SizedBox(height: AppSpacing.md),
            ExcludeSemantics(
              child: _EpisodeGrid(seasons: grid, color: color),
            ),
          ],
          if (step != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              label: 'From ${step.from} to ${step.to}',
              excludeSemantics: true,
              child: Row(
                children: [
                  Text(
                    step.from,
                    style: AppType.meta.copyWith(
                      color: room.inkTertiary,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: room.inkTertiary,
                    ),
                  ),
                  Text(
                    step.to,
                    style: AppType.meta
                        .weight(FontWeight.w600)
                        .copyWith(color: room.ink),
                  ),
                ],
              ),
            ),
          ],
          if (open != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: open,
              child: const Row(
                children: [
                  Expanded(child: Text('Open in library')),
                  Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: room.hair)) : null,
      ),
      child: content,
    );
  }

  /// The title's page, when every file went into one.
  VoidCallback? _opener(BuildContext context) {
    final service = report.service;
    final payloads = {
      for (final file in report.files)
        switch (service) {
          ServiceKey.radarr => file.movie,
          ServiceKey.lidarr => file.artist,
          _ => file.series,
        },
    };
    final ids = {for (final each in payloads) intOrNull(each?['id'])};
    if (ids.length != 1 || ids.single == null) return null;
    final payload = payloads.first!;
    final focus = report.instanceId.isEmpty ? null : report.instanceId;
    switch (service) {
      case ServiceKey.lidarr:
        return () => context.push(
          ServiceRoutes.lidarrArtist(ids.single!, instanceId: focus),
        );
      case ServiceKey.radarr:
        final tmdb = intOrNull(payload['tmdbId']) ?? 0;
        if (tmdb <= 0) return null;
        return () => context.openMedia(MediaKey.movie(tmdb), focus: focus);
      case _:
        final key = MediaKey.ofSeries(
          tmdbId: intOrNull(payload['tmdbId']),
          tvdbId: intOrNull(payload['tvdbId']),
        );
        if (key == null) return null;
        return () => context.openMedia(key, focus: focus);
    }
  }
}

/// `S1 1 2 3 …`: the episodes that went in, a row per season.
class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({required this.seasons, required this.color});

  final Map<int, List<int>> seasons;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final MapEntry(key: season, value: numbers) in seasons.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 32,
                  height: 28,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      seasonChipLabel(season),
                      style: AppType.meta.copyWith(color: room.inkSecondary),
                    ),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: AppSpacing.xxs,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      for (final number in numbers)
                        Container(
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.22),
                            borderRadius: AppRadius.borderRadiusXs,
                          ),
                          // Sized by its number: a centred child with no
                          // factor would take the whole row.
                          child: Center(
                            widthFactor: 1,
                            heightFactor: 1,
                            child: Text(
                              '$number',
                              style: AppType.label.tabular.copyWith(
                                color: room.ink,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
