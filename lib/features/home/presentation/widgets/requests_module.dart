/// Requests: the requests waiting for the operator's answer, with Approve
/// and Decline in the row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// `2 wait for you`: how many requests wait, from Seerr's count of them.
///
/// [floor] when a Seerr gave no count and its page was full. `All answered`
/// once every request on the module was answered here and nothing else
/// waits.
String requestsSubtitle(int count, {bool floor = false}) {
  if (count == 0) return 'All answered';
  if (count == 1 && !floor) return '1 waits for you';
  return '${floor ? Lexicon.floor(count) : count} wait for you';
}

/// Requests: the requests waiting for the operator's answer, a few rows,
/// each with Approve and Decline.
///
/// Absent when nothing waits and when no Seerr is set up: a module with
/// nothing to say steps aside. Never in Needs you: a request is somebody
/// waiting politely, not something that stopped working. A request answered
/// here keeps its row, saying what happened, until the Home is read again.
class HomeRequestsModule extends ConsumerWidget {
  const HomeRequestsModule({super.key});

  static const _title = 'Requests';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.seerr),
      ),
    )) {
      return const SizedBox.shrink();
    }
    final read = ref.watch(
      dashboardDecisionSourceProvider(DecisionSource.requests),
    );
    final answered = ref.watch(answeredRequestsProvider);
    final value = read.value;
    if (value == null) {
      if (read.hasError) {
        final coverage = SourceCoverage.failure(ServiceKey.seerr, read.error);
        return HomeModuleFrame.silent(
          title: _title,
          coverage: coverage,
          onRetry: () => retryDashboardServices(ref, const [ServiceKey.seerr]),
        );
      }
      return const HomeModuleFrame.loading(title: _title);
    }
    final coverage = value.coverage;
    final waiting = [
      for (final decision in value.decisions)
        if (decision.kind == DecisionKind.pendingRequest &&
            !answered.containsKey(decision.id))
          decision,
    ];
    final rows = [...waiting, for (final a in answered.values) a.decision];
    if (rows.isEmpty) {
      // With one Seerr silent, its requests are unknown, not absent.
      if (coverage.failed.isNotEmpty) {
        return HomeModuleFrame.silent(
          title: _title,
          coverage: coverage,
          onRetry: () => retryDashboardServices(ref, coverage.failedServices),
        );
      }
      return const SizedBox.shrink();
    }

    final cap = decisionCapFor(
      desktopShell: AppBreakpoints.isDesktopShell(context),
      compact: AppBreakpoints.isCompactDesktop(context),
    );
    final shown = rankDecisions(rows, cap: cap);
    // Seerr's own count, never the rows: the page holds a few of them.
    final counted = ref.watch(pendingRequestCountProvider).value;
    final count = counted?.count ?? waiting.length;
    final subtitle = requestsSubtitle(
      count,
      floor: counted?.floor ?? coverage.isFloor,
    );
    final note = coverageNote(coverage);
    final shownWaiting = shown
        .where((decision) => !answered.containsKey(decision.id))
        .length;

    return HomeModuleFrame(
      title: _title,
      subtitle: subtitle,
      semanticLabel: joinSpokenParts([
        _title,
        spokenCountPhrase(subtitle),
        if (note != null) spokenFromDotted(note),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null) HomeCoverageNote(note: note, coverage: coverage),
          for (final (index, decision) in shown.indexed)
            DecisionRow(
              key: ValueKey(decision.id),
              decision: decision,
              divided: index > 0,
              outcome: answered[decision.id]?.outcome,
            ),
          if (count > shownWaiting)
            HomeModuleLink(
              label: 'See all requests',
              onTap: () => context.go(ServiceRoutes.seerrRequests),
            ),
        ],
      ),
    );
  }
}
