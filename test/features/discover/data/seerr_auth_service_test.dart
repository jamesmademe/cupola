/// Signing in to Seerr with an account, against the fake Seerr and plex.tv:
/// each way in, what it sends and never sends, the server it refuses to sign
/// in to, and the words each refusal reads as.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/discover/data/plex_tv_client.dart';
import 'package:cupola/features/discover/data/seerr_auth_service.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/discover/presentation/seerr_sign_in_notice.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// [profile]'s Seerr as a connection that has not signed in yet: its
/// address, no key, no account.
ServiceInstance _bare(ConfigProfile profile) => ServiceInstance(
  id: WorldIds.seerr,
  service: profile.connection(WorldIds.seerr).service,
  url: profile.connection(WorldIds.seerr).instance.url,
);

Future<(ProfileHarness, SeerrAuthService)> _start(
  ConfigProfile profile, {
  DateTime? now,
}) async {
  final harness = await ProfileHarness.start(profile);
  final service = SeerrAuthService.forConnection(
    _bare(profile),
    now: now == null ? null : () => now,
  );
  addTearDown(service.close);
  return (harness, service);
}

Future<Object> _failure(Future<Object?> Function() run) async {
  try {
    await run();
  } catch (error) {
    return error;
  }
  fail('it succeeded');
}

Iterable<String> _authRoutes(ProfileHarness harness) => harness.network
    .requestsTo(WorldIds.seerr)
    .where((r) => r.path.startsWith('/api/v1/auth/'))
    .map((r) => '${r.method} ${r.path}');

