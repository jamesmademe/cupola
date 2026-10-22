@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/data/seerr_auth_service.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_known_arr.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/profiles/world.dart';
import '../test_helpers/settings_scope.dart';

/// P9 against the macOS lab: the household's Seerr, which the operator holds
/// the key of, and a friend's Seerr, where he holds an account of his own
/// that may only request.
///
/// The second server is a real container (`seerr-sara`, 127.0.0.1:5056, the
/// same image as the household's, set up on the lab's Jellyfin) that
/// `test/e2e/testlab/seerr_sara.py` initializes and seeds: its admin is the
/// friend, the operator's local account carries REQUEST alone, one Jellyfin
/// user is imported, and one movie Radarr does not have waits for approval.
/// The accounts and that request are read from the state file the script
/// writes, never guessed.
///
/// Everything below runs the app's own code: [SeerrAuthService] signs in,
/// [seerrClientFor] carries the session and the CSRF token, [SeerrAccounts]
/// keeps the account, and the providers answer. The offline counterpart is
/// `Profiles.p9`.
void main() {
  late _Lab lab;
  ProviderContainer? container;

  setUpAll(() async {
    lab = _Lab.load();
    await lab.waitForServers();
    container = await lab.container();
    await lab.signIn(container!);
  });

  tearDownAll(() async {
    final live = container;
    container = null;
    if (live == null) return;
    // The session the sign-in opened ends here, as the app's sign out does,
    // so a rerun starts from the same server state this one found.
    await live.read(seerrAccountsProvider).signOut(_friendId);
    live.dispose();
  });

  group('the friend\'s server', () {
    test('answers as Seerr on Jellyfin, and offers a way in', () async {
      final auth = SeerrAuthService.forConnection(lab.friendConnection());
      addTearDown(auth.close);

      final facts = await auth.readServer();

      expect(facts.family, SeerrFamily.seerr);
      expect(facts.version, matches(r'^3\.'));
      expect(facts.mediaServer, SeerrMediaServer.jellyfin);
      expect(facts.signIn.state, SeerrSignInState.open);
      expect(facts.signIn.offers(SeerrSignInMethod.local), isTrue);
    });

    test('a wrong password is refused as one', () async {
      final auth = SeerrAuthService.forConnection(lab.friendConnection());
      addTearDown(auth.close);
      final facts = await auth.readServer();

      final error = await _caught(
        () => auth.signInWithEmail(
          facts,
          email: lab.operatorEmail,
          password: '${lab.operatorPassword}-not-it',
        ),
      );

      expect(seerrRefusalOf(error), SeerrRefusal.wrongEmailOrPassword);
    });
  });

  group('the operator on the friend\'s server', () {
    test('signs in with a local account that may only request', () async {
      final saved = container!
          .read(currentSettingsProvider)
          .instanceById(_friendId)!;
      final account = saved.account!;

      expect(account.kind, SeerrAccountKind.local);
      expect(account.isSignedIn, isTrue);
      expect(account.login, lab.operatorEmail);
      expect(account.userId, lab.operatorUserId);
      expect(account.permissions, SeerrPermission.request.value);

      final grant = SeerrGrant.account(permissions: account.permissions);
      expect(grant.role, SeerrRole.requester);
      expect(
        grant.may(SeerrAbility.request, kind: SeerrMediaKind.movie),
        isTrue,
      );
      expect(grant.may(SeerrAbility.approve), isFalse);
      expect(grant.may(SeerrAbility.seeEveryonesRequests), isFalse);
      expect(grant.may(SeerrAbility.readSettings), isFalse);

      // Read again by the app's providers: the account, not the key.
      expect(container!.read(seerrGrantProvider(_friendId)), grant);
      // And again from the server: `/auth/me` still says REQUEST alone.
      await container!.read(seerrAccountsProvider).refresh(_friendId);
      expect(
        container!.read(seerrGrantProvider(_friendId))!.role,
        SeerrRole.requester,
      );
      // Testing the connection asks Sara's server as the account.
      expect(
        (await diagnoseSeerr(saved)).status,
        ServiceConnectionStatus.connected,
      );
    });

    test('reads the request he left, still waiting', () async {
      final seerr = container!.read(seerrServiceForProvider(_friendId));

      final requests = await seerr.getRequests();
      expect(
        requests,
        hasLength(1),
        reason: 'the seed leaves one request on Sara\'s server',
      );
      final mine = requests.single;

      expect(mine.id, lab.requestId);
      expect(mine.status, RequestStatus.pendingApproval);
      expect(mine.type, 'movie');
      expect(mine.is4k, isFalse);
      expect(mine.media?.tmdbId, lab.tmdbId);
      expect(mine.media?.title, lab.title);
      // Waiting for the friend's approval, and on no arr yet.
      expect(mine.media?.status, SeerrMediaAvailability.pending);
      expect(mine.media?.copies, isEmpty);
      expect(mine.requestedBy?.id, lab.operatorUserId);
      expect(mine.requestedBy?.displayName, isNotEmpty);

      // Nobody picked a destination: no arr hears of it before approval.
      expect(mine.serverId, isNull);
      expect(mine.profileId, isNull);
    });

    test('may not read the settings the household\'s key may', () async {
      final friend = await container!
          .read(seerrServiceForProvider(_friendId))
          .knownServers();
      expect(friend, isA<SeerrKnownArrsNotAllowed>());

      final household = await container!
          .read(
            seerrServiceForProvider(
              ServiceInstance.primaryIdFor(ServiceKey.seerr),
            ),
          )
          .knownServers();
      expect(household, isA<SeerrKnownArrsRead>());
      expect(
        (household as SeerrKnownArrsRead).servers.map((arr) => arr.service),
        containsAll([ServiceKey.radarr, ServiceKey.sonarr]),
      );
    });

    test(
      'is a requester here and the operator at home, one connection each',
      () async {
        final householdId = ServiceInstance.primaryIdFor(ServiceKey.seerr);

        expect(
          container!.read(seerrGrantProvider(_friendId))!.role,
          SeerrRole.requester,
        );
        expect(
          container!.read(seerrGrantProvider(householdId))!.role,
          SeerrRole.manager,
        );

        // Two connections, two servers: the household's answers its key, the
        // friend's answers the account, and neither is the other's address.
        final settings = container!.read(currentSettingsProvider);
        final seerrs = settings.instancesOf(ServiceKey.seerr);
        expect(seerrs, hasLength(2));
        expect(settings.instanceById(_friendId)!.url, lab.friendUrl);
        expect(
          settings.instanceById(householdId)!.url,
          _Lab.householdUrl,
          reason: 'the household\'s server is the lab\'s main one',
        );

        // The household's own reads still work with the key, beside the
        // account's: the two connections do not borrow each other's way in.
        final requests = await container!
            .read(seerrServiceForProvider(householdId))
            .getRequests();
        expect(requests, isA<List<SeerrRequest>>());
      },
    );
  });
}

