import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/activity/data/selected_download.dart';
import 'package:cupola/features/activity/domain/activity_download.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/domain/download_page.dart';
import 'package:cupola/features/activity/domain/stuck_download_fault.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart'
    show downloadAskersProvider;
import 'package:cupola/features/activity/presentation/download_actions.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_history_row.dart';
import 'package:cupola/features/activity/presentation/widgets/decision_fault_card.dart';
import 'package:cupola/features/activity/presentation/widgets/download_parts.dart';
import 'package:cupola/features/activity/presentation/widgets/stuck_download_card.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart'
    show HomeCoverageNote;
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_episode_providers.dart'
    show mediaSonarrProfilesProvider;
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/media_split.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart'
    show mediaRadarrProfilesProvider;
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_download_row.dart'
    show openArrTitle;
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/download_join.dart'
    show downloadJoinKey;
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/source_coverage.dart'
    show coverageNote;
import 'package:cupola/features/services/presentation/dashboard_sections.dart'
    show bringUnderLens;
import 'package:cupola/features/services/presentation/kept_waiting_provider.dart'
    show keptWaitingKey;
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One download's own page (`/activity/download?i=&id=`): who it is, where
/// it stands and how fast, the steps from the grab to the server, what can
/// be done, and the facts.
///
/// Read from its address alone ([downloadAt] over the queue Activity reads),
/// so a link opens it. A stuck one leads with its remedy, the card Needs you
/// draws. Read again with Activity's downloads while it is on screen; the
/// speed it draws is sampled from the moment it was opened.
class DownloadPage extends ConsumerStatefulWidget {
  const DownloadPage({
    super.key,
    required this.instanceId,
    required this.downloadKey,
  }) : _inspector = false;

  /// The page as the desktop's inspector holds it, beside the table where
  /// the download was chosen: no room of its own, no way back, the pane's
  /// column. Removing the download clears the choice.
  const DownloadPage.inspector({
    super.key,
    required this.instanceId,
    required this.downloadKey,
  }) : _inspector = true;

  /// The connection the download was read from: its \*arr's, or its
  /// client's when no \*arr asked for it.
  final String instanceId;

  /// The client's id for the transfer ([downloadPageKey]).
  final String downloadKey;

  final bool _inspector;

