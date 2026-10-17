/// Connect's address away: offered under the address at home, refused in
/// plain http across the internet as the connection form refuses it, tested
/// beside the one at home and saved with the connection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';
import '../../../test_helpers/onboarding_router.dart';
import '../../../test_helpers/profiles/profiles.dart';

const _away = 'https://radarr.example.net';

Future<(ProfileHarness, ProviderContainer)> _firstRunAtRadarr(
  WidgetTester tester, {
  String address = WorldHosts.radarr,
  Size viewport = const Size(800, 2400),
}) async {
  final harness = await ProfileHarness.start(Profiles.p3);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      initialSettingsProvider.overrideWith((ref) => const SettingsModel()),
      initialOnboardingCompletedProvider.overrideWith((ref) => false),
    ],
  );
  addTearDown(container.dispose);
  final router = onboardingRouter();
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
  await harness.settle(tester);
  await _tap(tester, harness, 'Set up a service');
  await _tap(tester, harness, 'Start with another service');
  await tester.scrollUntilVisible(
    find.text('Set up Radarr'),
    100,
    scrollable: find
        .descendant(
          of: find.byType(OnboardingStart),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await _tap(tester, harness, 'Set up Radarr');
  await tester.enterText(_field('Address at home'), address);
  await tester.enterText(_field('API key'), worldKey(WorldIds.radarr));
  await harness.settle(tester);
  return (harness, container);
}

Future<void> _tap(
  WidgetTester tester,
  ProfileHarness harness,
  String text,
) async {
  await tester.tap(find.text(text).first);
  await harness.settle(tester);
}

Finder _field(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is OnboardingField && widget.label == label,
  ),
  matching: find.byType(TextField),
);

/// Opens the address away and types [url] into it.
Future<void> _addAway(
  WidgetTester tester,
  ProfileHarness harness,
  String url,
) async {
  await _tap(tester, harness, 'Add an address away');
  await tester.enterText(_field('Address away\u00A0· optional'), url);
  await harness.settle(tester);
}

void main() {
  testWidgets('the link opens the address away under the one at home, with '
      'the keyboard on it', (tester) async {
    final (harness, _) = await _firstRunAtRadarr(tester);

    expect(_field('Address away\u00A0· optional'), findsNothing);
    await _tap(tester, harness, 'Add an address away');

    final away = _field('Address away\u00A0· optional');
    expect(away, findsOneWidget);
    expect(find.text('Add an address away'), findsNothing);
    expect(tester.widget<TextField>(away).focusNode?.hasFocus, isTrue);
    expect(
      tester.getRect(away).top,
      greaterThan(tester.getRect(_field('Address at home')).bottom),
    );
    expect(
      tester.getRect(away).bottom,
      lessThan(tester.getRect(_field('API key')).top),
    );

    await harness.unmount(tester);
  });

  testWidgets('home answering and away silent: saved with both addresses, '
      'the one away not checked from here', (tester) async {
    final (harness, container) = await _firstRunAtRadarr(tester);
    await _addAway(tester, harness, _away);

    await _tap(tester, harness, 'Test connection');

    expect(find.text('Radarr answered.'), findsOneWidget);
    expect(find.text('At home\u00A0· nas.home.arpa:7878'), findsOneWidget);
    expect(find.text('Not checked from here.'), findsOneWidget);
    expect(
      find.text("Cupola tries it when the home address doesn't answer."),
      findsOneWidget,
    );
    expect(find.text('Away\u00A0· radarr.example.net'), findsOneWidget);

    await tester.tap(find.text('Continue').first);
    await harness.settle(tester);

    final radarr = container
        .read(currentSettingsProvider)
        .primaryOf(ServiceKey.radarr);
    expect(radarr?.url, WorldHosts.radarr);
    expect(radarr?.away?.url, _away);

    await harness.unmount(tester);
  });

  testWidgets('neither address answering: one red naming both, and no way on', (
    tester,
  ) async {
    final (harness, container) = await _firstRunAtRadarr(
      tester,
      address: 'http://radarr.home.arpa:7878',
    );
    await _addAway(tester, harness, _away);

    await _tap(tester, harness, 'Test connection');

    expect(find.text('Radarr did not answer at home or away'), findsOneWidget);
    expect(find.text('At home\u00A0· radarr.home.arpa:7878'), findsOneWidget);
    expect(find.text('Away\u00A0· radarr.example.net'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(
      container.read(currentSettingsProvider).primaryOf(ServiceKey.radarr),
      isNull,
    );

    await harness.unmount(tester);
  });

  testWidgets('plain http across the internet is refused in either field, '
      'with Use https, and nothing is sent', (tester) async {
    final (harness, _) = await _firstRunAtRadarr(tester);
    await _addAway(tester, harness, 'http://radarr.example.net');

    const refusal =
        "Cupola doesn't send your key over plain http across the internet. "
        'Use its https address, or leave this empty.';
    expect(find.text(refusal), findsOneWidget);
    expect(find.text('Use https'), findsOneWidget);

    final asked = harness.network.requests.length;
    await _tap(tester, harness, 'Test connection');
    expect(harness.network.requests.length, asked, reason: 'nothing sent');
    expect(find.text('Radarr answered.'), findsNothing);

    await _tap(tester, harness, 'Use https');
    expect(
      tester
          .widget<TextField>(_field('Address away\u00A0· optional'))
          .controller!
          .text,
      _away,
    );
    expect(find.text('Use https'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('an empty address at home is said at its field', (tester) async {
    final (harness, _) = await _firstRunAtRadarr(tester, address: '');

    await _tap(tester, harness, 'Test connection');

    expect(find.text('Add the address at home'), findsOneWidget);
    expect(find.text('Server URL is required'), findsNothing);
    final home = _field('Address at home');
    expect(tester.widget<TextField>(home).focusNode?.hasFocus, isTrue);

    await harness.unmount(tester);
  });
}
