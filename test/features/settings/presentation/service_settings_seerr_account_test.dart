/// Signing in to Seerr with an account from its connection's form: the choice
/// between the key and an account, each way in against the fake Seerr and
/// plex.tv, signing out, and a server that cannot be signed in to.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/platform/browser_opener.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';
import '../../../test_helpers/profiles/profiles.dart';

const _surface = Size(430, 2600);

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

/// [profile]'s Seerr connection signed out: its account kept, its session
/// gone.
ConfigProfile _signedOut(ConfigProfile profile) {
  final seerr = profile.connection(WorldIds.seerr);
  return profile.withConnection(
    ProfileConnection(
      seerr.instance.copyWith(account: seerr.instance.account!.signedOut),
      behaviour: seerr.behaviour,
      seerrAccount: seerr.seerrAccount,
      seerrRelease: seerr.seerrRelease,
      seerrMediaServer: seerr.seerrMediaServer,
    ),
  );
}

Future<(ProfileHarness, ProviderContainer, _Browser)> _pumpForm(
  WidgetTester tester,
  ConfigProfile profile,
) async {
  final browser = _Browser();
  final harness = await ProfileHarness.start(
    profile,
    overrides: [browserOpenerProvider.overrideWithValue(browser)],
  );
  harness.network.followFakeTime(tester.binding);
  final container = harness.container();
  await tester.binding.setSurfaceSize(_surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: ServiceSettingsScreen(
          service: ServiceKey.seerr,
          instanceId: WorldIds.seerr,
          certificateProber: (_, {pinnedFingerprint = ''}) async => null,
          localNetworkProbe: (_, {timeout = Duration.zero}) async =>
              LocalNetworkAccess.unrestricted,
        ),
      ),
    ),
  );
  await harness.settle(tester);
  return (harness, container, browser);
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _tap(
  WidgetTester tester,
  ProfileHarness harness,
  Finder finder,
) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await harness.settle(tester);
}

ServiceInstance _saved(ProviderContainer container) =>
    container.read(currentSettingsProvider).instanceById(WorldIds.seerr)!;

Iterable<String> _authRoutes(ProfileHarness harness) => harness.network
    .requestsTo(WorldIds.seerr)
    .where((r) => r.path.startsWith('/api/v1/auth/'))
    .map((r) => '${r.method} ${r.path}');

