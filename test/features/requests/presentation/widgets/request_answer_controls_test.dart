/// The control for a request's answer: the one Approve and Decline every
/// list of waiting requests draws.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/presentation/widgets/activity_actions.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/requests/presentation/widgets/request_answer_controls.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../../test_helpers/profiles/profiles.dart';

const _seerr = WorldIds.seerr;

/// Sara's Seerr, where the operator's own account may see everyone's
/// requests and may not decide on them.
final _p9Sees = Profiles.p9.withSeerrPermissions(
  SeerrPermission.request.value | SeerrPermission.requestView.value,
);

const _friendReason = "Your account on Jellyseerr can't approve requests.";

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  Widget control, {
  Size size = const Size(390, 800),
}) => pumpWithProfile(
  tester,
  profile,
  surfaceSize: size,
  child: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: control),
  ),
);

/// Charge, the first request waiting on P6's Seerr.
Widget _row({String instanceId = _seerr, DashboardDecision? decision}) =>
    RequestAnswerControls.row(
      instanceId: instanceId,
      requestId: 1,
      title: 'Charge',
      decision: decision,
    );

Iterable<String> _writes(ProfileHarness harness, String instanceId) => harness
    .network
    .requestsTo(instanceId)
    .where((r) => r.method != 'GET')
    .map((r) => '${r.method} ${r.uri.path}');

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(RequestAnswerControls)),
);

Finder get _approve => find.byTooltip('Approve Charge');
Finder get _decline => find.byTooltip('Decline Charge');

Finder _ring(Finder inside) => find.descendant(
  of: inside,
  matching: find.byType(CircularProgressIndicator),
);

