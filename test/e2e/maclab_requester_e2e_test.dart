@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/capability/permission_refusal.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/data/seerr_auth_service.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/discover/presentation/seerr_sign_in_notice.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/settings_scope.dart';

/// A household member's own Seerr account against the real Seerr of the
/// macOS lab (Seerr 3.4.1 set up on Jellyfin 12.1), through the app's own
/// code: [SeerrAuthService] signs in, [seerrClientFor] carries the session
/// and the CSRF token, [SeerrAccounts] and the providers keep the account.
///
/// The offline suite proves the same paths against the fakes in
/// `test/test_helpers/profiles/fakes/seerr_sessions.dart`; this proves the
/// fakes answer as Seerr does. The bootstrap seeds the two accounts it signs
/// in as, each with REQUEST alone, and writes their generated passwords to
/// the lab's credentials file (`CUPOLA_MACLAB_CREDENTIALS_FILE`, or
/// `.ai/scratch/zz_maclab/state/credentials.env` under the working
/// directory). Asking for a title needs the lab's Seerr to reach TMDB.
///
/// The CSRF group restarts the Seerr container twice, to turn the protection
/// on and to put it back. It runs last.
void main() {
  late _Lab lab;

  setUpAll(() async {
    lab = _Lab.load();
    await lab.waitForSeerr();
  });

  group('the server', () {
    test('says how it may be signed in to', () async {
      final auth = SeerrAuthService.forConnection(lab.accountConnection());
      addTearDown(auth.close);

      final facts = await auth.readServer();

      expect(facts.family, SeerrFamily.seerr);
      expect(facts.version, matches(r'^3\.'));
      expect(facts.mediaServer, SeerrMediaServer.jellyfin);
      expect(facts.signIn.state, SeerrSignInState.open);
      expect(facts.signIn.offered, const [
        SeerrSignInMethod.jellyfin,
        SeerrSignInMethod.jellyfinQuickConnect,
        SeerrSignInMethod.local,
      ]);

      final container = await lab.container([lab.accountConnection()]);
      expect(
        await container.read(seerrServerFactsProvider(_accountId).future),
        facts,
      );
    });
  });

  group('email and password', () {
    test('a wrong password is refused as one', () async {
      final auth = SeerrAuthService.forConnection(lab.accountConnection());
      addTearDown(auth.close);
      final facts = await auth.readServer();

      final error = await _caught(
        () => auth.signInWithEmail(
          facts,
          email: lab.email,
          password: '${lab.emailPassword}-not-it',
        ),
      );

      expect(seerrRefusalOf(error), SeerrRefusal.wrongEmailOrPassword);
      expect(
        SeerrSignInNotice.ofSignIn(error, method: SeerrSignInMethod.local).kind,
        SeerrSignInNoticeKind.wrongEmailOrPassword,
      );
    });

    test('the right one signs in, as a requester', () async {
      final auth = SeerrAuthService.forConnection(lab.accountConnection());
      addTearDown(auth.close);
      final facts = await auth.readServer();

      final account = await auth.signInWithEmail(
        facts,
        email: lab.email,
        password: lab.emailPassword,
      );

      expect(account.kind, SeerrAccountKind.local);
      expect(account.isSignedIn, isTrue);
      expect(account.login, lab.email);
      expect(account.userId, greaterThan(1));
      expect(account.displayName, isNotEmpty);
      // `/auth/me`, not the sign-in's own answer, which says 0.
      expect(account.permissions, SeerrPermission.request.value);
      final grant = SeerrGrant.account(permissions: account.permissions);
      expect(grant.role, SeerrRole.requester);
      expect(grant.may(SeerrAbility.request, kind: SeerrMediaKind.movie), true);
      expect(grant.may(SeerrAbility.approve), isFalse);
      expect(grant.may(SeerrAbility.seeEveryonesRequests), isFalse);

      // Kept on its connection, and read back through the providers.
      final container = await lab.container([lab.accountConnection()]);
      await container
          .read(seerrAccountsProvider)
          .signedIn(lab.accountConnection(), account);
      expect(container.read(seerrGrantProvider(_accountId)), grant);
      final saved = container
          .read(currentSettingsProvider)
          .instanceById(_accountId)!;
      expect(saved.isConfigured, isTrue);
      expect(saved.credential, isEmpty);
      // Testing the connection asks Seerr as the account.
      expect(
        (await diagnoseSeerr(saved)).status,
        ServiceConnectionStatus.connected,
      );

      // The account's own requests, and nobody else's.
      final requests = await container
          .read(seerrServiceForProvider(_accountId))
          .getRequests();
      expect(
        requests.map((request) => request.requestedBy?.id).toSet(),
        anyOf(isEmpty, {account.userId}),
      );
      final quota = await container.read(seerrQuotaProvider(_accountId).future);
      expect(quota, isNotNull);
    });
  });

  group('a way in the operator closed', () {
    test('turned off since the methods were read: the route says so', () async {
      final operator = seerrClientFor(lab.keyConnection());
      addTearDown(operator.close);
      final auth = SeerrAuthService.forConnection(lab.accountConnection());
      addTearDown(auth.close);
      final facts = await auth.readServer();
      expect(facts.signIn.offers(SeerrSignInMethod.local), isTrue);

      await lab.setMainSettings(operator, {'localLogin': false});
      addTearDown(() => lab.setMainSettings(operator, {'localLogin': true}));

      final error = await _caught(
        () => auth.signInWithEmail(
          facts,
          email: lab.email,
          password: lab.emailPassword,
        ),
      );
      expect(seerrRefusalOf(error), SeerrRefusal.signInTurnedOff);
      expect(
        SeerrSignInNotice.ofSignIn(error, method: SeerrSignInMethod.local).kind,
        SeerrSignInNoticeKind.methodTurnedOff,
      );
      // Read again, the methods no longer offer it.
      final now = await auth.readServer();
      expect(now.signIn.offers(SeerrSignInMethod.local), isFalse);
    });

    test('a Jellyfin user the server does not take', () async {
      final operator = seerrClientFor(lab.keyConnection());
      addTearDown(operator.close);
      final stranger = await lab.newJellyfinUser();
      addTearDown(stranger.remove);
      await lab.setMainSettings(operator, {'newPlexLogin': false});
      addTearDown(() => lab.setMainSettings(operator, {'newPlexLogin': true}));

      final auth = SeerrAuthService.forConnection(lab.accountConnection());
      addTearDown(auth.close);
      final error = await _caught(
        () async => auth.signInWithMediaServer(
          await auth.readServer(),
          username: stranger.name,
          password: stranger.password,
        ),
      );

      expect(seerrRefusalOf(error), SeerrRefusal.accountNotAllowed);
      expect(
        SeerrSignInNotice.ofSignIn(
          error,
          method: SeerrSignInMethod.jellyfin,
        ).kind,
        SeerrSignInNoticeKind.accountNotAllowed,
      );
    });
  });

  group('as the account', () {
    test('asks for a movie, and is refused the operator\'s writes', () async {
      final operator = lab.operator();
      await _withdrawRequestsFor(operator, _movie);

      final container = await lab.signedInContainer();
      final seerr = container.read(seerrServiceForProvider(_accountId));

      await seerr.createRequest(mediaType: 'movie', mediaId: _movie);
      final mine = (await seerr.getRequests())
          .where((request) => request.media?.tmdbId == _movie)
          .single;
      expect(mine.status, RequestStatus.pendingApproval);
      expect(mine.requestedBy?.id, lab.accountOf(container).userId);
      addTearDown(() => _withdrawRequestsFor(operator, _movie));

      // A 4K copy the account may not ask for.
      final fourK = await _caught(
        () => seerr.createRequest(
          mediaType: 'movie',
          mediaId: _movie,
          is4k: true,
        ),
      );
      expect(seerrRefusalOf(fourK), SeerrRefusal.requestNotAllowed);

      // The operator's write: Seerr refuses it, `/auth/me` still answers, so
      // it is a permission the account lacks, never a refused key or an
      // ended session.
      final checkedBefore = lab.accountOf(container).checkedAt;
      final approve = await _caught(() => seerr.approveRequest(mine.id));
      expect(seerrRefusalOf(approve), SeerrRefusal.permissionDenied);
      expect(isPermissionRefusal(approve), isTrue);
      expect(
        classifyConnectionFailure(approve),
        isNot(ServiceFailureReason.sessionEnded),
      );
      final decline = await _caught(() => seerr.declineRequest(mine.id));
      expect(seerrRefusalOf(decline), SeerrRefusal.permissionDenied);
      await pumpEventQueue();
      final after = lab.accountOf(container);
      expect(after.isSignedIn, isTrue, reason: 'still signed in');
      expect(after.checkedAt, isNot(checkedBefore), reason: 'asked /auth/me');

      // Its own request, still waiting: the account may cancel it.
      await seerr.deleteRequest(mine.id);
      expect(
        (await seerr.getRequests()).where((r) => r.media?.tmdbId == _movie),
        isEmpty,
      );
    });

    test('follows the permissions the operator gives it', () async {
      final container = await lab.signedInContainer();
      final userId = lab.accountOf(container).userId;
      final operator = seerrClientFor(lab.keyConnection());
      addTearDown(operator.close);
      Future<void> grant(int permissions) => operator.post(
        '/api/v1/user/$userId/settings/permissions',
        data: {'permissions': permissions},
      );
      addTearDown(() => grant(SeerrPermission.request.value));

      await grant(
        SeerrPermission.request.value | SeerrPermission.manageRequests.value,
      );
      await container.read(seerrAccountsProvider).refresh(_accountId);

      expect(
        container.read(seerrGrantProvider(_accountId))!.role,
        SeerrRole.manager,
      );
    });
  });

  group('Jellyfin', () {
    test('a wrong password is refused as one', () async {
      final auth = SeerrAuthService.forConnection(lab.accountConnection());
      addTearDown(auth.close);
      final facts = await auth.readServer();

      final error = await _caught(
        () => auth.signInWithMediaServer(
          facts,
          username: lab.viewer,
          password: '${lab.viewerPassword}-not-it',
        ),
      );

      expect(seerrRefusalOf(error), SeerrRefusal.wrongUsernameOrPassword);
      expect(
        SeerrSignInNotice.ofSignIn(
          error,
          method: SeerrSignInMethod.jellyfin,
        ).kind,
        SeerrSignInNoticeKind.wrongUsernameOrPassword,
      );
    });

    test('a username and password sign in', () async {
      final account = await lab.signInWithJellyfin();

      expect(account.kind, SeerrAccountKind.jellyfin);
      expect(account.login, lab.viewer);
      expect(account.isSignedIn, isTrue);
      expect(account.permissions, SeerrPermission.request.value);
    });

    test('a Quick Connect code approved in Jellyfin signs in', () async {
      final auth = SeerrAuthService.forConnection(lab.accountConnection());
      addTearDown(auth.close);
      final facts = await auth.readServer();
      expect(facts.signIn.offers(SeerrSignInMethod.jellyfinQuickConnect), true);

      final code = await auth.startQuickConnect(facts);
      expect(code.code, matches(r'^\d{6}$'));
      expect(await auth.quickConnectApproved(code), isFalse);

      // Somebody signed in to a Jellyfin app types the code there.
      await lab.approveQuickConnect(code.code);
      var approved = false;
      for (var attempt = 0; attempt < 10 && !approved; attempt++) {
        approved = await auth.quickConnectApproved(code);
        if (!approved) await Future<void>.delayed(const Duration(seconds: 1));
      }
      expect(approved, isTrue);

      final account = await auth.finishQuickConnect(facts, code);
      expect(account.kind, SeerrAccountKind.jellyfin);
      expect(account.login, lab.viewer);
      expect(account.isSignedIn, isTrue);
      expect(account.userId, (await lab.signInWithJellyfin()).userId);
    });
  });

  group('signing out', () {
    test('the server forgets the session', () async {
      final container = await lab.signedInContainer();
      final before = container
          .read(currentSettingsProvider)
          .instanceById(_accountId)!;

      await container.read(seerrAccountsProvider).signOut(_accountId);

      final after = container
          .read(currentSettingsProvider)
          .instanceById(_accountId)!;
      expect(after.isSignedOut, isTrue);
      expect(after.account!.login, lab.email, reason: 'one step back in');
      // Nothing is sent for it now: the connection reads as signed out.
      final local = await _caught(
        () async => container.read(seerrServiceForProvider(_accountId)),
      );
      expect(
        classifyConnectionFailure(local),
        ServiceFailureReason.sessionEnded,
      );

      // A client still holding the old session: the server no longer knows it.
      final staleClient = seerrClientFor(before);
      addTearDown(staleClient.close);
      final stale = SeerrService(staleClient);
      final error = await _caught(stale.getRequests);
      expect(seerrRefusalOf(error), SeerrRefusal.sessionEnded);
      _expectSignedOutWords(error);
      expect(
        (await diagnoseSeerr(before)).reason,
        ServiceFailureReason.sessionEnded,
      );
    });

    test('a session the server ended reads as ended, every time', () async {
      final container = await lab.signedInContainer();
      final instance = container
          .read(currentSettingsProvider)
          .instanceById(_accountId)!;
      final seerr = container.read(seerrServiceForProvider(_accountId));
      expect(await seerr.getRequests(), isA<List<SeerrRequest>>());
      // A second client of the same session, kept across requests the way a
      // background read keeps one.
      var ended = 0;
      final held = seerrClientFor(
        instance,
        events: SeerrSessionEvents(onSessionEnded: () => ended++),
      );
      addTearDown(held.close);

      // Signed out on another device, behind this one's back.
      await signOutOfSeerr(instance);

      final first = await _caught(seerr.getRequests);
      expect(seerrRefusalOf(first), SeerrRefusal.sessionEnded);
      _expectSignedOutWords(first);
      await pumpEventQueue();
      expect(
        container
            .read(currentSettingsProvider)
            .instanceById(_accountId)!
            .isSignedOut,
        isTrue,
      );

      // The kept client finds out, then goes on without the session, and
      // Seerr answers that with a 401 of its own: the same ended session,
      // said once, never a refused credential.
      for (var read = 0; read < 2; read++) {
        final error = await _caught(() => SeerrService(held).getRequests());
        expect(seerrRefusalOf(error), SeerrRefusal.sessionEnded);
        _expectSignedOutWords(error);
      }
      expect(ended, 1);
    });
  });

  group('behind a gateway', () {
    test('custom headers reach Seerr, and the account signs in', () async {
      final gateway = await _Gateway.start(lab.seerrUrl);
      addTearDown(gateway.close);
      final access = CustomHeaders([
        (name: _Gateway.header, value: gateway.secret),
      ]);
      final connection = lab.accountConnection(
        url: gateway.url,
        access: access,
      );

      final auth = SeerrAuthService.forConnection(connection);
      addTearDown(auth.close);
      final facts = await auth.readServer();
      final account = await auth.signInWithEmail(
        facts,
        email: lab.email,
        password: lab.emailPassword,
      );
      expect(account.isSignedIn, isTrue);

      final container = await lab.container([connection]);
      await container.read(seerrAccountsProvider).signedIn(connection, account);
      await container.read(seerrServiceForProvider(_accountId)).getRequests();

      expect(gateway.refused, 0);
      expect(gateway.let, greaterThanOrEqualTo(5));

      // The same address without the header meets the gateway, not Seerr.
      final bare = SeerrAuthService.forConnection(
        lab.accountConnection(url: gateway.url),
      );
      addTearDown(bare.close);
      await _caught(bare.readServer);
      expect(gateway.refused, greaterThan(0));
    });
  });

  group('Plex', () {
    // Skipped from inside, so `--run-skipped` cannot turn it into a pass.
    test('signs in through plex.tv', () {
      markTestSkipped(
        'Needs a second Seerr set up on Plex with a real plex.tv account, '
        'and a person to approve the PIN on app.plex.tv: run by hand, see '
        'test/e2e/README.md, "Signing in with Plex".',
      );
    });
  });

  group('with CSRF protection on', () {
    test('writes as the key and as an account pass the guard', () async {
      final operatorClient = seerrClientFor(lab.keyConnection());
      addTearDown(operatorClient.close);
      await lab.setCsrfProtection(operatorClient, on: true);
      addTearDown(() async {
        final client = seerrClientFor(lab.keyConnection());
        try {
          await lab.setCsrfProtection(client, on: false);
        } finally {
          client.close();
        }
      });

      // The guard is up: a write without the token is refused, key and all.
      final raw = await _rawJson(
        'POST',
        '${lab.seerrUrl}/api/v1/request/1/decline',
        headers: {'X-Api-Key': lab.apiKey},
      );
      expect(raw.status, 403);
      expect(raw.body, {'message': 'invalid csrf token'});

      // Signing in is a write too.
      final container = await lab.signedInContainer();
      final seerr = container.read(seerrServiceForProvider(_accountId));
      final operator = lab.operator();
      await _withdrawRequestsFor(operator, _movie);
      addTearDown(() => _withdrawRequestsFor(operator, _movie));

      await seerr.createRequest(mediaType: 'movie', mediaId: _movie);
      final mine = (await seerr.getRequests())
          .where((request) => request.media?.tmdbId == _movie)
          .single;
      await operator.declineRequest(mine.id);
      await operator.deleteRequest(mine.id);
      expect(
        (await operator.getRequests()).where((r) => r.media?.tmdbId == _movie),
        isEmpty,
      );

      // A Quick Connect code is asked for with a write as well.
      final auth = SeerrAuthService.forConnection(lab.accountConnection());
      addTearDown(auth.close);
      final code = await auth.startQuickConnect(await auth.readServer());
      expect(code.code, matches(r'^\d{6}$'));

      // Signing out is a write: the server forgets the session all the same.
      final before = container
          .read(currentSettingsProvider)
          .instanceById(_accountId)!;
      await container.read(seerrAccountsProvider).signOut(_accountId);
      final staleClient = seerrClientFor(before);
      addTearDown(staleClient.close);
      final ended = await _caught(SeerrService(staleClient).getRequests);
      expect(seerrRefusalOf(ended), SeerrRefusal.sessionEnded);
    });
  });
}

