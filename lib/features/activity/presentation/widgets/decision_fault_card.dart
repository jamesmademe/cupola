import 'package:flutter/material.dart';

import 'package:cupola/features/activity/domain/fault_words.dart';
import 'package:cupola/features/activity/presentation/widgets/fault_card.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart'
    show DecisionControl;
import 'package:cupola/features/settings/domain/service_key.dart';

/// A fault's card in Needs you for every kind but a stuck download
/// (`StuckDownloadCard`): its words ([faultWordsOf]) and the kind's own
/// control as the amber fill, gated as the Home's row gates it.
class DecisionFaultCard extends StatelessWidget {
  const DecisionFaultCard({
    super.key,
    required this.decision,
    this.divided = false,
    this.whole = false,
  });

  final DashboardDecision decision;
  final bool divided;

  /// The Needs you page's card: a slab of its own.
  final bool whole;

  @override
  Widget build(BuildContext context) {
    final words = faultWordsOf(decision);
    final art = HomeRowArt.large(
      posterUrl: decision.posterUrl,
      icon: decision.service.icon,
    );
    final primary = DecisionControl.fill(
      decision: decision,
      label: faultActionLabel(decision),
    );
    return whole
        ? FaultCard.whole(
            headline: words.headline,
            explanation: words.explanation,
            source: words.source,
            why: words.why,
            art: art,
            primary: primary,
          )
        : FaultCard(
            headline: words.headline,
            explanation: words.explanation,
            source: words.source,
            why: words.why,
            art: art,
            primary: primary,
            divided: divided,
          );
  }
}
