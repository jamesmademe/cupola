/// A link to something the app does not know lands somewhere that says so,
/// never on a different real thing.
///
/// `/settings/service/<unknown>` opened Seerr's form and `/activity/<unknown>`
/// opened the movies' activity, each under a link that named something else.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/features/activity/presentation/activity_screen.dart';

import '../test_helpers/settings_scope.dart';

void main() {
  testWidgets('an unknown kind of activity lands on Activity, never on the '
      'movies\'', (tester) async {
    final container = ProviderContainer(
      overrides: await settingsScopeOverrides(),
      retry: (_, _) => null,
    );
    final router = container.read(routerProvider);
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

    router.go('/activity/not-a-kind');
    await tester.pumpAndSettle();

    expect(find.byType(ActivityScreen), findsNothing);
    expect(router.state.uri.toString(), '/activity');

    // A kind it knows still opens its own.
    router.go('/activity/series');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ActivityScreen>(find.byType(ActivityScreen))
          .serviceType
          .name,
      'series',
    );

    // The Activity tab polls: its timers go with the container.
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(minutes: 1));
  });
}
