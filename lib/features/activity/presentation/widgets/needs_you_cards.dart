/// What Needs you draws, on All and on its own page: a card per fault, the
/// rows of the requests that wait.
library;

import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/presentation/widgets/decision_fault_card.dart';
import 'package:cupola/features/activity/presentation/widgets/storage_alert_card.dart';
import 'package:cupola/features/activity/presentation/widgets/stuck_download_card.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart'
    show HomeRowArt;
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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
  }) : _row = false;

  /// A line of a wide list, the remedy beside it: All on a tablet or a
  /// desktop, where the whole card is on the Needs you page.
  const NeedsYouCard.row({super.key, required this.entry, this.divided = false})
    : whole = false,
      _row = true;

  final FaultEntry entry;
  final bool divided;

  /// The Needs you page's card: a slab of its own.
  final bool whole;

  final bool _row;

  @override
  Widget build(BuildContext context) {
    if (entry.downloadKey case final key?) {
      return _row
          ? StuckDownloadCard.row(downloadKey: key, divided: divided)
          : StuckDownloadCard(downloadKey: key, divided: divided, whole: whole);
    }
    final decision = entry.decision!;
    if (decision.kind == DecisionKind.storageAlert) {
      return _row
          ? StorageAlertCard.row(decision: decision, divided: divided)
          : StorageAlertCard(
              decision: decision,
              divided: divided,
              whole: whole,
            );
    }
    return _row
        ? DecisionFaultCard.row(decision: decision, divided: divided)
        : DecisionFaultCard(decision: decision, divided: divided, whole: whole);
  }
}

/// `2 requests wait for your approval`.
String requestsWaitLine(int count) => count == 1
    ? '1 request waits for your approval'
    : '$count requests wait for your approval';

/// The requests that wait, under their line in blue, each with Approve and
/// Decline; one answered here says what happened in their place.
///
/// [requestOf] holds the requests read whole, by their decision's id, for
/// Approve to name the server without reading one again.
List<Widget> requestRowsOf(
  List<DashboardDecision> requests,
  Map<String, AnsweredRequest> answered,
  Color blue, {
  Map<String, SeerrRequest> requestOf = const {},
}) {
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
        request: requestOf[decision.id],
      ),
  ];
}

/// What and who the requests that wait are, the first two of them:
/// `Charge · Anna · Metropolis · Luca`, then how many more.
String requestsWaitSummary(List<DashboardDecision> requests) {
  final named = [
    for (final request in requests.take(2))
      [
        request.title,
        if (request.detail.isNotEmpty) request.detail,
      ].join(dotSeparator),
  ];
  final more = requests.length - named.length;
  return [...named, if (more > 0) '$more more'].join(dotSeparator);
}

/// The requests that wait, as one line of a wide list: `2 requests wait for
/// your approval` by its blue dot, what and who under it, and Review, which
/// opens them where each has its Approve and Decline.
class RequestsWaitRow extends StatelessWidget {
  const RequestsWaitRow({
    super.key,
    required this.requests,
    required this.onReview,
    this.divided = false,
  });

  final List<DashboardDecision> requests;
  final VoidCallback onReview;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final blue = statusToneColor(
      Theme.of(context).colorScheme,
      StatusTone.info,
      surface: room.slab,
    );
    final line = requestsWaitLine(requests.length);
    final summary = requestsWaitSummary(requests);
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final review = OutlinedButton(
      onPressed: onReview,
      child: Text('Review', semanticsLabel: 'Review the requests that wait'),
    );
    final words = Semantics(
      container: true,
      label: '$line. ${summary.replaceAll(dotSeparator, ', ')}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: blue),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  line,
                  maxLines: 2,
                  style: AppType.row.copyWith(color: room.ink),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
          ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: room.hair)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 54,
              child: FittedBox(
                child: HomeRowArt.large(
                  posterUrl: '',
                  icon: ServiceKey.seerr.icon,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: large
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        words,
                        const SizedBox(height: AppSpacing.sm),
                        review,
                      ],
                    )
                  : words,
            ),
            if (!large) ...[const SizedBox(width: AppSpacing.md), review],
          ],
        ),
      ),
    );
  }
}
