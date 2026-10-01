import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/search/presentation/search_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The Search tab before anything is typed, on a household where none of the
/// services it queries is set up: one `Set up X` per service, each into its
/// own form, and a sentence that asks for any one of them.
void main() {
  Future<Uri?> pumpSearch(
    WidgetTester tester,
    ConfigProfile profile, {
    String? tap,
  }) async {
    Uri? landedOn;
    final harness = await ProfileHarness.start(profile);
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
        GoRoute(
          path: '/settings/service/:service',
          builder: (_, state) {
            landedOn = state.uri;
            return const Scaffold(body: Text('the form'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp.router(
          theme: AppTheme.darkTheme(),
          routerConfig: router,
        ),
      ),
    );
    await harness.settle(tester);
    if (tap != null) {
      await tester.ensureVisible(find.text(tap));
      await tester.tap(find.text(tap));
      await harness.settle(tester);
    }
    return landedOn;
  }

  // P2 without its Seerr: nothing at all is set up.
  final nothingSetUp = Profiles.p2.without(ServiceKey.seerr);

  testWidgets('nothing searchable set up: one Set up X per service, and "or"', (
    tester,
  ) async {
    await pumpSearch(tester, nothingSetUp);

    expect(find.text('No searchable service is set up'), findsOneWidget);
    expect(
      find.text(
        'Set up Seerr, Radarr, Sonarr, Lidarr, Bazarr, Jellyfin or Plex to '
        'search your libraries from here.',
      ),
      findsOneWidget,
    );
    for (final service in globalSearchServices) {
      expect(find.text('Set up ${service.title}'), findsOneWidget);
    }
    expect(find.text('Open Settings'), findsNothing);
    // One ink button, the rest ghosts: one thing to do first.
    expect(find.widgetWithText(FilledButton, 'Set up Seerr'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Set up Radarr'),
      findsOneWidget,
    );
  });

  testWidgets('each Set up X opens that service\'s own form', (tester) async {
    final landedOn = await pumpSearch(
      tester,
      nothingSetUp,
      tap: 'Set up Radarr',
    );

    expect(landedOn?.path, ServiceRoutes.setUp(ServiceKey.radarr));
  });

  testWidgets('P3, with Radarr, Sonarr and Seerr: no Set up, the services '
      'it will ask', (tester) async {
    await pumpSearch(tester, Profiles.p3);

    expect(find.text('Search across every service'), findsOneWidget);
    expect(find.textContaining('Set up'), findsNothing);
  });
}
