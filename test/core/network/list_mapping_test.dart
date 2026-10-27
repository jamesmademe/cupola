import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';

/// Answers every request with one canned reply.
class _Answer implements HttpClientAdapter {
  _Answer(this.status, this.body, {this.contentType});

  final int status;
  final String body;
  final String? contentType;

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
      if (contentType != null) Headers.contentTypeHeader: [contentType!],
    },
  );
}

const _gatewayPage =
    '<!DOCTYPE html><html><head><title>Sign in</title></head>'
    '<body><form><input type="password" name="password"></form></body></html>';

/// A list large enough to cross the transformer's isolate threshold.
String _movies(int count) => jsonEncode([
  for (var i = 0; i < count; i++)
    {
      'id': i,
      'title': 'Movie $i',
      'sortTitle': 'movie $i',
      'overview': 'Padding that makes each record a few hundred bytes. ' * 3,
      'year': 2000 + i % 20,
      'tmdbId': 1000 + i,
      'genres': ['Drama', 'Thriller'],
    },
]);

ApiClient _api(HttpClientAdapter adapter) {
  final client = ApiClient(baseUrl: 'https://radarr.example.com', apiKey: 'k');
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
  group('a list read that is mapped where it is decoded', () {
    test('maps every record of a large body', () async {
      final body = _movies(1500);
      expect(utf8.encode(body).length, greaterThan(50 * 1024));
      final service = RadarrService(
        _api(_Answer(200, body, contentType: 'application/json')),
      );

      final movies = await service.getMoviesOrThrow();

      expect(movies, hasLength(1500));
      expect(movies.first.title, 'Movie 0');
      expect(movies.last.id, 1499);
      expect(movies[700].tmdbId, 1700);
    });

    test('maps a small body the same way', () async {
      final service = RadarrService(
        _api(
          _Answer(
            200,
            _movies(3),
            contentType: 'application/json; charset=utf-8',
          ),
        ),
      );

      final movies = await service.getMoviesOrThrow();

      expect(movies.map((m) => m.title), ['Movie 0', 'Movie 1', 'Movie 2']);
    });

    test(
      'a gateway page sent as text/html is still recognised as a gateway',
      () async {
        // The transformer maps only JSON bodies, so a page keeps the String the
        // gateway recognisers read, whatever the list it was asked for.
        final service = RadarrService(
          _api(_Answer(200, _gatewayPage, contentType: 'text/html')),
        );

        final error = await _failure(service.getMoviesOrThrow());

        expect((error as DioException).error, isA<AccessGatewayAnswer>());
      },
    );

    test(
      'a large body labelled JSON that is a page fails as an unexpected answer',
      () async {
        final page = '$_gatewayPage${'<!-- padding -->' * 5000}';
        expect(utf8.encode(page).length, greaterThan(50 * 1024));
        final service = RadarrService(
          _api(_Answer(200, page, contentType: 'application/json')),
        );

        final error = await _failure(service.getMoviesOrThrow());

        expect((error as DioException).error, isA<UnexpectedAnswer>());
        expect(
          classifyConnectionFailure(error),
          ServiceFailureReason.invalidResponse,
        );
      },
    );

    test(
      'a record the mapper cannot read fails as the reader always did, not as a DioException',
      () async {
        // One record with a field of another type, as an arr of another version
        // might send. The mapper throws a TypeError; that must reach the caller
        // unwrapped, so a failure classifier does not read it as a network fault.
        final small = jsonDecode(_movies(3)) as List<dynamic>
          ..[1] = {'id': 1, 'title': 'Bad', 'year': 'nineteen'};
        final large = jsonDecode(_movies(1500)) as List<dynamic>
          ..[700] = {'id': 700, 'title': 'Bad', 'year': 'nineteen'};

        for (final body in [jsonEncode(small), jsonEncode(large)]) {
          final service = RadarrService(
            _api(_Answer(200, body, contentType: 'application/json')),
          );

          final error = await _failure(service.getMoviesOrThrow());

          expect(error, isA<TypeError>(), reason: '${body.length} bytes');
        }
      },
    );

    test('a refused status is not mapped', () async {
      final service = RadarrService(
        _api(_Answer(500, _movies(3), contentType: 'application/json')),
      );

      final error = await _failure(service.getMoviesOrThrow());

      expect(error, isA<DioException>());
      expect((error as DioException).response?.statusCode, 500);
    });
  });
}
