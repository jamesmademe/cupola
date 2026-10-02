/// The fake Seerr answers a household member's own account the way Seerr
/// v3.5.0 does, and plex.tv answers the PIN sign-in, all through a raw `Dio`:
/// no client of the app's is involved.
///
/// Where the domain already reads a body (`classifySeerrRefusal`,
/// `SeerrServerFacts`, `SeerrGrant`), the fake's answer is handed to it, so a
/// drift between the fake and the wire the domain was written against fails
/// here first.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/domain/seerr_quota.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';

import '../../test_helpers/profiles/profiles.dart';

/// A bare HTTP client that keeps the cookies it is sent, the way a session
/// interceptor would, and sends only what a test asks for.
class _Client {
  _Client(this.base, {this.key});

  final String base;

  /// Sent as `X-Api-Key` when set.
  String? key;

  /// Whether a write carries the `XSRF-TOKEN` it was handed as
  /// `X-XSRF-TOKEN`.
  bool sendsXsrf = false;

  /// Whether the cookies kept are sent back.
  bool sendsCookies = true;

  final Map<String, String> cookies = {};

  /// Every `Set-Cookie` line of the last answer.
  List<String> setCookies = const [];

  final Dio _dio = Dio(BaseOptions(validateStatus: (_) => true));

  Future<Response<dynamic>> get(String path) => send('GET', path);

  Future<Response<dynamic>> post(String path, [Object? data]) =>
      send('POST', path, data: data);

  Future<Response<dynamic>> send(
    String method,
    String path, {
    Object? data,
    Map<String, String> headers = const {},
  }) async {
    final write = method != 'GET';
    final response = await _dio.request<dynamic>(
      path.startsWith('http') ? path : '$base$path',
      data: data,
      options: Options(
        method: method,
        headers: {
          ...headers,
          if (key != null) 'X-Api-Key': key,
          if (sendsCookies && cookies.isNotEmpty)
            'Cookie': [
              for (final entry in cookies.entries)
                '${entry.key}=${entry.value}',
            ].join('; '),
          if (write && sendsXsrf && cookies['XSRF-TOKEN'] != null)
            'X-XSRF-TOKEN': cookies['XSRF-TOKEN']!,
        },
      ),
    );
    setCookies = response.headers['set-cookie'] ?? const [];
    for (final line in setCookies) {
      final pair = line.split(';').first;
      final at = pair.indexOf('=');
      cookies[pair.substring(0, at)] = pair.substring(at + 1);
    }
    return response;
  }

  String? setCookieLine(String name) =>
      setCookies.where((line) => line.startsWith('$name=')).firstOrNull;
}

/// What the domain makes of [response] to `method path`.
SeerrRefusal? _verdict(Response<dynamic> response) => classifySeerrRefusal(
  status: response.statusCode,
  method: response.requestOptions.method,
  path: response.requestOptions.uri.path,
  body: response.data,
);

const _endpointBody = {
  'status': 403,
  'error': 'You do not have permission to access this endpoint',
};

Future<(ProfileHarness, _Client)> _start(ConfigProfile profile) async {
  final harness = await ProfileHarness.start(profile);
  return (harness, _Client(WorldHosts.seerr));
}

