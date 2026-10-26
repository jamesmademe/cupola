import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/screen_title.dart';
import 'package:cupola/core/widgets/setup_doors.dart';
import 'package:cupola/demo/demo_door.dart';
import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/demo/presentation/demo_mark.dart';
import 'package:cupola/demo/presentation/demo_settings_card.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../test_helpers/fake_secure_settings_store.dart';
import '../test_helpers/onboarding_router.dart';

/// The way into the demo and out of it: the Welcome's door, offered only to
/// an app with no connection, the mark after each tab's name, and Settings'
/// way out.
void main() {
  group('the Welcome', () {
    Future<List<SettingsModel>> pumpWelcome(
      WidgetTester tester, {
      SettingsModel settings = const SettingsModel(),
      bool door = true,
      Object? refusal,
    }) async {
      final entered = <SettingsModel>[];
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureSettingsStoreProvider.overrideWithValue(
            FakeSecureSettingsStore(),
          ),
          initialSettingsProvider.overrideWith((ref) => settings),
          initialOnboardingCompletedProvider.overrideWith((ref) => false),
          if (door)
            demoDoorProvider.overrideWithValue(
              DemoDoor(
                enter: (leaving) async {
                  entered.add(leaving);
                  if (refusal != null) throw refusal;
                },
                leave: () async {},
              ),
            ),
        ],
      );
      addTearDown(container.dispose);
      final router = onboardingRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.darkTheme(),
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return entered;
    }

    testWidgets('offers the demo to an app with no connection, and opens it '
        'over its settings', (tester) async {
      final entered = await pumpWelcome(tester);
      await tester.tap(find.text('Explore a demo home'));
      await tester.pumpAndSettle();
      expect(entered, [const SettingsModel()]);
    });

    testWidgets('never offers it over a connection', (tester) async {
      await pumpWelcome(
        tester,
        settings: SettingsModel(
          instances: [
            ServiceInstance(
              id: 'radarr',
              service: ServiceKey.radarr,
              url: 'http://nas.local:7878',
            ),
          ],
        ),
      );
      expect(find.text('Explore a demo home'), findsNothing);
    });

    testWidgets('never offers it where there is no app to swap', (
      tester,
    ) async {
      await pumpWelcome(tester, door: false);
      expect(find.text('Explore a demo home'), findsNothing);
    });

    testWidgets('says so when the demo could not open', (tester) async {
      await pumpWelcome(tester, refusal: const DemoRefused());
      await tester.tap(find.text('Explore a demo home'));
      await tester.pump();
      expect(find.text('Could not open the demo home.'), findsOneWidget);
    });
  });

  group('the doors', () {
    testWidgets('say the demo door\'s line as its hint', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: SetupDoors(
              onSetUp: () {},
              onCopy: () {},
              onSignIn: () {},
              onDemo: () {},
            ),
          ),
        ),
      );
      expect(
        find.semantics.byLabel('Explore a demo home'),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          hint: SetupDoors.demoHint,
        ),
      );
      handle.dispose();
    });
  });

  Widget inDemo(Widget child, {bool running = true, DemoDoor? door}) =>
      ProviderScope(
        overrides: [
          demoRunningProvider.overrideWithValue(running),
          if (door != null) demoDoorProvider.overrideWithValue(door),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(body: ListView(children: [child])),
        ),
      );

  group('the mark', () {
    testWidgets('follows a tab\'s name in the demo, and nowhere else', (
      tester,
    ) async {
      await tester.pumpWidget(inDemo(const ScreenTitle('Stack')));
      expect(find.text('Demo'), findsOneWidget);
      await tester.pumpWidget(
        inDemo(const ScreenTitle('Stack'), running: false),
      );
      expect(find.text('Demo'), findsNothing);
      expect(find.text('Stack'), findsOneWidget);
    });

    testWidgets('is one button with its way out said', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(inDemo(const DemoMark()));
      expect(
        find.semantics.byLabel('Demo home'),
        isSemantics(isButton: true, hasTapAction: true, hint: DemoMark.hint),
      );
      expect(
        tester.getSize(find.byType(DemoMark)).height,
        greaterThanOrEqualTo(44),
      );
      handle.dispose();
    });
  });

  group('Settings', () {
    testWidgets('opens on where the visitor is, and leaves without asking', (
      tester,
    ) async {
      var left = 0;
      await tester.pumpWidget(
        inDemo(
          const DemoSettingsCard(),
          door: DemoDoor(enter: (_) async {}, leave: () async => left++),
        ),
      );
      expect(find.text("You're exploring a demo home"), findsOneWidget);
      await tester.tap(find.text('Leave demo'));
      await tester.pump();
      expect(left, 1);
    });

    testWidgets('has nothing to say outside the demo', (tester) async {
      await tester.pumpWidget(inDemo(const DemoSettingsCard(), running: false));
      expect(find.text('Leave demo'), findsNothing);
    });
  });
}
