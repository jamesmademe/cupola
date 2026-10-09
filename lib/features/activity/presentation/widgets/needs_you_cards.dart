/// What Needs you draws, on All and on its own page: a card per fault, the
/// rows of the requests that wait.
library;

import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/activity/presentation/widgets/decision_fault_card.dart';
import 'package:cupola/features/activity/presentation/widgets/storage_alert_card.dart';
import 'package:cupola/features/activity/presentation/widgets/stuck_download_card.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';

/// One card of Needs you: a fault's decision, or one stuck download of it,
/// since each stuck download has a way out of its own.
typedef FaultEntry = ({
  String id,
  DashboardDecision? decision,
  String? downloadKey,
});

/// The cards [faults] make, in their order.
List<FaultEntry> faultEntriesOf(Iterable<DashboardDecision> faults) => [
  for (final decision in faults)
    if (decision.kind == DecisionKind.stalledDownload &&
        decision.downloadKeys.isNotEmpty)
      for (final key in decision.downloadKeys)
        (id: 'download-$key', decision: null, downloadKey: key)
    else
      (id: decision.id, decision: decision, downloadKey: null),
];

/// The card an entry is: a stuck download's, a disk alert's, or the plain
/// one with the kind's own control.
class NeedsYouCard extends StatelessWidget {
  const NeedsYouCard({
    super.key,
    required this.entry,
    this.divided = false,
    this.whole = false,
  });

  final FaultEntry entry;
  final bool divided;

  /// The Needs you page's card: a slab of its own.
  final bool whole;

  @override
  Widget build(BuildContext context) {
    if (entry.downloadKey case final key?) {
      return StuckDownloadCard(
        downloadKey: key,
        divided: divided,
        whole: whole,
      );
    }
    final decision = entry.decision!;
    return decision.kind == DecisionKind.storageAlert
        ? StorageAlertCard(decision: decision, divided: divided, whole: whole)
        : DecisionFaultCard(decision: decision, divided: divided, whole: whole);
  }
}

/// `2 requests wait for your approval`.
String requestsWaitLine(int count) => count == 1
    ? '1 request waits for your approval'
    : '$count requests wait for your approval';

/// The requests that wait, under their line in blue, each with Approve and
/// Decline; one answered here says what happened in their place.
List<Widget> requestRowsOf(
  List<DashboardDecision> requests,
  Map<String, AnsweredRequest> answered,
  Color blue,
) {
  final waiting = requests
      .where((decision) => !answered.containsKey(decision.id))
      .length;
  return [
    if (waiting > 0)
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: blue),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                requestsWaitLine(waiting),
                style: AppType.label.copyWith(color: blue),
              ),
            ),
          ],
        ),
      ),
    for (final (index, decision) in requests.indexed)
      DecisionRow(
        key: ValueKey(decision.id),
        decision: decision,
        divided: index > 0,
        outcome: answered[decision.id]?.outcome,
      ),
  ];
}