  @override
  ConsumerState<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends ConsumerState<DownloadPage> {
  List<RateSample> _trace = const [];
  late final DateTime _openedAt;

  /// A Stop (true) or a Resume (false) sent, standing until the queue says
  /// the same, or for two reads that do not: then the queue's word stands.
  bool? _held;
  int _heldReads = 0;

  /// A write in flight: Stop, Resume or Remove.
  bool _busy = false;

  /// The last pace line drawn while the download moved. It keeps the pace's
  /// room once a Stop takes the line away, or shortens it, so the page does
  /// not move under a finger.
  String? _keptPace;

  @override
  void initState() {
    super.initState();
    _openedAt = ref.read(stallClockProvider)();
    _trace = withRateSample(
      _trace,
      _find(ref.read(servicesQueueProvider).value),
      at: _openedAt,
    );
  }

  ServiceQueueItem? _find(ServicesQueue? queue) => queue == null
      ? null
      : downloadAt(
          queue.items,
          instanceId: widget.instanceId,
          key: widget.downloadKey,
        );

  @override
  Widget build(BuildContext context) {
    ref.watchWhileLive(
      context,
      activityLivePollProvider(ActivityTab.downloads),
    );
    ref.listen(servicesQueueProvider, (previous, next) {
      final queue = next.value;
      if (queue == null || identical(queue, previous?.value)) return;
      final item = _find(queue);
      setState(() {
        _trace = withRateSample(
          _trace,
          item,
          at: ref.read(stallClockProvider)(),
        );
        if (_held != null && (item?.held == _held || ++_heldReads >= 2)) {
          _held = null;
          _heldReads = 0;
        }
      });
    });
    final queue = ref.watch(servicesQueueProvider);
    final now = ref.watch(stallClockProvider)();
    final item = _find(queue.value);
    final poster = item?.posterUrl;
    final light = poster == null || poster.isEmpty
        ? null
        : ref.watch(titleLightProvider(poster)).value;

    List<Widget> body(double column) => switch ((queue.value, item)) {
      (null, _) => [
        const SizedBox(height: AppSpacing.lg),
        AppSkeleton.detailBody(),
      ],
      (final value?, null) => _gone(value, now),
      (_, final item?) => _download(
        item,
        now,
        wide: column >= 520,
        light: light,
      ),
    };

    if (widget._inspector) {
      return LayoutBuilder(
        builder: (context, box) => ListView(
          padding: const EdgeInsets.fromLTRB(
            _inspectorInset,
            AppSpacing.sm,
            _inspectorInset,
            AppSpacing.xl,
          ),
          children: body(box.maxWidth - 2 * _inspectorInset),
        ),
      );
    }

    final page = LayoutBuilder(
      builder: (context, box) {
        final column = (box.maxWidth - 2 * AppSpacing.lg).clamp(
          0.0,
          AppBreakpoints.readingWell,
        );
        final gutter = (box.maxWidth - column) / 2;
        final insets = MediaQuery.paddingOf(context);
        final children = body(column);
        return MediaPinnedPlates(
          inset: gutter,
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                gutter,
                insets.top + AppSpacing.md,
                gutter,
                // Clear of the floating bar; where there is none, a margin.
                math.max(
                  AppSpacing.xxl,
                  FloatingNavBarMetrics.getScrollViewBottomPadding(context),
                ),
              ),
              children: [
                // The back plate floats here, pinned (`MediaPinnedPlates`).
                const SizedBox(height: MediaPinnedPlates.reserve),
                const SizedBox(height: AppSpacing.md),
                ...children,
              ],
            ),
          ),
        );
      },
    );
    return MediaRoom(light: light, child: page);
  }

  List<Widget> _download(
    ServiceQueueItem item,
    DateTime now, {
    required bool wide,
    required TitleLight? light,
  }) {
    final requests = ref.watch(downloadAskersProvider);
    final settings = ref.watch(currentSettingsProvider);
    final player = downloadPlayers
        .where(settings.isServiceConfigured)
        .firstOrNull;
    final stand = downloadStandOf(item, held: _held);
    final profile = _profileOf(item);
    final client = downloadClientOf(item);
    final address = switch (client) {
      final client? => switch (settings.instanceById(client.instanceId)) {
        final instance? => connectionAddress(instance.url),
        null => null,
      },
      null => null,
    };
    final fault = _faultHead(item);
    final pace = downloadPaceLine(item, now: now, held: _held);
    // A stopped line never replaces the moving one: Resume brings the moving
    // line back, and it must find the room it had.
    if (pace != null && stand != DownloadStand.stopped) _keptPace = pace;
    return [
      DownloadHero(
        title: item.queueTitle?.name ?? item.title,
        meta: downloadMetaLine(
          item,
          request: requestFor(item, requests),
          now: now,
        ),
        posterUrl: item.posterUrl,
        icon: item.service.icon,
        wide: wide,
      ),
      const SizedBox(height: AppSpacing.xl),
      DownloadReadout(
        stand: stand,
        percent: downloadPercent(item),
        progress: item.progress,
        pace: pace,
        keptPace: _keptPace,
        steps: downloadStepsOf(item, player: player, now: now, held: _held),
        trace: _trace,
        watched: _trace.isEmpty ? null : now.difference(_openedAt),
      ),
      const SizedBox(height: AppSpacing.lg),
      // A fault's remedy takes the lead's place, the one amber fill.
      if (fault != null) ...[fault, const SizedBox(height: AppSpacing.lg)],
      _Commands(
        item: item,
        quiet: fault != null,
        // A remedy that opens the client is the page's Open already.
        opensClient:
            fault != null &&
            (item.fault == InFlightFault.stalled ||
                item.fault == InFlightFault.failed) &&
            stuckActionsFor(item).primary == StuckAction.openClient,
        held: _held ?? item.held,
        busy: _busy,
        light: light,
        onOpen: () => _open(item),
        onStop: canStopDownload(item) ? () => _stop(item) : null,
        onRemove: hasArrRecord(item) && item.fault == null
            ? () => _remove(item)
            : null,
      ),
      const SizedBox(height: AppSpacing.lg),
      DownloadFacts(
        facts: downloadFactsOf(item, profile: profile, clientAddress: address),
      ),
    ];
  }

  /// The card of the fault a download stands on: a stall or a failure with
  /// its cause and its ways out, an import with its Review, as Needs you
  /// draws it.
  Widget? _faultHead(ServiceQueueItem item) {
    switch (item.fault) {
      case InFlightFault.stalled || InFlightFault.failed:
        return StuckDownloadCard.remedy(downloadKey: keptWaitingKey(item));
      case InFlightFault.needsImport:
        final decision = ref
            .watch(dashboardDecisionsProvider)
            .decisions
            .where(
              (decision) =>
                  decision.kind == DecisionKind.importBlocked &&
                  decision.service == item.service &&
                  (decision.instanceId == item.instanceId ||
                      decision.actionInstanceId == item.instanceId),
            )
            .firstOrNull;
        return decision == null
            ? null
            : DecisionFaultCard(decision: decision, whole: true);
      case null:
        return null;
    }
  }

  /// The name of the profile [item] was grabbed under, once its \*arr has
  /// listed them.
  String? _profileOf(ServiceQueueItem item) {
    final id = item.queueTitle?.qualityProfileId;
    if (id == null) return null;
    final profiles = switch (item.service) {
      ServiceKey.radarr => ref.watch(
        mediaRadarrProfilesProvider(item.instanceId),
      ),
      ServiceKey.sonarr => ref.watch(
        mediaSonarrProfilesProvider(item.instanceId),
      ),
      _ => null,
    };
    return profiles?.value?[id];
  }

  /// The page gone: what is no longer in the queue, with its import of
  /// today when one landed; or, when its source did not answer, who.
  List<Widget> _gone(ServicesQueue queue, DateTime now) {
    final room = CupolaRoom.of(context);
    final silent = queue.coverage.failed.keys.any(
      (source) => source.instanceId == widget.instanceId,
    );
    if (silent) {
      return [
        HomeCoverageNote(
          note: coverageNote(queue.coverage) ?? '',
          coverage: queue.coverage,
        ),
      ];
    }
    final wanted = downloadJoinKey(widget.downloadKey);
    final landed =
        (ref.watch(servicesArrivalsProvider).value?.entries ?? const [])
            .where(
              (entry) =>
                  entry.instanceId == widget.instanceId &&
                  downloadJoinKey(entry.downloadId) == wanted,
            )
            .firstOrNull;
    return [
      Text(
        'This download is no longer in the queue',
        style: AppType.section.copyWith(color: room.ink),
      ),
      if (landed != null) ...[
        const SizedBox(height: AppSpacing.lg),
        ActivityHistoryRow(entry: landed),
      ],
    ];
  }

  Future<void> _refresh() async {
    invalidateDownloads(ref);
    try {
      await ref.read(servicesQueueProvider.future);
    } catch (_) {}
  }

  /// The title's page, under Activity: a movie or a series by TMDB's id
  /// (TVDB's for a series with no other), an artist or an author on its
  /// \*arr; a transfer no \*arr asked for, its client's room.
  Future<void> _open(ServiceQueueItem item) async {
    final key = switch (item.service) {
      ServiceKey.radarr when item.tmdbId != null => MediaKey.movie(
        item.tmdbId!,
      ),
      ServiceKey.sonarr when item.tmdbId != null => MediaKey.tv(item.tmdbId!),
      ServiceKey.sonarr when item.tvdbId != null => MediaKey.tvdb(item.tvdbId!),
      _ => null,
    };
    if (key != null) {
      await context.openMedia(
        key,
        focus: item.instanceId,
        posterUrl: item.posterUrl,
      );
      return;
    }
    if (await openArrTitle(
      context,
      service: item.service,
      mediaId: item.mediaId,
      instanceId: item.instanceId,
    )) {
      return;
    }
    final target = item.clientService ?? item.service;
    await bringUnderLens(
      ref,
      target,
      item.clientService == null ? item.instanceId : item.clientInstanceId,
    );
    if (!mounted) return;
    context.go(ServiceRoutes.forService(target));
  }

  /// Stop, or Resume once stopped, in the client moving the bytes.
  Future<void> _stop(ServiceQueueItem item) async {
    final stop = !(_held ?? item.held);
    setState(() => _busy = true);
    final done = await stopDownload(context, ref, item, stop: stop);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (done) {
        _held = stop;
        _heldReads = 0;
      }
    });
  }

  /// Remove, after the neutral question Needs you asks. Then the page
  /// closes, since there is nothing left on it; in the inspector, the choice
  /// is cleared.
  Future<void> _remove(ServiceQueueItem item) async {
    final removed = await removeDownload(
      context,
      ref,
      item,
      onConfirmed: () => setState(() => _busy = true),
    );
    if (!mounted) return;
    if (!removed) {
      setState(() => _busy = false);
      return;
    }
    if (widget._inspector) {
      ref.read(selectedDownloadProvider.notifier).clear();
      return;
    }
    final pane = MediaPane.maybeOf(context);
    if (pane != null) {
      pane.onBack();
    } else {
      await Navigator.of(context).maybePop();
    }
  }
}

