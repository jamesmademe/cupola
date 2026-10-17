/// The household member's way in: the Welcome's "I have a Seerr account",
/// where their Seerr is, their own account on it, and the app opening for
/// them. Against the fake Seerr of each requester profile, from nothing
/// saved.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/platform/browser_opener.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/domain/seerr_invite.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/onboarding/presentation/requester_sign_in_screen.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';
import '../../../test_helpers/onboarding_router.dart';
import '../../../test_helpers/profiles/profiles.dart';

class _Browser implements BrowserOpener {
  final opened = <Uri>[];
  var closed = 0;

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }

  @override
  Future<void> close() async => closed++;
}

/// A first run, nothing saved, against [profile]'s world, opened on the
/// Welcome and through its door to the sign-in; or, with [invite], opened by
/// the invite's link, as the router rewrites it.
Future<(ProfileHarness, ProviderContainer, _Browser)> _atSignIn(
  WidgetTester tester,
  ConfigProfile profile, {
  SeerrInvite? invite,
  SeerrInvite? held,
  CertificateProber certificateProber = neverFindsACertificate,
}) async {
  final browser = _Browser();
  final harness = await ProfileHarness.start(profile);
  harness.network.followFakeTime(tester.binding);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1400);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      initialSettingsProvider.overrideWith(
        // Minted at the app's start on a first run, as every run has one.
        // and with Seerr's first slot standing empty, as a first run's does.
        (ref) => const SettingsModel(
          plexClientId: worldPlexClientId,
          // A key the keychain kept from an earlier install, with no
          // address left beside it.
          instances: [
            ServiceInstance(
              id: 'seerr',
              service: ServiceKey.seerr,
              credential: 'sentinel-stale-key',
            ),
          ],
        ),
      ),
      initialOnboardingCompletedProvider.overrideWith((ref) => false),
      browserOpenerProvider.overrideWithValue(browser),
    ],
  );
  addTearDown(container.dispose);
  // An invite shown in person, as the receiving screen leaves it.
  if (held != null) container.read(pendingInviteProvider.notifier).hold(held);
  final router = onboardingRouter(
    certificateProber: certificateProber,
    initialLocation: held != null
        ? ServiceRoutes.welcomeSignIn
        : invite == null
        ? ServiceRoutes.welcome
        : Uri(
            path: ServiceRoutes.welcomeSignIn,
            queryParameters: invite.toUri().queryParameters,
          ).toString(),
  );
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
  if (invite == null && held == null) {
    await _tap(tester, harness, find.text('I have a Seerr account'));
  }
  return (harness, container, browser);
}

Future<void> _tap(
  WidgetTester tester,
  ProfileHarness harness,
  Finder finder,
) async {
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await harness.settle(tester);
}

/// Taps [finder] and waits for the trust prompt it leads to. Not settled:
/// the sign-in's busy line turns behind the prompt until it is answered.
Future<void> _toTrustPrompt(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Finder _address() => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is OnboardingField && widget.label == 'Seerr address',
  ),
  matching: find.byType(TextField),
);

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

ServiceInstance? _seerr(ProviderContainer container) =>
    container.read(currentSettingsProvider).primaryOf(ServiceKey.seerr);

/// The app opened for whoever signed in: the way in is over and the shell is
/// drawn for them.
void _expectOpenedFor(ProviderContainer container, Audience audience) {
  expect(find.byKey(onboardingHomeStandIn), findsOneWidget);
  expect(container.read(onboardingCompletedProvider), isTrue);
  expect(container.read(shellAudienceProvider), audience);
}