/// The account connection's id: not the primary id, so the providers reach
/// it by name rather than through the lens.
const _accountId = 'seerr-household';

/// The Matrix (1999): a movie the lab's Radarr does not have.
const _movie = 603;

/// The lab as the bootstrap left it.
class _Lab {
  _Lab._(this._values);

  factory _Lab.load() {
    final named = Platform.environment['CUPOLA_MACLAB_CREDENTIALS_FILE'];
    final path = named == null || named.isEmpty
        ? '.ai/scratch/zz_maclab/state/credentials.env'
        : named;
    final file = File(path);
    if (!file.existsSync()) {
      fail(
        'No lab credentials at $path: run test/e2e/maclab/bootstrap.sh, or '
        'point CUPOLA_MACLAB_CREDENTIALS_FILE at its credentials file.',
      );
    }
    final values = <String, String>{};
    for (final line in file.readAsLinesSync()) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      values[line.substring(0, separator)] = line.substring(separator + 1);
    }
    return _Lab._(values);
  }

  final Map<String, String> _values;

  String _value(String name) {
    final value = _values[name];
    if (value == null || value.isEmpty) {
      fail('The lab credentials have no $name: run the bootstrap again.');
    }
    return value;
  }

  final seerrUrl = 'http://127.0.0.1:5055';
  final jellyfinUrl = 'http://127.0.0.1:8096';

  String get project =>
      Platform.environment['CUPOLA_MACLAB_PROJECT'] ?? 'cupola-maclab';

  String get apiKey => _value('CUPOLA_MACLAB_SEERR_API_KEY');
  String get email => _value('CUPOLA_MACLAB_SEERR_REQUESTER_EMAIL');
  String get emailPassword => _value('CUPOLA_MACLAB_SEERR_REQUESTER_PASSWORD');
  String get viewer => _value('CUPOLA_MACLAB_JELLYFIN_REQUESTER_USERNAME');
  String get viewerPassword =>
      _value('CUPOLA_MACLAB_JELLYFIN_REQUESTER_PASSWORD');

  /// The operator's connection, with the key.
  ServiceInstance keyConnection() => ServiceInstance(
    id: ServiceInstance.primaryIdFor(ServiceKey.seerr),
    service: ServiceKey.seerr,
    url: seerrUrl,
    credential: apiKey,
  );

  /// The operator's [SeerrService], closed when the test ends.
  SeerrService operator() {
    final client = seerrClientFor(keyConnection());
    addTearDown(client.close);
    return SeerrService(client);
  }

  /// A household member's connection, before signing in.
  ServiceInstance accountConnection({
    String? url,
    ConnectionAccess access = const NoAccess(),
  }) => ServiceInstance(
    id: _accountId,
    service: ServiceKey.seerr,
    url: url ?? seerrUrl,
    access: access,
    account: const SeerrAccountSignIn(kind: SeerrAccountKind.local),
  );

  /// The app's providers over settings holding [instances], with a real
  /// settings service behind them.
  Future<ProviderContainer> container(List<ServiceInstance> instances) async {
    final overrides = await settingsScopeOverrides(
      customize: (settings) => instances.fold(
        settings,
        (model, instance) => model.copyWithInstance(instance),
      ),
    );
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    return container;
  }

  /// A container whose household connection signed in with email.
  Future<ProviderContainer> signedInContainer() async {
    final auth = SeerrAuthService.forConnection(accountConnection());
    try {
      final facts = await auth.readServer();
      final account = await auth.signInWithEmail(
        facts,
        email: email,
        password: emailPassword,
      );
      final container = await this.container([accountConnection()]);
      await container
          .read(seerrAccountsProvider)
          .signedIn(accountConnection(), account);
      return container;
    } finally {
      auth.close();
    }
  }

  SeerrAccountSignIn accountOf(ProviderContainer container) => container
      .read(currentSettingsProvider)
      .instanceById(_accountId)!
      .account!;

  Future<SeerrAccountSignIn> signInWithJellyfin() async {
    final auth = SeerrAuthService.forConnection(accountConnection());
    try {
      final facts = await auth.readServer();
      return await auth.signInWithMediaServer(
        facts,
        username: viewer,
        password: viewerPassword,
      );
    } finally {
      auth.close();
    }
  }

  /// What a person signed in to a Jellyfin app does with the code: Jellyfin's
  /// own Quick Connect, not Seerr's.
  Future<void> approveQuickConnect(String code) async {
    const device =
        'MediaBrowser Client="Cupola Lab", Device="Lab", '
        'DeviceId="cupola-maclab-quick-connect", Version="1.0"';
    final signedIn = await _rawJson(
      'POST',
      '$jellyfinUrl/Users/AuthenticateByName',
      headers: {'Authorization': device},
      body: {'Username': viewer, 'Pw': viewerPassword},
    );
    expect(signedIn.status, 200, reason: 'the viewer signs in to Jellyfin');
    final json = signedIn.body as Map<String, dynamic>;
    final token = json['AccessToken'] as String;
    final userId = (json['User'] as Map<String, dynamic>)['Id'] as String;
    final authorized = await _rawJson(
      'POST',
      '$jellyfinUrl/QuickConnect/Authorize?code=$code&userId=$userId',
      headers: {'Authorization': '$device, Token="$token"'},
    );
    expect(authorized.status, 200, reason: 'Jellyfin takes the code');
  }

  /// Writes [changes] into Seerr's main settings, which take effect at once.
  /// The route merges what it is sent.
  Future<void> setMainSettings(
    ApiClient operator,
    Map<String, Object> changes,
  ) => operator.post('/api/v1/settings/main', data: changes);

  /// A Jellyfin user nobody imported into Seerr.
  Future<_JellyfinUser> newJellyfinUser() async {
    final token = _value('CUPOLA_MACLAB_JELLYFIN_TOKEN');
    final admin =
        'MediaBrowser Client="Cupola Lab", Device="Lab", '
        'DeviceId="cupola-maclab-requester", Version="1.0", Token="$token"';
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final name = 'stranger-$stamp';
    final password = 'pw-$stamp';
    final created = await _rawJson(
      'POST',
      '$jellyfinUrl/Users/New',
      headers: {'Authorization': admin},
      body: {'Name': name, 'Password': password},
    );
    expect(created.status, 200, reason: 'Jellyfin makes the user');
    final id = (created.body as Map<String, dynamic>)['Id'] as String;
    return _JellyfinUser(
      name: name,
      password: password,
      remove: () => _rawJson(
        'DELETE',
        '$jellyfinUrl/Users/$id',
        headers: {'Authorization': admin},
      ),
    );
  }

  /// Seerr's own setting, which takes a restart. Through the operator's
  /// client, so turning it off again meets the guard it turns off.
  Future<void> setCsrfProtection(ApiClient client, {required bool on}) async {
    final network = ((await client.get('/api/v1/settings/network')).data as Map)
        .cast<String, dynamic>();
    if (network['csrfProtection'] == on) return;
    await client.post(
      '/api/v1/settings/network',
      data: {...network, 'csrfProtection': on},
    );
    final restarted = await Process.run('docker', [
      'restart',
      '$project-seerr-1',
    ]);
    expect(restarted.exitCode, 0, reason: '${restarted.stderr}');
    await waitForSeerr();
  }

  Future<void> waitForSeerr() async {
    for (var attempt = 0; attempt < 90; attempt++) {
      try {
        final status = await _rawJson('GET', '$seerrUrl/api/v1/status');
        if (status.status == 200) return;
      } on IOException {
        // Not up yet.
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    fail('The lab Seerr did not come up at $seerrUrl');
  }
}

/// A Jellyfin user a test made, and how to remove it.
class _JellyfinUser {
  const _JellyfinUser({
    required this.name,
    required this.password,
    required this.remove,
  });

  final String name;
  final String password;
  final Future<Object?> Function() remove;
}

/// Every request for [tmdbId], withdrawn by the operator: a run stopped
/// halfway leaves the next one a clean server.
Future<void> _withdrawRequestsFor(SeerrService operator, int tmdbId) async {
  for (final request in await operator.getRequests()) {
    if (request.media?.tmdbId == tmdbId) {
      await operator.deleteRequest(request.id);
    }
  }
}

/// The words an ended session reads with: blue, "Sign in again", no Retry.
void _expectSignedOutWords(Object error) {
  final reason = classifyConnectionFailure(error);
  expect(reason, ServiceFailureReason.sessionEnded);
  expect(failureTone(reason), StatusTone.info);
  expect(failureRetryHelps(reason), isFalse);
  expect(isPermissionRefusal(error), isFalse);
}

Future<Object> _caught(Future<Object?> Function() action) async {
  try {
    await action();
  } catch (error) {
    return error;
  }
  fail('expected a refusal, and the request went through');
}

/// One request outside the app: the lab playing another device, or proving
/// a guard is up.
Future<({int status, Object? body})> _rawJson(
  String method,
  String url, {
  Map<String, String> headers = const {},
  Object? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse(url));
    headers.forEach(request.headers.set);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      decoded = text;
    }
    return (status: response.statusCode, body: decoded);
  } finally {
    client.close(force: true);
  }
}