/// The inspector's inset, the pane's own.
const double _inspectorInset = 14;

/// What can be done: the title's page lit by its light, then Stop (Resume
/// once stopped) and Remove side by side, as a Media page sets its lead
/// over the quieter actions. Under a fault's remedy the title's page is
/// quiet too: the remedy is the page's one fill.
class _Commands extends StatelessWidget {
  const _Commands({
    required this.item,
    required this.quiet,
    this.opensClient = false,
    required this.held,
    required this.busy,
    required this.light,
    required this.onOpen,
    required this.onStop,
    required this.onRemove,
  });

  final ServiceQueueItem item;

  /// Whether a fault's remedy leads above.
  final bool quiet;

  /// Whether that remedy is `Open in qBittorrent`: then a transfer no title
  /// owns has no Open of its own to add.
  final bool opensClient;
  final bool held;
  final bool busy;
  final TitleLight? light;
  final VoidCallback onOpen;
  final VoidCallback? onStop;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final titled = item.mediaId != null || item.tmdbId != null;
    final showsOpen = titled || !opensClient;
    final name = item.queueTitle?.name ?? item.title;
    final label = Text(titled ? 'Open $name' : 'Open in ${clientName(item)}');
    final lead = quiet
        ? OutlinedButton(onPressed: onOpen, child: label)
        : FilledButton(
            onPressed: onOpen,
            style: titled
                ? mediaLeadStyle(context, light)
                : AppTheme.primaryButtonStyle(context),
            child: label,
          );
    final rest = <Widget>[
      if (onStop != null)
        Tooltip(
          message: held
              ? 'Picks up where it stopped'
              : 'Keeps what has arrived',
          child: OutlinedButton.icon(
            onPressed: busy ? null : onStop,
            icon: Icon(
              held ? Icons.play_arrow_rounded : Icons.stop_rounded,
              size: 17,
            ),
            label: Text(
              held ? 'Resume' : 'Stop',
              semanticsLabel: held
                  ? 'Resume, picks up where it stopped'
                  : 'Stop, keeps what has arrived',
            ),
          ),
        ),
      if (onRemove != null)
        OutlinedButton.icon(
          onPressed: busy ? null : onRemove,
          icon: const Icon(Icons.delete_outline_rounded, size: 17),
          label: const Text('Remove'),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showsOpen) lead,
        if (rest.isNotEmpty) ...[
          if (showsOpen) const SizedBox(height: AppSpacing.row),
          if (downloadStacked(context))
            for (final (index, button) in rest.indexed) ...[
              if (index > 0) const SizedBox(height: AppSpacing.sm),
              button,
            ]
          else
            Row(
              children: [
                for (final (index, button) in rest.indexed) ...[
                  if (index > 0) const SizedBox(width: AppSpacing.row),
                  Expanded(child: button),
                ],
              ],
            ),
        ],
      ],
    );
  }
}
