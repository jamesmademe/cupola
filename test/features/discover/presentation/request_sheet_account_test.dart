/// The request sheet of an account that may not choose where requests go:
/// the title alone, its quality and its seasons, under who approves it and how
/// much of the quota is left. No server, profile or folder, and none of
/// Seerr's servers read. The key's sheet, beside it, picks them and the
/// seasons.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/domain/seerr_request_gate.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/presentation/widgets/request_bottom_sheet.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

Widget _sheet(
  WorldTitle title, {
  SeerrRequestCopies copies = SeerrRequestCopies.both,
  VoidCallback? onDone,
}) => Scaffold(
  body: SingleChildScrollView(
    child: RequestBottomSheet(
      mediaId: title.tmdbId,
      mediaType: title.isSeries ? 'tv' : 'movie',
      copies: copies,
      title: title.title,
      onRequestComplete: onDone ?? () {},
    ),
  ),
);

List<NetworkRequest> _posts(ProfileHarness harness, String seerr) => harness
    .network
    .requestsTo(seerr)
    .where((r) => r.method == 'POST' && r.path == '/api/v1/request')
    .toList();

Map<String, Object?> _sent(ProfileHarness harness, String seerr) =>
    (jsonDecode(_posts(harness, seerr).single.body) as Map)
        .cast<String, Object?>();

int _bits(List<SeerrPermission> permissions) =>
    permissions.fold(0, (mask, permission) => mask | permission.value);

