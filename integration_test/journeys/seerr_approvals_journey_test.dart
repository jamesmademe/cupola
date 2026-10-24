/// The approvals of whoever runs the stack, the family of G-18 and G-19,
/// against the world of L7.
///
/// The world: the household Seerr with its operator (the key), Anna (who may
/// only ask) and the seven requests in every state. A member asks first, in
/// the app of a member; the operator answers in the app of the operator,
/// on the same server and the same data.
///
/// What each journey proves, in the app's own words:
///
/// - **G-18**: the operator answers a request with changes. `Approve`, the
///   sheet `Approve <title>` with its `Server`, `Quality profile` and
///   `Root folder`, `Approve request`, and the row's `Approved · sent to
///   Radarr`. Radarr holds the movie with the profile that was chosen.
/// - **G-19**: the operator says no. `Decline`, `Decline this request?`,
///   `Decline request`, and the row's `Declined`. The server holds the
///   request, declined.
///
/// The app is the operator's: the Seerr with its key, and the arrs of the
/// lab. The world's own requests are never answered here: every journey
/// answers a request it made itself, and cleans it up afterwards.
@Tags(['e2e'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';

import 'testlab_journey_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('G-18 · the operator answers a request with changes', (
    tester,
  ) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

    // The member asks first: the request has to exist, and it has to be
    // hers, because that is who the operator answers.
    final member = await LabApp.asRequester(tester);
    final title = member.world.approveTitle;
    await member.openTitleFromSearch(
      tester,
      type: 'movie',
      tmdbId: title.tmdbId,
      title: title.title,
    );
    await member.surface.see('Request');
    await tester.tap(find.widgetWithText(FilledButton, 'Request'));
    await member.surface.see('Submit request');
    await tester.tap(find.text('Submit request'));
    await member.surface.see('Request submitted');
    final asked = (await member.seerr.getRequests())
        .where((request) => request.media?.tmdbId == title.tmdbId)
        .single;
    member.trackRequest(asked.id);
    expect(asked.status, RequestStatus.pendingApproval);

    // The operator's app, on the same server.
    final app = await member.reopenAs(tester, LabProfile.operator);
    await app.go(tester, ServiceRoutes.activityRequests);
    await app.surface.see(title.title);

    // The row of that request, and the control that answers it.
    final row = find.ancestor(
      of: find.text(title.title),
      matching: find.byType(DecisionRow),
    );
    expect(row, findsWidgets, reason: 'the queue draws no row for it');
    await app.tapIn(
      tester,
      find.descendant(
        of: row,
        matching: find.widgetWithText(FilledButton, 'Approve'),
      ),
    );

    // The sheet: where it goes, and what it goes with.
    await app.surface.see('Approve ${title.title}');
    await app.surface.see('Server');
    await app.surface.see('Quality profile');
    await app.surface.see('Root folder');
    await app.surface.see('Approve request');

    // The change: another quality profile, the one the operator picked.
    final profiles = await app.radarr.profiles();
    final chosen = profiles.firstWhere(
      (profile) => profile.id != 1,
      orElse: () => profiles.first,
    );
    await app.tapIn(tester, find.text('Quality profile').first);
    await app.surface.see(chosen.name);
    await app.tapIn(tester, find.text(chosen.name).last);
    await settle(tester, const Duration(milliseconds: 600));
    await app.surface.see(chosen.name);

    await app.tapIn(tester, find.text('Approve request'));
    await app.surface.seePart('Approved');

    // The server's own record: the movie is in Radarr, with the profile
    // that was chosen and the folder of the server.
    Map<String, dynamic>? movie;
    final end = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(end)) {
      movie = await app.radarr.movie(title.tmdbId);
      if (movie != null) break;
      await settle(tester, const Duration(seconds: 1));
    }
    expect(movie, isNotNull, reason: 'Radarr never took the movie');
    expect(movie!['qualityProfileId'], chosen.id);
    expect(movie['rootFolderPath'], '/media/movies');

    // The request is answered, on the server too.
    final answered = await app.server.request(asked.id);
    expect(answered?['status'], 2, reason: 'the request is not approved');

    // The lab's cleanup: the movie out of Radarr, the request out of Seerr,
    // and the exclusion the search may have left.
    final movieId = movie['id'] as int;
    await app.radarr.deleteMovie(movieId);
    await app.radarr.deleteExclusionsOf(title.title);
  }, timeout: const Timeout(Duration(minutes: 15)));

  testWidgets('G-19 · the operator declines a request', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

    // The member asks first, as in G-18.
    final member = await LabApp.asRequester(tester);
    final title = member.world.askTitle;
    await member.openTitleFromSearch(
      tester,
      type: 'movie',
      tmdbId: title.tmdbId,
      title: title.title,
    );
    await member.surface.see('Request');
    await tester.tap(find.widgetWithText(FilledButton, 'Request'));
    await member.surface.see('Submit request');
    await tester.tap(find.text('Submit request'));
    await member.surface.see('Request submitted');
    final asked = (await member.seerr.getRequests())
        .where((request) => request.media?.tmdbId == title.tmdbId)
        .single;
    member.trackRequest(asked.id);

    // The operator's app says no.
    final app = await member.reopenAs(tester, LabProfile.operator);
    await app.go(tester, ServiceRoutes.activityRequests);
    await app.surface.see(title.title);
    final row = find.ancestor(
      of: find.text(title.title),
      matching: find.byType(DecisionRow),
    );
    expect(row, findsWidgets, reason: 'the queue draws no row for it');
    await app.tapIn(
      tester,
      find.descendant(
        of: row,
        matching: find.widgetWithText(OutlinedButton, 'Decline'),
      ),
    );

    // The question, in neutral ink, and the answer.
    await app.surface.see('Decline this request?');
    await app.tapIn(
      tester,
      find.widgetWithText(FilledButton, 'Decline request'),
    );
    await app.surface.see('Request declined');
    await app.surface.see('Declined');

    // The server's own record: the request is declined, and it is still on
    // record.
    final declined = await app.server.request(asked.id);
    expect(declined, isNotNull, reason: 'the request is gone');
    expect(declined?['status'], 3, reason: 'the request is not declined');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
