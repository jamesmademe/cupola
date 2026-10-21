/// A request that waits is answered from its row in the Activity feed with
/// the control every list draws, on the phone's card and on the desktop's
/// table row, and its overflow menu no longer carries Approve and Decline.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Charge, waiting on [instanceId]'s Seerr, as the feed draws it.
GlobalActivityItem _row(
  String instanceId, {
  RequestStatus status = RequestStatus.pendingApproval,
}) => GlobalActivityItem(
  kind: GlobalActivityKind.request,
  service: ServiceKey.seerr,
  serviceType: ServiceType.discover,
  instanceId: instanceId,
  title: 'Charge',
  subtitle: 'Anna\u00A0· Movie',
  status: const MediaStatusInfo(
    availability: MediaAvailability.unknown,
    labelOverride: 'Pending',
  ),
  request: SeerrRequest(
    id: 1,
    status: status,
    type: 'movie',
    createdAt: '2026-10-08T10:00:00.000Z',
    media: const RequestMedia(
      id: 1,
      tmdbId: 1,
      mediaType: 'movie',
      title: 'Charge',
    ),
  ),
);

final _p9Sees = Profiles.p9.withSeerrPermissions(
  SeerrPermission.request.value | SeerrPermission.requestView.value,
);

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  GlobalActivityItem item, {
  double? desktopWidth,
}) => pumpWithProfile(
  tester,
  profile,
  surfaceSize: Size(desktopWidth ?? 390, 800),
  child: desktopWidth == null
      ? Scaffold(body: GlobalActivityItemTile(item: item))
      : MediaQuery(
          data: MediaQueryData(size: Size(desktopWidth, 800)),
          child: Scaffold(body: GlobalActivityItemTile(item: item)),
        ),
);

Iterable<String> _writes(ProfileHarness harness, String instanceId) => harness
    .network
    .requestsTo(instanceId)
    .where((r) => r.method != 'GET')
    .map((r) => '${r.method} ${r.uri.path}');

/// The table draws on a desktop build only, and the override has to be undone
/// inside the test body: `flutter_test` asserts on it before tear-downs run.
Future<void> _onDesktop(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  group("the phone's card", () {
    testWidgets('P1: a waiting request carries the pair, and no overflow '
        'menu', (tester) async {
      final harness = await _pump(tester, Profiles.p1, _row(WorldIds.seerr));

      expect(find.byTooltip('Approve Charge'), findsOneWidget);
      expect(find.byTooltip('Decline Charge'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
      expect(find.text('Approve request'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('P1: a request already answered carries nothing', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        _row(WorldIds.seerr, status: RequestStatus.approved),
      );

      expect(find.byTooltip('Approve Charge'), findsNothing);
      expect(find.byTooltip('Decline Charge'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('P1: Approve asks, sends, and the card says where it went', (
      tester,
    ) async {
      final harness = await _pump(tester, Profiles.p1, _row(WorldIds.seerr));

      await tester.tap(find.byTooltip('Approve Charge'));
      await harness.settle(tester);
      expect(find.text('Approve Charge'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Approve request'));
      await harness.settle(tester);

      expect(_writes(harness, WorldIds.seerr), [
        'POST /api/v1/request/1/approve',
      ]);
      expect(find.textContaining('Approved\u00A0· '), findsOneWidget);
      expect(find.byTooltip('Approve Charge'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('P2: the requester has no pair on her own request', (
      tester,
    ) async {
      final harness = await _pump(tester, Profiles.p2, _row(WorldIds.seerr));

      expect(find.byTooltip('Approve Charge'), findsNothing);
      expect(find.byTooltip('Decline Charge'), findsNothing);
      expect(find.text('Charge'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets("P9: on Sara's Seerr the pair is dimmed and says why", (
      tester,
    ) async {
      final harness = await _pump(tester, _p9Sees, _row(WorldIds.seerrFriend));

      final approve = find.byTooltip('Approve Charge');
      expect(approve, findsOneWidget);
      await tester.tap(approve);
      await tester.pump();

      expect(
        find.text("Your account on Jellyseerr can't approve requests."),
        findsOneWidget,
      );
      expect(find.text('Approve this request?'), findsNothing);
      expect(
        _writes(
          harness,
          WorldIds.seerrFriend,
        ).where((w) => w.startsWith('POST')),
        isEmpty,
      );

      await harness.unmount(tester);
    });
  });

  group("the desktop's table row", () {
    testWidgets('P1: the pair is in the row without a hover, as two small '
        'plates', (tester) async {
      await _onDesktop(() async {
        final harness = await _pump(
          tester,
          Profiles.p1,
          _row(WorldIds.seerr),
          desktopWidth: 1200,
        );

        expect(find.byType(AppCard), findsNothing);
        final approve = find.widgetWithText(FilledButton, 'Approve');
        final decline = find.widgetWithText(OutlinedButton, 'Decline');
        expect(approve, findsOneWidget);
        expect(decline, findsOneWidget);
        expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
        for (final button in [approve, decline]) {
          expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
        }

        await tester.tap(decline);
        await harness.settle(tester);
        expect(find.text('Decline this request?'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Decline request'));
        await harness.settle(tester);

        expect(_writes(harness, WorldIds.seerr), [
          'POST /api/v1/request/1/decline',
        ]);
        expect(find.text('Declined'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);

        await harness.unmount(tester);
      });
    });

    testWidgets('a narrower window keeps the pair and sheds cells instead', (
      tester,
    ) async {
      await _onDesktop(() async {
        final harness = await _pump(
          tester,
          Profiles.p1,
          _row(WorldIds.seerr),
          desktopWidth: 720,
        );

        expect(tester.takeException(), isNull);
        expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Decline'), findsOneWidget);

        await harness.unmount(tester);
      });
    });

    testWidgets('P2: the requester has none there either', (tester) async {
      await _onDesktop(() async {
        final harness = await _pump(
          tester,
          Profiles.p2,
          _row(WorldIds.seerr),
          desktopWidth: 1200,
        );

        expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
        expect(find.widgetWithText(OutlinedButton, 'Decline'), findsNothing);

        await harness.unmount(tester);
      });
    });
  });
}
