import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/activity/domain/fault_words.dart';
import 'package:cupola/features/activity/presentation/widgets/fault_card.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart'
    show DecisionControl, runDecision;
import 'package:cupola/features/settings/domain/service_key.dart';

/// A fault's card in Needs you for every kind but a stuck download
/// (`StuckDownloadCard`): its words ([faultWordsOf]) and the kind's own
/// control as the amber fill, gated as the Home's row gates it. A health
/// check failing on several \*arrs opens the first with the fill and each
/// other one with a quieter way out.
class DecisionFaultCard extends ConsumerWidget {
  const DecisionFaultCard({
    super.key,
    required this.decision,
    this.divided = false,
    this.whole = false,
  }) : _row = false;

  /// A line of a wide list ([FaultCard.row]).
  const DecisionFaultCard.row({
    super.key,
    required this.decision,
    this.divided = false,
  }) : whole = false,
       _row = true;

  final DashboardDecision decision;
  final bool divided;

  /// The Needs you page's card: a slab of its own.
  final bool whole;

  final bool _row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = faultWordsOf(decision);
    final art = HomeRowArt.large(
      posterUrl: decision.posterUrl,
      icon: decision.service.icon,
    );
    final primary = DecisionControl.fill(
      decision: decision,
      label: faultActionLabel(decision),
    );
    return FaultCard.inForm(
      _row
          ? FaultCardForm.row
          : whole
          ? FaultCardForm.whole
          : FaultCardForm.card,
      headline: words.headline,
      explanation: words.explanation,
      source: words.source,
      why: words.why,
      art: art,
      primary: primary,
      secondary: [
        for (final member in decision.members.skip(1))
          (
            label: openHealthCheckLabel(member),
            onPressed: () => runDecision(context, ref, member),
            semanticLabel: null,
          ),
      ],
      divided: divided,
    );
  }
}
