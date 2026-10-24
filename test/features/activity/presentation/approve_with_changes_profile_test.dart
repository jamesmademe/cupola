import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/presentation/service_all_screens.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Approve where you choose, end to end against the world's Seerr.
///
/// The sheet opens on where Seerr would send the request; a change of server,
/// profile or folder is written first (`PUT /api/v1/request/{id}`), with
/// every field the request already carried, and then approved. The world's
/// Seerr offers two profiles and two folders on every server and remembers
/// the edit, so the sheet has choices to open and the write can be read back.
///
/// Charge (request 1) waits naming no profile and no folder of its own, as
/// Seerr keeps a request asked for without the advanced options: it goes with
/// its server's. That is what makes comparing the choice with the request's
/// own fields wrong, and these tests fail if the app does it again.
void main() {
  List<NetworkRequest> writes(ProfileHarness harness) => harness.network
      .requestsTo(WorldIds.seerr)
      .where((r) => r.method != 'GET')
      .toList();

  int reads(ProfileHarness harness, String path) => harness.network
      .requestsTo(WorldIds.seerr)
      .where((r) => r.method == 'GET' && r.uri.path == path)
      .length;

  Future<ProfileHarness> openSheet(
    WidgetTester tester,
    ConfigProfile profile,
  ) async {
    final harness = await pumpWithProfile(
      tester,
      profile,
      child: const ServiceAllRequestsScreen(),
    );
    final approve = find.byTooltip('Approve Charge');
    await tester.ensureVisible(approve);
    await tester.pump();
    await tester.tap(approve);
    await harness.settle(tester);
    expect(find.text('Approve request'), findsOneWidget);
    return harness;
  }

  Future<void> confirm(WidgetTester tester, ProfileHarness harness) async {
    await tester.ensureVisible(find.text('Approve request'));
    await tester.tap(find.text('Approve request'));
    await harness.settle(tester);
  }

  testWidgets('P1, another profile: the edit goes first, with what the '
      'request carried, then the approval', (tester) async {
    final harness = await openSheet(tester, Profiles.p1);

    await tester.tap(find.text('Quality profile'));
    await harness.settle(tester);
    await tester.tap(find.text('Any').last);
    await harness.settle(tester);
    await confirm(tester, harness);

    final sent = writes(harness);
    expect(
      [for (final r in sent) '${r.method} ${r.uri.path}'],
      ['PUT /api/v1/request/1', 'POST /api/v1/request/1/approve'],
    );
    expect(sent.first.json, {
      'mediaType': 'movie',
      'is4k': false,
      'serverId': 0,
      'profileId': 2,
      'rootFolder': '/mnt/tank/media/films',
      'tags': [2],
    });
    // Seerr kept it: the request now names the profile it was sent with.
    final kept = harness.network.seerrState(WorldIds.seerr).requestEdits[1];
    expect(kept?.profileId, 2);
  });

  testWidgets('P1, the choice it opened on: approved, nothing edited', (
    tester,
  ) async {
    final harness = await openSheet(tester, Profiles.p1);

    await confirm(tester, harness);

    expect(
      [for (final r in writes(harness)) '${r.method} ${r.uri.path}'],
      ['POST /api/v1/request/1/approve'],
      reason:
          'Charge names no profile and no folder: it goes with Radarr\'s, '
          'and choosing those again changes nothing.',
    );
  });

  testWidgets('P6, another server: its id, its profile and its folder', (
    tester,
  ) async {
    final harness = await openSheet(tester, Profiles.p6);

    await tester.tap(find.text('Radarr Archive'));
    await harness.settle(tester);
    expect(find.text('SD-720p'), findsOneWidget);
    await confirm(tester, harness);

    final sent = writes(harness);
    expect(
      [for (final r in sent) '${r.method} ${r.uri.path}'],
      ['PUT /api/v1/request/1', 'POST /api/v1/request/1/approve'],
    );
    expect(sent.first.json, {
      'mediaType': 'movie',
      'is4k': false,
      'serverId': 2,
      'profileId': 3,
      'rootFolder': '/mnt/tank/media/archive',
      'tags': [2],
    });
  });

  testWidgets('P1, decided in Seerr meanwhile: the edit is refused, nothing '
      'is approved, the conflict is said and the lists read again', (
    tester,
  ) async {
    final harness = await openSheet(tester, Profiles.p1);
    harness.network.seerrState(WorldIds.seerr).decidedElsewhere.add(1);
    final before = reads(harness, '/api/v1/request');

    await tester.tap(find.text('Quality profile'));
    await harness.settle(tester);
    await tester.tap(find.text('Any').last);
    await harness.settle(tester);
    await confirm(tester, harness);

    expect(
      [for (final r in writes(harness)) '${r.method} ${r.uri.path}'],
      ['PUT /api/v1/request/1'],
    );
    expect(
      find.text('That request had already been updated somewhere else.'),
      findsOneWidget,
    );
    expect(reads(harness, '/api/v1/request'), greaterThan(before));
  });
}
