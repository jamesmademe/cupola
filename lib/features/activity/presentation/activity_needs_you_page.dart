import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart'
    show needsYouMeta;
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';
import 'package:cupola/features/activity/presentation/widgets/import_done_card.dart';
import 'package:cupola/features/activity/presentation/widgets/needs_you_cards.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

/// Needs you, whole: every fault on a card of its own with its evidence and
/// its way out, then the requests that wait.
///
/// Under the title, what it holds (`3 faults · 2 requests`) and who was asked:
/// `All 12 services answered at 20:53`, or which did not, in their tone. The
/// Home's Review opens it, and so does the heading on All.
class ActivityNeedsYouPage extends ConsumerStatefulWidget {
  const ActivityNeedsYouPage({super.key});

  @override
  ConsumerState<ActivityNeedsYouPage> createState() =>
      _ActivityNeedsYouPageState();
}

class _ActivityNeedsYouPageState extends ConsumerState<ActivityNeedsYouPage> {
  /// When every source last answered: the time under the title.
  DateTime? _answeredAt;

  @override
  Widget build(BuildContext context) {
    final decisions = ref.watch(dashboardDecisionsProvider);
    final coverage = decisions.coverage;
    if (coverage.pending.isEmpty && _answeredAt == null) {
      _answeredAt = ref.read(stallClockProvider)();
    }
    ref.listen(dashboardDecisionsProvider, (previous, next) {
      if (next.coverage.pending.isEmpty) {
        _answeredAt = ref.read(stallClockProvider)();
      }
    });
    final answered = ref.watch(answeredRequestsProvider);
    final entries = faultEntriesOf(
      decisions.decisions.where((decision) => decision.isFault),
    );
    final waiting = [
      for (final decision in decisions.decisions)
        if (decision.kind == DecisionKind.pendingRequest &&
            !answered.containsKey(decision.id))
          decision,
    ];
    final requests = [...waiting, for (final a in answered.values) ?a.decision];
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final blue = statusToneColor(scheme, StatusTone.info, surface: room.slab);
    final note = coverageNote(coverage);
    final report = ref.watch(importReportProvider);

    Widget slab(List<Widget> children) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        0,
      ),
      child: ActivitySlab(children: children),
    );

    // Said only once every source answered: before then, or with one
    // silent, nothing on the page is not nothing wrong.
    final nothing =
        report == null &&
        entries.isEmpty &&
        requests.isEmpty &&
        coverage.pending.isEmpty &&
        coverage.failed.isEmpty;

    return AmbientScaffold(
      appBar: GlassAppBar(title: const Text('Needs you')),
      body: RefreshIndicator(
        onRefresh: () => refreshActivity(ref, ActivityTab.all),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            _Heading(
              faults: entries.length,
              requests: waiting.length,
              answeredLine: note == null && coverage.answered.isNotEmpty
                  ? _answeredLine(coverage.answered.length, _answeredAt)
                  : null,
              note: note == null
                  ? null
                  : HomeCoverageNote(note: note, coverage: coverage),
            ),
            if (report != null)
              slab([ImportDoneCard(report: report, whole: true)]),
            for (final entry in entries)
              slab([
                NeedsYouCard(
                  key: ValueKey(entry.id),
                  entry: entry,
                  whole: true,
                ),
              ]),
            if (requests.isNotEmpty)
              slab(requestRowsOf(requests, answered, blue)),
            if (nothing)
              const AppEmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'Nothing needs you',
                message:
                    'A download that stops, a disk that reports errors or a '
                    'request that waits for an answer appears here.',
              ),
          ],
        ),
      ),
    );
  }
}

/// `All 12 services answered at 20:53`.
String? _answeredLine(int count, DateTime? at) {
  if (at == null) return null;
  final who = count == 1 ? 'The one service' : 'All $count services';
  return '$who answered at ${formatClockTime(at)}';
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.faults,
    required this.requests,
    this.answeredLine,
    this.note,
  });

  final int faults;
  final int requests;
  final String? answeredLine;
  final Widget? note;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final amber = statusToneColor(
      scheme,
      StatusTone.warning,
      surface: room.slab,
    );
    final blue = statusToneColor(scheme, StatusTone.info, surface: room.slab);
    final style = AppType.label;
    final meta = needsYouMeta(faults: faults, requests: requests);

    Widget dot(Color color) => Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meta.isNotEmpty)
            Semantics(
              label: meta.replaceAll(' · ', ', '),
              excludeSemantics: true,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xxs,
                children: [
                  if (faults > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        dot(amber),
                        Text(
                          faults == 1 ? '1 fault' : '$faults faults',
                          style: style.copyWith(color: amber),
                        ),
                      ],
                    ),
                  if (requests > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        dot(blue),
                        Text(
                          requests == 1 ? '1 request' : '$requests requests',
                          style: style.copyWith(color: blue),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          if (answeredLine case final line?) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(line, style: AppType.meta.copyWith(color: room.inkSecondary)),
          ],
          if (note case final note?) ...[
            const SizedBox(height: AppSpacing.xs),
            note,
          ],
        ],
      ),
    );
  }
}
