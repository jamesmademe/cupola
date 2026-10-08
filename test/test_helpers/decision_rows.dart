import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

/// Every decision the stack is waiting on, drawn as the [DecisionRow] it is.
///
/// The Home no longer lists decisions: faults lead Needs you as one line and
/// requests fill their own module. The row, with the control it carries for
/// each kind, is still the unit those two open on, so a test of a row's
/// control mounts the row itself, with the decisions the app's own provider
/// builds from the profile's network (`dashboardDecisionsProvider`, folded and
/// ranked as the Home reads them), in the scope the test already pumps.
///
/// [where] keeps only the decisions it accepts: a request, say, or one kind.
class ProvidedDecisionRows extends ConsumerWidget {
  const ProvidedDecisionRows({super.key, this.where});

  final bool Function(DashboardDecision decision)? where;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decisions = [
      for (final decision in ref.watch(dashboardDecisionsProvider).decisions)
        if (where?.call(decision) ?? true) decision,
    ];
    return SingleChildScrollView(
      child: Column(
        children: [
          for (final (index, decision) in decisions.indexed)
            DecisionRow(
              key: ValueKey(decision.id),
              decision: decision,
              divided: index > 0,
            ),
        ],
      ),
    );
  }
}
