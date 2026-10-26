import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/shell/presentation/desktop/desktop_downloads_poll.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/router.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_lifecycle.dart';
import 'package:cupola/features/requests/presentation/requests_screen.dart';
import 'package:cupola/features/services/presentation/stack_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/settings_home_screen.dart';
import 'package:cupola/features/shell/presentation/settings_back_claim.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_nav_rail.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

import '../../../test_helpers/fake_services.dart';

/// The bar the Home arrives with: the operator's Home · Discover · Activity ·
/// Stack, the requester's Home · Discover · Requests, Settings in neither, and
/// the routes each may reach.
void main() {
  group('NavTab.barFor', () {
    test('the operator has the control room, the requester has her '
        'requests', () {
      expect(NavTab.barFor(Audience.operator), [
        NavTab.home,
        NavTab.discover,
        NavTab.activity,
        NavTab.stack,
      ]);
      expect(NavTab.barFor(Audience.requester), [
        NavTab.home,
        NavTab.discover,
        NavTab.requests,
      ]);
    });

    test('Settings is in no bar', () {
      for (final audience in Audience.values) {
        expect(NavTab.barFor(audience), isNot(contains(NavTab.settings)));
      }
    });
  });

  group('the operator', () {
    testWidgets('opens on the Home, with four tabs and no Settings', (
      tester,
    ) async {
      final container = await _pump(tester, _operator);

      expect(_location(container), ServiceRoutes.home);
      expect(find.byType(HomeScreen), findsOneWidget);
      for (final tab in NavTab.barFor(Audience.operator)) {
        expect(_tab(tab), findsOneWidget, reason: tab.label);
      }
      expect(_tab(NavTab.requests), findsNothing);
      expect(_tab(NavTab.settings), findsNothing);
    });

    testWidgets('Stack is the stack, and its gear opens Settings', (
      tester,
    ) async {
      final container = await _pump(tester, _operator);

      await tester.tap(_tab(NavTab.stack));
      await tester.pumpAndSettle();
      expect(_location(container), ServiceRoutes.stack);
      expect(find.byType(StackScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(_location(container), ServiceRoutes.settings);
      expect(find.byType(SettingsHomeScreen), findsOneWidget);
    });

    testWidgets('Settings goes back to Stack, by its arrow and by the '
        'system\'s back', (tester) async {
      final container = await _pump(tester, _operator);
      await tester.tap(_tab(NavTab.stack));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back to Stack'));
      await tester.pumpAndSettle();
      expect(_location(container), ServiceRoutes.stack);

      // Android's back on the Settings root: back to Stack, not out of the
      // app.
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(_location(container), ServiceRoutes.stack);
    });

    testWidgets('on Settings the app claims Android\'s back, so a predictive '
        'back goes to the tab and does not leave the app', (tester) async {
      // With predictive back the system hands a back to the app only when the
      // framework has claimed it, and on a branch root no navigator does.
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      // Nothing claimed yet is the system's back.
      bool lastClaim() =>
          calls
              .where(
                (call) =>
                    call.method == 'SystemNavigator.setFrameworkHandlesBack',
              )
              .map((call) => call.arguments as bool)
              .lastOrNull ??
          false;

      final container = await _pump(tester, _operator);
      // The app tells the engine only once it is in front.
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/lifecycle',
        const StringCodec().encodeMessage(AppLifecycleState.resumed.toString()),
        (_) {},
      );
      await tester.pumpAndSettle();
      await tester.tap(_tab(NavTab.stack));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(lastClaim(), isTrue);

      // A page pushed inside Settings and popped again leaves the claim.
      container.read(routerProvider).go(ServiceRoutes.settingsHome);
      await tester.pumpAndSettle();
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(_location(container), ServiceRoutes.settings);
      expect(lastClaim(), isTrue);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(_location(container), ServiceRoutes.stack);
      expect(
        lastClaim(),
        isFalse,
        reason: 'back on a tab root belongs to the system again',
      );
    });

    test('the app claims the back for Settings above every navigator', () {
      // The page tests pump their own app; this holds the real one's builder.
      expect(
        File('lib/main.dart').readAsStringSync(),
        contains('child: SettingsBackClaim('),
      );
    });

    testWidgets('a tab left from Settings keeps its own back', (tester) async {
      // The control: Settings stays built in its branch when a tab is
      // tapped, and its back must not answer from there.
      final container = await _pump(tester, _operator);
      await tester.tap(_tab(NavTab.stack));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(_tab(NavTab.home));
      await tester.pumpAndSettle();
      expect(await tester.binding.handlePopRoute(), isFalse);
      await tester.pumpAndSettle();
      expect(_location(container), ServiceRoutes.home);
    });

    testWidgets('a location from the Dashboard lands on Stack in one hop, '
        'query and all', (tester) async {
      final container = await _pump(tester, _operator);

      container.read(routerProvider).go('/dashboard/radarr/wanted?i=radarr');
      await tester.pumpAndSettle();

      expect(_location(container), '/stack/radarr/wanted?i=radarr');
    });

    testWidgets('a location from before the Dashboard lands there too', (
      tester,
    ) async {
      final container = await _pump(tester, _operator);

      container.read(routerProvider).go('/services/sonarr');
      await tester.pumpAndSettle();

      // Sonarr's node opens its first tab.
      expect(_location(container), startsWith('/stack/sonarr'));
    });

    testWidgets('the requester\'s tab sends the operator to Seerr\'s '
        'requests', (tester) async {
      final container = await _pump(tester, _operator);

      container.read(routerProvider).go(ServiceRoutes.requests);
      await tester.pumpAndSettle();

      expect(_location(container), ServiceRoutes.seerrRequests);
    });
  });

  group('the requester', () {
    testWidgets('opens on her Home, with Home, Discover and Requests', (
      tester,
    ) async {
      final container = await _pump(tester, _requester);

      expect(_location(container), ServiceRoutes.home);
      for (final tab in NavTab.barFor(Audience.requester)) {
        expect(_tab(tab), findsOneWidget, reason: tab.label);
      }
      for (final tab in [NavTab.activity, NavTab.stack, NavTab.settings]) {
        expect(_tab(tab), findsNothing, reason: tab.label);
      }
    });

    testWidgets('her account opens Settings, and its arrow brings her '
        'Home', (tester) async {
      final container = await _pump(tester, _requester);

      await tester.tap(find.bySemanticsLabel('Anna, your account'));
      await tester.pumpAndSettle();
      expect(_location(container), ServiceRoutes.settings);

      await tester.tap(find.byTooltip('Back to Home'));
      await tester.pumpAndSettle();
      expect(_location(container), ServiceRoutes.home);
    });

    testWidgets('Requests is her tab', (tester) async {
      final container = await _pump(tester, _requester);

      await tester.tap(_tab(NavTab.requests));
      await tester.pumpAndSettle();

      expect(_location(container), ServiceRoutes.requests);
      expect(find.byType(RequestsScreen), findsOneWidget);
    });

    for (final denied in [
      '/activity',
      // Each of Activity's views, and the page's old addresses: Activity is
      // the operator's whole, whichever way it is reached.
      '/activity/downloads',
      '/activity/requests',
      '/activity/requests?i=seerr',
      '/activity/history',
      '/activity/blocklist',
      '/activity/discover',
      '/stack',
      '/stack/radarr',
      '/dashboard/sonarr',
      '/import/review',
    ]) {
      testWidgets('$denied is the operator\'s, so she lands Home', (
        tester,
      ) async {
        final container = await _pump(tester, _requester);

        container.read(routerProvider).go(denied);
        await tester.pumpAndSettle();

        expect(_location(container), ServiceRoutes.home);
      });
    }
  });

  group('the desktop window', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('Settings waits at the foot of the rail, one ⌘, away', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      try {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final container = await _pump(
          tester,
          _operator,
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        final settings = find.descendant(
          of: find.byType(DesktopNavRail),
          matching: find.text('Settings'),
        );
        expect(settings, findsOneWidget);
        // The key is the row's hint, printed only under the pointer.
        expect(
          tester
              .widget<Semantics>(
                find
                    .ancestor(of: settings, matching: find.byType(Semantics))
                    .first,
              )
              .properties
              .hint,
          '⌘,',
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.comma);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        expect(_location(container), ServiceRoutes.settings);

        // ⌘1 is the first tab of the bar, the Home.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        expect(_location(container), ServiceRoutes.home);

        await tester.tap(settings);
        await tester.pumpAndSettle();
        expect(_location(container), ServiceRoutes.settings);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('the shell\'s hold', () {
    testWidgets('a new audience waits for the app to come back', (
      tester,
    ) async {
      final container = await _pump(tester, _operator);
      expect(container.read(shellAudienceProvider), Audience.operator);

      // The operator signs in to a requester's account in Settings: every
      // other connection goes, and the app is now for a requester.
      container.read(_settings.notifier).state = _requester;
      await tester.pumpAndSettle();
      expect(container.read(audienceProvider), Audience.requester);
      expect(container.read(shellAudienceProvider), Audience.operator);
      expect(_tab(NavTab.stack), findsOneWidget);

      final foreground = container.read(appInForegroundProvider.notifier);
      foreground.set(false);
      foreground.set(true);
      await tester.pumpAndSettle();

      expect(container.read(shellAudienceProvider), Audience.requester);
      expect(_tab(NavTab.stack), findsNothing);
      expect(_tab(NavTab.requests), findsOneWidget);
    });
  });
}

const _operator = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      url: 'http://radarr.test',
      credential: 'key',
    ),
  ],
);

const _requester = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'seerr',
      service: ServiceKey.seerr,
      url: 'http://seerr.test',
      account: SeerrAccountSignIn(
        kind: SeerrAccountKind.local,
        login: 'anna@home.test',
        userId: 7,
        displayName: 'Anna',
        session: 'session',
        // REQUEST only: a household member, not a manager.
        permissions: 32,
      ),
    ),
  ],
);

