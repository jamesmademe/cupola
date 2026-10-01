import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/presentation/discover_detail_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Request reads both copies of a title once Seerr has a 4K server.
///
/// P6's Seerr sends to Radarr and to Radarr 4K. Coffee Run is on disk in HD
/// only; Elephants Dream is on disk in HD and downloading in 4K. P5's Seerr
/// has no 4K server.
void main() {
  final openRequest = find.byWidgetPredicate(
    (widget) => widget is FilledButton && widget.onPressed != null,
  );

  Future<ProfileHarness> pump(
    WidgetTester tester,
    ConfigProfile profile,
    WorldTitle title,
  ) async {
    final harness = await ProfileHarness.start(profile);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: DiscoverDetailScreen(
              mediaId: title.tmdbId,
              mediaType: 'movie',
              heroTag: 'discover_movie_${title.key}',
            ),
          ),
        ),
      ),
    );
    await harness.settle(tester);
    return harness;
  }

  testWidgets('P6: a film on disk in HD only can be requested in 4K, on the '
      '4K server', (tester) async {
    final harness = await pump(tester, Profiles.p6, WorldTitles.coffeeRun);

    // It read "Available" and offered nothing, on a Seerr with a 4K server.
    final request = find.ancestor(
      of: find.text('Request'),
      matching: openRequest,
    );
    expect(request, findsOneWidget);
    expect(find.text('Only the 4K copy can be requested.'), findsOneWidget);

    await tester.ensureVisible(request);
    await tester.tap(request);
    await harness.settle(tester);

    // The 4K server alone, and its profile: no standard server is offered
    // for a copy already on disk.
    expect(find.text('Ultra-HD'), findsOneWidget);
    expect(find.text('HD-1080p'), findsNothing);
    await tester.tap(find.text('Submit request'));
    await harness.settle(tester);

    final sent = harness.network
        .requestsTo(WorldIds.seerr)
        .where((r) => r.method == 'POST' && r.uri.path == '/api/v1/request')
        .single
        .json;
    expect(sent, containsPair('is4k', true));
    expect(sent, containsPair('serverId', 1));

    await harness.unmount(tester);
  });

  testWidgets('P6: a film on disk in HD and on its way in 4K stays closed', (
    tester,
  ) async {
    final harness = await pump(tester, Profiles.p6, WorldTitles.elephantsDream);

    expect(
      find.ancestor(of: find.text('Available'), matching: openRequest),
      findsNothing,
    );
    expect(
      find.text('Already in your library, nothing to request.'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('P5: without a 4K server, a film on disk in HD stays closed', (
    tester,
  ) async {
    final harness = await pump(tester, Profiles.p5, WorldTitles.coffeeRun);

    expect(
      find.ancestor(of: find.text('Request'), matching: openRequest),
      findsNothing,
    );
    expect(
      find.text('Already in your library, nothing to request.'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });
}
