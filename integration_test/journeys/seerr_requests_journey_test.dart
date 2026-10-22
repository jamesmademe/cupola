/// The requests of a household member, the family of G-15 to G-17 and G-20,
/// against the world of L7.
///
/// The world: the household Seerr, Anna (who may only ask, with a quota of
/// three movies and six seasons every seven days), Luca (who may ask for 4K
/// and is approved on the spot), seven requests in every state, and three
/// titles left free for these flows. The seed picks the free titles at every
/// run, so the journeys read them from the world's own file.
///
/// What each journey proves, in the app's own words:
///
/// - **G-15**: a member asks for a movie. `Request`, the sheet that sends
///   the title alone, `Submit request`, `Request submitted`. The server holds
///   the request, waiting for whoever runs the server.
/// - **G-16**: a member asks for a series, and says which season. `Seasons`,
///   `Season 2`, `Submit request`. The server holds the request with that
///   season and no other.
/// - **G-17**: a member asks for 4K, which her account may not have. The
///   app draws no 4K choice at all, and the server refuses the write the
///   app therefore never sends.
/// - **G-20**: a member takes back her own request. `Cancel request?`,
///   `Keep it`, then `Cancel request` and `Request canceled`.
///
/// The app is hers: only her Seerr account is set up, so the audience is
/// hers and no service name is on the screen. Every journey cleans up the
/// request it made, through the same API the app used to write it, so the
/// world's own requests are never touched.
@Tags(['e2e'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/requests/presentation/widgets/requester_request_row.dart';

import 'testlab_journey_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'G-15 · a household member asks for a movie',
    (tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final app = await LabApp.asRequester(tester);
      final title = app.world.askTitle;

      await app.openTitleFromSearch(
        tester,
        type: 'movie',
        tmdbId: title.tmdbId,
        title: title.title,
      );
      await app.surface.see('Request');
      await tester.tap(find.widgetWithText(FilledButton, 'Request'));

      // The sheet of a requester: the title alone, with the quality the
      // account may have, and no server, no profile and no folder.
      await app.surface.see('Submit request');
      await app.surface.see('Quality');
      await app.surface.see('Standard');
      expect(
        app.surface.draws('Quality profile'),
        isFalse,
        reason: 'the requester is offered no profile',
      );
      expect(
        app.surface.draws('Root folder'),
        isFalse,
        reason: 'the requester is offered no folder',
      );

      await tester.tap(find.text('Submit request'));
      await app.surface.see('Request submitted');

      // The server's own record of the same fact, read through the app's
      // client: her request, waiting.
      final mine = await app.seerr.getRequests();
      final made = mine
          .where((request) => request.media?.tmdbId == title.tmdbId)
          .toList();
      expect(made, hasLength(1), reason: 'the server holds one request');
      expect(made.single.status, RequestStatus.pendingApproval);
      expect(made.single.requestedBy?.id, app.world.requesterId);

      // The lab's cleanup, even when the journey fails halfway.
      app.trackRequest(made.single.id);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'G-16 · a household member asks for a series, and says which season',
    (tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final app = await LabApp.asRequester(tester);
      final series = app.world.seriesTitle;

      await app.openTitleFromSearch(
        tester,
        type: 'tv',
        tmdbId: series.tmdbId,
        title: series.title,
      );
      await app.surface.see('Request');
      await tester.tap(find.widgetWithText(FilledButton, 'Request'));

      // The seasons the server may still take, one chip each.
      await app.surface.see('Seasons');
      await app.surface.see('Season ${series.season}');
      await app.surface.see('Submit request');

      // Only the season the world left free stays ticked: the others are
      // left alone, as a person would.
      for (final chip in find.byType(FilterChip).evaluate()) {
        final label = (chip.widget as FilterChip).label;
        if (label is! Text) continue;
        final number = label.data;
        if (number == null || number == 'Season ${series.season}') continue;
        await tester.tap(find.text(number).first);
        await settle(tester, const Duration(milliseconds: 400));
      }

      await tester.tap(find.text('Submit request'));
      await app.surface.see('Request submitted');

      final mine = await app.seerr.getRequests();
      final made = mine
          .where((request) => request.media?.tmdbId == series.tmdbId)
          .toList();
      expect(made, hasLength(1), reason: 'the server holds one request');
      expect(made.single.status, RequestStatus.pendingApproval);
      expect(
        made.single.seasons?.map((season) => season.seasonNumber).toList(),
        [series.season],
        reason: 'the request names the season that was asked for',
      );

      app.trackRequest(made.single.id);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'G-17 · a household member asks for 4K, which her account may not have',
    (tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final app = await LabApp.asRequester(tester);
      final title = app.world.askTitle;

      await app.openTitleFromSearch(
        tester,
        type: 'movie',
        tmdbId: title.tmdbId,
        title: title.title,
      );
      await app.surface.see('Request');
      await tester.tap(find.widgetWithText(FilledButton, 'Request'));
      await app.surface.see('Submit request');

      // The app's own answer: the copy is chosen only where the account and
      // the server both take 4K, so the sheet says which copy it is and
      // draws no choice that could not be made.
      await app.surface.see('Quality');
      await app.surface.see('Standard');
      expect(
        app.surface.draws('4K'),
        isFalse,
        reason: 'no 4K choice is drawn for an account that may not take it',
      );

      // The server's answer to the write the app therefore never sends: the
      // account may not ask for 4K, and the request is not born.
      final before = (await app.seerr.getRequests()).length;
      Object? refused;
      try {
        await app.seerr.createRequest(
          mediaType: 'movie',
          mediaId: title.tmdbId,
          is4k: true,
        );
      } on Object catch (error) {
        refused = error;
      }
      expect(refused, isNotNull, reason: 'the server took a 4K request');
      expect(
        seerrRefusalOf(refused!),
        anyOf(SeerrRefusal.requestNotAllowed, SeerrRefusal.permissionDenied),
      );
      final after = await app.seerr.getRequests();
      expect(
        after.length,
        before,
        reason: 'the refused request was born anyway',
      );
      expect(
        after.where((request) => request.media?.tmdbId == title.tmdbId),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'G-20 · a household member takes back her own request',
    (tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final app = await LabApp.asRequester(tester);
      final title = app.world.askTitle;

      // She asks first, the way she would: the journey takes back a request
      // of her own that waits.
      await app.openTitleFromSearch(
        tester,
        type: 'movie',
        tmdbId: title.tmdbId,
        title: title.title,
      );
      await app.surface.see('Request');
      await tester.tap(find.widgetWithText(FilledButton, 'Request'));
      await app.surface.see('Submit request');
      await tester.tap(find.text('Submit request'));
      await app.surface.see('Request submitted');

      final made = (await app.seerr.getRequests())
          .where((request) => request.media?.tmdbId == title.tmdbId)
          .single;
      app.trackRequest(made.id);

      // Her own list: the request that waits, with the one thing she may do.
      await app.go(tester, ServiceRoutes.requests);
      await app.surface.see(title.title);
      expect(
        app.surface.count(RequesterWaitingCard),
        greaterThanOrEqualTo(1),
        reason: 'her list draws no card for a request that waits',
      );

      // The question, and the way out of it: the request stays.
      await app.tapIn(
        tester,
        find.widgetWithText(OutlinedButton, 'Cancel request').first,
      );
      await app.surface.see('Cancel request?');
      await app.surface.see('Keep it');
      await tester.tap(find.widgetWithText(TextButton, 'Keep it'));
      await app.surface.unsee('Cancel request?');
      expect(
        (await app.seerr.getRequests())
            .where((request) => request.id == made.id)
            .length,
        1,
        reason: 'keeping the request took it away',
      );

      // And the other answer: the request is gone.
      await app.tapIn(
        tester,
        find.widgetWithText(OutlinedButton, 'Cancel request').first,
      );
      await app.surface.see('Cancel request?');
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel request'));
      await app.surface.see('Request canceled');

      expect(
        (await app.seerr.getRequests()).where(
          (request) => request.id == made.id,
        ),
        isEmpty,
        reason: 'the server still holds the request',
      );
      expect(await app.server.request(made.id), isNull);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