/// The P9 profile's id for the friend's server, so the lab and the offline
/// profile name the same connection.
const _friendId = WorldIds.seerrFriend;

/// The lab as the bootstrap left it: the household's key in
/// `credentials.env`, the friend's server in `seerr-sara.json`.
class _Lab {
  _Lab._(this._credentials, this._sara);

  factory _Lab.load() {
    final credentials = _readEnv(
      Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE'] ??
          '.ai/scratch/zz_testlab/state/credentials.env',
      'run test/e2e/testlab/bootstrap.sh, or point '
      'CUPOLA_TESTLAB_CREDENTIALS_FILE at its credentials file',
    );
    final named = Platform.environment['CUPOLA_TESTLAB_SEERR_SARA_FILE'];
    final path = named == null || named.isEmpty
        ? '.ai/scratch/zz_testlab/state/seerr-sara.json'
        : named;
    final file = File(path);
    if (!file.existsSync()) {
      fail(
        'No second Seerr state at $path: run test/e2e/testlab/bootstrap.sh '
        '(or test/e2e/testlab/seerr_sara.py), or point '
        'CUPOLA_TESTLAB_SEERR_SARA_FILE at its state file.',
      );
    }
    final sara = (jsonDecode(file.readAsStringSync()) as Map)
        .cast<String, dynamic>();
    return _Lab._(credentials, sara);
  }

