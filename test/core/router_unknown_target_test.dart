/// A link to something the app does not know lands somewhere that says so,
/// never on a different real thing.
///
/// `/settings/service/<unknown>` opened Seerr's form and `/activity/<unknown>`
/// opened the movies' activity, each under a link that named something else.
/// Activity's per-service pages are gone: each of those kinds is a redirect
/// to where that thing lives now, in one hop, and anything else under
/// `/activity` is All.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart';
import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/data/home_live.dart';

import '../test_helpers/settings_scope.dart';

void main() {
  late ProviderContainer container;
  late GoRouter router;

  Future<void> pump(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(),
        homeLivePollProvider.overrideWith((ref) {}),
        // The page's own polls: a test about routes ends before the
        // container that holds their timers is disposed.
        activityLivePollProvider.overrideWith((ref, tab) {}),
        featuredAdvancesProvider.overrideWithValue(false),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    router = container.read(routerProvider);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an unknown kind of activity lands on Activity, never on a '
      "service's queue", (tester) async {
    await pump(tester);

    router.go('/activity/not-a-kind');
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/activity');
    expect(
      tester.widget<ActivityPage>(find.byType(ActivityPage)).tab,
      ActivityTab.all,
    );
  });

  testWidgets('a kind it knew goes to where the thing lives now, in one '
      'hop', (tester) async {
    await pump(tester);

    for (final (old, now) in [
      ('/activity/movies', '/stack/radarr/queue'),
      ('/activity/series', '/stack/sonarr/queue'),
      ('/activity/music', '/stack/lidarr/queue'),
      ('/activity/discover', '/activity/requests'),
      ('/activity/discover?i=seerr-2', '/activity/requests?i=seerr-2'),
    ]) {
      router.go(old);
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), now, reason: old);
    }
    // Requests is Activity's own view, with the connection the link named.
    expect(
      tester.widget<ActivityPage>(find.byType(ActivityPage)).requestsOf,
      'seerr-2',
    );
  });
}