void main() {
  testWidgets('with an email: where the Seerr is, the ways in, the password, '
      'and the app opens for a requester', (tester) async {
    const anna = WorldSeerrUsers.annaLocal;
    final (harness, container, _) = await _atSignIn(tester, Profiles.p2);

    expect(find.byType(RequesterSignInScreen), findsOneWidget);
    expect(find.text('Where is your Seerr?'), findsOneWidget);
    expect(
      find.text(
        'Whoever runs your server can tell you, or send you an invite.',
      ),
      findsOneWidget,
    );

    await tester.enterText(_address(), WorldHosts.seerr);
    await _tap(tester, harness, find.text('Continue'));

    expect(find.textContaining('Sign in to '), findsOneWidget);
    expect(find.text('Sign in with email'), findsOneWidget);
    expect(
      find.text(
        "Your password goes only to nas.home.arpa:5055. Cupola doesn't keep "
        'it.',
      ),
      findsOneWidget,
    );
    expect(
      _seerr(container)?.url,
      isEmpty,
      reason: 'nothing saved before a sign-in',
    );

    await _tap(tester, harness, find.text('Sign in with email'));
    await tester.enterText(_field('Email'), anna.email);
    await tester.enterText(_field('Password'), anna.password);
    await _tap(tester, harness, find.widgetWithText(FilledButton, 'Sign in'));

    final saved = _seerr(container)!;
    expect(
      container.read(currentSettingsProvider).instancesOf(ServiceKey.seerr),
      hasLength(1),
      reason: 'the empty first slot is the one signed in, not one beside it',
    );
    expect(saved.isConfigured, isTrue);
    expect(saved.credential, isEmpty, reason: 'the stale key goes');
    expect(saved.url, WorldHosts.seerr);
    expect(saved.account?.userId, anna.id);
    expect(saved.account?.isSignedIn, isTrue);
    expect(saved.credential, isEmpty);
    _expectOpenedFor(container, Audience.requester);

    final prefs = container.read(sharedPreferencesProvider);
    final everythingInPrefs = [
      for (final key in prefs.getKeys()) '$key=${prefs.get(key)}',
    ].join('\n');
    expect(everythingInPrefs, isNot(contains(anna.password)));

    await harness.unmount(tester);
  });

  testWidgets('with Plex: the Plex page, approved, opens the app', (
    tester,
  ) async {
    final (harness, container, browser) = await _atSignIn(
      tester,
      Profiles.p2ViaPlex,
    );

    await tester.enterText(_address(), WorldHosts.seerr);
    await _tap(tester, harness, find.text('Continue'));
    await _tap(tester, harness, find.text('Continue with Plex'));

    expect(find.text('Finish signing in with Plex'), findsOneWidget);
    final pin = harness.network.plexTv.pins.single;
    expect(browser.opened, hasLength(1));

    harness.network.claimPlexPin(pin.id);
    await tester.pump(const Duration(seconds: 1));
    await harness.settle(tester);

    expect(_seerr(container)?.account?.kind, SeerrAccountKind.plex);
    expect(browser.closed, 1);
    _expectOpenedFor(container, Audience.requester);

    await harness.unmount(tester);
  });

  testWidgets('with Jellyfin: the username and password Anna watches with', (
    tester,
  ) async {
    const anna = WorldSeerrUsers.annaJellyfin;
    final (harness, container, _) = await _atSignIn(
      tester,
      Profiles.p2ViaJellyfin,
    );

    await tester.enterText(_address(), WorldHosts.seerr);
    await _tap(tester, harness, find.text('Continue'));
    await _tap(tester, harness, find.text('Sign in with Jellyfin'));
    await tester.enterText(_field('Username'), anna.login);
    await tester.enterText(_field('Password'), anna.password);
    await _tap(tester, harness, find.widgetWithText(FilledButton, 'Sign in'));

    expect(_seerr(container)?.account?.kind, SeerrAccountKind.jellyfin);
    _expectOpenedFor(container, Audience.requester);

    await harness.unmount(tester);
  });

  testWidgets('an address that does not answer: red, and Check the address '
      'puts the cursor back in it', (tester) async {
    final (harness, container, _) = await _atSignIn(tester, Profiles.p2);

    await tester.enterText(_address(), 'http://seerr.home.arpa:5055');
    await _tap(tester, harness, find.text('Continue'));

    expect(find.text('Seerr did not answer'), findsOneWidget);
    expect(_address(), findsOneWidget, reason: 'the address stays to fix');

    await _tap(tester, harness, find.text('Check the address'));
    expect(tester.widget<TextField>(_address()).focusNode?.hasFocus, isTrue);
    expect(find.text('Seerr did not answer'), findsNothing);
    expect(_seerr(container)?.url, isEmpty);

    await harness.unmount(tester);
  });

  testWidgets('an empty address is said at its field, and nothing is asked', (
    tester,
  ) async {
    final (harness, _, _) = await _atSignIn(tester, Profiles.p2);
    final asked = harness.network.requests.length;

    await _tap(tester, harness, find.text('Continue'));

    expect(find.text('Add the address of your Seerr'), findsOneWidget);
    expect(harness.network.requests.length, asked);

    await harness.unmount(tester);
  });

  testWidgets('Back from the ways in returns to the address, and from the '
      'address to the Welcome', (tester) async {
    final (harness, _, _) = await _atSignIn(tester, Profiles.p2);

    await tester.enterText(_address(), WorldHosts.seerr);
    await _tap(tester, harness, find.text('Continue'));
    expect(find.text('Sign in with email'), findsOneWidget);

    await _tap(tester, harness, find.byType(BackButton));
    expect(find.text('Where is your Seerr?'), findsOneWidget);
    expect(
      tester.widget<TextField>(_address()).controller!.text,
      WorldHosts.seerr,
    );

    await _tap(tester, harness, find.byType(BackButton));
    expect(find.text('I have a Seerr account'), findsOneWidget);

    await harness.unmount(tester);
  });

  group('with an invite', () {
    const away = 'https://seerr.example.net';

    testWidgets('its link reads the server at once: no address to type, and '
        'the connection keeps both addresses', (tester) async {
      const anna = WorldSeerrUsers.annaLocal;
      final (harness, container, _) = await _atSignIn(
        tester,
        Profiles.p2,
        invite: const SeerrInvite(home: WorldHosts.seerr, away: away),
      );

      expect(find.text('Sign in with email'), findsOneWidget);

      await _tap(tester, harness, find.text('Sign in with email'));
      await tester.enterText(_field('Email'), anna.email);
      await tester.enterText(_field('Password'), anna.password);
      await _tap(tester, harness, find.widgetWithText(FilledButton, 'Sign in'));

      final saved = _seerr(container)!;
      expect(saved.url, WorldHosts.seerr);
      expect(saved.away?.url, away, reason: 'the invite\'s address away');
      expect(saved.account?.isSignedIn, isTrue);
      _expectOpenedFor(container, Audience.requester);

      await harness.unmount(tester);
    });

    testWidgets('shown in person, it is taken from memory once, and reaches '
        'the server through what its gateway asks for', (tester) async {
      const anna = WorldSeerrUsers.annaLocal;
      const gate = CustomHeaders([(name: 'X-Gate', value: 'sentinel-gate')]);
      final (harness, container, _) = await _atSignIn(
        tester,
        Profiles.p2,
        held: const SeerrInvite(home: WorldHosts.seerr, homeAccess: gate),
      );

      expect(container.read(pendingInviteProvider), isNull);
      // Read at once: past the address, on the ways in.
      expect(find.text('Sign in with email'), findsOneWidget);
      final asked = harness.network.requestsToHost('nas.home.arpa');
      expect(asked, isNotEmpty);
      for (final request in asked) {
        expect(
          request.headers.map((k, v) => MapEntry(k.toLowerCase(), v)),
          containsPair('x-gate', 'sentinel-gate'),
          reason: '${request.method} ${request.uri.path}',
        );
      }
      expect(find.textContaining('sentinel'), findsNothing);

      await _tap(tester, harness, find.text('Sign in with email'));
      await tester.enterText(_field('Email'), anna.email);
      await tester.enterText(_field('Password'), anna.password);
      await _tap(tester, harness, find.widgetWithText(FilledButton, 'Sign in'));

      final saved = _seerr(container)!;
      expect(saved.access, gate);
      expect(saved.account?.isSignedIn, isTrue);
      _expectOpenedFor(container, Audience.requester);

      await harness.unmount(tester);
    });

    testWidgets('a second one opened over the first starts afresh', (
      tester,
    ) async {
      final (harness, _, _) = await _atSignIn(
        tester,
        Profiles.p2,
        invite: const SeerrInvite(home: 'http://seerr.home.arpa:5055'),
      );
      expect(find.text('Seerr did not answer'), findsOneWidget);

      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      router.go(
        Uri(
          path: ServiceRoutes.welcomeSignIn,
          queryParameters: const SeerrInvite(
            home: WorldHosts.seerr,
          ).toUri().queryParameters,
        ).toString(),
      );
      await harness.settle(tester);

      expect(find.text('Sign in with email'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('pasted in the address, it is read the same', (tester) async {
      final (harness, _, _) = await _atSignIn(tester, Profiles.p2);
      const invite = SeerrInvite(home: WorldHosts.seerr, away: away);

      await tester.enterText(_address(), 'Here: ${invite.toLink()} ciao');
      await harness.settle(tester);

      expect(find.text('Sign in with email'), findsOneWidget);
      await _tap(tester, harness, find.byType(BackButton));
      expect(
        tester.widget<TextField>(_address()).controller!.text,
        WorldHosts.seerr,
        reason: 'the link gives way to the address it names',
      );

      await harness.unmount(tester);
    });

    testWidgets('one that is not whole is said at the address, and nothing is '
        'asked', (tester) async {
      final (harness, _, _) = await _atSignIn(tester, Profiles.p2);
      final asked = harness.network.requests.length;

      await tester.enterText(_address(), 'cupola://invite?v=1');
      await harness.settle(tester);

      expect(
        find.text("This invite isn't whole. Ask for a new one."),
        findsOneWidget,
      );
      expect(harness.network.requests.length, asked);

      await harness.unmount(tester);
    });

    testWidgets('away from home, the server is read at the address away', (
      tester,
    ) async {
      final (harness, _, _) = await _atSignIn(
        tester,
        Profiles.p2,
        invite: const SeerrInvite(
          home: 'http://seerr.home.arpa:5055',
          away: WorldHosts.seerr,
        ),
      );

      expect(find.text('Sign in with email'), findsOneWidget);
      expect(
        find.text('Seerr did not answer'),
        findsNothing,
        reason: 'home did not answer a knock, and away did',
      );

      await harness.unmount(tester);
    });
  });

  group('a certificate nothing trusts', () {
    const probe = (
      certificate: ServerCertificate(
        fingerprint:
            'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12',
        subject: 'CN=nas.home.arpa',
        issuer: 'CN=nas.home.arpa',
      ),
      rotated: false,
    );

    testWidgets('declined, is a choice: said in blue, with the certificate '
        'to look at again, and no settings to go to', (tester) async {
      final (harness, _, _) = await _atSignIn(
        tester,
        Profiles.p2,
        certificateProber: (url, {pinnedFingerprint = ''}) async =>
            UntrustedCertificate(probe),
      );
      harness.network.behave(WorldIds.seerr, ConnectionBehaviour.untrustedTls);

      await tester.enterText(_address(), WorldHosts.seerr);
      await _toTrustPrompt(tester, find.text('Continue'));
      expect(find.text('Self-signed certificate'), findsOneWidget);
      await _tap(tester, harness, find.text('Cancel'));

      expect(find.text("You didn't trust Seerr's certificate"), findsOneWidget);
      expect(find.textContaining('settings'), findsNothing);
      expect(find.text('Retry'), findsNothing);

      await _toTrustPrompt(tester, find.text('Show the certificate'));
      expect(find.text('Self-signed certificate'), findsOneWidget);
      harness.network.behave(WorldIds.seerr, ConnectionBehaviour.answers);
      await _tap(tester, harness, find.text('Trust this certificate'));

      expect(find.text('Sign in with email'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a port that answers plain http is the same notice, even when '
        'its handshake only ran out of time', (tester) async {
      final (harness, _, _) = await _atSignIn(
        tester,
        Profiles.p2,
        certificateProber: (url, {pinnedFingerprint = ''}) async =>
            const PlainHttpPort(),
      );
      harness.network.behave(WorldIds.seerr, ConnectionBehaviour.timesOut);

      await tester.enterText(_address(), WorldHosts.seerr);
      await _tap(tester, harness, find.text('Continue'));

      expect(
        find.text("Seerr didn't open a secure connection"),
        findsOneWidget,
      );
      expect(find.text('Seerr did not answer'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('with none to show, the secure connection did not open: '
        'amber, and the address to check', (tester) async {
      final (harness, _, _) = await _atSignIn(tester, Profiles.p2);
      harness.network.behave(WorldIds.seerr, ConnectionBehaviour.untrustedTls);

      await tester.enterText(_address(), WorldHosts.seerr);
      await _tap(tester, harness, find.text('Continue'));

      expect(
        find.text("Seerr didn't open a secure connection"),
        findsOneWidget,
      );
      expect(
        find.text('Check the address: Seerr may answer at http:// instead.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);

      await _tap(tester, harness, find.text('Check the address'));
      expect(tester.widget<TextField>(_address()).focusNode?.hasFocus, isTrue);

      await harness.unmount(tester);
    });
  });
}