void main() {
  group('the server, before anyone signs in', () {
    test('reads who answers and the ways in it offers', () async {
      final (_, service) = await _start(Profiles.p2ViaJellyfin);

      final facts = await service.readServer();

      expect(facts.family, SeerrFamily.seerr);
      expect(facts.signIn.offered, [
        SeerrSignInMethod.jellyfin,
        SeerrSignInMethod.jellyfinQuickConnect,
        SeerrSignInMethod.local,
      ]);
    });

    test('a server in its first setup is never signed in to', () async {
      final profile = Profiles.p2ViaJellyfin.withBehaviour(
        WorldIds.seerr,
        ConnectionBehaviour.notInitialized,
      );
      final (harness, service) = await _start(profile);

      final facts = await service.readServer();
      expect(facts.signIn.state, SeerrSignInState.notSetUp);
      expect(
        SeerrSignInNotice.ofMethods(facts.signIn),
        SeerrSignInNotice.notSetUp,
      );

      const anna = WorldSeerrUsers.annaJellyfin;
      final error = await _failure(
        () => service.signInWithMediaServer(
          facts,
          username: anna.login,
          password: anna.password,
        ),
      );
      expect(error, isA<SeerrSignInRefused>());
      // Nothing was sent: the first media-server sign-in would have made its
      // sender the admin.
      expect(_authRoutes(harness), isEmpty);
      expect(harness.network.seerrState(WorldIds.seerr).createdUsers, isEmpty);
    });

    test('a server with every way in off says so, in blue', () async {
      final profile = Profiles.p2.withBehaviour(
        WorldIds.seerr,
        const ConnectionBehaviour.signInDisabled(SeerrSignInMethod.local),
      );
      final (_, service) = await _start(
        profile.withSeerrRelease(SeerrRelease.overseerr),
      );

      final facts = await service.readServer();
      // Overseerr always offers Plex; its local sign-in is off here.
      expect(facts.signIn.offered, [SeerrSignInMethod.plex]);
    });

    test('something else at the address stops before any secret', () async {
      final profile = Profiles.p2.withBehaviour(
        WorldIds.seerr,
        const ConnectionBehaviour.answersAsOtherService(ServiceKey.radarr),
      );
      final (harness, service) = await _start(profile);

      final error = await _failure(service.readServer);
      final notice = SeerrSignInNotice.ofServerRead(
        error,
        url: WorldHosts.seerr,
      );

      expect(notice.kind, SeerrSignInNoticeKind.notSeerr);
      expect(
        notice.title,
        "Something answered at nas.home.arpa:5055, but it isn't Seerr",
      );
      expect(_authRoutes(harness), isEmpty);
    });

    test('nothing at the address is the one red notice', () async {
      final profile = Profiles.p2.withBehaviour(
        WorldIds.seerr,
        ConnectionBehaviour.didNotAnswer,
      );
      final (_, service) = await _start(profile);

      final notice = SeerrSignInNotice.ofServerRead(
        await _failure(service.readServer),
        url: WorldHosts.seerr,
      );

      expect(notice.tone, StatusTone.error);
      expect(notice.title, 'Seerr did not answer');
      expect(
        notice.sentence,
        'Nothing replied at nas.home.arpa:5055 from this phone.',
      );
      expect(notice.retryHelps, isTrue);
    });
  });

  group('with an email and a password', () {
    test('signs in, and keeps the session and the account', () async {
      final now = DateTime.utc(2026, 10, 2, 9);
      final (harness, service) = await _start(Profiles.p2, now: now);
      const anna = WorldSeerrUsers.annaLocal;
      final facts = await service.readServer();

      final account = await service.signInWithEmail(
        facts,
        email: anna.email,
        password: anna.password,
      );

      expect(account.kind, SeerrAccountKind.local);
      expect(account.login, anna.email);
      expect(account.userId, anna.id);
      expect(account.displayName, WorldPeople.anna);
      // `/auth/me`'s, not the sign-in answer's `0`.
      expect(account.permissions, 32);
      expect(account.checkedAt, now);
      expect(account.session, startsWith('s%3A'));
      final signIn = harness.network
          .requestsTo(WorldIds.seerr)
          .firstWhere((r) => r.path == '/api/v1/auth/local');
      expect(signIn.headers['cookie'], isNull);
      expect(signIn.headers.containsKey('x-api-key'), isFalse);
      // The session works: a client sending it is Anna.
      expect(
        harness.network.seerrState(WorldIds.seerr).resume(account.session),
        isNotNull,
      );
    });

    test('a wrong password reads as the pair that did not work', () async {
      final (_, service) = await _start(Profiles.p2);
      final facts = await service.readServer();

      final notice = SeerrSignInNotice.ofSignIn(
        await _failure(
          () => service.signInWithEmail(
            facts,
            email: WorldSeerrUsers.annaLocal.email,
            password: 'sentinel-wrong-password',
          ),
        ),
        method: SeerrSignInMethod.local,
      );

      expect(notice.kind, SeerrSignInNoticeKind.wrongEmailOrPassword);
      expect(notice.tone, StatusTone.warning);
      expect(notice.title, "That email and password didn't work");
      expect(notice.sentence, 'Check them and sign in again.');
      expect('$notice${notice.spoken}', isNot(contains('sentinel')));
    });

    test('with CSRF on, the sign-in fetches its token first', () async {
      final (_, service) = await _start(
        Profiles.p2.withBehaviour(
          WorldIds.seerr,
          ConnectionBehaviour.csrfProtected,
        ),
      );
      const anna = WorldSeerrUsers.annaLocal;
      final facts = await service.readServer();

      final account = await service.signInWithEmail(
        facts,
        email: anna.email,
        password: anna.password,
      );

      expect(account.isSignedIn, isTrue);
    });
  });

  group('with Jellyfin', () {
    test('a username and password sign in as the Jellyfin user', () async {
      final (harness, service) = await _start(Profiles.p2ViaJellyfin);
      const anna = WorldSeerrUsers.annaJellyfin;
      final facts = await service.readServer();

      final account = await service.signInWithMediaServer(
        facts,
        username: anna.login,
        password: anna.password,
      );

      expect(account.kind, SeerrAccountKind.jellyfin);
      expect(account.login, anna.login);
      final body =
          harness.network
                  .requestsTo(WorldIds.seerr)
                  .firstWhere((r) => r.path == '/api/v1/auth/jellyfin')
                  .json
              as Map;
      // Never a hostname: that is what sets a new server up.
      expect(body.keys, unorderedEquals(['username', 'password']));
    });

    test('Jellyfin refusing the pair says to use its own', () async {
      final (_, service) = await _start(Profiles.p2ViaJellyfin);
      final facts = await service.readServer();

      final notice = SeerrSignInNotice.ofSignIn(
        await _failure(
          () => service.signInWithMediaServer(
            facts,
            username: 'anna',
            password: 'sentinel-wrong-password',
          ),
        ),
        method: SeerrSignInMethod.jellyfin,
      );

      expect(notice.title, "That username and password didn't work");
      expect(notice.sentence, 'Use the ones you watch Jellyfin with.');
    });

    test('Quick Connect: a code, approved from Jellyfin, signs in', () async {
      final (harness, service) = await _start(Profiles.p2ViaJellyfin);
      final facts = await service.readServer();

      final code = await service.startQuickConnect(facts);
      expect(code.code, hasLength(6));
      expect(await service.quickConnectApproved(code), isFalse);

      harness.network.approveQuickConnect(WorldIds.seerr, code.code);
      expect(await service.quickConnectApproved(code), isTrue);
      final account = await service.finishQuickConnect(facts, code);

      expect(account.kind, SeerrAccountKind.jellyfin);
      expect(account.login, WorldSeerrUsers.annaJellyfin.login);
      expect(account.displayName, WorldPeople.anna);
      expect('$code', isNot(contains(code.code)));
    });

    test('a code nobody approved in ten minutes expires', () async {
      final (harness, service) = await _start(Profiles.p2ViaJellyfin);
      final facts = await service.readServer();
      final code = await service.startQuickConnect(facts);

      harness.network.elapse(const Duration(minutes: 11));

      expect(
        await _failure(() => service.quickConnectApproved(code)),
        isA<SeerrQuickConnectExpired>(),
      );
    });

    test('Quick Connect is offered only from Seerr 3.4', () async {
      final (_, service) = await _start(
        Profiles.p2.withSeerrRelease(SeerrRelease.jellyseerr2),
      );
      final facts = await service.readServer();

      expect(
        facts.signIn.offers(SeerrSignInMethod.jellyfinQuickConnect),
        isFalse,
      );
      expect(
        await _failure(() => service.startQuickConnect(facts)),
        isA<SeerrSignInRefused>(),
      );
    });
  });

  group('with Plex, through plex.tv', () {
    test('a PIN, approved on app.plex.tv, hands Seerr the token', () async {
      final (harness, service) = await _start(Profiles.p2ViaPlex);
      final plexTv = PlexTvClient(clientIdentifier: 'world-client-id');
      addTearDown(plexTv.close);
      final facts = await service.readServer();
      expect(facts.signIn.offered.first, SeerrSignInMethod.plex);

      final pin = await plexTv.createPin();
      expect(
        plexTv.authUrl(pin).toString(),
        'https://app.plex.tv/auth#?clientID=world-client-id'
        '&code=${pin.code}&context%5Bdevice%5D%5Bproduct%5D=Cupola',
      );
      expect(await plexTv.authTokenOf(pin), isNull);

      harness.network.claimPlexPin(pin.id);
      final token = await plexTv.authTokenOf(pin);
      final account = await service.signInWithPlex(facts, authToken: token!);

      expect(account.kind, SeerrAccountKind.plex);
      expect(account.login, isEmpty);
      expect(account.userId, WorldSeerrUsers.annaPlex.id);

      // plex.tv never gets Seerr's cookie or a key; Seerr never a Plex
      // header but the one token in the body.
      for (final request in harness.network.requestsToHost('plex.tv')) {
        expect(request.headers.containsKey('cookie'), isFalse);
        expect(request.headers.containsKey('x-api-key'), isFalse);
        expect(request.headers['x-plex-client-identifier'], 'world-client-id');
        expect(request.headers['x-plex-product'], 'Cupola');
      }
      for (final request in harness.network.requestsTo(WorldIds.seerr)) {
        expect(request.headers.containsKey('x-plex-token'), isFalse);
      }
      expect('$account', isNot(contains(token)));
    });

    test('a PIN nobody approved expires on plex.tv', () async {
      final (harness, _) = await _start(Profiles.p2ViaPlex);
      final plexTv = PlexTvClient(clientIdentifier: 'world-client-id');
      addTearDown(plexTv.close);
      final pin = await plexTv.createPin();

      harness.network.elapse(const Duration(minutes: 31));

      expect(
        await _failure(() => plexTv.authTokenOf(pin)),
        isA<PlexTvPinExpired>(),
      );
    });

    test(
      'a Plex account the server does not share with is not let in',
      () async {
        final (harness, service) = await _start(Profiles.p2ViaPlex);
        final facts = await service.readServer();
        final plexTv = PlexTvClient(clientIdentifier: 'world-client-id');
        addTearDown(plexTv.close);
        final pin = await plexTv.createPin();
        harness.network.claimPlexPin(
          pin.id,
          authToken: 'sentinel-stranger-token',
        );
        final token = (await plexTv.authTokenOf(pin))!;

        final notice = SeerrSignInNotice.ofSignIn(
          await _failure(() => service.signInWithPlex(facts, authToken: token)),
          method: SeerrSignInMethod.plex,
        );

        expect(notice.kind, SeerrSignInNoticeKind.accountNotAllowed);
        expect(notice.title, "This account can't sign in here yet");
        expect(notice.spoken, isNot(contains('sentinel')));
      },
    );
  });

  test('signing out ends the session on the server', () async {
    final harness = await ProfileHarness.start(Profiles.p2);
    final instance = Profiles.p2.connection(WorldIds.seerr).instance;
    final state = harness.network.seerrState(WorldIds.seerr);
    final session = harness.network.seerrSessionOf(WorldIds.seerr);

    await signOutOfSeerr(instance);

    expect(state.resume(session), isNull);
    expect(
      harness.network
          .requestsTo(WorldIds.seerr)
          .map((r) => '${r.method} ${r.path}'),
      ['POST /api/v1/auth/logout'],
    );
  });

  test('a sign-in turned off since the methods were read redraws them', () {
    final notice = SeerrSignInNotice.methodTurnedOff;
    expect(notice.tone, StatusTone.info);
    expect(notice.title, 'This way of signing in was just turned off');
  });

  test('a password goes over http:// only past the warning, off home', () {
    expect(passwordTravelsInClear('http://seerr.example.net'), isTrue);
    expect(passwordTravelsInClear('http://203.0.113.7:5055'), isTrue);
    expect(passwordTravelsInClear('https://seerr.example.net'), isFalse);
    expect(passwordTravelsInClear('http://nas.home.arpa:5055'), isFalse);
    expect(passwordTravelsInClear('http://192.168.1.20:5055'), isFalse);
    expect(passwordTravelsInClear('http://nas:5055'), isFalse);
    expect(passwordTravelsInClear('http://localhost:5055'), isFalse);
    expect(
      SeerrSignInNotice.notEncrypted.title,
      "This address isn't encrypted",
    );
  });

  test('a saved account signed out reads blue, and names the server', () {
    final notice = SeerrSignInNotice.signedOut('Casa Requests');
    expect(notice.tone, StatusTone.info);
    expect(notice.title, 'Signed out of Casa Requests');
    expect(
      notice.sentence,
      'Sign in again to keep asking for movies and series.',
    );
  });
}