void main() {
  group('the requester (P2)', () {
    testWidgets('a movie: no pickers, no profile, the server decides', (
      tester,
    ) async {
      var done = false;
      final harness = await pumpWithProfile(
        tester,
        Profiles.p2,
        child: _sheet(WorldTitles.bigBuckBunny, onDone: () => done = true),
      );

      for (final picker in ['Server', 'Quality profile', 'Root folder']) {
        expect(find.text(picker), findsNothing, reason: picker);
      }
      expect(find.text('Quality'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(
        find.text('Requests on this server are approved by its owner.'),
        findsOneWidget,
      );
      // None of the operator's servers was read.
      expect(
        harness.network
            .requestsTo(WorldIds.seerr)
            .where((r) => r.path.startsWith('/api/v1/service/')),
        isEmpty,
      );

      await tester.tap(find.text('Submit request'));
      await harness.settle(tester);

      expect(_sent(harness, WorldIds.seerr), {
        'mediaType': 'movie',
        'mediaId': WorldTitles.bigBuckBunny.tmdbId,
        'is4k': false,
      });
      expect(done, isTrue);

      await harness.unmount(tester);
    });

    testWidgets('a series, season by season where the server allows it', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p2,
        child: _sheet(WorldTitles.agent327),
      );

      for (final season in [1, 2, 3]) {
        expect(find.text('Season $season'), findsOneWidget);
      }
      await tester.tap(find.text('Season 3'));
      await tester.pump();
      await tester.tap(find.text('Submit request'));
      await harness.settle(tester);

      expect(_sent(harness, WorldIds.seerr)['seasons'], [1, 2]);

      await harness.unmount(tester);
    });

    testWidgets('her quota is reached: Request dims, says so, sends nothing', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p2.withBehaviour(
          WorldIds.seerr,
          ConnectionBehaviour.quotaReached,
        ),
        child: _sheet(WorldTitles.bigBuckBunny),
      );

      const limit =
          "You've asked for 5 movies in the last 7 days, the most this "
          'server allows.';
      expect(find.text(limit), findsOneWidget);

      await tester.tap(find.text('Submit request'));
      await tester.pump();
      expect(find.text(limit), findsNWidgets(2));
      expect(_posts(harness, WorldIds.seerr), isEmpty);

      await harness.unmount(tester);
    });

    testWidgets('a refusal is said in the server\'s own terms', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p2,
        child: _sheet(WorldTitles.bigBuckBunny),
      );
      harness.network.on(
        WorldIds.seerr,
        'POST',
        '/api/v1/request',
        (_) => NetworkReply.json({
          'message': 'Request for this media already exists.',
        }, status: 409),
      );

      await tester.tap(find.text('Submit request'));
      await harness.settle(tester);

      expect(find.text('Already requested.'), findsOneWidget);
      expect(find.textContaining('Seerr'), findsNothing);

      await harness.unmount(tester);
    });
  });

  testWidgets('P2: a series with nothing left to ask for says so', (
    tester,
  ) async {
    var done = false;
    final harness = await pumpWithProfile(
      tester,
      Profiles.p2,
      child: _sheet(WorldTitles.agent327, onDone: () => done = true),
    );
    // A success status that made no request.
    harness.network.on(
      WorldIds.seerr,
      'POST',
      '/api/v1/request',
      (_) => NetworkReply.json({
        'message': 'No seasons available to request',
      }, status: 202),
    );

    await tester.tap(find.text('Submit request'));
    await harness.settle(tester);

    expect(
      find.text('Every season is already on the server or requested.'),
      findsOneWidget,
    );
    expect(find.text('Request submitted'), findsNothing);
    expect(done, isFalse);

    await harness.unmount(tester);
  });

  group('the operator with the key (P1)', () {
    testWidgets('picks the server and the profile, and the seasons too', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p1,
        child: _sheet(WorldTitles.agent327),
      );

      expect(find.text('Quality profile'), findsOneWidget);
      for (final season in [1, 2, 3]) {
        expect(find.text('Season $season'), findsOneWidget);
      }
      await tester.tap(find.text('Season 3'));
      await tester.pump();
      await tester.tap(find.text('Submit request'));
      await harness.settle(tester);

      final sent = _sent(harness, WorldIds.seerr);
      expect(sent['seasons'], [1, 2]);
      expect(sent['profileId'], isNotNull);
      expect(sent['serverId'], isNotNull);

      await harness.unmount(tester);
    });

    testWidgets('a server that takes a series whole: no chips, the seasons '
        'said and sent', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p1,
        overrides: [
          seerrServerFactsProvider.overrideWith(
            (ref, id) async => SeerrServerFacts.fromPublicSettings(const {
              'initialized': true,
              'partialRequestsEnabled': false,
            }),
          ),
        ],
        child: _sheet(WorldTitles.agent327),
      );

      expect(find.byType(FilterChip), findsNothing);
      expect(find.text('Seasons 1, 2 and 3'), findsOneWidget);
      await tester.tap(find.text('Submit request'));
      await harness.settle(tester);

      expect(_sent(harness, WorldIds.seerr)['seasons'], [1, 2, 3]);

      await harness.unmount(tester);
    });

    testWidgets('every season ticked still names them: Seerr would ask again '
        'for one somebody is waiting for', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p1,
        child: _sheet(WorldTitles.agent327),
      );

      await tester.tap(find.text('Submit request'));
      await harness.settle(tester);

      expect(_sent(harness, WorldIds.seerr)['seasons'], [1, 2, 3]);

      await harness.unmount(tester);
    });
  });

  group("the operator's account on Sara's Seerr (P9)", () {
    final friend = Profiles.p9.withLens(ServiceKey.seerr, WorldIds.seerrFriend);

    testWidgets('4K where the account and the server both take it', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        friend.withSeerrPermissions(
          _bits([SeerrPermission.request, SeerrPermission.request4k]),
        ),
        child: _sheet(WorldTitles.bigBuckBunny),
      );

      // He is told why there are no pickers, about the account.
      expect(
        find.text("Your account on Jellyseerr can't choose where requests go."),
        findsOneWidget,
      );
      await tester.tap(find.text('4K'));
      await tester.pump();
      await tester.tap(find.text('Submit request'));
      await harness.settle(tester);

      expect(_sent(harness, WorldIds.seerrFriend), containsPair('is4k', true));

      await harness.unmount(tester);
    });

    testWidgets('no 4K for an account that may not ask for it', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        friend,
        child: _sheet(WorldTitles.bigBuckBunny),
      );

      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('4K'), findsNothing);

      await harness.unmount(tester);
    });
  });
}
