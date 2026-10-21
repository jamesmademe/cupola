import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cupola/core/network/same_origin_http_client.dart';

String? _header(http.BaseRequest request, String name) {
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
  }
  return null;
}

void main() {
  group('SameOriginHttpClient', () {
    test('follows a same-origin redirect and keeps the credential', () async {
      final seen = <String>[];
      final inner = MockClient((request) async {
        seen.add(request.url.toString());
        if (request.url.path == '/start') {
          return http.Response('', 302, headers: {'location': '/next'});
        }
        expect(_header(request, 'X-Api-Key'), 'secret');
        return http.Response('image', 200);
      });
      final client = SameOriginHttpClient(inner);
      addTearDown(client.close);

      final response = await client.get(
        Uri.parse('https://nas.local/start'),
        headers: {'X-Api-Key': 'secret'},
      );

      expect(response.statusCode, 200);
      expect(response.body, 'image');
      expect(seen, ['https://nas.local/start', 'https://nas.local/next']);
    });

    test(
      'refuses a cross-origin redirect before it carries a credential',
      () async {
        var targetCalls = 0;
        final inner = MockClient((request) async {
          if (request.url.host == 'nas.local') {
            return http.Response(
              '',
              302,
              headers: {'location': 'https://evil.example/p.png'},
            );
          }
          targetCalls++;
          return http.Response('image', 200);
        });
        final client = SameOriginHttpClient(inner);
        addTearDown(client.close);

        await expectLater(
          client.get(
            Uri.parse('https://nas.local/poster.jpg'),
            headers: {'X-Api-Key': 'secret'},
          ),
          throwsA(isA<http.ClientException>()),
        );
        expect(targetCalls, 0);
      },
    );

    test('follows a cross-origin redirect when nothing is at risk', () async {
      var targetCalls = 0;
      final inner = MockClient((request) async {
        if (request.url.host == 'tmdb.org') {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://cdn.example/p.png'},
          );
        }
        targetCalls++;
        return http.Response('image', 200);
      });
      final client = SameOriginHttpClient(inner);
      addTearDown(client.close);

      final response = await client.get(
        Uri.parse('https://tmdb.org/poster.jpg'),
      );

      expect(response.statusCode, 200);
      expect(targetCalls, 1);
    });

    test('refuses a downgrade to http even without a credential', () async {
      var targetCalls = 0;
      final inner = MockClient((request) async {
        if (request.url.scheme == 'https') {
          return http.Response(
            '',
            302,
            headers: {'location': 'http://nas.local/next'},
          );
        }
        targetCalls++;
        return http.Response('image', 200);
      });
      final client = SameOriginHttpClient(inner);
      addTearDown(client.close);

      await expectLater(
        client.get(Uri.parse('https://nas.local/poster.jpg')),
        throwsA(isA<http.ClientException>()),
      );
      expect(targetCalls, 0);
    });

    test('stops a redirect loop at maxRedirects', () async {
      var calls = 0;
      final inner = MockClient((request) async {
        calls++;
        return http.Response('', 302, headers: {'location': '/loop'});
      });
      final client = SameOriginHttpClient(inner, maxRedirects: 2);
      addTearDown(client.close);

      await expectLater(
        client.get(Uri.parse('https://nas.local/start')),
        throwsA(isA<http.ClientException>()),
      );
      expect(calls, 3);
    });

    test('a redirect without Location is returned, not followed', () async {
      final inner = MockClient((request) async => http.Response('', 302));
      final client = SameOriginHttpClient(inner);
      addTearDown(client.close);

      final response = await client.get(
        Uri.parse('https://nas.local/poster.jpg'),
      );

      expect(response.statusCode, 302);
    });
  });
}
