import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/api/base_arr_service.dart' show ArrActivityMixin;
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/features/activity/data/acted_faults.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/domain/stuck_download_fault.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart'
    show connectionArrServiceProvider;
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart'
    show ActivitySlab;
import 'package:cupola/features/activity/presentation/widgets/fault_card.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart'
    show bringUnderLens;
import 'package:cupola/features/services/presentation/kept_waiting_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart'
    show writeFailureReason;
import 'package:cupola/features/settings/domain/service_key.dart';

/// A stuck download's card in Needs you: its proof, and its ways out.
///
/// Found by [downloadKey] in the in-flight read the fault came from. Once a
/// way out was taken it says what happened ([actedFaultsProvider]) until
/// Activity is read again; Keep waiting's note carries Undo.
class StuckDownloadCard extends ConsumerStatefulWidget {
  const StuckDownloadCard({
    super.key,
    required this.downloadKey,
    this.divided = false,
    this.whole = false,
  }) : _remedy = false,
       _row = false;

  /// A line of a wide list ([FaultCard.row]): the remedy beside it, Remove
  /// and Keep waiting behind its ⋯.
  const StuckDownloadCard.row({
    super.key,
    required this.downloadKey,
    this.divided = false,
  }) : whole = false,
       _remedy = false,
       _row = true;

  /// The card on the download's own page, under where it stands: its cause
  /// and its ways out, with nothing the page already says above it (the
  /// title, the release, the bar).
  const StuckDownloadCard.remedy({super.key, required this.downloadKey})
    : divided = false,
      whole = true,
      _remedy = true,
      _row = false;

  final String downloadKey;
  final bool _remedy;
  final bool _row;
  final bool divided;

  /// The Needs you page's card: a slab of its own.
  final bool whole;

  @override
  ConsumerState<StuckDownloadCard> createState() => _StuckDownloadCardState();
}

class _StuckDownloadCardState extends ConsumerState<StuckDownloadCard> {
  StuckAction? _busy;