double _opacityOf(WidgetTester tester, Finder button) => tester
    .widget<Opacity>(
      find.descendant(of: button, matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  group('the row', () {
    testWidgets('Approve is the ink fill, Decline the outline, one width '
        'each, and each is named by its title', (tester) async {
      final harness = await _pump(tester, Profiles.p6, _row());

      expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Decline'), findsOneWidget);
      expect(_approve, findsOneWidget);
      expect(_decline, findsOneWidget);
      expect(
        tester.getSize(find.byType(FilledButton)).width,
        tester.getSize(find.byType(OutlinedButton)).width,
      );
      // The 44pt floor, padded to Material's 48 on a touch build.
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(44),
      );

      await harness.unmount(tester);
    });

    testWidgets('side by side while both verbs fit their half, one under '
        'the other once they would be cut', (tester) async {
      final wide = await _pump(tester, Profiles.p6, _row());
      expect(
        tester.getTopLeft(find.byType(FilledButton)).dy,
        tester.getTopLeft(find.byType(OutlinedButton)).dy,
      );
      await wide.unmount(tester);

      // A narrow row at a large reading size: the verb no longer fits half.
      final narrow = await _pump(
        tester,
        Profiles.p6,
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: SizedBox(width: 240, child: _row()),
        ),
      );
      final approve = tester.getRect(find.byType(FilledButton));
      final decline = tester.getRect(find.byType(OutlinedButton));
      expect(decline.top, greaterThan(approve.bottom));
      expect(approve.width, decline.width);
      await narrow.unmount(tester);
    });

    testWidgets('each button speaks its verb with the title, as one button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final harness = await _pump(tester, Profiles.p6, _row());

      expect(
        tester.getSemantics(find.widgetWithText(FilledButton, 'Approve')),
        containsSemantics(
          label: 'Approve Charge',
          isButton: true,
          isEnabled: true,
        ),
      );
      expect(
        tester.getSemantics(find.widgetWithText(OutlinedButton, 'Decline')),
        containsSemantics(
          label: 'Decline Charge',
          isButton: true,
          isEnabled: true,
        ),
      );

      handle.dispose();
      await harness.unmount(tester);
    });

    testWidgets('Approve names the server, then sends, and the pair gives '
        'way to where it went', (tester) async {
      final harness = await _pump(tester, Profiles.p6, _row());

      await tester.tap(_approve);
      await harness.settle(tester);
      expect(find.text('Approve this request?'), findsOneWidget);
      expect(
        find.text('Charge goes to Radarr 1 and starts downloading.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Approve request'));
      await harness.settle(tester);

      expect(_writes(harness, _seerr), ['POST /api/v1/request/1/approve']);
      expect(find.text('Approved\u00A0· sent to Radarr 1'), findsOneWidget);
      expect(_approve, findsNothing);
      expect(_decline, findsNothing);
      expect(
        _container(tester).read(answeredRequestsProvider)['seerr-seerr-1'],
        (decision: null, outcome: 'Approved\u00A0· sent to Radarr 1'),
      );

      await harness.unmount(tester);
    });

    testWidgets('Decline asks, neutrally, then declines and says so', (
      tester,
    ) async {
      final harness = await _pump(tester, Profiles.p6, _row());

      await tester.tap(_decline);
      await harness.settle(tester);
      expect(find.text('Decline this request?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Decline request'));
      await harness.settle(tester);

      expect(_writes(harness, _seerr), ['POST /api/v1/request/1/decline']);
      expect(find.text('Declined'), findsOneWidget);
      expect(_approve, findsNothing);
      expect(_decline, findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('a confirmation turned down sends nothing and leaves the '
        'pair as it was', (tester) async {
      final harness = await _pump(tester, Profiles.p6, _row());

      await tester.tap(_approve);
      await harness.settle(tester);
      await tester.tap(find.text('Cancel'));
      await harness.settle(tester);
      await tester.tap(_decline);
      await harness.settle(tester);
      await tester.tap(find.text('Cancel'));
      await harness.settle(tester);

      expect(_writes(harness, _seerr), isEmpty);
      expect(_approve, findsOneWidget);
      expect(_decline, findsOneWidget);
      expect(_container(tester).read(answeredRequestsProvider), isEmpty);
      expect(_ring(find.byType(RequestAnswerControls)), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets("the Home's row is kept with its answer", (tester) async {
      const decision = DashboardDecision(
        kind: DecisionKind.pendingRequest,
        id: 'seerr-$_seerr-1',
        service: ServiceKey.seerr,
        title: 'Charge',
        detail: '',
        occurredAt: null,
        actionId: 1,
        instanceId: _seerr,
      );
      final harness = await _pump(
        tester,
        Profiles.p6,
        _row(decision: decision),
      );

      await tester.tap(_decline);
      await harness.settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Decline request'));
      await harness.settle(tester);

      expect(_container(tester).read(answeredRequestsProvider)[decision.id], (
        decision: decision,
        outcome: 'Declined',
      ));

      await harness.unmount(tester);
    });

    test('the key it answers under is the Home row\'s own id', () async {
      final harness = await ProfileHarness.start(
        Profiles.p1.withConnection(WorldConnections.seerrCabin),
      );
      final container = harness.container(retry: (_, _) => null);

      final requests = await container.read(
        dashboardDecisionSourceProvider(DecisionSource.requests).future,
      );

      expect(requests.decisions, isNotEmpty);
      for (final decision in requests.decisions) {
        expect(
          seerrRequestKey(decision.instanceId, decision.actionId!),
          decision.id,
        );
      }
    });
  });

  group('while an answer is in flight', () {
    testWidgets('Approve is busy at once, in its own place, the other waits, '
        'and a second tap does nothing', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await _pump(
        tester,
        Profiles.p6.withLatency(_seerr, const Duration(seconds: 1)),
        _row(),
      );
      final rect = tester.getRect(find.byType(FilledButton));
      final declineRect = tester.getRect(find.byType(OutlinedButton));

      await tester.tap(_approve);
      await tester.pump();

      expect(_ring(find.byType(FilledButton)), findsOneWidget);
      expect(_ring(find.byType(OutlinedButton)), findsNothing);
      expect(tester.getRect(find.byType(FilledButton)), rect);
      expect(tester.getRect(find.byType(OutlinedButton)), declineRect);
      expect(
        tester.getSemantics(find.byType(FilledButton)),
        containsSemantics(
          label: 'Approve Charge',
          value: 'Checking where it goes',
          isButton: true,
          isEnabled: true,
        ),
      );
      // The other one of the pair waits, dimmed.
      expect(_opacityOf(tester, find.byType(OutlinedButton)), lessThan(0.5));

      // Neither a second Approve nor a Decline starts anything.
      await tester.tap(_approve);
      await tester.tap(_decline);
      await tester.pump();
      await harness.settle(tester);
      expect(find.text('Approve this request?'), findsOneWidget);
      expect(find.text('Decline this request?'), findsNothing);

      // Idle again behind the confirmation.
      expect(_ring(find.byType(FilledButton)), findsNothing);
      await tester.tap(find.text('Cancel'));
      await harness.settle(tester);
      expect(_approve, findsOneWidget);

      handle.dispose();
      await harness.unmount(tester);
    });

    testWidgets('Decline is busy while it is sent, and Approve waits', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final harness = await _pump(
        tester,
        Profiles.p6.withLatency(_seerr, const Duration(seconds: 1)),
        _row(),
      );

      await tester.tap(_decline);
      await harness.settle(tester);
      expect(find.text('Decline this request?'), findsOneWidget);
      // Idle behind the question, which a person is answering.
      expect(_ring(find.byType(OutlinedButton)), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Decline request'));
      await tester.pump();

      expect(_ring(find.byType(OutlinedButton)), findsOneWidget);
      expect(_ring(find.byType(FilledButton)), findsNothing);
      expect(
        tester.getSemantics(find.byType(OutlinedButton)),
        containsSemantics(label: 'Decline Charge', value: 'Declining'),
      );
      expect(_opacityOf(tester, find.byType(FilledButton)), lessThan(0.5));

      // A tap on the waiting Approve asks nothing.
      await tester.tap(_approve);
      await tester.pump();
      expect(find.text('Approve this request?'), findsNothing);

      await harness.settle(tester);
      expect(_writes(harness, _seerr), ['POST /api/v1/request/1/decline']);
      expect(find.text('Declined'), findsOneWidget);

      handle.dispose();
      await harness.unmount(tester);
    });
  });

  group('the gate of the Seerr it answers on', () {
    testWidgets('the requester has no pair, and no answer', (tester) async {
      final harness = await _pump(tester, Profiles.p2, _row());

      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text('Approve'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets("an account that may not approve keeps the pair, dimmed, "
        'and is told why', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await _pump(
        tester,
        _p9Sees,
        _row(instanceId: WorldIds.seerrFriend),
      );

      expect(_approve, findsOneWidget);
      expect(_decline, findsOneWidget);
      // Dimmed, and still a live button for a screen reader: never
      // `Semantics(enabled: false)`.
      final approve = tester.getSemantics(find.byType(FilledButton));
      expect(
        approve,
        containsSemantics(isButton: true, isEnabled: true, hint: _friendReason),
      );
      expect(_opacityOf(tester, find.byType(FilledButton)), lessThan(0.5));

      for (final button in [_approve, _decline]) {
        await tester.tap(button);
        await tester.pump();
        expect(find.text(_friendReason), findsOneWidget);
        expect(find.text('Approve this request?'), findsNothing);
        expect(find.text('Decline this request?'), findsNothing);
        await tester.pump(const Duration(seconds: 10));
      }
      expect(
        _writes(
          harness,
          WorldIds.seerrFriend,
        ).where((w) => w.startsWith('POST')),
        isEmpty,
      );

      handle.dispose();
      await harness.unmount(tester);
    });
  });

  group('the card', () {
    testWidgets('stacks the pair, with a glyph on Approve, and takes the '
        "page's fill for it", (tester) async {
      var done = 0;
      final lit = FilledButton.styleFrom(backgroundColor: Colors.orange);
      final harness = await _pump(
        tester,
        Profiles.p6,
        RequestAnswerControls.card(
          instanceId: _seerr,
          requestId: 1,
          title: 'Charge',
          approveStyle: lit,
          onDone: () => done++,
        ),
      );

      expect(
        tester.getTopLeft(find.byType(OutlinedButton)).dy,
        greaterThan(tester.getBottomLeft(find.byType(FilledButton)).dy),
      );
      expect(
        tester.getSize(find.byType(FilledButton)).width,
        tester.getSize(find.byType(OutlinedButton)).width,
      );
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byType(FilledButton))
            .style
            ?.backgroundColor
            ?.resolve({}),
        Colors.orange,
      );

      // Over whatever way it ended: here, a question turned down.
      await tester.tap(_decline);
      await harness.settle(tester);
      await tester.tap(find.text('Cancel'));
      await harness.settle(tester);
      expect(done, 1);

      await harness.unmount(tester);
    });
  });

  group('the compact pair', () {
    testWidgets('is a 28pt plate in a 44pt target, and says its answer '
        'small', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p6,
        const RequestAnswerControls.compact(
          instanceId: _seerr,
          requestId: 1,
          title: 'Charge',
        ),
      );

      for (final button in [
        find.byType(FilledButton),
        find.byType(OutlinedButton),
      ]) {
        expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
        expect(
          tester
              .getSize(
                find
                    .descendant(of: button, matching: find.byType(Material))
                    .first,
              )
              .height,
          28,
        );
      }

      await tester.tap(_decline);
      await harness.settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Decline request'));
      await harness.settle(tester);
      expect(find.text('Declined'), findsOneWidget);

      await harness.unmount(tester);
    });
  });

  test('the phases say what a screen reader hears of each', () {
    expect(RequestAnswerPhase.checking.spoken, 'Checking where it goes');
    expect(RequestAnswerPhase.approving.spoken, 'Approving');
    expect(RequestAnswerPhase.declining.spoken, 'Declining');
    expect(RequestAnswerPhase.declining.isApproval, isFalse);
    expect(RequestAnswerPhase.checking.isApproval, isTrue);
  });
}
