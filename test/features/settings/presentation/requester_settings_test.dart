import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/requester_account_page.dart';
import 'package:cupola/features/settings/presentation/settings_home_screen.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';
import 'package:cupola/features/shell/presentation/portal_coach_mark.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Anna's Settings (the spec of the requester, § 6.2): her account, what she
/// sets for herself, the app, and the one way into the operator's app. Each
/// absence is checked against the operator's Settings, where the row is.
void main() {
  const phone = Size(390, 2400);

  /// The server's own name, as it says it (the world's is Jellyseerr's), and
  /// its address: the one service name she reads, in her account.
  const where = 'Jellyseerr · nas.home.arpa:5055';

  /// The operator's rows and pages she never meets.
  const operatorsRows = [
    'Connections',
    'Background search',
    'Trusted certificates',
    'GitHub',
    'Hints',
    'Revisit onboarding',
    'Set up another device',
    'Reset app data',
  ];

  Future<ProfileHarness> pump(
    WidgetTester tester,
    Widget child, {
    ConfigProfile? profile,
  }) => pumpWithProfile(
    tester,
    profile ?? Profiles.p2,
    child: child,
    surfaceSize: phone,
  );

  group('her Settings, on a phone', () {
    testWidgets('her account first, then General, About, and Set up a '
        'service last', (tester) async {
      final harness = await pump(tester, const SettingsHomeScreen());

      expect(find.text('Account'), findsOne);
      expect(find.text('Signed in as ${WorldPeople.anna}'), findsOne);
      expect(find.text(where), findsOne);
      for (final row in [
        'Region',
        'Appearance',
        'Home',
        'Send feedback',
        'Licenses & trademarks',
      ]) {
        expect(find.text(row), findsOne, reason: row);
      }
      expect(find.text('Set up a service'), findsOne);
      for (final row in operatorsRows) {
        expect(find.text(row), findsNothing, reason: row);
      }
      // Last: nothing under it.
      final last = tester.getRect(find.text('Set up a service'));
      expect(
        tester.getRect(find.text('Licenses & trademarks')).top,
        lessThan(last.top),
      );

      await harness.unmount(tester);
    });

    testWidgets('the operator keeps every row of his (P1)', (tester) async {
      final harness = await pump(
        tester,
        const SettingsHomeScreen(),
        profile: Profiles.p1,
      );

      for (final row in operatorsRows) {
        expect(find.text(row), findsWidgets, reason: row);
      }
      expect(find.text('Set up a service'), findsNothing);
      expect(find.textContaining('Signed in as'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('signed out, the account says so in blue, as the Home does', (
      tester,
    ) async {
      final harness = await pump(
        tester,
        const SettingsHomeScreen(),
        profile: Profiles.p2.withSeerrSignedOut(WorldIds.seerr),
      );

      expect(find.text('You were signed out'), findsOne);
      expect(find.textContaining('Signed in as'), findsNothing);

      await harness.unmount(tester);
    });
  });

  group('her account', () {
    testWidgets('who she is, large, then Sign out and Remove this server', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final harness = await pump(tester, const RequesterAccountPage());

      // Her name heads the page, the way she signs in and the server under
      // it, and the head speaks once.
      expect(find.text(WorldPeople.anna), findsOne);
      expect(find.text(WorldSeerrUsers.annaLocal.email), findsOne);
      expect(find.text(where), findsOne);
      expect(
        find.bySemanticsLabel(
          'Signed in as ${WorldPeople.anna}. '
          '${WorldSeerrUsers.annaLocal.email}. $where',
        ),
        findsOne,
      );
      // Sign out is a row beside Remove this server, not a button by her name.
      expect(find.widgetWithText(OutlinedButton, 'Sign out'), findsNothing);
      expect(find.text('Sign out'), findsOne);
      expect(find.text('Remove this server'), findsOne);

      await harness.unmount(tester);
      semantics.dispose();
    });

    for (final (profile, how) in [
      (Profiles.p2ViaJellyfin, 'Jellyfin account'),
      (Profiles.p2ViaPlex, 'Plex account'),
    ]) {
      testWidgets('through ${profile.title}, the head says $how', (
        tester,
      ) async {
        final harness = await pump(
          tester,
          const RequesterAccountPage(),
          profile: profile,
        );

        expect(find.text(how), findsOne);

        await harness.unmount(tester);
      });
    }

    testWidgets('Sign out asks first, then signs her out', (tester) async {
      final harness = await pump(tester, const RequesterAccountPage());

      await tester.tap(find.text('Sign out'));
      await harness.settle(tester);
      expect(find.text('Sign out of Jellyseerr?'), findsOne);

      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Signed out, the page goes back to the way in.
      expect(find.text('Sign in again'), findsOne);
      expect(find.text(WorldPeople.anna), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('signed out, her words: You were signed out, and Sign in '
        'again', (tester) async {
      final harness = await pump(
        tester,
        const RequesterAccountPage(),
        profile: Profiles.p2.withSeerrSignedOut(WorldIds.seerr),
      );

      expect(find.text('You were signed out'), findsOne);
      expect(
        find.text('Sign in again to keep asking for movies and series.'),
        findsOne,
      );
      expect(find.text('Sign in again'), findsOne);
      expect(find.textContaining('Signed out of'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('Remove this server asks first, signs her out on the server, '
        'then forgets the connection', (tester) async {
      final harness = await pump(tester, const RequesterAccountPage());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RequesterAccountPage)),
      );

      await tester.tap(find.text('Remove this server'));
      await harness.settle(tester);
      expect(find.text('Remove this server?'), findsOne);
      expect(
        find.text(
          'Cupola signs you out and forgets its address. Your requests stay '
          'on the server.',
        ),
        findsOne,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Remove this server'));
      // The sign-out goes to the server and back, and the snack bar runs its
      // four seconds: a bounded wait rather than the harness's settle.
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        harness.network
            .requestsTo(WorldIds.seerr)
            .where((r) => r.path == '/api/v1/auth/logout'),
        isNotEmpty,
      );
      expect(
        container.read(currentSettingsProvider).instancesOf(ServiceKey.seerr),
        isEmpty,
      );

      await harness.unmount(tester);
    });
  });

  group('her app around Settings', () {
    // Each starts on Settings: the Home's posters would reach for the image
    // cache's directory, which a test has not.
    Future<(ProfileHarness, GoRouter, ProviderContainer)> pumpApp(
      WidgetTester tester, {
      ConfigProfile? profile,
      Size size = const Size(390, 844),
      String location = ServiceRoutes.settings,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = await ProfileHarness.start(profile ?? Profiles.p2);
      harness.network.followFakeTime(tester.binding);
      final container = harness.container();
      final router = container.read(routerProvider)..go(location);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.darkTheme(),
            routerConfig: router,
          ),
        ),
      );
      await harness.settle(tester);
      return (harness, router, container);
    }

    Future<void> unmount(
      WidgetTester tester,
      ProfileHarness harness,
      ProviderContainer container,
    ) async {
      await harness.unmount(tester);
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('the operator\'s settings pages send her to Settings', (
      tester,
    ) async {
      final (harness, router, container) = await pumpApp(tester);

      for (final location in [
        ServiceRoutes.settingsCertificates,
        ServiceRoutes.settingsBackgroundSearch,
      ]) {
        router.go(location);
        await harness.settle(tester);
        expect(router.state.uri.path, ServiceRoutes.settings, reason: location);
      }

      await unmount(tester, harness, container);
    });

    testWidgets('the operator\'s account is in the connection\'s form (P1)', (
      tester,
    ) async {
      final (harness, router, container) = await pumpApp(
        tester,
        profile: Profiles.p1,
      );

      router.go(ServiceRoutes.settingsAccountFor(instanceId: WorldIds.seerr));
      await harness.settle(tester);

      expect(
        router.state.uri.path,
        ServiceRoutes.settingsFor(ServiceKey.seerr),
      );
      expect(router.state.uri.queryParameters['i'], WorldIds.seerr);

      // The connection's form arms a timer of its own, which the harness's
      // settle, stopping at the first quiet frame, leaves running.
      await tester.pump(const Duration(seconds: 5));
      await unmount(tester, harness, container);
    });

    testWidgets('her bar has no Portal: no drag, no coach mark', (
      tester,
    ) async {
      final (harness, _, container) = await pumpApp(tester);

      expect(
        tester
            .widget<FloatingBottomNavBar>(find.byType(FloatingBottomNavBar))
            .verticalDragDelegate,
        isNull,
      );
      expect(find.byType(PortalCoachMark), findsNothing);

      await unmount(tester, harness, container);
    });

    testWidgets('the operator\'s bar has it (P1)', (tester) async {
      final (harness, _, container) = await pumpApp(
        tester,
        profile: Profiles.p1,
      );

      expect(
        tester
            .widget<FloatingBottomNavBar>(find.byType(FloatingBottomNavBar))
            .verticalDragDelegate,
        isNotNull,
      );
      expect(find.byType(PortalCoachMark), findsOne);

      await unmount(tester, harness, container);
    });

    testWidgets(
      'on a Mac, her rail and her pane',
      (tester) async {
        final (harness, _, container) = await pumpApp(
          tester,
          size: const Size(1440, 900),
        );

        final rail = find.byType(SettingsMasterDetail);
        for (final section in SettingsMasterDetail.requesterSections) {
          expect(
            find.descendant(of: rail, matching: find.text(section.label)),
            findsWidgets,
            reason: section.label,
          );
        }
        expect(find.text('Signed in as ${WorldPeople.anna}'), findsOne);
        expect(find.text('Set up a service'), findsOne);
        for (final row in operatorsRows) {
          expect(find.text(row), findsNothing, reason: row);
        }

        await unmount(tester, harness, container);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  });
}
