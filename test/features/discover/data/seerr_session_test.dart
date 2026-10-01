/// The Seerr transport against the fake Seerr: what the key sends, and the
/// CSRF token it answers.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/capability/permission_refusal.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';

import '../../../test_helpers/profiles/profiles.dart';

ApiClient _client(ConfigProfile profile) {
  final client = seerrClientFor(profile.connection(WorldIds.seerr).instance);
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
  test('the key travels as X-Api-Key', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final client = _client(Profiles.p1);

    await client.get('/api/v1/request', queryParameters: {'take': 1});

    final sent = harness.network.requestsTo(WorldIds.seerr).single;
    expect(sent.headers['x-api-key'], worldKey(WorldIds.seerr));
    expect(sent.headers['cookie'], isNull);
  });

  group('CSRF', () {
    final protected = Profiles.p1.withBehaviour(
      WorldIds.seerr,
      ConnectionBehaviour.csrfProtected,
    );

    test(
      'a write refused for its token fetches one and goes once more',
      () async {
        final harness = await ProfileHarness.start(protected);
        final client = _client(protected);

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
        expect(sent.last.headers['x-api-key'], worldKey(WorldIds.seerr));
      },
    );

    test('a token kept from a read goes with the first write', () async {
      final harness = await ProfileHarness.start(protected);
      final client = _client(protected);

      await client.get('/api/v1/settings/public');
      await client.delete('/api/v1/media/1');

      expect(
        harness.network
            .requestsTo(WorldIds.seerr)
            .map((r) => '${r.method} ${r.path}'),
        ['GET /api/v1/settings/public', 'DELETE /api/v1/media/1'],
      );
    });

    test('refused again, it fails once as a refused token', () async {
      final harness = await ProfileHarness.start(protected);
      // A guard that refuses even the token it hands out.
      harness.network.on(
        WorldIds.seerr,
        'DELETE',
        '/api/v1/media/1',
        (_) =>
            NetworkReply.json({'message': 'invalid csrf token'}, status: 403),
      );
      final client = _client(protected);

      final error = await _failure(() => client.delete('/api/v1/media/1'));

      expect((error as DioException).error, isA<SeerrCsrfRefused>());
      expect(
        classifyConnectionFailure(error),
        ServiceFailureReason.csrfRefused,
      );
      // Never the key refused: the key was never the question.
      expect(isPermissionRefusal(error), isFalse);
      expect(seerrRefusalOf(error), SeerrRefusal.csrfToken);
      final writes = harness.network
          .requestsTo(WorldIds.seerr)
          .where((r) => r.method == 'DELETE');
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

    test('a key Seerr refuses is still the key refused', () async {
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
      expect(harness.network.requestsTo(WorldIds.seerr), hasLength(1));
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