void main() {
  group('signs in each way', () {
    test('a local account: the cookie, then /auth/me as Anna', () async {
      final (_, client) = await _start(Profiles.p2);
      const anna = WorldSeerrUsers.annaLocal;

      final signIn = await client.post('/api/v1/auth/local', {
        'email': anna.email,
        'password': anna.password,
      });

      expect(signIn.statusCode, 200);
      // The route selects four columns: the answer carries the entity's
      // `permissions: 0`, whatever the account holds (Seerr 3.4.1, live).
      expect(signIn.data, {
        'permissions': 0,
        'warnings': const <String>[],
        'id': anna.id,
        'requestCount': 0,
        'displayName': anna.email,
      });
      final cookie = client.setCookieLine('connect.sid')!;
      expect(cookie, startsWith('connect.sid=s%3A'));
      expect(cookie, contains('; Path=/; Expires='));
      expect(cookie, endsWith('; HttpOnly; SameSite=Lax'));

      final me = await client.get('/api/v1/auth/me');
      expect(me.statusCode, 200);
      expect(me.data['displayName'], WorldPeople.anna);
      expect(me.data['userType'], 2);
      expect(me.data['email'], anna.email);
      expect(SeerrGrant.fromWhoAmI(me.data).permissions, 32);
      // No new cookie on an ordinary request: the session does not roll the
      // cookie, only the server's row.
      expect(client.setCookieLine('connect.sid'), isNull);
    });

    test('Jellyfin: username and password, a Jellyfin user', () async {
      final (_, client) = await _start(Profiles.p2ViaJellyfin);
      const anna = WorldSeerrUsers.annaJellyfin;

      final signIn = await client.post('/api/v1/auth/jellyfin', {
        'username': anna.login,
        'password': anna.password,
      });

      expect(signIn.statusCode, 200);
      expect(signIn.data['jellyfinUsername'], anna.login);
      expect(signIn.data, isNot(contains('email')));
      expect(client.cookies, contains('connect.sid'));
      final me = await client.get('/api/v1/auth/me');
      expect(me.data['id'], anna.id);
      expect(me.data['userType'], 3);
    });

    test('Jellyfin Quick Connect: a code, approved elsewhere, then the '
        'session', () async {
      final (harness, client) = await _start(Profiles.p2ViaJellyfin);

      final initiate = await client.post(
        '/api/v1/auth/jellyfin/quickconnect/initiate',
      );
      expect(initiate.statusCode, 200);
      final code = initiate.data['code'] as String;
      final secret = initiate.data['secret'] as String;
      expect(code, matches(RegExp(r'^\d{6}$')));

      final waiting = await client.get(
        '/api/v1/auth/jellyfin/quickconnect/check?secret=$secret',
      );
      expect(waiting.data, {'authenticated': false});
      // Nobody approved it yet: Jellyfin's 404, relayed.
      final early = await client.post(
        '/api/v1/auth/jellyfin/quickconnect/authenticate',
        {'secret': secret},
      );
      expect(early.statusCode, 404);
      expect(early.data, {'message': 'INVALID_CREDENTIALS'});

      harness.network.approveQuickConnect(WorldIds.seerr, code);
      final approved = await client.get(
        '/api/v1/auth/jellyfin/quickconnect/check?secret=$secret',
      );
      expect(approved.data, {'authenticated': true});

      final signIn = await client.post(
        '/api/v1/auth/jellyfin/quickconnect/authenticate',
        {'secret': secret},
      );
      expect(signIn.statusCode, 200);
      expect(client.cookies, contains('connect.sid'));
      final me = await client.get('/api/v1/auth/me');
      expect(me.data['displayName'], WorldPeople.anna);

      // Approved, the code signs in again, with a session of its own.
      final first = client.cookies['connect.sid'];
      client.cookies.remove('connect.sid');
      final again = await client.post(
        '/api/v1/auth/jellyfin/quickconnect/authenticate',
        {'secret': secret},
      );
      expect(again.statusCode, 200);
      expect(client.cookies['connect.sid'], allOf(isNotNull, isNot(first)));
    });

    test('Plex: a PIN on plex.tv, claimed, then its token to Seerr', () async {
      final (harness, client) = await _start(Profiles.p2ViaPlex);
      final plexTv = _Client('https://$plexTvHost');
      const headers = {
        'Accept': 'application/json',
        'X-Plex-Product': 'Cupola',
        'X-Plex-Client-Identifier': 'cupola-test-client',
      };

      final created = await plexTv.send(
        'POST',
        '/api/v2/pins?strong=true',
        headers: headers,
      );
      expect(created.statusCode, 201);
      final id = created.data['id'] as int;
      expect(created.data['code'], hasLength(25));
      expect(created.data['authToken'], isNull);
      expect(created.data['expiresAt'], isA<String>());

      final waiting = await plexTv.send(
        'GET',
        '/api/v2/pins/$id',
        headers: headers,
      );
      expect(waiting.data['authToken'], isNull);
      // Only the identifier that made the PIN may read it.
      final stranger = await plexTv.send(
        'GET',
        '/api/v2/pins/$id',
        headers: {...headers, 'X-Plex-Client-Identifier': 'someone-else'},
      );
      expect(stranger.statusCode, 404);

      harness.network.claimPlexPin(id);
      final claimed = await plexTv.send(
        'GET',
        '/api/v2/pins/$id',
        headers: headers,
      );
      final token = claimed.data['authToken'] as String;
      expect(token, WorldSeerrUsers.annaPlex.plexToken);

      final signIn = await client.post('/api/v1/auth/plex', {
        'authToken': token,
      });
      expect(signIn.statusCode, 200);
      final me = await client.get('/api/v1/auth/me');
      expect(me.data['userType'], 1);
      expect(me.data['displayName'], WorldPeople.anna);
      // plex.tv saw no cookie and no Seerr key; Seerr saw no Plex token.
      for (final request in harness.network.requestsToHost(plexTvHost)) {
        expect(request.headers, isNot(contains('cookie')));
        expect(request.headers, isNot(contains('x-api-key')));
      }
      for (final request in harness.network.requestsTo(WorldIds.seerr)) {
        expect(request.headers, isNot(contains('x-plex-token')));
      }
    });

    test(
      'the session the app would have saved answers as the account',
      () async {
        final (harness, client) = await _start(Profiles.p2);
        client.cookies['connect.sid'] = harness.network.seerrSessionOf(
          WorldIds.seerr,
        );

        final me = await client.get('/api/v1/auth/me');

        expect(me.statusCode, 200);
        expect(me.data['id'], WorldSeerrUsers.annaLocal.id);
      },
    );

    test('the API key is still the admin, user 1', () async {
      final (_, client) = await _start(Profiles.p2);
      client.key = worldKey(WorldIds.seerr);

      final me = await client.get('/api/v1/auth/me');

      expect(me.data['id'], 1);
      expect(SeerrGrant.fromWhoAmI(me.data).permissions, 2);
    });
  });

  group('a session sees only its own', () {
    Future<_Client> anna() async {
      final (harness, client) = await _start(Profiles.p2);
      client.cookies['connect.sid'] = harness.network.seerrSessionOf(
        WorldIds.seerr,
      );
      return client;
    }

    test('requests: hers, where the key reads everybody\'s', () async {
      final client = await anna();

      final mine = await client.get('/api/v1/request?take=50');
      final everyone = await (_Client(
        WorldHosts.seerr,
        key: worldKey(WorldIds.seerr),
      )).get('/api/v1/request?take=50');

      List<Object?> by(Response<dynamic> r) => [
        for (final row in r.data['results'] as List)
          (row as Map)['requestedBy']['id'],
      ];
      expect(by(mine).toSet(), {2});
      expect(by(mine), hasLength(5));
      expect(by(everyone).toSet(), {2, 3});
    });

    test(
      "another member's requests are refused, in the route's words",
      () async {
        final client = await anna();

        final listed = await client.get('/api/v1/request?requestedBy=3');
        final one = await client.get('/api/v1/request/2');

        expect(listed.statusCode, 403);
        expect(listed.data, {
          'message': "You do not have permission to view this user's requests.",
        });
        expect(_verdict(listed), SeerrRefusal.permissionDenied);
        expect(one.statusCode, 403);
        expect(one.data, {
          'message': 'You do not have permission to view this request.',
        });
      },
    );

    test('the user list leaves the emails out', () async {
      final client = await anna();

      final users = await client.get('/api/v1/user');

      final rows = (users.data['results'] as List).cast<Map>();
      expect(rows, isNotEmpty);
      expect(rows.every((u) => !u.containsKey('email')), isTrue);
    });

    test('her quota is hers to read, and nobody else\'s', () async {
      final client = await anna();

      final own = await client.get('/api/v1/user/2/quota');
      final other = await client.get('/api/v1/user/3/quota');

      expect(own.statusCode, 200);
      final quota = SeerrQuota.fromJson(own.data);
      expect(quota.movie.limit, isNull);
      expect(quota.movie.restricted, isFalse);
      expect(other.statusCode, 403);
      expect(other.data, {
        'message':
            "You do not have permission to view this user's request limits.",
      });
    });
  });

  group('is refused correctly', () {
    test('nothing at all: the request validator answers first', () async {
      final (_, client) = await _start(Profiles.p2);

      final requests = await client.get('/api/v1/request');
      final me = await client.get('/api/v1/auth/me');
      final logout = await client.post('/api/v1/auth/logout');
      final status = await client.get('/api/v1/status');

      // Seerr 3.4.1, live: neither the key's header nor a session cookie, and
      // the OpenAPI validator refuses before the permission check is asked.
      for (final refused in [requests, me, logout]) {
        expect(refused.statusCode, 401);
        expect(refused.data['message'], "cookie 'connect.sid' required");
      }
      // The public routes answer anyone.
      expect(status.statusCode, 200);
    });

    test(
      'a session Seerr does not know: the permission check\'s body',
      () async {
        final (_, client) = await _start(Profiles.p2);
        client.cookies['connect.sid'] = 's%3Aunknown.signature';

        final requests = await client.get('/api/v1/request');
        final me = await client.get('/api/v1/auth/me');
        final logout = await client.post('/api/v1/auth/logout');

        expect(requests.statusCode, 403);
        expect(requests.data, _endpointBody);
        expect(_verdict(requests), SeerrRefusal.endpointRefused);
        expect(me.data, _endpointBody);
        expect(_verdict(me), SeerrRefusal.sessionEnded);
        // Signing out asks for no permission: it answers the same either way.
        expect(logout.statusCode, 200);
      },
    );

    test('a key Seerr does not know reads as nobody', () async {
      final (_, client) = await _start(Profiles.p2);
      client.key = 'not-the-key';

      final requests = await client.get('/api/v1/request');

      expect(requests.data, _endpointBody);
    });

    test(
      'refusesKey sends the same body, and the sign-in still works',
      () async {
        final (_, client) = await _start(
          Profiles.p2.withBehaviour(
            WorldIds.seerr,
            ConnectionBehaviour.refusesKey,
          ),
        );
        client.key = worldKey(WorldIds.seerr);

        final refused = await client.get('/api/v1/request');
        expect(refused.statusCode, 403);
        expect(refused.data, _endpointBody);

        client.key = null;
        final signIn = await client.post('/api/v1/auth/local', {
          'email': WorldSeerrUsers.annaLocal.email,
          'password': WorldSeerrUsers.annaLocal.password,
        });
        expect(signIn.statusCode, 200);
      },
    );

    test("the operator's routes refuse a requester, the gate's body", () async {
      final (harness, client) = await _start(Profiles.p2);
      client.cookies['connect.sid'] = harness.network.seerrSessionOf(
        WorldIds.seerr,
      );

      for (final (method, path) in const [
        ('POST', '/api/v1/request/1/approve'),
        ('POST', '/api/v1/request/2/decline'),
        ('GET', '/api/v1/settings/radarr'),
        ('DELETE', '/api/v1/media/811631'),
        ('GET', '/api/v1/issue'),
      ]) {
        final response = await client.send(method, path);
        expect(response.statusCode, 403, reason: '$method $path');
        expect(response.data, _endpointBody, reason: '$method $path');
        expect(_verdict(response), SeerrRefusal.endpointRefused);
      }
      // `/auth/me` still answers, so the domain reads it as a permission.
      final me = await client.get('/api/v1/auth/me');
      expect(
        SeerrRefusal.endpointRefused.afterWhoAmI(me.statusCode),
        SeerrRefusal.permissionDenied,
      );
    });

    test('a request: hers is made and waits, 4K is not hers to ask', () async {
      final (harness, client) = await _start(Profiles.p2);
      client.cookies['connect.sid'] = harness.network.seerrSessionOf(
        WorldIds.seerr,
      );

      final made = await client.post('/api/v1/request', {
        'mediaType': 'movie',
        'mediaId': WorldTitles.spring.tmdbId,
      });
      final fourK = await client.post('/api/v1/request', {
        'mediaType': 'movie',
        'mediaId': WorldTitles.spring.tmdbId,
        'is4k': true,
      });

      expect(made.statusCode, 201);
      expect(made.data['status'], 1);
      expect(made.data['requestedBy']['id'], 2);
      expect(fourK.statusCode, 403);
      expect(fourK.data, {
        'message': 'You do not have permission to make 4K movie requests.',
      });
      expect(_verdict(fourK), SeerrRefusal.requestNotAllowed);
    });

    test('auto-approval is read from the permissions', () async {
      final profile = Profiles.p2.withSeerrPermissions(
        SeerrPermission.request.value | SeerrPermission.autoApprove.value,
      );
      final (harness, client) = await _start(profile);
      client.cookies['connect.sid'] = harness.network.seerrSessionOf(
        WorldIds.seerr,
      );

      final made = await client.post('/api/v1/request', {
        'mediaType': 'movie',
        'mediaId': WorldTitles.spring.tmdbId,
      });
      final me = await client.get('/api/v1/auth/me');

      expect(made.data['status'], 2);
      expect(me.data['permissions'], 32 | 128);
    });

    test('cancelling: hers while it waits, a 401 once it does not', () async {
      final (harness, client) = await _start(Profiles.p2);
      client.cookies['connect.sid'] = harness.network.seerrSessionOf(
        WorldIds.seerr,
      );

      // Request 1 is Anna's and waits; request 3 is hers and was approved.
      final pending = await client.send('DELETE', '/api/v1/request/1');
      final approved = await client.send('DELETE', '/api/v1/request/3');

      expect(pending.statusCode, 204);
      expect(approved.statusCode, 401);
      expect(approved.data, {
        'message': 'You do not have permission to delete this request.',
      });
      expect(_verdict(approved), SeerrRefusal.noLongerCancellable);
    });

    test(
      'quotaReached: the quota says so and the request is refused',
      () async {
        final (harness, client) = await _start(
          Profiles.p2.withBehaviour(
            WorldIds.seerr,
            ConnectionBehaviour.quotaReached,
          ),
        );
        client.cookies['connect.sid'] = harness.network.seerrSessionOf(
          WorldIds.seerr,
        );

        final quota = await client.get('/api/v1/user/2/quota');
        final movie = await client.post('/api/v1/request', {
          'mediaType': 'movie',
          'mediaId': WorldTitles.spring.tmdbId,
        });
        final series = await client.post('/api/v1/request', {
          'mediaType': 'tv',
          'mediaId': WorldTitles.agent327.tmdbId,
          'seasons': [1],
        });

        final read = SeerrQuota.fromJson(quota.data);
        expect(read.movie.restricted, isTrue);
        expect(read.tv.restricted, isTrue);
        expect(read.movie.remaining, 0);
        expect(movie.data, {'message': 'Movie Quota exceeded.'});
        expect(series.data, {'message': 'Series Quota exceeded.'});
        expect(_verdict(movie), SeerrRefusal.quotaReached);
        expect(_verdict(series), SeerrRefusal.quotaReached);
      },
    );

    // One network per test: each `ProfileHarness.start` installs its own.
    for (final (what, profile, route, body, status, reply, verdict) in [
      (
        'a wrong password',
        Profiles.p2,
        'local',
        {'email': WorldSeerrUsers.annaLocal.email, 'password': 'wrong'},
        403,
        {'message': 'Access denied.'},
        SeerrRefusal.wrongEmailOrPassword,
      ),
      (
        'no password',
        Profiles.p2,
        'local',
        {'email': WorldSeerrUsers.annaLocal.email},
        500,
        {'error': 'You must provide both an email address and a password.'},
        SeerrRefusal.malformedSignIn,
      ),
      (
        'a wrong Jellyfin password',
        Profiles.p2ViaJellyfin,
        'jellyfin',
        {'username': 'anna', 'password': 'wrong'},
        401,
        {'message': 'INVALID_CREDENTIALS'},
        SeerrRefusal.wrongUsernameOrPassword,
      ),
      (
        'Jellyfin on a Plex server',
        Profiles.p2ViaPlex,
        'jellyfin',
        {'username': 'anna', 'password': WorldSeerrUsers.annaPlex.password},
        500,
        {'error': 'Jellyfin login is disabled'},
        SeerrRefusal.signInTurnedOff,
      ),
      (
        'Plex on a Jellyfin server',
        Profiles.p2ViaJellyfin,
        'plex',
        {'authToken': WorldSeerrUsers.annaPlex.plexToken},
        500,
        {'error': 'Plex login is disabled'},
        SeerrRefusal.signInTurnedOff,
      ),
      (
        'a token plex.tv has never seen',
        Profiles.p2ViaPlex,
        'plex',
        {'authToken': 'forged'},
        500,
        {'message': 'Unable to authenticate.'},
        SeerrRefusal.plexCheckFailed,
      ),
      (
        'no Plex token',
        Profiles.p2ViaPlex,
        'plex',
        <String, Object?>{},
        500,
        {'message': 'Authentication token required.'},
        SeerrRefusal.malformedSignIn,
      ),
    ]) {
      test('a sign-in refused for $what, in the route\'s own words', () async {
        final (_, client) = await _start(profile);

        final response = await client.post('/api/v1/auth/$route', body);

        expect(response.statusCode, status);
        expect(response.data, reply);
        expect(_verdict(response), verdict);
        expect(response.headers['set-cookie'], isNull);
      });
    }

    test('a Plex account the server does not share with is denied', () async {
      final (harness, client) = await _start(Profiles.p2ViaPlex);
      final plexTv = _Client('https://$plexTvHost');
      final pin = await plexTv.send(
        'POST',
        '/api/v2/pins?strong=true',
        headers: {'X-Plex-Client-Identifier': 'cupola-test-client'},
      );
      harness.network.claimPlexPin(
        pin.data['id'] as int,
        authToken: 'world-stranger-plex-token',
      );

      final signIn = await client.post('/api/v1/auth/plex', {
        'authToken': 'world-stranger-plex-token',
      });

      expect(signIn.statusCode, 403);
      expect(signIn.data, {'message': 'Access denied.'});
      expect(_verdict(signIn), SeerrRefusal.accountNotAllowed);
    });
  });

  group("a user's settings", () {
    const notYours = {
      'message': "You do not have permission to view this user's settings.",
    };
    const general = {'username': 'anna', 'email': 'anna@home.arpa'};

    Future<_Client> signedIn(ConfigProfile profile) async {
      final (harness, client) = await _start(profile);
      client.cookies['connect.sid'] = harness.network.seerrSessionOf(
        WorldIds.seerr,
      );
      return client;
    }

    test("Anna writes her own, and not user 1's", () async {
      final client = await signedIn(Profiles.p2);

      final own = await client.post('/api/v1/user/2/settings/main', general);
      final owners = await client.post('/api/v1/user/1/settings/main', general);
      final read = await client.get('/api/v1/user/1/settings/main');
      final link = await client.post(
        '/api/v1/user/1/settings/linked-accounts/plex',
        {'authToken': WorldSeerrUsers.annaPlex.plexToken},
      );

      expect(own.statusCode, 200);
      expect(own.data['username'], 'anna');
      // `isOwnProfileOrAdmin`, through the error handler, in one sentence
      // for a read and a write alike.
      expect(owners.statusCode, 403);
      expect(owners.data, notYours);
      expect(read.data, notYours);
      expect(_verdict(owners), SeerrRefusal.permissionDenied);
      expect(link.data, notYours);
    });

    test(
      'her permissions are the admin\'s, behind the permission check',
      () async {
        final client = await signedIn(Profiles.p2);

        final read = await client.get('/api/v1/user/2/settings/permissions');
        final write = await client.post('/api/v1/user/2/settings/permissions', {
          'permissions': 2,
        });
        final remove = await client.send('DELETE', '/api/v1/user/3');

        expect(read.data, _endpointBody);
        expect(write.data, _endpointBody);
        expect(remove.data, _endpointBody);
      },
    );

    test('her password: the current one first, and eight characters', () async {
      final client = await signedIn(Profiles.p2);
      const path = '/api/v1/user/2/settings/password';

      final short = await client.post(path, {
        'currentPassword': WorldSeerrUsers.annaLocal.password,
        'newPassword': 'short',
      });
      final wrong = await client.post(path, {
        'currentPassword': 'wrong',
        'newPassword': 'a-new-password',
      });
      final changed = await client.post(path, {
        'currentPassword': WorldSeerrUsers.annaLocal.password,
        'newPassword': 'a-new-password',
      });

      expect(short.data, {
        'message': 'Password must be at least 8 characters.',
      });
      expect(wrong.data, {'message': 'Current password is invalid.'});
      expect(changed.statusCode, 204);
    });

    test('MANAGE_USERS reaches everybody\'s settings, but user 1 stays '
        'user 1\'s', () async {
      final client = await signedIn(
        Profiles.p2.withSeerrPermissions(
          SeerrPermission.request.value | SeerrPermission.manageUsers.value,
        ),
      );

      final luca = await client.post('/api/v1/user/3/settings/main', {
        'username': 'luca',
      });
      final owner = await client.post('/api/v1/user/1/settings/main', general);
      final lucasLink = await client.post(
        '/api/v1/user/3/settings/linked-accounts/plex',
        {'authToken': WorldSeerrUsers.luca.plexToken},
      );

      expect(luca.statusCode, 200);
      expect(owner.statusCode, 403);
      expect(owner.data, {
        'message': "You do not have permission to modify this user's settings.",
      });
      // Linking an account is the user's own business, MANAGE_USERS or not.
      expect(lucasLink.data, notYours);
    });

    test('the key is user 1, who may write anybody\'s', () async {
      final (_, client) = await _start(Profiles.p2);
      client.key = worldKey(WorldIds.seerr);

      final own = await client.post('/api/v1/user/1/settings/main', {
        'username': 'operator',
      });
      final anna = await client.post('/api/v1/user/2/settings/main', general);

      expect(own.statusCode, 200);
      expect(anna.statusCode, 200);
    });
  });

  group('server states', () {
    test('signInDisabled(local): settings say so, the route refuses', () async {
      final (_, client) = await _start(
        Profiles.p2.withBehaviour(
          WorldIds.seerr,
          const ConnectionBehaviour.signInDisabled(SeerrSignInMethod.local),
        ),
      );

      final settings = await client.get('/api/v1/settings/public');
      final signIn = await client.post('/api/v1/auth/local', {
        'email': WorldSeerrUsers.annaLocal.email,
        'password': WorldSeerrUsers.annaLocal.password,
      });

      expect(settings.data['localLogin'], isFalse);
      final facts = SeerrServerFacts.fromPublicSettings(
        settings.data,
        version: '2.7.3',
      );
      expect(facts.signIn.offers(SeerrSignInMethod.local), isFalse);
      expect(signIn.data, {'error': 'Password sign-in is disabled.'});
      expect(_verdict(signIn), SeerrRefusal.signInTurnedOff);
    });

    test(
      'signInDisabled(jellyfin) turns the media-server sign-in off',
      () async {
        final (_, client) = await _start(
          Profiles.p2ViaJellyfin.withBehaviour(
            WorldIds.seerr,
            const ConnectionBehaviour.signInDisabled(
              SeerrSignInMethod.jellyfin,
            ),
          ),
        );

        final settings = await client.get('/api/v1/settings/public');
        final signIn = await client.post('/api/v1/auth/jellyfin', {
          'username': 'anna',
          'password': WorldSeerrUsers.annaJellyfin.password,
        });

        expect(settings.data['mediaServerLogin'], isFalse);
        expect(
          SeerrServerFacts.fromPublicSettings(
            settings.data,
            version: '3.5.0',
          ).signIn.offered,
          [SeerrSignInMethod.local],
        );
        expect(signIn.data, {'error': 'Jellyfin login is disabled'});
      },
    );

    test('signInDisabled(Quick Connect): nothing in the settings, the '
        'initiate fails', () async {
      final (_, client) = await _start(
        Profiles.p2ViaJellyfin.withBehaviour(
          WorldIds.seerr,
          const ConnectionBehaviour.signInDisabled(
            SeerrSignInMethod.jellyfinQuickConnect,
          ),
        ),
      );

      final initiate = await client.post(
        '/api/v1/auth/jellyfin/quickconnect/initiate',
      );

      expect(initiate.statusCode, 500);
      expect(initiate.data, {'message': 'Failed to initiate quick connect.'});

      // A code asked for before it was turned off is checked in vain.
      final check = await client.get(
        '/api/v1/auth/jellyfin/quickconnect/check?secret=${'A' * 64}',
      );
      expect(check.statusCode, 401);
      expect(check.data, {'message': 'Failed to check Quick Connect status'});
    });

    test('notInitialized: nothing to sign in to, and a Plex sign-in would '
        'make an admin', () async {
      // Seerr 3.5.0, so that Quick Connect's own first-setup refusal is there.
      final (harness, client) = await _start(
        Profiles.p2ViaJellyfin.withBehaviour(
          WorldIds.seerr,
          ConnectionBehaviour.notInitialized,
        ),
      );
      client.key = worldKey(WorldIds.seerr);

      final settings = await client.get('/api/v1/settings/public');
      final requests = await client.get('/api/v1/request');

      expect(settings.data['initialized'], isFalse);
      expect(settings.data['mediaServerType'], 4);
      expect(
        SeerrServerFacts.fromPublicSettings(settings.data).signIn.state,
        SeerrSignInState.notSetUp,
      );
      // The key acts as user 1, and there is nobody yet.
      expect(requests.data, _endpointBody);

      final quickConnect = await client.post(
        '/api/v1/auth/jellyfin/quickconnect/authenticate',
        {'secret': 'a' * 64},
      );
      expect(quickConnect.data, {
        'message': 'Quick Connect is not available during initial setup.',
      });
      expect(_verdict(quickConnect), SeerrRefusal.serverNotSetUp);

      // The trap: the first Plex sign-in becomes the admin.
      client.key = null;
      final signIn = await client.post('/api/v1/auth/plex', {
        'authToken': WorldSeerrUsers.annaPlex.plexToken,
      });
      expect(signIn.statusCode, 200);
      expect(signIn.data['permissions'], SeerrPermission.admin.value);
      expect(
        harness.network.seerrState(WorldIds.seerr).createdUsers,
        hasLength(1),
      );
    });
  });

  group('/status and /settings/public follow the release', () {
    Future<(Map<String, dynamic>, String)> read(ConfigProfile profile) async {
      final (_, client) = await _start(profile);
      final status = await client.get('/api/v1/status');
      final settings = await client.get('/api/v1/settings/public');
      return (
        settings.data as Map<String, dynamic>,
        status.data['version'] as String,
      );
    }

    test('the world answers as Jellyseerr 2.7.3 on Jellyfin', () async {
      final (settings, version) = await read(Profiles.p1);
      final facts = SeerrServerFacts.fromPublicSettings(
        settings,
        version: version,
      );

      expect(version, '2.7.3');
      expect(facts.family, SeerrFamily.jellyseerr);
      expect(facts.signIn.offered, [
        SeerrSignInMethod.jellyfin,
        SeerrSignInMethod.local,
      ]);
      // Seerr's settings name a default Radarr 4K.
      expect(facts.has4k(SeerrMediaKind.movie), isTrue);
      expect(facts.has4k(SeerrMediaKind.tv), isFalse);
    });

    test('P2-J is Seerr 3.5.0, with Quick Connect', () async {
      final (settings, version) = await read(Profiles.p2ViaJellyfin);
      final facts = SeerrServerFacts.fromPublicSettings(
        settings,
        version: version,
      );

      expect(facts.family, SeerrFamily.seerr);
      expect(facts.signIn.offered, [
        SeerrSignInMethod.jellyfin,
        SeerrSignInMethod.jellyfinQuickConnect,
        SeerrSignInMethod.local,
      ]);
    });

    test('P2-P is set up with Plex', () async {
      final (settings, version) = await read(Profiles.p2ViaPlex);

      expect(settings['mediaServerType'], 1);
      expect(
        SeerrServerFacts.fromPublicSettings(
          settings,
          version: version,
        ).signIn.offered,
        [SeerrSignInMethod.plex, SeerrSignInMethod.local],
      );
    });

    test('Overseerr has no Jellyfin sign-in and no Quick Connect', () async {
      final profile = Profiles.p2.withSeerrRelease(SeerrRelease.overseerr);
      final (settings, version) = await read(profile);
      final (_, client) = await _start(profile);

      expect(version, '1.35.0');
      expect(settings, isNot(contains('mediaServerType')));
      expect(
        SeerrServerFacts.fromPublicSettings(settings, version: version).family,
        SeerrFamily.overseerr,
      );
      final jellyfin = await client.post('/api/v1/auth/jellyfin', {
        'username': 'anna',
        'password': 'x',
      });
      expect(jellyfin.statusCode, 404);
    });

    test('Quick Connect is not there before 3.4.0', () async {
      final (_, client) = await _start(
        Profiles.p2ViaJellyfin.withSeerrRelease(SeerrRelease.seerr.at('3.3.0')),
      );

      final initiate = await client.post(
        '/api/v1/auth/jellyfin/quickconnect/initiate',
      );

      expect(initiate.statusCode, 404);
    });
  });

  group('meets CSRF', () {
    test('every write needs the token, the key and the sign-in too', () async {
      final (_, client) = await _start(
        Profiles.p2.withBehaviour(
          WorldIds.seerr,
          ConnectionBehaviour.csrfProtected,
        ),
      );

      // A write before any token: refused, and handed the secret only.
      final blind = await client.post('/api/v1/auth/local', {
        'email': WorldSeerrUsers.annaLocal.email,
        'password': WorldSeerrUsers.annaLocal.password,
      });
      expect(blind.statusCode, 403);
      expect(blind.data, {'message': 'invalid csrf token'});
      expect(_verdict(blind), SeerrRefusal.csrfToken);
      expect(client.setCookieLine('_csrf'), isNotNull);
      expect(client.setCookieLine('XSRF-TOKEN'), isNull);

      // A read hands out the token, on every answer.
      client.cookies.clear();
      await client.get('/api/v1/settings/public');
      expect(
        client.setCookieLine('_csrf'),
        endsWith('; Path=/; HttpOnly; Secure; SameSite=Strict'),
      );
      expect(
        client.setCookieLine('XSRF-TOKEN'),
        endsWith('; Path=/; Secure; SameSite=Strict'),
      );

      // The cookie without the header is not enough.
      final noHeader = await client.post('/api/v1/auth/local', {
        'email': WorldSeerrUsers.annaLocal.email,
        'password': WorldSeerrUsers.annaLocal.password,
      });
      expect(noHeader.data, {'message': 'invalid csrf token'});

      client.sendsXsrf = true;
      final signIn = await client.post('/api/v1/auth/local', {
        'email': WorldSeerrUsers.annaLocal.email,
        'password': WorldSeerrUsers.annaLocal.password,
      });
      expect(signIn.statusCode, 200);
      // With CSRF on, the session cookie is Strict.
      expect(client.setCookieLine('connect.sid'), endsWith('SameSite=Strict'));
      final request = await client.post('/api/v1/request', {
        'mediaType': 'movie',
        'mediaId': WorldTitles.spring.tmdbId,
      });
      expect(request.statusCode, 201);

      // The API key does not get past the guard either.
      final operator = _Client(WorldHosts.seerr, key: worldKey(WorldIds.seerr));
      final approve = await operator.post('/api/v1/request/1/approve');
      expect(approve.data, {'message': 'invalid csrf token'});
      await operator.get('/api/v1/status');
      operator.sendsXsrf = true;
      final retried = await operator.post('/api/v1/request/1/approve');
      expect(retried.statusCode, 200);
    });

    test('without the protection, no CSRF cookie is ever sent', () async {
      final (_, client) = await _start(Profiles.p2);

      await client.get('/api/v1/settings/public');
      await client.post('/api/v1/auth/local', {
        'email': WorldSeerrUsers.annaLocal.email,
        'password': WorldSeerrUsers.annaLocal.password,
      });

      expect(client.cookies.keys, ['connect.sid']);
    });
  });

  group('expires', () {
    test(
      'sessionExpired: the saved session is over, a new one works',
      () async {
        final (harness, client) = await _start(
          Profiles.p2.withBehaviour(
            WorldIds.seerr,
            ConnectionBehaviour.sessionExpired,
          ),
        );
        client.cookies['connect.sid'] = harness.network.seerrSessionOf(
          WorldIds.seerr,
        );

        final me = await client.get('/api/v1/auth/me');
        final requests = await client.get('/api/v1/request');
        expect(me.statusCode, 403);
        expect(_verdict(me), SeerrRefusal.sessionEnded);
        expect(requests.data, _endpointBody);

        final operator = _Client(
          WorldHosts.seerr,
          key: worldKey(WorldIds.seerr),
        );
        expect((await operator.get('/api/v1/request')).statusCode, 200);

        final signIn = await client.post('/api/v1/auth/local', {
          'email': WorldSeerrUsers.annaLocal.email,
          'password': WorldSeerrUsers.annaLocal.password,
        });
        expect(signIn.statusCode, 200);
        expect((await client.get('/api/v1/auth/me')).statusCode, 200);
      },
    );

    test('30 days after its last use, on the network clock', () async {
      final (harness, client) = await _start(Profiles.p2);
      client.cookies['connect.sid'] = harness.network.seerrSessionOf(
        WorldIds.seerr,
      );

      // Each use moves the server's expiry: 29 days, twice, is still in.
      harness.network.elapse(const Duration(days: 29));
      expect((await client.get('/api/v1/auth/me')).statusCode, 200);
      harness.network.elapse(const Duration(days: 29));
      expect((await client.get('/api/v1/auth/me')).statusCode, 200);

      harness.network.elapse(const Duration(days: 31));
      final me = await client.get('/api/v1/auth/me');
      expect(me.statusCode, 403);
      expect(_verdict(me), SeerrRefusal.sessionEnded);
    });

    test('signing out ends the session on the server', () async {
      final (harness, client) = await _start(Profiles.p2);
      client.cookies['connect.sid'] = harness.network.seerrSessionOf(
        WorldIds.seerr,
      );

      final out = await client.post('/api/v1/auth/logout');
      final me = await client.get('/api/v1/auth/me');

      expect(out.data, {'status': 'ok'});
      expect(me.statusCode, 403);
    });

    test('a Quick Connect code times out', () async {
      final (harness, client) = await _start(Profiles.p2ViaJellyfin);
      final initiate = await client.post(
        '/api/v1/auth/jellyfin/quickconnect/initiate',
      );
      final secret = initiate.data['secret'] as String;

      harness.network.elapse(seerrQuickConnectLifetime);
      final check = await client.get(
        '/api/v1/auth/jellyfin/quickconnect/check?secret=$secret',
      );

      expect(check.statusCode, 404);
      expect(check.data, {'message': 'Failed to check Quick Connect status'});
    });
  });

  group('the Plex PIN in fake time', () {
    testWidgets('claimed before it expires, then refused once it has', (
      tester,
    ) async {
      final harness = await ProfileHarness.start(Profiles.p2ViaPlex);
      harness.network.followFakeTime(tester.binding);
      final plexTv = _Client('https://$plexTvHost');
      const headers = {'X-Plex-Client-Identifier': 'cupola-test-client'};

      // Dio's I/O runs on the real event loop; the time between is fake.
      Future<Response<dynamic>> send(String method, String path) async =>
          (await tester.runAsync(
            () => plexTv.send(method, path, headers: headers),
          ))!;
      Future<Response<dynamic>> poll(int id) => send('GET', '/api/v2/pins/$id');

      final first = await send('POST', '/api/v2/pins?strong=true');
      final id = first.data['id'] as int;
      // Ten minutes of the person not yet signed in on app.plex.tv.
      for (var minute = 0; minute < 10; minute++) {
        expect((await poll(id)).data['authToken'], isNull);
        await tester.pump(const Duration(minutes: 1));
      }
      harness.network.claimPlexPin(id);
      expect(
        (await poll(id)).data['authToken'],
        WorldSeerrUsers.annaPlex.plexToken,
      );

      final second = await send('POST', '/api/v2/pins?strong=true');
      final late = second.data['id'] as int;
      final expiresAt = DateTime.parse(second.data['expiresAt'] as String);
      await tester.pump(expiresAt.difference(harness.network.currentTime));

      final expired = await poll(late);
      expect(expired.statusCode, 404);
      expect(() => harness.network.claimPlexPin(late), throwsStateError);
    });
  });

  group('P9: the operator, and a friend\'s Seerr', () {
    test("his key is the admin at home; at Sara's he is a requester", () async {
      final harness = await ProfileHarness.start(Profiles.p9);
      final home = _Client(WorldHosts.seerr, key: worldKey(WorldIds.seerr));
      final friend = _Client(WorldHosts.seerrFriend)
        ..cookies['connect.sid'] = harness.network.seerrSessionOf(
          WorldIds.seerrFriend,
        );

      final meHome = await home.get('/api/v1/auth/me');
      final meThere = await friend.get('/api/v1/auth/me');
      expect(meHome.data['id'], 1);
      expect(meThere.data['displayName'], WorldPeople.operatorName);
      expect(SeerrGrant.fromWhoAmI(meThere.data).permissions, 32);
      // Over TLS the session cookie is Secure.
      await friend.post('/api/v1/auth/local', {
        'email': WorldSeerrUsers.operatorAtFriend.email,
        'password': WorldSeerrUsers.operatorAtFriend.password,
      });
      expect(
        friend.setCookieLine('connect.sid'),
        endsWith('; HttpOnly; Secure; SameSite=Lax'),
      );

      expect((await home.post('/api/v1/request/1/approve')).statusCode, 200);
      final refused = await friend.post('/api/v1/request/1/approve');
      expect(refused.data, _endpointBody);
      // His own list there is empty: nobody filed anything under him.
      final mine = await friend.get('/api/v1/request');
      expect(mine.data['results'], isEmpty);
    });
  });
}