/// The settings a test can change while the app runs.
final _settings = StateProvider<SettingsModel>((ref) => _operator);

/// A tab of the bar, by its glyph: the pill writes only the selected tab's
/// name.
/// [tab]'s glyph in the bar, not a page's button that shares it (Discover
/// on the requester's Home).
Finder _tab(NavTab tab) => find.descendant(
  of: find.byType(FloatingBottomNavBar),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Icon &&
        (widget.icon == tab.icon || widget.icon == tab.selectedIcon),
  ),
);

String _location(ProviderContainer container) =>
    container.read(routerProvider).state.uri.toString();

Future<ProviderContainer> _pump(
  WidgetTester tester,
  SettingsModel settings, {
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      ...overrides,
      initialOnboardingCompletedProvider.overrideWith((ref) => true),
      _settings.overrideWith((ref) => settings),
      currentSettingsProvider.overrideWith((ref) => ref.watch(_settings)),
      seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
      atriumTrendingProvider.overrideWith((ref) async => const []),
      comingSoonProvider.overrideWith((ref) async => const []),
      // The Home's thirty-second poll: a test about the bar ends before the
      // container that holds its timer is disposed.
      homeLivePollProvider.overrideWith((ref) {}),
      homeRecoveryPollProvider.overrideWith((ref) {}),
      sidebarInFlightPollProvider.overrideWith((ref) {}),
      desktopDownloadsPollProvider.overrideWith((ref) {}),
      featuredAdvancesProvider.overrideWithValue(false),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: container.read(routerProvider),
        // As the app's own builder claims Android's back for Settings.
        builder: (context, child) => SettingsBackClaim(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}
