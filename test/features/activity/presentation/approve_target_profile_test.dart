import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_actions.dart';
import 'package:cupola/features/activity/presentation/widgets/requests_list.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The approve confirmation names the server a request goes to, against the
/// servers Seerr's own settings list.
///
/// P6's Seerr sends standard films to Radarr and 4K ones to Radarr 4K, and
/// Cupola connects to both (the second labelled `4K`). P5's Seerr sends to a
/// Radarr Cupola has no connection to.
void main() {
  Future<ProfileHarness> pump(
    WidgetTester tester,
    ConfigProfile profile, {
    Widget child = const Scaffold(body: RequestsList()),
    void Function(ProfileNetwork network)? routes,
  }) async {
    final harness = await ProfileHarness.start(profile);
    routes?.call(harness.network);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(theme: AppTheme.darkTheme(), home: child),
      ),
    );
    await harness.settle(tester);
    return harness;
  }

  /// Opens the confirmation of the first waiting request on the list.
  Future<void> openApprove(WidgetTester tester, ProfileHarness harness) async {
    final approve = find.text('Approve').first;
    await tester.ensureVisible(approve);
    await tester.tap(approve);
    await harness.settle(tester);
  }

  testWidgets('P6: a standard request goes to Radarr, by name', (tester) async {
    final harness = await pump(tester, Profiles.p6);
    await openApprove(tester, harness);

    // It said "goes to the service that handles it", whichever that was.
    expect(
      find.text('Charge goes to Radarr and starts downloading.'),
      findsOneWidget,
    );
    expect(find.textContaining('the service that handles it'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P6: a 4K request goes to Radarr 4K', (tester) async {
    final harness = await pump(
      tester,
      Profiles.p6,
      routes: (network) => network.on(
        WorldIds.seerr,
        'GET',
        '/api/v1/request',
        (_) => NetworkReply.json({
          'pageInfo': {'pages': 1, 'pageSize': 50, 'results': 1, 'page': 1},
          'results': [
            {
              'id': 8,
              'status': 1,
              'type': 'movie',
              'is4k': true,
              'createdAt': _scriptedCreatedAt.toIso8601String(),
              'requestedBy': {'id': 3, 'displayName': WorldPeople.luca},
              'media': {
                'id': WorldTitles.sintel.tmdbId,
                'tmdbId': WorldTitles.sintel.tmdbId,
                'mediaType': 'movie',
                'status': 5,
                'status4k': 2,
              },
            },
          ],
        }),
      ),
    );
    await openApprove(tester, harness);

    expect(
      find.text('Sintel goes to Radarr · 4K and starts downloading.'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('P5: a Radarr Cupola has no connection to is said to be', (
    tester,
  ) async {
    final harness = await pump(tester, Profiles.p5);
    await openApprove(tester, harness);

    expect(
      find.text(
        'Charge goes to Radarr and starts downloading. Cupola has no '
        'connection to that server.',
      ),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('P6: Seerr settings that did not answer leave the server '
      'unnamed, never invented', (tester) async {
    final harness = await pump(
      tester,
      Profiles.p6,
      routes: (network) => network.on(
        WorldIds.seerr,
        'GET',
        '/api/v1/settings/radarr',
        (_) => NetworkReply.json({'message': 'boom'}, status: 500),
      ),
    );
    await openApprove(tester, harness);

    expect(
      find.text("Charge goes to Seerr's Radarr and starts downloading."),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('P6: a caller holding only the id has the request read first', (
    tester,
  ) async {
    final harness = await pump(
      tester,
      Profiles.p6,
      child: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => ActivityActions.approveRequest(
              context,
              ref,
              instanceId: '',
              requestId: 1,
              title: 'Charge',
            ),
            child: const Text('Decide'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Decide'));
    await harness.settle(tester);

    expect(
      harness.network
          .requestsTo(WorldIds.seerr)
          .map((r) => '${r.method} ${r.uri.path}'),
      containsAll(['GET /api/v1/request/1', 'GET /api/v1/settings/radarr']),
    );
    expect(
      find.text('Charge goes to Radarr and starts downloading.'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });
}

/// A creation time for a scripted request: any parseable instant will do.
final DateTime _scriptedCreatedAt = DateTime.utc(2026, 9, 30, 10);
