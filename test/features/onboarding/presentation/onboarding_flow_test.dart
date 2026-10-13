/// The way in against servers that answer: what is saved, when, and where the
/// person lands.
///
/// `onboarding_screen_test.dart` holds what the screens draw with no server
/// behind them (a transport that refuses everything). These cases need a
/// service to say yes, so they run on a configuration profile's fake network,
/// and the first of them mounts the app's own router to prove the whole way
/// out: the flag, the redirect and the Home.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/network/host_reach.dart';
import 'package:cupola/core/router.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/onboarding/presentation/onboarding_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';
import '../../../test_helpers/onboarding_router.dart';
import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/reel_finders.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  group('leaving the way in', () {
    testWidgets('a service that answers ends a first run on the Home, with '
        'the flag on', (tester) async {
      final flow = await _pumpFlow(tester, Profiles.p3, appRouter: true);
      final router = flow.container.read(routerProvider);
      expect(router.state.uri.path, ServiceRoutes.welcome);
      expect(find.byType(OnboardingScreen), findsOneWidget);

      await _openService(tester, flow, 'Radarr');
      await _fill(tester, flow, WorldHosts.radarr, WorldIds.radarr);
      await _tap(tester, flow, 'Test connection');
      expect(find.text('Radarr answered.'), findsOneWidget);
      // Nothing is saved until it has: the run could still be abandoned.
      expect(flow.container.read(settingsProvider).radarrUrl, isEmpty);
      expect(flow.container.read(onboardingCompletedProvider), isFalse);

      await _tap(tester, flow, 'Go to Home');

      // Saved, flagged, and out: the router never sends anyone away from the
      // way in, so leaving it is the screen's to do.
      expect(router.state.uri.path, ServiceRoutes.home);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(flow.container.read(onboardingCompletedProvider), isTrue);
      final saved = flow.container.read(settingsProvider);
      expect(saved.radarrUrl, WorldHosts.radarr);
      expect(saved.radarrApiKey, worldKey(WorldIds.radarr));
      // And it is the flag on disk that a next launch reads.
      expect(
        await flow.container
            .read(settingsServiceProvider)
            .loadOnboardingComplete(),
        isTrue,
      );

      await flow.harness.unmount(tester);
    });

    testWidgets('a run cut short after its first connection opens the Home, '
        'not the Welcome again', (tester) async {
      // Saved, never flagged: the app was closed on the step that answered.
      final flow = await _pumpFlow(
        tester,
        Profiles.p3,
        settings: settingsWithServices([ServiceKey.radarr]),
        appRouter: true,
      );
      final router = flow.container.read(routerProvider);

      expect(router.state.uri.path, ServiceRoutes.home);
      expect(find.byType(HomeScreen), findsOneWidget);

      await flow.harness.unmount(tester);
    });
  });

  group('the primary action', () {
    testWidgets('reads Continue for Seerr and Go to Home for Radarr, once '
        'they answer', (tester) async {
      final flow = await _pumpFlow(tester, Profiles.p3);

      // Seerr, which the door opens on, knows others: something follows it.
      await _tap(tester, flow, 'Set up a service');
      await _fill(tester, flow, WorldHosts.seerr, WorldIds.seerr);
      expect(_primary('Test connection'), findsOneWidget);
      await _tap(tester, flow, 'Test connection');
      expect(find.text('Seerr answered.'), findsOneWidget);
      expect(_primary('Continue'), findsOneWidget);
      expect(_primary('Go to Home'), findsNothing);

      // Radarr does not: the way in ends with it.
      await _tap(tester, flow, 'Start with another service');
      await _tap(tester, flow, 'Set up Radarr');
      expect(_primary('Test connection'), findsOneWidget);
      await _fill(tester, flow, WorldHosts.radarr, WorldIds.radarr);
      await _tap(tester, flow, 'Test connection');
      expect(find.text('Radarr answered.'), findsOneWidget);
      expect(_primary('Go to Home'), findsOneWidget);
      expect(_primary('Continue'), findsNothing);

      await flow.harness.unmount(tester);
    });

    // A verdict is about what was typed when it was given. Editing after
    // "answered" and still being offered the way forward would save an
    // address or a key nobody tested, which is the one thing the way in
    // promises not to do.
    for (final (field, what) in [(0, 'address'), (1, 'key')]) {
      testWidgets('editing the $what after it answered asks for a new test', (
        tester,
      ) async {
        final flow = await _pumpFlow(tester, Profiles.p3);
        await _openService(tester, flow, 'Radarr');
        await _fill(tester, flow, WorldHosts.radarr, WorldIds.radarr);
        await _tap(tester, flow, 'Test connection');
        expect(find.text('Radarr answered.'), findsOneWidget);
        expect(_primary('Go to Home'), findsOneWidget);

        final input = find.byType(TextField).at(field);
        final typed = tester.widget<TextField>(input).controller!.text;
        await tester.enterText(input, '${typed}x');
        await flow.harness.settle(tester);

        expect(find.text('Radarr answered.'), findsNothing);
        expect(_primary('Test connection'), findsOneWidget);
        expect(_primary('Go to Home'), findsNothing);
        // Nothing was saved on the way, and nothing is for the asking.
        expect(flow.container.read(settingsProvider).radarrUrl, isEmpty);

        // Put back as it was tested, the answer holds again.
        await tester.enterText(input, typed);
        await flow.harness.settle(tester);
        expect(_primary('Go to Home'), findsOneWidget);

        await flow.harness.unmount(tester);
      });
    }

    testWidgets('an edited address is saved only once it has answered', (
      tester,
    ) async {
      final flow = await _pumpFlow(tester, Profiles.p3);
      await _openService(tester, flow, 'Radarr');
      await _fill(tester, flow, WorldHosts.radarr, WorldIds.radarr);
      await _tap(tester, flow, 'Test connection');

      // Moved to an address nothing answers at.
      await tester.enterText(
        find.byType(TextField).first,
        'http://elsewhere.home.arpa:7878',
      );
      await flow.harness.settle(tester);
      await _tap(tester, flow, 'Test connection');

      expect(_primary('Go to Home'), findsNothing);
      expect(flow.container.read(settingsProvider).radarrUrl, isEmpty);
      expect(flow.container.read(onboardingCompletedProvider), isFalse);

      await flow.harness.unmount(tester);
    });

    testWidgets('Continue on Seerr opens what it knows, and adding them '
        'leaves for the Home', (tester) async {
      final flow = await _pumpFlow(tester, Profiles.p3);
      await _tap(tester, flow, 'Set up a service');
      await _fill(tester, flow, WorldHosts.seerr, WorldIds.seerr);
      await _tap(tester, flow, 'Test connection');

      await _tap(tester, flow, 'Continue');

      // Seerr is saved before Found asks it anything; the way in is not over.
      expect(find.text('Step 2 of 2'), findsOneWidget);
      expect(flow.container.read(onboardingCompletedProvider), isFalse);
      expect(flow.container.read(settingsProvider).seerrUrl, WorldHosts.seerr);
      expect(
        flow.container.read(settingsProvider).seerrApiKey,
        worldKey(WorldIds.seerr),
      );

      await tester.tap(findLine('Add 2 services'));
      await flow.harness.settle(tester);

      expect(flow.router.state.uri.path, ServiceRoutes.home);
      expect(flow.container.read(onboardingCompletedProvider), isTrue);
      final saved = flow.container.read(settingsProvider);
      expect(saved.radarrUrl, isNotEmpty);
      expect(saved.radarrApiKey, worldKey(WorldIds.radarr));
      expect(saved.sonarrUrl, isNotEmpty);
      expect(saved.sonarrApiKey, worldKey(WorldIds.sonarr));

      await flow.harness.unmount(tester);
    });
  });

  group('what is saved', () {
    testWidgets('choosing another service saves only that service', (
      tester,
    ) async {
      final flow = await _pumpFlow(tester, Profiles.p3);

      // Seerr is typed in, then set aside for Radarr.
      await _tap(tester, flow, 'Set up a service');
      await _fill(tester, flow, WorldHosts.seerr, WorldIds.seerr);
      await _tap(tester, flow, 'Start with another service');
      await _tap(tester, flow, 'Set up Radarr');
      expect(findLine('Set up Radarr'), findsOneWidget);
      await _fill(tester, flow, WorldHosts.radarr, WorldIds.radarr);
      await _tap(tester, flow, 'Test connection');
      await _tap(tester, flow, 'Go to Home');

      final saved = flow.container.read(settingsProvider);
      expect(saved.radarrUrl, WorldHosts.radarr);
      expect(saved.radarrApiKey, worldKey(WorldIds.radarr));
      // What was typed for Seerr was never tested, so it is not a connection.
      expect(saved.seerrUrl, isEmpty);
      expect(saved.seerrApiKey, isEmpty);
      expect(saved.instances, hasLength(1));

      await flow.harness.unmount(tester);
    });

    testWidgets('a service that refuses the key is not saved, and the right '
        'key saves it', (tester) async {
      final flow = await _pumpFlow(
        tester,
        Profiles.p3.withBehaviour(
          WorldIds.radarr,
          ConnectionBehaviour.refusesKey,
        ),
      );
      await _openService(tester, flow, 'Radarr');
      await _fill(tester, flow, WorldHosts.radarr, WorldIds.radarr);

      await _tap(tester, flow, 'Test connection');

      // No way forward from a service that did not answer, and nothing saved.
      expect(find.text('Radarr answered.'), findsNothing);
      expect(_primary('Go to Home'), findsNothing);
      expect(flow.container.read(settingsProvider).radarrUrl, isEmpty);
      expect(flow.container.read(onboardingCompletedProvider), isFalse);

      // The key is put right on the server's side, and the same press works.
      flow.harness.network.behave(WorldIds.radarr, ConnectionBehaviour.answers);
      await _tap(tester, flow, 'Test connection');
      expect(find.text('Radarr answered.'), findsOneWidget);
      await _tap(tester, flow, 'Go to Home');

      expect(
        flow.container.read(settingsProvider).radarrUrl,
        WorldHosts.radarr,
      );
      expect(flow.router.state.uri.path, ServiceRoutes.home);

      await flow.harness.unmount(tester);
    });

    testWidgets('a revisit sets up one more service and leaves the rest as '
        'they were', (tester) async {
      // A household with Sonarr, opening the Welcome again from Settings: the
      // flag is on and stays on, and Radarr joins what was there.
      final flow = await _pumpFlow(
        tester,
        Profiles.p3,
        settings: settingsWith(
          sonarrUrl: WorldHosts.sonarr,
          sonarrApiKey: worldKey(WorldIds.sonarr),
        ),
        onboardingCompleted: true,
        initialLocation: ServiceRoutes.home,
      );
      flow.router.go(ServiceRoutes.welcome);
      await flow.harness.settle(tester);

      await _openService(tester, flow, 'Radarr');
      await _fill(tester, flow, WorldHosts.radarr, WorldIds.radarr);
      await _tap(tester, flow, 'Test connection');
      await _tap(tester, flow, 'Go to Home');

      final saved = flow.container.read(settingsProvider);
      expect(saved.radarrUrl, WorldHosts.radarr);
      expect(saved.sonarrUrl, WorldHosts.sonarr);
      expect(saved.sonarrApiKey, worldKey(WorldIds.sonarr));
      expect(flow.container.read(onboardingCompletedProvider), isTrue);
      expect(flow.router.state.uri.path, ServiceRoutes.home);

      await flow.harness.unmount(tester);
    });

    // A trust decision belongs to the host it was made against. The pin is
    // seeded from the *saved* address when a service is opened again, and a
    // save writes the address on screen. Without tying the fingerprint to the
    // origin it was accepted for, editing an address carried the old host's
    // certificate onto the new one, and because a pin is keyed by origin
    // alone, that bogus entry then failed closed for every service later
    // pointed at that host, with no trust prompt to explain it.
    testWidgets('editing an address does not move its certificate pin', (
      tester,
    ) async {
      final flow = await _pumpFlow(
        tester,
        Profiles.p3,
        settings: settingsWith(
          sonarrUrl: 'https://nas.lan:8989',
          sonarrApiKey: worldKey(WorldIds.sonarr),
          trustedCertificates: {'https://nas.lan:8989': 'AA:BB'},
        ),
        onboardingCompleted: true,
        initialLocation: ServiceRoutes.home,
      );
      flow.router.go(ServiceRoutes.welcome);
      await flow.harness.settle(tester);
      await _openService(tester, flow, 'Sonarr');

      // Resumed on the pinned address, and moved to the one the world answers
      // at: a different origin, which never presented that certificate.
      await tester.enterText(find.byType(TextField).first, WorldHosts.sonarr);
      await flow.harness.settle(tester);
      await _tap(tester, flow, 'Test connection');
      await _tap(tester, flow, 'Go to Home');

      final saved = flow.container.read(settingsProvider);
      expect(saved.sonarrUrl, WorldHosts.sonarr);
      // The new host has no pin; and the abandoned one is forgotten rather
      // than relocated.
      expect(saved.pinForUrl(WorldHosts.sonarr), isNull);
      expect(saved.trustedCertificates, isEmpty);

      await flow.harness.unmount(tester);
    });
  });
}

