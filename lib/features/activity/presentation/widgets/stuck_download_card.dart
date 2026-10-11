import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/features/activity/data/acted_faults.dart';
import 'package:cupola/features/activity/domain/activity_download.dart';
import 'package:cupola/features/activity/domain/stuck_download_fault.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart'
    show ActivitySlab;
import 'package:cupola/features/activity/presentation/widgets/fault_card.dart';
import 'package:cupola/features/activity/presentation/widgets/stuck_action_taker.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/presentation/kept_waiting_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

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

class _StuckDownloadCardState extends ConsumerState<StuckDownloadCard>
    with StuckActionTaker {
  @override
  String get stuckDownloadKey => widget.downloadKey;

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
                ? () => undoKeepWaiting(item)
                : null,
          );

    FaultCardAction secondary(StuckAction action) => (
      label: stuckActionLabel(action, item),
      onPressed: () => takeStuckAction(action, item),
      semanticLabel: '${stuckActionLabel(action, item)}, ${item.sentenceTitle}',
    );

    final primaryLabel = stuckActionLabel(actions.primary, item);
    final primary = SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: takingAction != null
            ? null
            : () => takeStuckAction(actions.primary, item),
        style: remedyFillStyle(context),
        child: takingAction == actions.primary
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                primaryLabel,
                semanticsLabel: '$primaryLabel, ${item.sentenceTitle}',
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
      release: release == item.title ? null : release,
      progress: item.progress,
    );
    // The explanation already says how long nothing has arrived, so a card's
    // proof is its route alone. The row has no explanation and keeps the time.
    final proof = widget._row
        ? stuckProof(item, now: now)
        : downloadRoute(item);
    final subtitle = stuckActionSubtitle(actions.primary, item);
    final quiet = [
      for (final action in actions.secondary)
        if (takingAction == null) secondary(action),
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
      art: art,
      release: words.release,
      proof: proof,
      progress: words.progress,
      primary: primary,
      primarySubtitle: subtitle,
      secondary: quiet,
      note: note,
      divided: widget.divided,
    );
  }
}
