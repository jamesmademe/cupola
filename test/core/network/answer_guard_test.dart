import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';

/// Answers every request with one canned reply.
class _Answer implements HttpClientAdapter {
  _Answer(this.status, this.body, {this.contentType, this.headers = const {}});

  final int status;
  final String body;
  final String? contentType;
  final Map<String, List<String>> headers;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes(
    Uint8List.fromList(utf8.encode(body)),
    status,
    headers: {
      ...headers,
      if (contentType != null) Headers.contentTypeHeader: [contentType!],
    },
  );
}

const _page =
    '<!DOCTYPE html><html><head><title>Welcome to nginx!</title></head>'
    '<body><p>session=abc123</p></body></html>';

ApiClient _api(
  HttpClientAdapter adapter, {
  String base = 'https://radarr.example.com',
}) {
  final client = ApiClient(baseUrl: base, apiKey: 'secret-key');
  client.dio.httpClientAdapter = adapter;
  return client;
}

Future<Object> _failure(Future<Object?> request) async {
  try {
    await request;
  } catch (error) {
    return error;
  }
  fail('expected the request to fail');
}

void main() {
  group('a request that asks for JSON', () {
    test('fails on a 200 web page, classified, without the page', () async {
      final client = _api(
        _Answer(
          200,
          _page,
          contentType: 'text/html; charset=utf-8',
          headers: {
            'server': ['nginx'],
            'set-cookie': ['session=abc123'],
          },
        ),
      );

      final error = await _failure(client.get('/api/v3/movie'));

      expect(error, isA<DioException>());
      final unexpected = (error as DioException).error;
      expect(unexpected, isA<UnexpectedAnswer>());
      // A web page is the address's fault, wherever it met the request.
      expect(classifyConnectionFailure(error), ServiceFailureReason.notFound);
      final answer = unexpected as UnexpectedAnswer;
      expect(answer.status, 200);
      expect(answer.isWebPage, isTrue);
      expect(answer.host, 'radarr.example.com');
      expect(answer.baseUrl, 'https://radarr.example.com');
      expect(webPageAnswerOf(error), same(answer));
      // What classification reads is kept; a cookie never is.
      expect(answer.headers.keys, containsAll(['content-type', 'server']));
      expect(answer.headers.containsKey('set-cookie'), isFalse);
      // Its words name the service, so they come from the surface.
      expect(connectionFailureDetail(error), isNull);
      expect(
        connectionFailureSentence(error, subject: 'Radarr'),
        'A web page answered at radarr.example.com instead of Radarr.',
      );
    });

    test('fails on a body that does not decode, whatever its label', () async {
      for (final contentType in ['application/json', 'text/plain']) {
        final client = _api(
          _Answer(200, '{"records": [', contentType: contentType),
        );

        final error = await _failure(client.get('/api/v3/movie'));

        expect(
          (error as DioException).error,
          isA<UnexpectedAnswer>(),
          reason: contentType,
        );
        expect(
          classifyConnectionFailure(error),
          ServiceFailureReason.invalidResponse,
        );
        // Not a web page, so the classification's own words stand.
        expect(connectionFailureDetail(error), isNull);
      }
    });

    test('keeps a body labelled text that is JSON', () async {
      final client = _api(
        _Answer(200, '{"version":"5.2.0"}', contentType: 'text/plain'),
      );

      final response = await client.get('/api/v3/system/status');

      expect(response.data, '{"version":"5.2.0"}');
    });

    test('leaves an empty write answer alone', () async {
      for (final (status, type) in [
        (200, null),
        (204, null),
        (200, 'text/html'),
        (200, 'application/json'),
      ]) {
        final client = _api(_Answer(status, '', contentType: type));

        final post = await client.post('/api/v3/command', data: {'name': 'x'});
        final delete = await client.delete('/api/v3/movie/1');

        expect(post.statusCode, status, reason: '$status $type');
        expect(delete.statusCode, status, reason: '$status $type');
      }
    });

    test('leaves a write that confirms itself in a word alone', () async {
      final client = _api(_Answer(200, 'OK', contentType: 'text/plain'));

      final response = await client.post('/api/system/tasks', data: {});

      expect(response.data, 'OK');
    });

    test('a write answered by a web page did not happen', () async {
      final client = _api(_Answer(200, _page, contentType: 'text/html'));

      final error = await _failure(
        client.post('/api/v3/command', data: {'name': 'RefreshMovie'}),
      );

      expect((error as DioException).error, isA<UnexpectedAnswer>());
    });

    test('names the port when the address names one', () async {
      final client = _api(
        _Answer(200, _page, contentType: 'text/html'),
        base: 'http://nas.home.arpa:7878',
      );

      final error = await _failure(client.get('/api/v3/movie'));

      expect(
        ((error as DioException).error as UnexpectedAnswer).host,
        'nas.home.arpa:7878',
      );
    });
  });

  group('a request that does not ask for JSON', () {
    test('reads text, and a page, as text', () async {
      // qBittorrent's version and login, SABnzbd's `_raw`, the JSON-RPC
      // clients: none sends `Accept: application/json`, and each reads its
      // own envelope.
      for (final (body, type) in [
        ('v4.6.2', 'text/plain; charset=UTF-8'),
        ('Ok.', 'text/plain'),
        (_page, 'text/html'),
      ]) {
        final dio = guardedDio(baseUrl: 'http://nas.home.arpa:8080');
        dio.httpClientAdapter = _Answer(200, body, contentType: type);

        final response = await dio.get<dynamic>('/api/v2/app/version');

        expect(response.data, body);
      }
    });

    test('a plain or byte response type is never checked', () async {
      final dio = guardedDio(
        baseUrl: 'https://radarr.example.com',
        headers: {'Accept': 'application/json'},
      );
      dio.httpClientAdapter = _Answer(
        200,
        'line one\nline two',
        contentType: 'text/plain',
      );

      final response = await dio.get<dynamic>(
        '/api/v3/log/file/radarr.txt',
        options: Options(responseType: ResponseType.plain),
      );

      expect(response.data, 'line one\nline two');
    });
  });

  group('UnexpectedAnswer', () {
    test('holds a bounded prefix of the body', () {
      final answer = UnexpectedAnswer(status: 200, body: 'x' * 20000);

      expect(answer.bodyPrefix!.length, UnexpectedAnswer.bodyPrefixLimit);
    });

    test('never prints its body or its headers', () {
      final answer = UnexpectedAnswer(
        status: 200,
        headers: {
          'content-type': ['text/html'],
          'server': ['nginx/1.25 secret-build'],
        },
        body: '<html><input type="password" value="hunter2"></html>',
        host: 'radarr.example.com',
      );
      final printed = [
        answer.toString(),
        connectionFailureSentence(answer),
        DioException(
          requestOptions: RequestOptions(path: '/api/v3/movie'),
          error: answer,
        ).toString(),
      ].join('\n');

      expect(printed, isNot(contains('hunter2')));
      expect(printed, isNot(contains('secret-build')));
      expect(printed, isNot(contains('text/html')));
      expect(answer.toString(), 'UnexpectedAnswer(200)');
    });
  });
}
