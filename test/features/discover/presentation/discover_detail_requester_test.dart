/// A title's page as the gate of its Seerr says: the requester reads no
/// service name and none of the operator's controls, and an account that may
/// not do something keeps the control, dimmed, saying why.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/presentation/discover_detail_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

Widget _page(WorldTitle title) => DiscoverDetailScreen(
  mediaId: title.tmdbId,
  mediaType: title.isSeries ? 'tv' : 'movie',
  heroTag: 'discover_${title.key}',
);

/// Every service name a requester never reads.
final _operatorNames = [
  for (final service in ServiceKey.values)
    if (service != ServiceKey.jellyfin && service != ServiceKey.plex)
      service.title,
];

void _expectNoServiceName() {
  for (final name in _operatorNames) {
    expect(find.textContaining(name), findsNothing, reason: name);
  }
}

void main() {
  group('the requester (P2)', () {
    testWidgets('her request waits: no service named, nothing to manage', (
      tester,
    ) async {
      // Charge: her own request, waiting for approval.
      final harness = await pumpWithProfile(
        tester,
        Profiles.p2,
        child: _page(WorldTitles.charge),
      );

      expect(find.text('Requested'), findsOneWidget);
      expect(find.text('Waiting for approval.'), findsOneWidget);
      expect(find.text('Manage'), findsNothing);
      expect(find.text('Open'), findsNothing);
      _expectNoServiceName();

      await harness.unmount(tester);
    });

    testWidgets('a title on its way says so, and not who is fetching it', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p2,
        child: _page(WorldTitles.spriteFright),
      );

      expect(find.text('Requested'), findsOneWidget);
      expect(find.text('On its way.'), findsOneWidget);
      expect(find.text('Manage'), findsNothing);
      _expectNoServiceName();

      await harness.unmount(tester);
    });

    testWidgets('a title nobody holds: Request, and no jump into the stack', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p2,
        child: _page(WorldTitles.agent327),
      );

      expect(find.text('Request'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
      _expectNoServiceName();

      await harness.unmount(tester);
    });

    testWidgets('movies only: a series keeps Request, dimmed, and says why', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p2.withSeerrPermissions(SeerrPermission.requestMovie.value),
        child: Scaffold(body: _page(WorldTitles.agent327)),
      );

      const reason = "You can't ask for series on this server.";
      expect(find.text('Request'), findsOneWidget);
      expect(find.text(reason), findsOneWidget);

      // Tappable, never disabled: the tap says why and opens nothing.
      await tester.tap(find.text('Request'));
      await tester.pump();
      expect(find.text(reason), findsNWidgets(2));
      expect(find.text('Submit request'), findsNothing);

      await harness.unmount(tester);
    });
  });

  group('the operator', () {
    testWidgets('P3, the key: the page he has always had', (tester) async {
      // No 4K server, so the waiting standard copy closes Request.
      final harness = await pumpWithProfile(
        tester,
        Profiles.p3,
        child: _page(WorldTitles.charge),
      );

      expect(find.text('Waiting for approval in Seerr.'), findsOneWidget);
      expect(find.text('Manage'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets("P9, on Sara's Seerr: Manage dimmed, and why on a tap", (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p9.withLens(ServiceKey.seerr, WorldIds.seerrFriend),
        child: Scaffold(body: _page(WorldTitles.charge)),
      );

      // His account may not manage media there: the control stays.
      expect(find.text('Manage'), findsOneWidget);
      // The operator reads the services: the state names Seerr.
      expect(find.text('Waiting for approval in Seerr.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pump();
      expect(
        // The server by the name it gives itself.
        find.text("Your account on Jellyseerr can't manage media."),
        findsOneWidget,
      );
      // No sheet opened.
      expect(find.text('Clear data'), findsNothing);

      await harness.unmount(tester);
    });
  });
}