Finder _primary(String label) =>
    find.ancestor(of: findLine(label), matching: find.byType(FilledButton));

/// What a case reads back: the profile's network, what the way in saved, and
/// where it left for.
typedef _Flow = ({
  ProfileHarness harness,
  ProviderContainer container,
  GoRouter router,
});

/// Mounts the way in on [profile]'s network, starting from [settings].
///
/// [appRouter] mounts the app's own router, redirects and Home included, for
/// the cases that are about leaving the way in; the others use a router that
/// only has the way in and a stand-in for the Home, so a case can start
/// anywhere.
Future<_Flow> _pumpFlow(
  WidgetTester tester,
  ConfigProfile profile, {
  SettingsModel settings = const SettingsModel(),
  bool onboardingCompleted = false,
  bool appRouter = false,
  String initialLocation = ServiceRoutes.welcome,
}) async {
  final harness = await ProfileHarness.start(profile);
  harness.network.followFakeTime(tester.binding);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 2400);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      initialSettingsProvider.overrideWith((ref) => settings),
      initialOnboardingCompletedProvider.overrideWith(
        (ref) => onboardingCompleted,
      ),
      hostReachProvider.overrideWithValue(harness.network.reach),
      // The Home's polls, off: a profile is read once, and a poll's timer
      // would outlive a container disposed at teardown.
      homeLivePollProvider.overrideWith((ref) {}),
      homeRecoveryPollProvider.overrideWith((ref) {}),
      activityLivePollProvider.overrideWith((ref, tab) {}),
      featuredAdvancesProvider.overrideWithValue(false),
    ],
  );
  addTearDown(container.dispose);
  final router = appRouter
      ? container.read(routerProvider)
      : onboardingRouter(initialLocation: initialLocation);
  if (!appRouter) addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          // Reduce Motion: the ring's sweep repeats for ever, so with motion on
          // nothing ever settles.
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  await harness.settle(tester);
  return (harness: harness, container: container, router: router);
}

Future<void> _tap(WidgetTester tester, _Flow flow, String label) async {
  await tester.tap(find.text(label).first);
  await flow.harness.settle(tester);
}

/// Connect for [title]: the door, then the list, then the row.
Future<void> _openService(WidgetTester tester, _Flow flow, String title) async {
  await _tap(tester, flow, 'Set up a service');
  await _tap(tester, flow, 'Start with another service');
  await _tap(
    tester,
    flow,
    title == 'Seerr' || title == 'Prowlarr' ? title : 'Set up $title',
  );
}

/// Types [host] and the key the world gives [id] into Connect's two fields.
Future<void> _fill(
  WidgetTester tester,
  _Flow flow,
  String host,
  String id,
) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), host);
  await tester.enterText(fields.at(1), worldKey(id));
  await flow.harness.settle(tester);
}
