import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/home/presentation/widgets/requests_module.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

DashboardDecision _request(String title, int id, {int hoursAgo = 2}) =>
    DashboardDecision(
      kind: DecisionKind.pendingRequest,
      id: 'seerr--$id',
      service: ServiceKey.seerr,
      title: title,
      detail: 'Seerr · Anna',
      occurredAt: DateTime(2026, 10, 8, 20).subtract(Duration(hours: hoursAgo)),
      actionId: id,
    );

class _Answered extends AnsweredRequests {
  _Answered(this.initial);

  final Map<String, AnsweredRequest> initial;

  @override
  Map<String, AnsweredRequest> build() => initial;
}

/// Requests on the Home: how many wait, from Seerr's count, and a request
/// answered here keeps its row until the Home is read again.
void main() {
  test('how many wait, from the count Seerr gives', () {
    expect(requestsSubtitle(2), '2 wait for you');
    expect(requestsSubtitle(1), '1 waits for you');
    expect(requestsSubtitle(50, floor: true), '50+ wait for you');
    expect(requestsSubtitle(0), 'All answered');
  });

  test('when it was asked, as the row says it', () {
    final now = DateTime(2026, 10, 8, 20);
    expect(askedAgo(DateTime(2026, 10, 8, 18), now: now), '2\u00A0h ago');
    expect(askedAgo(DateTime(2026, 10, 8, 19, 58), now: now), '2\u00A0min ago');
    expect(askedAgo(DateTime(2026, 10, 7, 9), now: now), 'yesterday');
    expect(askedAgo(DateTime(2026, 10, 4, 9), now: now), 'Sunday');
    expect(askedAgo(DateTime(2026, 9, 20, 9), now: now), 'Sun 20 Sep');
  });

  testWidgets('an approved request says where it went, without its '
      'buttons, beside the ones still waiting', (tester) async {
    final charge = _request('Charge', 1);
    final metropolis = _request('Metropolis', 2, hoursAgo: 20);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsScopeOverrides(configured: const [ServiceKey.seerr]),
          // Seerr's list read again after the approval: Charge waits no more.
          dashboardDecisionSourceProvider.overrideWith(
            (ref, source) async =>
                (decisions: [metropolis], coverage: SourceCoverage.none),
          ),
          pendingRequestCountProvider.overrideWith(
            (ref) async => (count: 1, floor: false),
          ),
          answeredRequestsProvider.overrideWith(
            () => _Answered({
              charge.id: (
                decision: charge,
                outcome: 'Approved · sent to Radarr',
              ),
            }),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(body: HomeRequestsModule()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 waits for you'), findsOne);
    expect(find.text('Charge'), findsOne);
    expect(find.text('Approved · sent to Radarr'), findsOne);
    expect(find.text('Metropolis'), findsOne);
    // The answered row has no buttons of its own; Metropolis keeps its.
    expect(find.byTooltip('Approve Charge'), findsNothing);
    expect(find.byTooltip('Decline Charge'), findsNothing);
    expect(find.byTooltip('Approve Metropolis'), findsOne);
    // Ranked with the rest as it was: the one waiting longest first.
    expect(
      tester.getTopLeft(find.text('Metropolis')).dy,
      lessThan(tester.getTopLeft(find.text('Charge')).dy),
    );
  });

  testWidgets('a request answered elsewhere leaves the list at once, with no '
      'row of its own', (tester) async {
    final charge = _request('Charge', 1);
    final metropolis = _request('Metropolis', 2, hoursAgo: 20);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsScopeOverrides(configured: const [ServiceKey.seerr]),
          // Seerr's list as it was read, before the answer reached it.
          dashboardDecisionSourceProvider.overrideWith(
            (ref, source) async => (
              decisions: [charge, metropolis],
              coverage: SourceCoverage.none,
            ),
          ),
          pendingRequestCountProvider.overrideWith(
            (ref) async => (count: 1, floor: false),
          ),
          answeredRequestsProvider.overrideWith(
            // Answered from the Activity feed, say: no Home row to keep.
            () => _Answered({charge.id: (decision: null, outcome: 'Declined')}),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(body: HomeRequestsModule()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Metropolis'), findsOne);
    expect(find.byTooltip('Approve Metropolis'), findsOne);
    expect(find.text('Charge'), findsNothing);
    expect(find.byTooltip('Approve Charge'), findsNothing);
    expect(find.text('Declined'), findsNothing);
  });

  testWidgets('read again, the answered rows give way', (tester) async {
    final container = ProviderContainer(
      overrides: [
        answeredRequestsProvider.overrideWith(
          () => _Answered({
            'a': (decision: _request('Charge', 1), outcome: 'Declined'),
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(answeredRequestsProvider), hasLength(1));
    container.read(answeredRequestsProvider.notifier).clear();
    expect(container.read(answeredRequestsProvider), isEmpty);
  });
}
