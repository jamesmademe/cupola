/// The Seerr transport against the fake Seerr: what each way in sends, the
/// session an account keeps, the CSRF token both answer, and the three 403s
/// told apart.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/capability/permission_refusal.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The account [harness] starts signed in as on [id], as the app would have
/// saved it.
SeerrAccountSignIn _account(ProfileHarness harness, {String id = 'seerr'}) =>
    SeerrAccountSignIn(
      kind: SeerrAccountKind.local,
      session: harness.network.seerrSessionOf(id),
    );

/// An account with no session yet: the client a sign-in is sent with.
const _signingIn = SeerrAccountSignIn(kind: SeerrAccountKind.local);

ServiceInstance _instance(ConfigProfile profile, {String id = 'seerr'}) =>
    profile.connection(id).instance;

ApiClient _client(
  ConfigProfile profile, {
  SeerrSignIn? signIn,
  SeerrSessionEvents events = const SeerrSessionEvents(),
}) {
  final client = seerrClientFor(
    _instance(profile),
    signIn: signIn,
    events: events,
  );
  addTearDown(client.close);
  return client;
}

String? _cookie(NetworkRequest request, String name) =>
    _cookiesOf(request)[name];

/// The cookies [request] carried, by name, the way Seerr reads them.
Map<String, String> _cookiesOf(NetworkRequest request) {
  final header = request.headers['cookie'];
  if (header == null || header.isEmpty) return const {};
  return {
    for (final part in header.split(';'))
      if (part.contains('='))
        part.substring(0, part.indexOf('=')).trim(): part
            .substring(part.indexOf('=') + 1)
            .trim(),
  };
}

Future<Object> _failure(Future<Object?> Function() request) async {
  try {
    await request();
  } catch (error) {
    return error;
  }
  fail('the request succeeded');
}