  static Map<String, String> _readEnv(String path, String remedy) {
    final file = File(path);
    if (!file.existsSync()) fail('No lab credentials at $path: $remedy.');
    final values = <String, String>{};
    for (final line in file.readAsLinesSync()) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      values[line.substring(0, separator)] = line.substring(separator + 1);
    }
    return values;
  }

  final Map<String, String> _credentials;
  final Map<String, dynamic> _sara;

  /// The lab's main Seerr, which the operator holds the key of.
  static const householdUrl = 'http://127.0.0.1:5055';

  String get friendUrl => (_sara['url'] as String?) ?? 'http://127.0.0.1:5056';

  String get apiKey {
    final key = _credentials['CUPOLA_TESTLAB_SEERR_API_KEY'];
    if (key == null || key.isEmpty) {
      fail('The lab credentials have no Seerr key: run the bootstrap again.');
    }
    return key;
  }

  Map<String, dynamic> get _operator =>
      (_sara['operator'] as Map).cast<String, dynamic>();

  Map<String, dynamic> get _request =>
      (_sara['request'] as Map).cast<String, dynamic>();

  String get operatorEmail => _operator['email'] as String;
  String get operatorPassword => _operator['password'] as String;
  int get operatorUserId => (_operator['userId'] as num).toInt();
  int get requestId => (_request['id'] as num).toInt();
  int get tmdbId => (_request['tmdbId'] as num).toInt();
  String get title => _request['title'] as String;

  /// The household's connection: the key, the primary id, the lens.
  ServiceInstance householdConnection() => ServiceInstance(
    id: ServiceInstance.primaryIdFor(ServiceKey.seerr),
    service: ServiceKey.seerr,
    url: householdUrl,
    credential: apiKey,
  );

  /// The friend's connection: no key, an account that has not signed in yet.
  ServiceInstance friendConnection() => ServiceInstance(
    id: _friendId,
    service: ServiceKey.seerr,
    url: friendUrl,
    account: const SeerrAccountSignIn(kind: SeerrAccountKind.local),
  );

  /// The app's providers over settings holding both servers, with a real
  /// settings service behind them.
  Future<ProviderContainer> container() async {
    final overrides = await settingsScopeOverrides(
      customize: (settings) => settings
          .copyWithInstance(householdConnection())
          .copyWithInstance(friendConnection()),
    );
    return ProviderContainer(overrides: overrides);
  }

  /// The operator signs in to the friend's server, and the app keeps it.
  Future<void> signIn(ProviderContainer container) async {
    final connection = friendConnection();
    final auth = SeerrAuthService.forConnection(connection);
    try {
      final facts = await auth.readServer();
      final account = await auth.signInWithEmail(
        facts,
        email: operatorEmail,
        password: operatorPassword,
      );
      expect(account.userId, operatorUserId, reason: 'the seeded account');
      await container.read(seerrAccountsProvider).signedIn(connection, account);
    } finally {
      auth.close();
    }
  }

  Future<void> waitForServers() async {
    await _waitFor(householdUrl);
    await _waitFor(friendUrl);
  }

  Future<void> _waitFor(String url) async {
    for (var attempt = 0; attempt < 90; attempt++) {
      try {
        final status = await _rawJson('GET', '$url/api/v1/status');
        if (status.status == 200) return;
      } on IOException {
        // Not up yet.
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    fail('Seerr did not answer at $url');
  }
}

Future<Object> _caught(Future<Object?> Function() action) async {
  try {
    await action();
  } catch (error) {
    return error;
  }
  fail('expected a refusal, and the request went through');
}

/// One request outside the app: proving a server is up.
Future<({int status, Object? body})> _rawJson(String method, String url) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse(url));
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