/// An access gateway in front of the lab's Seerr, as a reverse proxy with an
/// access rule is: a request carrying [header] with [secret] goes through as
/// it came; any other is turned away with a page of the gateway's own.
class _Gateway {
  _Gateway._(this._server, this._upstream, this.secret);

  static const header = 'X-Lab-Gate';

  static Future<_Gateway> start(String upstream) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final gateway = _Gateway._(
      server,
      Uri.parse(upstream),
      'gate-${DateTime.now().microsecondsSinceEpoch}',
    );
    server.listen(gateway._handle);
    return gateway;
  }

  final HttpServer _server;
  final Uri _upstream;
  final String secret;
  final _client = HttpClient()..autoUncompress = false;

  /// Requests let through, and turned away.
  int let = 0;
  int refused = 0;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    if (request.headers.value(header) != secret) {
      refused++;
      response
        ..statusCode = HttpStatus.forbidden
        ..headers.contentType = ContentType.html
        ..write('<html><body>Turned away at the gateway</body></html>');
      await response.close();
      return;
    }
    let++;
    final body = await request.fold<List<int>>(
      [],
      (all, part) => all..addAll(part),
    );
    final forwarded = await _client.openUrl(
      request.method,
      _upstream.replace(path: request.uri.path, query: request.uri.query),
    );
    forwarded.followRedirects = false;
    request.headers.forEach((name, values) {
      if (name == 'host' || name == 'content-length') return;
      for (final value in values) {
        forwarded.headers.add(name, value);
      }
    });
    forwarded.contentLength = body.length;
    forwarded.add(body);
    final answer = await forwarded.close();
    final bytes = await answer.fold<List<int>>(
      [],
      (all, part) => all..addAll(part),
    );
    response.statusCode = answer.statusCode;
    answer.headers.forEach((name, values) {
      if (name == 'content-length' || name == 'transfer-encoding') return;
      for (final value in values) {
        response.headers.add(name, value);
      }
    });
    response.contentLength = bytes.length;
    response.add(bytes);
    await response.close();
  }

  Future<void> close() async {
    _client.close(force: true);
    await _server.close(force: true);
  }
}
