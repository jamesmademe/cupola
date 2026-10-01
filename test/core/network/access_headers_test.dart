import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/answer_guard.dart';
import 'package:cupola/core/network/connection_access_registry.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/core/utils/image_utils.dart';

import '../../test_helpers/scripted_http_adapter.dart';

const _token = {
  'CF-Access-Client-Id': 'id.access',
  'CF-Access-Client-Secret': 'secret',
};

Dio _dio(
  ScriptedHttpAdapter adapter, {
  Map<String, String> access = _token,
  Map<String, dynamic>? headers,
}) {
  final dio = guardedDio(
    baseUrl: 'https://radarr.example.com',
    accessHeaders: access,
    headers: headers,
  )..httpClientAdapter = adapter;
  addTearDown(dio.close);
  return dio;
}

String? _header(ScriptedRequest request, String name) {
  for (final MapEntry(:key, :value) in request.headers.entries) {
    if (key.toLowerCase() == name.toLowerCase()) return '$value';
  }
  return null;
}

void main() {
  group('a connection\'s access headers', () {
    test('travel on every request, whatever the request sets itself', () async {
      final adapter = ScriptedHttpAdapter([const ScriptedReply(body: {})]);
      final dio = _dio(adapter);

      await dio.get('/api/v3/movie');
      await dio.post(
        '/api/v3/command',
        data: {'name': 'RefreshMovie'},
        options: Options(headers: {'X-Request': 'own'}),
      );

      for (final request in adapter.requests) {
        expect(_header(request, 'CF-Access-Client-Id'), 'id.access');
        expect(_header(request, 'CF-Access-Client-Secret'), 'secret');
      }
      expect(_header(adapter.lastRequest, 'X-Request'), 'own');
    });

    test('never take the service\'s own header away', () async {
      final adapter = ScriptedHttpAdapter([const ScriptedReply(body: {})]);
      final dio = _dio(
        adapter,
        access: const {'x-api-key': 'not-the-key', 'X-Proxy': 'p'},
        headers: {'X-Api-Key': 'the-key'},
      );

      await dio.get('/api/v3/movie');

      expect(_header(adapter.lastRequest, 'X-Api-Key'), 'the-key');
      expect(_header(adapter.lastRequest, 'X-Proxy'), 'p');
    });

    test('are named on the request, so a gateway can tell they were sent', () {
      final dio = guardedDio(
        baseUrl: 'https://radarr.example.com',
        accessHeaders: const {'X-Proxy-Key': 'v'},
      );
      addTearDown(dio.close);
      expect(dio.options.extra[kAccessHeaderNamesExtra], ['X-Proxy-Key']);

      final plain = guardedDio(baseUrl: 'https://radarr.example.com');
      addTearDown(plain.close);
      expect(plain.options.extra.containsKey(kAccessHeaderNamesExtra), isFalse);
    });

    test('never reach another host: a redirect there is refused before '
        'anything is sent to it', () async {
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(
          statusCode: 302,
          headers: {
            'location': ['https://elsewhere.example.net/collect'],
          },
        ),
        const ScriptedReply(body: {}),
      ]);
      final dio = _dio(adapter);

      await expectLater(
        dio.get('/api/v3/movie'),
        throwsA(
          isA<DioException>().having(
            (e) => classifyConnectionFailure(e),
            'reason',
            ServiceFailureReason.redirected,
          ),
        ),
      );
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.uri.host, 'radarr.example.com');
    });

    test('follow a redirect on the same host', () async {
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(
          statusCode: 301,
          headers: {
            'location': ['/radarr/api/v3/movie'],
          },
        ),
        const ScriptedReply(body: []),
      ]);
      final dio = _dio(adapter);

      await dio.get('/api/v3/movie');

      expect(adapter.requests, hasLength(2));
      final followed = adapter.requests.last;
      expect(followed.uri.host, 'radarr.example.com');
      expect(_header(followed, 'CF-Access-Client-Secret'), 'secret');
    });

    test('count as sent when a sign-in page answers anyway', () async {
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(
          body:
              '<!DOCTYPE html><html><body><form><input type="password">'
              '</form></body></html>',
          headers: {
            'content-type': ['text/html'],
          },
        ),
      ]);
      final dio = _dio(adapter, access: const {'X-Proxy-Key': 'k'});

      Object? failure;
      try {
        await dio.get('/api/v3/movie');
      } catch (error) {
        failure = error;
      }

      final gateway = accessGatewayOf(failure);
      expect(gateway?.kind, AccessGatewayKind.signInPage);
      expect(gateway?.credentialsSent, isTrue);
    });

    test('never appear in what a failure says', () async {
      const sentinel = 'sentinel-5c1d';
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(
          statusCode: 302,
          headers: {
            'location': [
              'https://team.cloudflareaccess.com/cdn-cgi/access/login/x',
            ],
          },
        ),
      ]);
      final dio = _dio(
        adapter,
        access: const {
          'CF-Access-Client-Id': '$sentinel-id',
          'CF-Access-Client-Secret': '$sentinel-secret',
        },
      );

      Object? failure;
      try {
        await dio.get('/api/v3/movie');
      } catch (error) {
        failure = error;
      }

      expect(accessGatewayOf(failure)?.credentialsSent, isTrue);
      final said = [
        '$failure',
        connectionFailureSentence(failure),
        connectionFailureSentence(failure, subject: 'Radarr'),
        '${ClassifiedFailure.of(failure)}',
        '${accessGatewayOf(failure)}',
      ].join('\n');
      expect(said, isNot(contains(sentinel)));
    });

    test('ride in the headers the background release search is handed', () {
      final client = ApiClient(
        baseUrl: 'https://radarr.example.com',
        apiKey: 'key',
        accessHeaders: _token,
      );
      addTearDown(client.close);

      expect(client.headers, containsPair('CF-Access-Client-Id', 'id.access'));
      expect(client.headers, containsPair('X-Api-Key', 'key'));
    });

    test('go with an arr\'s artwork to its own address only', () {
      ConnectionAccessRegistry.update([
        (url: 'https://radarr.example.com/', headers: _token),
      ]);
      addTearDown(ConnectionAccessRegistry.reset);

      final local = ImageUtils.extractPosterUrl(
        [
          {'coverType': 'poster', 'url': '/MediaCover/1/poster.jpg'},
        ],
        baseUrl: 'https://radarr.example.com',
        apiKey: 'key',
      );
      final remote = ImageUtils.extractPosterUrl(
        [
          {
            'coverType': 'poster',
            'remoteUrl': 'https://image.tmdb.org/t/p/original/a.jpg',
          },
        ],
        baseUrl: 'https://radarr.example.com',
        apiKey: 'key',
      );
      final other = ImageUtils.extractPosterUrl(
        [
          {'coverType': 'poster', 'url': '/MediaCover/1/poster.jpg'},
        ],
        baseUrl: 'https://sonarr.example.com',
        apiKey: 'key',
      );

      expect(local.headers, {..._token, 'X-Api-Key': 'key'});
      expect(remote.headers, isNull);
      expect(other.headers, {'X-Api-Key': 'key'});
    });
  });
}