void main() {
  testWidgets('a signed-in account says who, and signs out', (tester) async {
    final (harness, container, _) = await _pumpForm(tester, Profiles.p2);
    final session = harness.network.seerrSessionOf(WorldIds.seerr);

    expect(find.text('Sign in with'), findsOneWidget);
    expect(find.text('Signed in as ${WorldPeople.anna}'), findsOneWidget);
    expect(find.textContaining('nas.home.arpa:5055'), findsWidgets);
    // An account has no key to show.
    expect(_field('API key'), findsNothing);

    await _tap(
      tester,
      harness,
      find.widgetWithText(OutlinedButton, 'Sign out'),
    );
    expect(find.textContaining('Sign out of '), findsOneWidget);
    expect(
      find.text("You'll need your password to sign in again."),
      findsOneWidget,
    );
    await _tap(tester, harness, find.widgetWithText(FilledButton, 'Sign out'));

    expect(_authRoutes(harness), contains('POST /api/v1/auth/logout'));
    expect(
      harness.network.seerrState(WorldIds.seerr).resume(session),
      isNull,
      reason: 'the server let the session go',
    );
    final saved = _saved(container);
    expect(saved.account?.session, isEmpty);
    expect(saved.account?.login, WorldSeerrUsers.annaLocal.email);
    expect(find.textContaining('Signed out of '), findsOneWidget);
    expect(find.text('Sign in again'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('signed out, signing in again needs the password alone', (
    tester,
  ) async {
    const anna = WorldSeerrUsers.annaLocal;
    final (harness, container, _) = await _pumpForm(
      tester,
      _signedOut(Profiles.p2),
    );
    expect(find.textContaining('Signed out of '), findsOneWidget);

    await _tap(tester, harness, find.text('Sign in again'));
    // The way she came in, her email already there.
    final email = tester.widget<TextField>(_field('Email'));
    expect(email.controller!.text, anna.email);
    await tester.enterText(_field('Password'), anna.password);
    await _tap(tester, harness, find.widgetWithText(FilledButton, 'Sign in'));

    final saved = _saved(container);
    expect(saved.account?.isSignedIn, isTrue);
    expect(saved.account?.permissions, 32);
    expect(saved.isConfigured, isTrue);
    expect(find.text('Signed in as ${WorldPeople.anna}'), findsOneWidget);
    final signIn = harness.network
        .requestsTo(WorldIds.seerr)
        .lastWhere((r) => r.path == '/api/v1/auth/local');
    expect(signIn.headers['cookie'], isNull);

    await harness.unmount(tester);
  });

  testWidgets('the key, then an account: the methods, a refusal, a sign-in', (
    tester,
  ) async {
    const anna = WorldSeerrUsers.annaLocal;
    final (harness, container, _) = await _pumpForm(tester, Profiles.p1);
    expect(_field('API key'), findsOneWidget);

    await _tap(tester, harness, find.bySemanticsLabel('An account'));
    // Nothing to test until an account has signed in.
    expect(find.text('Test connection'), findsNothing);
    await _tap(tester, harness, find.text('Continue'));

    expect(find.textContaining('Sign in to '), findsOneWidget);
    expect(find.text('Sign in with Jellyfin'), findsOneWidget);
    expect(find.text('Sign in with email'), findsOneWidget);
    expect(
      find.text(
        "Your password goes only to nas.home.arpa:5055. Cupola doesn't keep "
        'it.',
      ),
      findsOneWidget,
    );

    await _tap(tester, harness, find.text('Sign in with email'));
    await tester.enterText(_field('Email'), anna.email);
    await tester.enterText(_field('Password'), 'sentinel-wrong-password');
    await _tap(tester, harness, find.widgetWithText(FilledButton, 'Sign in'));
    expect(find.text("That email and password didn't work"), findsOneWidget);
    expect(find.text('Check them and sign in again.'), findsOneWidget);
    // The password left the form when it was sent.
    expect(
      tester.widget<TextField>(_field('Password')).controller!.text,
      isEmpty,
    );
    expect(find.textContaining('sentinel'), findsNothing);

    await tester.enterText(_field('Password'), anna.password);
    await _tap(tester, harness, find.widgetWithText(FilledButton, 'Sign in'));

    final saved = _saved(container);
    expect(saved.account?.userId, anna.id);
    expect(saved.credential, isEmpty, reason: 'an account takes the key out');
    expect(find.text('Signed in as ${WorldPeople.anna}'), findsOneWidget);

    // The password and the session, nowhere they should not be: the session
    // in secure storage only, the password nowhere at all.
    final prefs = container.read(sharedPreferencesProvider);
    final everythingInPrefs = [
      for (final key in prefs.getKeys()) '$key=${prefs.get(key)}',
    ].join('\n');
    expect(everythingInPrefs, isNot(contains(anna.password)));
    expect(everythingInPrefs, isNot(contains(saved.account!.session)));
    final secure =
        container.read(secureSettingsStoreProvider) as FakeSecureSettingsStore;
    expect(secure.entries['secure_seerr_session'], saved.account!.session);
    expect(secure.entries.values, isNot(contains(anna.password)));
    expect(secure.entries.containsKey('secure_seerr_api_key'), isFalse);

    await harness.unmount(tester);
  });

  testWidgets('Quick Connect: the code, approved from Jellyfin', (
    tester,
  ) async {
    final (harness, container, _) = await _pumpForm(
      tester,
      _signedOut(Profiles.p2ViaJellyfin),
    );
    // Signed out with Jellyfin: signing in again opens the Jellyfin form,
    // and the code is one way back from it.
    await _tap(tester, harness, find.text('Sign in again'));
    await _tap(tester, harness, find.text('Sign in another way'));
    await _tap(tester, harness, find.text('Sign in with a code from Jellyfin'));
    expect(
      find.text(
        "Open Jellyfin on a device where you're signed in, then enter this "
        'code under Quick Connect.',
      ),
      findsOneWidget,
    );
    final code = harness.network
        .seerrState(WorldIds.seerr)
        .quickConnectCodes
        .single
        .code;
    expect(find.text(code), findsOneWidget);

    harness.network.approveQuickConnect(WorldIds.seerr, code);
    await tester.pump(const Duration(seconds: 2));
    await harness.settle(tester);

    expect(_saved(container).account?.kind, SeerrAccountKind.jellyfin);
    expect(find.text('Signed in as ${WorldPeople.anna}'), findsOneWidget);

    await harness.unmount(tester);
  });

  group('Plex', () {
    testWidgets('the Plex page, approved, signs in and closes', (tester) async {
      final (harness, container, browser) = await _pumpForm(
        tester,
        _signedOut(Profiles.p2ViaPlex),
      );

      // A Plex account signs in again with Plex, straight away.
      await _tap(tester, harness, find.text('Sign in again'));
      expect(find.text('Finish signing in with Plex'), findsOneWidget);
      expect(
        find.text('Approve Cupola on the Plex page, then come back here.'),
        findsOneWidget,
      );
      final pin = harness.network.plexTv.pins.single;
      expect(
        browser.opened.single.toString(),
        startsWith(
          'https://app.plex.tv/auth#?clientID=$worldPlexClientId'
          '&code=${pin.code}&context%5Bdevice%5D%5Bproduct%5D=Cupola',
        ),
      );

      harness.network.claimPlexPin(pin.id);
      await tester.pump(const Duration(seconds: 1));
      await harness.settle(tester);

      expect(_saved(container).account?.isSignedIn, isTrue);
      expect(_saved(container).account?.kind, SeerrAccountKind.plex);
      expect(browser.closed, 1);
      expect(find.text('Signed in as ${WorldPeople.anna}'), findsOneWidget);
      for (final request in harness.network.requestsToHost('plex.tv')) {
        expect(request.headers.containsKey('cookie'), isFalse);
      }

      await harness.unmount(tester);
    });

    testWidgets('Cancel stops asking plex.tv, and closes the page', (
      tester,
    ) async {
      final (harness, container, browser) = await _pumpForm(
        tester,
        _signedOut(Profiles.p2ViaPlex),
      );
      await _tap(tester, harness, find.text('Sign in again'));
      await tester.pump(const Duration(seconds: 3));
      await harness.settle(tester);

      await _tap(tester, harness, find.widgetWithText(TextButton, 'Cancel'));
      final asked = harness.network.requestsToHost('plex.tv').length;
      await tester.pump(const Duration(seconds: 10));
      await harness.settle(tester);

      expect(harness.network.requestsToHost('plex.tv'), hasLength(asked));
      expect(browser.closed, 1);
      expect(find.text('Continue with Plex'), findsOneWidget);
      expect(_saved(container).account?.isSignedIn, isFalse);

      await harness.unmount(tester);
    });

    testWidgets('nobody approves it: timed out, and Start again', (
      tester,
    ) async {
      final (harness, container, _) = await _pumpForm(
        tester,
        _signedOut(Profiles.p2ViaPlex),
      );
      await _tap(tester, harness, find.text('Sign in again'));

      await tester.pump(const Duration(minutes: 16));
      await harness.settle(tester);

      expect(find.text('The Plex sign-in timed out'), findsOneWidget);
      expect(find.text('Start again'), findsOneWidget);
      expect(_saved(container).account?.isSignedIn, isFalse);
      expect(_authRoutes(harness), isNot(contains('POST /api/v1/auth/plex')));

      await harness.unmount(tester);
    });
  });

  testWidgets('a server in its first setup is never signed in to', (
    tester,
  ) async {
    final (harness, _, _) = await _pumpForm(
      tester,
      Profiles.p1.withBehaviour(
        WorldIds.seerr,
        ConnectionBehaviour.notInitialized,
      ),
    );

    await _tap(tester, harness, find.bySemanticsLabel('An account'));
    await _tap(tester, harness, find.text('Continue'));

    expect(find.text("This Seerr isn't set up yet"), findsOneWidget);
    expect(find.textContaining('Sign in with'), findsOneWidget);
    expect(_authRoutes(harness), isEmpty);

    await harness.unmount(tester);
  });

  testWidgets('every way in off: the key is offered instead', (tester) async {
    final seerr = Profiles.p1.connection(WorldIds.seerr);
    final profile = Profiles.p1.withConnection(
      seerr
          .withSeerrMediaServer(SeerrMediaServer.notConfigured)
          .withBehaviour(
            const ConnectionBehaviour.signInDisabled(SeerrSignInMethod.local),
          ),
    );
    final (harness, _, _) = await _pumpForm(tester, profile);

    await _tap(tester, harness, find.bySemanticsLabel('An account'));
    await _tap(tester, harness, find.text('Continue'));

    expect(find.text('This Seerr has sign-in turned off'), findsOneWidget);
    await _tap(tester, harness, find.text('Use the API key'));
    expect(_field('API key'), findsOneWidget);
    expect(_authRoutes(harness), isEmpty);

    await harness.unmount(tester);
  });

  testWidgets('nothing at the address: red, with Retry', (tester) async {
    final (harness, _, _) = await _pumpForm(
      tester,
      Profiles.p1.withBehaviour(
        WorldIds.seerr,
        ConnectionBehaviour.didNotAnswer,
      ),
    );

    await _tap(tester, harness, find.bySemanticsLabel('An account'));
    await _tap(tester, harness, find.text('Continue'));

    expect(find.text('Seerr did not answer'), findsOneWidget);
    expect(
      find.text('Nothing replied at nas.home.arpa:5055 from this device.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);

    await harness.unmount(tester);
  });
}
