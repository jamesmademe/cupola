import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/seerr_decisions_section.dart';

import '../../../../test_helpers/fake_api_client.dart';

SeerrRequest _request({
  required int id,
  String title = 'Dune',
  RequestStatus status = RequestStatus.pendingApproval,
  SeerrMediaAvailability mediaStatus = SeerrMediaAvailability.unknown,
  String requester = 'Ada',
  String type = 'movie',
}) => SeerrRequest(
  id: id,
  status: status,
  media: RequestMedia(
    title: title,
    year: '2021',
    tmdbId: id,
    status: mediaStatus,
  ),
  createdAt: '2026-09-15T00:00:00Z',
  type: type,
  requestedBy: RequestedBy(id: id, displayName: requester),
);

/// Drives the real [seerrDecisionsProvider] by overriding the service under it,
/// so the filter, the sort and the retry policy are the shipped ones.
Future<void> _pumpSection(
  WidgetTester tester, {
  List<SeerrRequest> requests = const [],
  Object? failure,
  Size size = const Size(1200, 2000),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final overrides = failure == null
      ? [requestsProvider.overrideWith((ref) async => requests)]
      : [
          seerrServiceProvider.overrideWithValue(
            SeerrService(FakeApiClient()..getException = failure),
          ),
        ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const Scaffold(
            body: SingleChildScrollView(child: SeerrDecisionsSection()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SeerrDecisionsSection', () {
    testWidgets('draws nothing when nothing is waiting', (tester) async {
      // A stack with auto-approvals sits here permanently. An empty well, or a
      // heading over a 0, would be a standing apology for a working setup.
      await _pumpSection(
        tester,
        requests: [_request(id: 1, status: RequestStatus.approved)],
      );

      expect(find.text('Needs a decision'), findsNothing);
      expect(find.text('Dune (2021)'), findsNothing);
    });

    testWidgets('leads with what is waiting, counted', (tester) async {
      await _pumpSection(
        tester,
        requests: [
          _request(id: 1, title: 'Dune'),
          _request(id: 2, title: 'Arrival'),
          _request(id: 3, status: RequestStatus.completed, title: 'Sicario'),
        ],
      );

      expect(find.text('Needs a decision'), findsOneWidget);
      // The count is what is waiting, not what exists.
      expect(find.text('2 waiting'), findsOneWidget);
      expect(find.text('Dune (2021)'), findsOneWidget);
      expect(find.text('Arrival (2021)'), findsOneWidget);
      expect(find.text('Sicario (2021)'), findsNothing);
    });

    testWidgets('a lost page of requests makes the count a floor', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      // Seerr holds ten; a page of them did not arrive, so the two waiting
      // ones counted here are the least there are.
      await _pumpSection(
        tester,
        requests: SeerrRequestList(
          [_request(id: 1, title: 'Dune'), _request(id: 2, title: 'Arrival')],
          total: 10,
          isPartial: true,
        ),
      );

      expect(find.text('2+ waiting'), findsOneWidget);
      expect(find.text('2 waiting'), findsNothing);
      expect(
        find.bySemanticsLabel('Needs a decision, at least 2 requests waiting'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('lists a waiting request whose media already landed', (
      tester,
    ) async {
      // The displayStatus trap, end to end: this request reads "Available" and
      // still needs a person. It is the one a naive filter drops.
      final pendingButAvailable = _request(
        id: 7,
        title: 'Blade Runner 2049',
        mediaStatus: SeerrMediaAvailability.available,
      );
      expect(pendingButAvailable.displayStatus.label, 'Available');

      await _pumpSection(tester, requests: [pendingButAvailable]);

      expect(find.text('Blade Runner 2049 (2021)'), findsOneWidget);
    });

    testWidgets('carries no status pill', (tester) async {
      // Pending is the one row the tone rule does not settle. Here the section
      // heading already says it, so the row does not restate it in colour —
      // that reading belongs to Activity, whose job is to say what needs doing.
      await _pumpSection(tester, requests: [_request(id: 1)]);

      expect(find.text('Pending'), findsNothing);
      expect(find.text('Available'), findsNothing);
    });

    testWidgets('both answers are reachable and name their request', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        requests: [
          _request(id: 1, title: 'Dune'),
          _request(id: 2, title: 'Arrival'),
        ],
      );

      // Named per row: four buttons all called "Approve" is four identical
      // stops in the rotor.
      expect(find.byTooltip('Approve request for Dune'), findsOneWidget);
      expect(find.byTooltip('Decline request for Dune'), findsOneWidget);
      expect(find.byTooltip('Approve request for Arrival'), findsOneWidget);
      expect(find.byTooltip('Decline request for Arrival'), findsOneWidget);
    });

    testWidgets('a row is one node, not four fragments', (tester) async {
      final handle = tester.ensureSemantics();

      await _pumpSection(
        tester,
        requests: [_request(id: 1, title: 'Dune', requester: 'Ada')],
      );

      final node = tester.getSemantics(find.byType(AppCard));
      expect(node.label, 'Dune (2021)');
      expect(node.value, contains('requested by Ada'));
      expect(node.value, contains('Movie'));

      // The '·' between the fragments is read out as "middle dot" when the row
      // is four separate stops, which is what the composed value replaces.
      expect(find.bySemanticsLabel('Ada'), findsNothing);

      handle.dispose();
    });

    testWidgets('a long title on a narrow phone does not break the row', (
      tester,
    ) async {
      // 360 is the phone the gutters were sized for, and the row carries a
      // poster, three lines of text and both answers at 48 each.
      await _pumpSection(
        tester,
        size: const Size(360, 800),
        requests: [
          _request(
            id: 1,
            title: 'The Lord of the Rings: The Fellowship of the Ring',
            requester: 'Konstantinos Papadopoulos',
          ),
        ],
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('the row survives an accessibility reading size', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        size: const Size(360, 1400),
        textScale: 2.0,
        requests: [_request(id: 1, title: 'Dune', requester: 'Ada')],
      );

      expect(tester.takeException(), isNull);
      // Still reachable at 2x: a control that overflows out of the row is a
      // control nobody can press.
      expect(find.byTooltip('Approve request for Dune'), findsOneWidget);
    });

    testWidgets('a Seerr that did not answer says so and offers a retry', (
      tester,
    ) async {
      await _pumpSection(tester, failure: Exception('unreachable'));

      expect(find.byType(InlineErrorRetry), findsOneWidget);
      // Never "nothing is waiting": that is a claim about a server that
      // answered.
      expect(find.text('Needs a decision'), findsNothing);
    });

    testWidgets('a Seerr that was never set up is not a fault', (tester) async {
      await _pumpSection(tester, failure: Exception('Seerr not configured'));

      expect(find.byType(InlineErrorRetry), findsNothing);
      expect(find.text('Needs a decision'), findsNothing);
    });
  });
}