  @override
  Widget build(BuildContext context) {
    final acted = ref.watch(
      actedFaultsProvider.select((acted) => acted[widget.downloadKey]),
    );
    final faults = ref.watch(servicesInFlightProvider).value?.faults;
    final item =
        acted?.item ??
        faults
            ?.where((item) => keptWaitingKey(item) == widget.downloadKey)
            .firstOrNull;
    if (item == null) return const SizedBox.shrink();

    final now = ref.watch(stallClockProvider)();
    final actions = stuckActionsFor(item);
    final note = acted == null
        ? null
        : (
            text: acted.note,
            onUndo: acted.action == StuckAction.keepWaiting
                ? () => _undoKeep(item)
                : null,
          );

    FaultCardAction secondary(StuckAction action) => (
      label: stuckActionLabel(action, item),
      onPressed: () => _take(action, item),
      semanticLabel: '${stuckActionLabel(action, item)}, ${item.title}',
    );

    final primaryLabel = stuckActionLabel(actions.primary, item);
    final primary = SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _busy != null ? null : () => _take(actions.primary, item),
        style: remedyFillStyle(context),
        child: _busy == actions.primary
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                primaryLabel,
                semanticsLabel: '$primaryLabel, ${item.title}',
              ),
      ),
    );

    final art = HomeRowArt.large(
      posterUrl: item.posterUrl ?? '',
      icon: Icons.download_rounded,
    );
    final release = item.names.machineName;
    final words = (
      headline: stuckHeadline(item),
      explanation: stuckExplanation(item, now: now),
      source: '${arrName(item)} · ${clientName(item)}',
      release: release == item.title ? null : release,
      proof: stuckProof(item, now: now),
      progress: item.progress,
    );
    final subtitle = stuckActionSubtitle(actions.primary, item);
    final quiet = [
      for (final action in actions.secondary)
        if (_busy == null) secondary(action),
    ];

    if (widget._remedy) {
      // A row of a slab, as in All: the cause at the size of a row, not of
      // a page's headline, under the readout that already names the fault.
      return ActivitySlab(
        children: [
          FaultCard(
            headline: words.explanation,
            primary: primary,
            primarySubtitle: subtitle,
            secondary: quiet,
            note: note,
          ),
        ],
      );
    }
    return FaultCard.inForm(
      widget._row
          ? FaultCardForm.row
          : widget.whole
          ? FaultCardForm.whole
          : FaultCardForm.card,
      headline: words.headline,
      explanation: words.explanation,
      source: widget.whole ? words.source : null,
      art: art,
      release: words.release,
      proof: words.proof,
      progress: words.progress,
      primary: primary,
      primarySubtitle: subtitle,
      secondary: quiet,
      note: note,
      divided: widget.divided,
    );
  }

  Future<void> _take(StuckAction action, ServiceQueueItem item) async {
    switch (action) {
      case StuckAction.openClient:
        final target = item.clientService ?? item.service;
        await bringUnderLens(
          ref,
          target,
          item.clientService == null ? item.instanceId : item.clientInstanceId,
        );
        if (!mounted) return;
        context.go(ServiceRoutes.forService(target));
        return;
      case StuckAction.keepWaiting:
        final now = ref.read(stallClockProvider)();
        final kept = ref
            .read(keptWaitingProvider.notifier)
            .keep(item, now: now);
        _acted(item, action, keptWaitingNote(kept.until, now: now));
        return;
      case StuckAction.remove:
        final ask = removeConfirmation(item);
        final answer = await showAppConfirmDialog(
          context: context,
          title: ask.title,
          message: ask.message,
          confirmLabel: ask.confirm,
          icon: Icons.delete_outline_rounded,
        );
        if (!answer.confirmed || !mounted) return;
        await _write(
          action,
          item,
          service: item.service,
          failure: "Could not remove ${item.title}'s download",
          call: () => _arr(item).removeFromQueue(
            int.parse(item.id),
            removeFromClient: true,
            blocklist: false,
          ),
        );
      case StuckAction.tryAnotherDownload:
        await _write(
          action,
          item,
          service: item.service,
          failure: 'Could not try another download',
          call: () => _arr(item).removeFromQueue(
            int.parse(item.id),
            removeFromClient: true,
            blocklist: true,
          ),
        );
      case StuckAction.lookForPeers:
        await _write(
          action,
          item,
          service: ServiceKey.qbittorrent,
          failure: 'Could not ask the trackers again',
          call: () => ref
              .read(qbittorrentServiceForProvider(item.clientInstanceId))
              .reannounce([item.downloadId!]),
        );
    }
  }

  ArrActivityMixin _arr(ServiceQueueItem item) => ref.read(
    connectionArrServiceProvider((_typeOf(item.service), item.instanceId)),
  );

  /// The call, its failure said with its cause, and the note once it is done.
  Future<void> _write(
    StuckAction action,
    ServiceQueueItem item, {
    required ServiceKey service,
    required String failure,
    required Future<void> Function() call,
  }) async {
    setState(() => _busy = action);
    try {
      await call();
    } catch (error) {
      if (mounted) {
        setState(() => _busy = null);
        SnackBarHelper.error(
          context,
          '$failure. ${writeFailureReason(service, error)}',
          cause: error,
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = null);
    _acted(item, action, stuckActionNote(action, item));
  }

  void _acted(ServiceQueueItem item, StuckAction action, String note) {
    ref
        .read(actedFaultsProvider.notifier)
        .act(widget.downloadKey, item: item, action: action, note: note);
    // The queue again, now that it changed: the fault goes, or stays and says
    // what it is. Keep waiting changes no queue, only what counts as a fault.
    if (action != StuckAction.keepWaiting) {
      for (final source in homeDownloadsSources) {
        ref.invalidate(source);
      }
    }
    ref.invalidate(dashboardDecisionSourceProvider(DecisionSource.queue));
  }

  void _undoKeep(ServiceQueueItem item) {
    ref.read(keptWaitingProvider.notifier).release(item);
    ref.read(actedFaultsProvider.notifier).forget(widget.downloadKey);
  }
}

ServiceType _typeOf(ServiceKey service) => switch (service) {
  ServiceKey.sonarr => ServiceType.series,
  ServiceKey.lidarr => ServiceType.music,
  _ => ServiceType.movies,
};
