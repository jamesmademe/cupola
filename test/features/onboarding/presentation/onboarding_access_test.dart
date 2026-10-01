/// The first run behind a gateway: the walk's test meets Cloudflare Access, a
/// password prompt or a sign-in page before any connection is saved, and the
/// remedy is answered in the step, with the connection form's own Access row.
/// It never opens a form for a connection that does not exist yet.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/onboarding/presentation/onboarding_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';
import '../../../test_helpers/profiles/profiles.dart';

/// A first run (nothing saved) on [profile]'s network, walked to Radarr's
/// step with its address and key typed.
Future<(ProfileHarness, ProviderContainer)> _firstRunAtRadarr(
  WidgetTester tester,
  ConfigProfile profile, {
  String address = WorldHosts.radarr,
}) async {
  final harness = await ProfileHarness.start(profile);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 2400);
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
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: OnboardingScreen(
          certificateProber: (_, {pinnedFingerprint = ''}) async => null,
          localNetworkProbe: (_, {timeout = Duration.zero}) async =>
              LocalNetworkAccess.unrestricted,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  await harness.settle(tester);
  await _tap(tester, harness, 'Set up my stack');
  await tester.tap(find.text('Radarr').first);
  await harness.settle(tester);
  await _tap(tester, harness, 'Continue with 1');
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), address);
  await tester.enterText(fields.at(1), worldKey(WorldIds.radarr));
  await harness.settle(tester);
  return (harness, container);
}

/// Taps [text] where it stands. No scrolling into view: the beat is a page
/// of a pager, and scrolling an enclosing scrollable would move the pager too.
Future<void> _tap(
  WidgetTester tester,
  ProfileHarness harness,
  String text,
) async {
  await tester.tap(find.text(text).first);
  await harness.settle(tester);
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

bool _selected(WidgetTester tester, String choice) =>
    tester
        .getSemantics(find.bySemanticsLabel(choice))
        .flagsCollection
        .isSelected ==
    Tristate.isTrue;

void main() {
  testWidgets('Cloudflare Access at first run: the remedy opens the Access '
      'row in the step, and the walk saves Radarr with its token', (
    tester,
  ) async {
    final (harness, container) = await _firstRunAtRadarr(tester, Profiles.p8);

    await _tap(tester, harness, 'Test connection');
    expect(
      find.text(
        'Radarr is behind Cloudflare Access. Cupola needs a service token to '
        'reach it.',
      ),
      findsOneWidget,
    );
    // No Access row until the remedy asks for it.
    expect(_field('Client ID'), findsNothing);

    await _tap(tester, harness, 'Add a service token');
    // Answered here: still the walk's step, no connection form.
    expect(find.byType(ServiceSettingsScreen), findsNothing);
    expect(find.text('Where does Radarr live?'), findsWidgets);
    expect(_selected(tester, 'Cloudflare Access'), isTrue);

    await tester.enterText(_field('Client ID'), WorldTokens.radarr.id);
    await tester.enterText(_field('Client secret'), WorldTokens.radarr.secret);
    await _tap(tester, harness, 'Test connection');
    expect(
      find.text('Access let the token through and Radarr answered.'),
      findsOneWidget,
    );

    await _tap(tester, harness, 'Finish');
    final radarr = container
        .read(settingsProvider)
        .instanceById(WorldIds.radarr);
    expect(radarr?.url, WorldHosts.radarr);
    expect(radarr?.credential, worldKey(WorldIds.radarr));
    expect(radarr?.access, WorldTokens.radarr.access);

    await harness.unmount(tester);
  });

  testWidgets('a password prompt at first run: an address typed with '
      'user:password@ becomes the proxy password, and the walk saves it', (
    tester,
  ) async {
    final (harness, container) = await _firstRunAtRadarr(
      tester,
      Profiles.p3.withBehaviour(
        WorldIds.radarr,
        const ConnectionBehaviour.behindPasswordPrompt(
          credentials: (username: 'matt', password: 'proxy-pw'),
        ),
      ),
      address: 'http://matt:proxy-pw@nas.home.arpa:7878',
    );
    // Accepted in the field: the test takes the credentials off it.
    expect(find.textContaining('Remove the username:password'), findsNothing);

    await _tap(tester, harness, 'Test connection');
    expect(find.text('Radarr answered.'), findsOneWidget);
    expect(_selected(tester, 'Password'), isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      WorldHosts.radarr,
    );

    await _tap(tester, harness, 'Finish');
    final radarr = container
        .read(settingsProvider)
        .instanceById(WorldIds.radarr);
    expect(radarr?.url, WorldHosts.radarr);
    expect(
      radarr?.access,
      const ProxyPassword(username: 'matt', password: 'proxy-pw'),
    );

    await harness.unmount(tester);
  });

  testWidgets('a password prompt at first run, no password typed: Add the '
      'password opens the row on Password', (tester) async {
    final (harness, _) = await _firstRunAtRadarr(
      tester,
      Profiles.p3.withBehaviour(
        WorldIds.radarr,
        const ConnectionBehaviour.behindPasswordPrompt(),
      ),
    );

    await _tap(tester, harness, 'Test connection');
    await _tap(tester, harness, 'Add the password');

    expect(find.byType(ServiceSettingsScreen), findsNothing);
    expect(_selected(tester, 'Password'), isTrue);
    expect(_field('Proxy username'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('a sign-in page at first run: Add access opens the row on '
      'Password, in the step', (tester) async {
    final (harness, _) = await _firstRunAtRadarr(
      tester,
      Profiles.p3.withBehaviour(
        WorldIds.radarr,
        const ConnectionBehaviour.behindSignInPage(),
      ),
    );

    await _tap(tester, harness, 'Test connection');
    expect(
      find.text(
        'Something in front of Radarr asks for a sign-in that Cupola cannot '
        'complete.',
      ),
      findsOneWidget,
    );
    await _tap(tester, harness, 'Add access');

    expect(find.byType(ServiceSettingsScreen), findsNothing);
    expect(_selected(tester, 'Password'), isTrue);

    await harness.unmount(tester);
  });
}