void main() {
  group('what each way in sends', () {
    test('the key: X-Api-Key and no session', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      final client = _client(Profiles.p1);

      await client.get('/api/v1/request', queryParameters: {'take': 1});

      final sent = harness.network.requestsTo(WorldIds.seerr).single;
      expect(sent.headers['x-api-key'], worldKey(WorldIds.seerr));
      expect(_cookie(sent, 'connect.sid'), isNull);
    });

    test('an account: its session cookie and no key', () async {
      final harness = await ProfileHarness.start(Profiles.p2);
      final session = harness.network.seerrSessionOf(WorldIds.seerr);
      final client = _client(Profiles.p2, signIn: _account(harness));

      final me = await client.get('/api/v1/auth/me');

      expect(me.data['displayName'], WorldPeople.anna);
      final sent = harness.network.requestsTo(WorldIds.seerr).single;
      expect(sent.headers.containsKey('x-api-key'), isFalse);
      expect(_cookie(sent, 'connect.sid'), session);
    });

    test(
      'a sign-in never carries the session, and the answer is kept',
      () async {
        final harness = await ProfileHarness.start(Profiles.p2);
        final kept = <String>[];
        final client = _client(
          Profiles.p2,
          signIn: _account(harness),
          events: SeerrSessionEvents(onSession: kept.add),
        );
        const anna = WorldSeerrUsers.annaLocal;

        await client.post(
          '/api/v1/auth/local',
          data: {'email': anna.email, 'password': anna.password},
        );
        final me = await client.get('/api/v1/auth/me');

        final [signIn, whoAmI] = harness.network.requestsTo(WorldIds.seerr);
        expect(_cookie(signIn, 'connect.sid'), isNull);
        expect(kept, hasLength(1));
        expect(kept.single, startsWith('s%3A'));
        expect(_cookie(whoAmI, 'connect.sid'), kept.single);
        expect(me.data['id'], anna.id);
      },
    );

    test(
      'a client with no session yet signs in, then is the account',
      () async {
        final harness = await ProfileHarness.start(Profiles.p2ViaJellyfin);
        String? session;
        final client = _client(
          Profiles.p2ViaJellyfin,
          signIn: _signingIn,
          events: SeerrSessionEvents(onSession: (value) => session = value),
        );
        const anna = WorldSeerrUsers.annaJellyfin;

        await client.post(
          '/api/v1/auth/jellyfin',
          data: {'username': anna.login, 'password': anna.password},
        );
        final requests = await client.get('/api/v1/request');

        expect(session, isNotNull);
        final first = harness.network.requestsTo(WorldIds.seerr).first;
        expect(first.headers['cookie'], isNull);
        // Her own requests only: the server read the session, not a key.
        final rows = (requests.data['results'] as List).cast<Map>();
        expect(rows.map((row) => (row['requestedBy'] as Map)['id']).toSet(), {
          anna.id,
        });
      },
    );

    test('a session lives beside a Cloudflare Access token', () async {
      final profile = Profiles.p2.withConnection(
        Profiles.p2
            .connection(WorldIds.seerr)
            .withAccess(WorldTokens.seerr.access)
            .withBehaviour(
              const ConnectionBehaviour.behindCloudflareAccess(
                serviceToken: WorldTokens.seerr,
              ),
            ),
      );
      final harness = await ProfileHarness.start(profile);
      final client = seerrClientFor(
        _instance(profile),
        signIn: _account(harness),
      );
      addTearDown(client.close);

      final me = await client.get('/api/v1/auth/me');

      expect(me.data['displayName'], WorldPeople.anna);
      final sent = harness.network.requestsTo(WorldIds.seerr).single;
      expect(sent.headers['cf-access-client-id'], WorldTokens.seerr.id);
      expect(
        _cookie(sent, 'connect.sid'),
        harness.network.seerrSessionOf(WorldIds.seerr),
      );
    });
  });

  group('redirects keep the cookie on the configured host', () {
    test(
      'a redirect to another host is never sent, so never the cookie',
      () async {
        final harness = await ProfileHarness.start(Profiles.p2);
        harness.network.on(
          WorldIds.seerr,
          'GET',
          '/api/v1/request',
          (_) => const NetworkReply(
            302,
            headers: {
              'location': ['https://elsewhere.example.net/api/v1/request'],
            },
          ),
        );
        final client = _client(Profiles.p2, signIn: _account(harness));

        final error = await _failure(() => client.get('/api/v1/request'));

        expect(
          classifyConnectionFailure(error),
          ServiceFailureReason.redirected,
        );
        expect(
          (error as DioException).error,
          isA<RedirectRefused>(),
          reason: 'refused before anything was sent',
        );
        expect(
          harness.network.requestsToHost('elsewhere.example.net'),
          isEmpty,
        );
      },
    );

    test('a redirect on the same host carries one session cookie', () async {
      final harness = await ProfileHarness.start(Profiles.p2);
      harness.network.on(
        WorldIds.seerr,
        'GET',
        '/api/v1/requests',
        (_) => NetworkReply(
          301,
          headers: {
            'location': ['${WorldHosts.seerr}/api/v1/auth/me'],
          },
        ),
      );
      final client = _client(Profiles.p2, signIn: _account(harness));

      final me = await client.get('/api/v1/requests');

      expect(me.data['displayName'], WorldPeople.anna);
      final followed = harness.network.requestsTo(WorldIds.seerr).last;
      expect(followed.path, '/api/v1/auth/me');
      expect(
        'connect.sid='.allMatches(followed.headers['cookie']!),
        hasLength(1),
      );
    });
  });

  group('CSRF, for the key and for an account', () {
    final protected = Profiles.p2.withBehaviour(
      WorldIds.seerr,
      ConnectionBehaviour.csrfProtected,
    );

    test(
      'the key: a refused write fetches a token and goes once more',
      () async {
        final profile = Profiles.p1.withBehaviour(
          WorldIds.seerr,
          ConnectionBehaviour.csrfProtected,
        );
        final harness = await ProfileHarness.start(profile);
        final client = _client(profile);

        final answer = await client.delete('/api/v1/media/1');

        expect(answer.statusCode, 204);
        final sent = harness.network.requestsTo(WorldIds.seerr);
        expect(sent.map((r) => '${r.method} ${r.path}'), [
          'DELETE /api/v1/media/1',
          'GET /api/v1/settings/public',
          'DELETE /api/v1/media/1',
        ]);
        expect(sent.first.headers.containsKey('x-xsrf-token'), isFalse);
        expect(sent.last.headers['x-xsrf-token'], isNotEmpty);
        expect(_cookie(sent.last, '_csrf'), isNotEmpty);
      },
    );

    test('an account: the same, with its session beside the secret', () async {
      final harness = await ProfileHarness.start(protected);
      final client = _client(protected, signIn: _account(harness));

      final made = await client.post(
        '/api/v1/request',
        data: {'mediaType': 'movie', 'mediaId': 1},
      );

      expect(made.statusCode, 201);
      final last = harness.network.requestsTo(WorldIds.seerr).last;
      expect(last.method, 'POST');
      expect(
        _cookie(last, 'connect.sid'),
        harness.network.seerrSessionOf(WorldIds.seerr),
      );
      expect(_cookie(last, '_csrf'), isNotEmpty);
      expect(last.headers['x-xsrf-token'], isNotEmpty);
    });

    test('a token kept from a read goes with the first write', () async {
      final harness = await ProfileHarness.start(protected);
      final client = _client(protected, signIn: _account(harness));

      await client.get('/api/v1/auth/me');
      await client.post(
        '/api/v1/request',
        data: {'mediaType': 'movie', 'mediaId': 1},
      );

      expect(
        harness.network
            .requestsTo(WorldIds.seerr)
            .map((r) => '${r.method} ${r.path}'),
        ['GET /api/v1/auth/me', 'POST /api/v1/request'],
      );
    });

    test('refused again, it fails once as a refused token', () async {
      final harness = await ProfileHarness.start(protected);
      // A guard that refuses even the token it hands out.
      harness.network.on(
        WorldIds.seerr,
        'POST',
        '/api/v1/request',
        (_) =>
            NetworkReply.json({'message': 'invalid csrf token'}, status: 403),
      );
      final client = _client(protected, signIn: _account(harness));

      final error = await _failure(
        () => client.post(
          '/api/v1/request',
          data: {'mediaType': 'movie', 'mediaId': 1},
        ),
      );

      expect((error as DioException).error, isA<SeerrCsrfRefused>());
      expect(
        classifyConnectionFailure(error),
        ServiceFailureReason.csrfRefused,
      );
      expect(isPermissionRefusal(error), isFalse);
      expect(seerrRefusalOf(error), SeerrRefusal.csrfToken);
      final writes = harness.network
          .requestsTo(WorldIds.seerr)
          .where((r) => r.method == 'POST');
      expect(writes, hasLength(2), reason: 'sent once more, never twice');
    });

    test('with the protection off, a write carries no token at all', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      final client = _client(Profiles.p1);

      await client.get('/api/v1/settings/public');
      await client.delete('/api/v1/media/1');

      final write = harness.network.requestsTo(WorldIds.seerr).last;
      expect(write.headers.containsKey('x-xsrf-token'), isFalse);
      expect(write.headers['cookie'], isNull);
    });
  });

  group('an ended session, a missing permission', () {
    test('a refusal /auth/me shares is an ended session', () async {
      final profile = Profiles.p2.withBehaviour(
        WorldIds.seerr,
        ConnectionBehaviour.sessionExpired,
      );
      final harness = await ProfileHarness.start(profile);
      var ended = 0;
      final client = _client(
        profile,
        signIn: _account(harness),
        events: SeerrSessionEvents(onSessionEnded: () => ended++),
      );

      final error = await _failure(() => client.get('/api/v1/request'));

      expect((error as DioException).error, isA<SeerrSessionEnded>());
      expect(
        classifyConnectionFailure(error),
        ServiceFailureReason.sessionEnded,
      );
      expect(seerrRefusalOf(error), SeerrRefusal.sessionEnded);
      expect(isPermissionRefusal(error), isFalse);
      expect(ended, 1);
      expect(
        harness.network
            .requestsTo(WorldIds.seerr)
            .map((r) => '${r.method} ${r.path}'),
        ['GET /api/v1/request', 'GET /api/v1/auth/me'],
      );

      // Said once per session, however many requests meet it.
      await _failure(() => client.get('/api/v1/request'));
      expect(ended, 1);
    });

    test('/auth/me refused on its own is an ended session too', () async {
      final profile = Profiles.p2.withBehaviour(
        WorldIds.seerr,
        ConnectionBehaviour.sessionExpired,
      );
      final harness = await ProfileHarness.start(profile);
      var ended = 0;
      final client = _client(
        profile,
        signIn: _account(harness),
        events: SeerrSessionEvents(onSessionEnded: () => ended++),
      );

      final error = await _failure(() => client.get('/api/v1/auth/me'));

      expect(
        classifyConnectionFailure(error),
        ServiceFailureReason.sessionEnded,
      );
      expect(ended, 1);
      expect(harness.network.requestsTo(WorldIds.seerr), hasLength(1));
    });

    test('a refusal /auth/me answers is the account lacking it', () async {
      final harness = await ProfileHarness.start(Profiles.p2);
      final whoAmI = <int>[];
      var ended = 0;
      final client = _client(
        Profiles.p2,
        signIn: _account(harness),
        events: SeerrSessionEvents(
          onSessionEnded: () => ended++,
          onWhoAmI: (me) => whoAmI.add(me['permissions'] as int),
        ),
      );

      final error = await _failure(
        () => client.post('/api/v1/request/1/approve'),
      );

      expect((error as DioException).error, isA<SeerrRefused>());
      expect(seerrRefusalOf(error), SeerrRefusal.permissionDenied);
      expect(isPermissionRefusal(error), isTrue);
      expect(
        classifyConnectionFailure(error),
        isNot(ServiceFailureReason.sessionEnded),
      );
      expect(whoAmI, [32]);
      expect(ended, 0);
    });

    test('the key keeps reading a refusal as the key refused', () async {
      final profile = Profiles.p1.withBehaviour(
        WorldIds.seerr,
        ConnectionBehaviour.refusesKey,
      );
      final harness = await ProfileHarness.start(profile);
      final client = _client(profile);

      final error = await _failure(() => client.get('/api/v1/request'));

      expect(
        classifyConnectionFailure(error),
        ServiceFailureReason.unauthorized,
      );
      // No /auth/me: the key is user 1, and has no session to have ended.
      expect(harness.network.requestsTo(WorldIds.seerr), hasLength(1));
    });

    test('nothing secret in what a failure prints', () async {
      final profile = Profiles.p2.withBehaviour(
        WorldIds.seerr,
        ConnectionBehaviour.sessionExpired,
      );
      final harness = await ProfileHarness.start(profile);
      final session = harness.network.seerrSessionOf(WorldIds.seerr);
      final client = _client(profile, signIn: _account(harness));

      final error = await _failure(() => client.get('/api/v1/request'));

      for (final text in [
        '$error',
        failureDiagnostic(error),
        connectionFailureSentence(error),
        '${_account(harness)}',
      ]) {
        expect(text, isNot(contains(session)));
        expect(text, isNot(contains('connect.sid')));
      }
    });
  });

  test('a service interceptor sees an answer before the guards do', () {
    final own = InterceptorsWrapper();
    final dio = guardedDio(
      baseUrl: 'https://example.com',
      interceptors: (_) => [own],
    );
    final redirects = dio.interceptors.indexWhere(
      (interceptor) => interceptor is SameOriginRedirectInterceptor,
    );
    expect(dio.interceptors.indexOf(own), lessThan(redirects));
  });
}
