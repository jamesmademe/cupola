import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_screen.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_tab.dart';

import '../../../../test_helpers/profiles/profiles.dart';

/// `/activity/{type}` asks whether its service is set up before it reads one.
///
/// The Activity and Wanted tabs used to read their arr in `initState`, and the
/// service provider throws for a connection that is not set up, so the route
/// was a build that failed rather than a page that said why. The requests list
/// read a Seerr that was not there and offered a Retry that could ask nobody.
void main() {
  Finder setUpButton(String service) => find.ancestor(
    of: find.text('Set up $service'),
    matching: find.byWidgetPredicate((widget) => widget is FilledButton),
  );

  // P5 knows its Radarr and Sonarr only through Seerr: Cupola has no
  // connection to either, so the Movies activity has nothing of its own to
  // read.
  testWidgets('P5: Movies activity says Radarr is not set up', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p5,
      child: const ActivityScreen(serviceType: ServiceType.movies),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Radarr is not set up'), findsOneWidget);
    expect(setUpButton('Radarr'), findsOneWidget);
    // Not even the Radarr Seerr knows: that one is Seerr's, not Cupola's.
    expect(harness.network.requestsTo(WorldIds.radarr), isEmpty);

    await harness.unmount(tester);
  });

  testWidgets('P5: the Wanted tab says so too, instead of failing on the '
      'swipe', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p5,
      child: const ActivityScreen(serviceType: ServiceType.movies),
    );

    await tester.tap(find.text('Wanted'));
    await harness.settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Radarr is not set up'), findsOneWidget);
    expect(setUpButton('Radarr'), findsOneWidget);
    expect(harness.network.requestsTo(WorldIds.radarr), isEmpty);

    await harness.unmount(tester);
  });

  // P4 has no Seerr at all.
  testWidgets('P4: the requests list says Seerr is not set up and asks '
      'nothing', (tester) async {
    final harness = await ProfileHarness.start(Profiles.p4);
    final failures = _FailureLog();
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        observers: [failures],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const ActivityScreen(serviceType: ServiceType.discover),
        ),
      ),
    );
    await tester.pump(const Duration(minutes: 1));

    expect(find.text('Seerr is not set up'), findsOneWidget);
    expect(setUpButton('Seerr'), findsOneWidget);
    // The dead end this replaced: an error state whose Retry asked nobody.
    expect(find.text('Retry'), findsNothing);
    expect(failures.providers, isEmpty);

    await harness.unmount(tester);
  });

  testWidgets('P3: Series activity reads the Sonarr it has', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p3,
      child: const Scaffold(body: ActivityTab(serviceType: ServiceType.series)),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Sonarr is not set up'), findsNothing);
    expect(harness.network.requestsTo(WorldIds.sonarr), isNotEmpty);

    await harness.unmount(tester);
  });

  testWidgets('P3: the requests list reads the Seerr it has', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p3,
      child: const ActivityScreen(serviceType: ServiceType.discover),
    );

    expect(find.text('Seerr is not set up'), findsNothing);
    expect(harness.network.requestsTo(WorldIds.seerr), isNotEmpty);

    await harness.unmount(tester);
  });
}

/// Every provider that failed while the page was up.
final class _FailureLog extends ProviderObserver {
  final providers = <String>[];

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    providers.add('${context.provider.name ?? context.provider}: $error');
  }
}
