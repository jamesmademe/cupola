import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/capability/permission_refusal.dart';
import 'package:cupola/core/network/answer_guard.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Answers every request with one canned reply, and keeps the requests.
class _Answer implements HttpClientAdapter {
  _Answer(
    this.status, {
    this.body = '',
    this.contentType = 'text/html',
    this.headers = const {},
  });

  final int status;
  final String body;
  final String contentType;
  final Map<String, List<String>> headers;
  final List<RequestOptions> seen = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(body)),
      status,
      headers: {
        ...headers,
        Headers.contentTypeHeader: [contentType],
      },
    );
  }
}

const _cloudflarePage =
    '<!DOCTYPE html><html><head><title>Forbidden</title></head></html>';
const _signInPage =
    '<!DOCTYPE html><html><body><form><input type="text" name="u">'
    "<input type='password' name='p'></form></body></html>";

ApiClient _api(
  HttpClientAdapter adapter, {
  String base = 'https://radarr.example.com',
}) {
  final client = ApiClient(baseUrl: base, apiKey: 'secret-key');
  client.dio.httpClientAdapter = adapter;
  return client;
}

Dio _dio(
  HttpClientAdapter adapter, {
  bool nativeBasicAuth = false,
  Map<String, dynamic>? headers,
}) {
  final dio = guardedDio(
    baseUrl: 'http://nas.home.arpa:8080',
    nativeBasicAuth: nativeBasicAuth,
    headers: headers,
  );
  dio.httpClientAdapter = adapter;
  return dio;
}

Future<DioException> _failure(Future<Object?> request) async {
  try {
    await request;
  } on DioException catch (error) {
    return error;
  }
  fail('expected the request to fail');
}

AccessGatewayAnswer? _gateway(DioException error) => accessGatewayOf(error);

void main() {
  group('Cloudflare Access', () {
    test('a redirect to the team domain is Access, not a redirect', () async {
      final adapter = _Answer(
        302,
        headers: {
          'location': [
            'https://cupola-home.cloudflareaccess.com/cdn-cgi/access/login/'
                'radarr.example.com?kid=1',
          ],
        },
      );

      final error = await _failure(_api(adapter).get('/api/v3/system/status'));

      expect(
        classifyConnectionFailure(error),
        ServiceFailureReason.accessGateway,
      );
      final gateway = _gateway(error)!;
      expect(gateway.kind, AccessGatewayKind.cloudflareAccess);
      expect(gateway.credentialsSent, isFalse);
      expect(gateway.gatewayHost, 'cupola-home.cloudflareaccess.com');
      expect(gateway.serviceHost, 'radarr.example.com');
      expect(adapter.seen, hasLength(1), reason: 'never followed');
    });

    test(
      'a redirect to /cdn-cgi/access/ on the same host is not followed',
      () async {
        final adapter = _Answer(
          302,
          headers: {
            'location': ['/cdn-cgi/access/login/radarr.example.com'],
          },
        );

        final error = await _failure(
          _api(adapter).get('/api/v3/system/status'),
        );

        expect(_gateway(error)?.kind, AccessGatewayKind.cloudflareAccess);
        expect(adapter.seen, hasLength(1));
      },
    );

    test(
      'a 401 with Cloudflare\'s page is Access, not a refused key',
      () async {
        final error = await _failure(
          _api(
            _Answer(
              401,
              body: _cloudflarePage,
              headers: {
                'server': ['cloudflare'],
                'cf-ray': ['8c1f2e3d4b5a6978-MXP'],
              },
            ),
          ).get('/api/v3/movie'),
        );

        expect(
          classifyConnectionFailure(error),
          ServiceFailureReason.accessGateway,
        );
        expect(_gateway(error)?.kind, AccessGatewayKind.cloudflareAccess);
        expect(_gateway(error)?.gatewayHost, 'radarr.example.com');
      },
    );

    test('a 403 whose challenge names the team domain is Access', () async {
      final error = await _failure(
        _api(
          _Answer(
            403,
            contentType: 'application/json',
            body: '{}',
            headers: {
              'www-authenticate': [
                'Cloudflare-Access realm="https://cupola-home.cloudflareaccess.com"',
              ],
            },
          ),
        ).get('/api/v3/movie'),
      );

      expect(_gateway(error)?.kind, AccessGatewayKind.cloudflareAccess);
      expect(_gateway(error)?.gatewayHost, 'cupola-home.cloudflareaccess.com');
      // Never "may not change this": the service never saw the request.
      expect(isPermissionRefusal(error), isFalse);
    });

    test('a service token sent is read off the request itself', () async {
      final dio = _dio(
        _Answer(
          401,
          body: _cloudflarePage,
          headers: {
            'server': ['cloudflare'],
            'cf-ray': ['8c1f'],
          },
        ),
        headers: {
          'CF-Access-Client-Id': 'abc.access',
          'CF-Access-Client-Secret': 'never-printed',
        },
      );

      final error = await _failure(dio.get<dynamic>('/api/v2/app/version'));

      expect(_gateway(error)?.credentialsSent, isTrue);
      expect(error.error.toString(), isNot(contains('never-printed')));
    });

    test('Cloudflare in front of a service that answered for itself is not '
        'Access', () async {
      // A 401 the service sent through a Cloudflare tunnel: its own JSON.
      final error = await _failure(
        _api(
          _Answer(
            401,
            contentType: 'application/json',
            body: '{"message":"Unauthorized"}',
            headers: {
              'server': ['cloudflare'],
              'cf-ray': ['8c1f'],
            },
          ),
        ).get('/api/v3/movie'),
      );

      expect(
        classifyConnectionFailure(error),
        ServiceFailureReason.unauthorized,
      );
    });
  });

  group('a sign-in page', () {
    test('a redirect to another host\'s login', () async {
      final error = await _failure(
        _api(
          _Answer(
            302,
            headers: {
              'location': ['https://auth.example.net/login?rd=x'],
            },
          ),
        ).get('/api/v3/system/status'),
      );

      expect(_gateway(error)?.kind, AccessGatewayKind.signInPage);
      expect(_gateway(error)?.gatewayHost, 'auth.example.net');
    });

    test(
      'a redirect to another host that is not a sign-in stays a redirect',
      () async {
        final error = await _failure(
          _api(
            _Answer(
              302,
              headers: {
                'location': ['https://cdn.example.net/radarr/'],
              },
            ),
          ).get('/api/v3/system/status'),
        );

        expect(error.error, isA<RedirectRefused>());
        expect(
          classifyConnectionFailure(error),
          ServiceFailureReason.redirected,
        );
      },
    );

    test('a 200 page with a password field, on any client', () async {
      for (final request in [
        _api(_Answer(200, body: _signInPage)).get('/api/v3/movie'),
        // qBittorrent asks for no JSON, and still did not reach qBittorrent.
        _dio(
          _Answer(200, body: _signInPage),
        ).get<dynamic>('/api/v2/app/version'),
      ]) {
        final error = await _failure(request);

        expect(_gateway(error)?.kind, AccessGatewayKind.signInPage);
      }
    });
  });

  group('a password prompt', () {
    final prompt = _Answer(
      401,
      body: '<html><title>401 Authorization Required</title></html>',
      headers: {
        'www-authenticate': ['Basic realm="Restricted"'],
      },
    );

    test('a Basic 401 in front of a service that does not use Basic', () async {
      final error = await _failure(
        _dio(prompt).get<dynamic>('/api/v2/app/version'),
      );

      expect(_gateway(error)?.kind, AccessGatewayKind.passwordPrompt);
      expect(_gateway(error)?.credentialsSent, isFalse);
    });

    test('a password sent is read off the request', () async {
      final error = await _failure(
        _dio(
          prompt,
          headers: {
            'Authorization': 'Basic ${base64Encode(utf8.encode('u:p'))}',
          },
        ).get<dynamic>('/api/v2/app/version'),
      );

      expect(_gateway(error)?.credentialsSent, isTrue);
    });

    test('is the service\'s own refusal where the service signs in with '
        'Basic', () async {
      final error = await _failure(
        _dio(prompt, nativeBasicAuth: true).get<dynamic>('/jsonrpc'),
      );

      expect(_gateway(error), isNull);
      expect(
        classifyConnectionFailure(error),
        ServiceFailureReason.unauthorized,
      );
    });

    test('a realm that names the service is the service\'s own', () async {
      final error = await _failure(
        _api(
          _Answer(
            401,
            body: '',
            headers: {
              'www-authenticate': ['Basic realm="Sonarr"'],
            },
          ),
        ).get('/api/v3/series'),
      );

      expect(_gateway(error), isNull);
      expect(
        classifyConnectionFailure(error),
        ServiceFailureReason.unauthorized,
      );
    });

    test('a plain 401 is the service refusing its key', () async {
      final error = await _failure(
        _api(
          _Answer(401, contentType: 'application/json', body: ''),
        ).get('/api/v3/movie'),
      );

      expect(_gateway(error), isNull);
      expect(
        classifyConnectionFailure(error),
        ServiceFailureReason.unauthorized,
      );
    });
  });

  group('the extra the access layer can name its headers under', () {
    test('a named header counts as access sent to a sign-in page', () {
      final request = RequestOptions(
        path: '/',
        headers: {'X-Gateway-Key': 'k'},
        extra: {
          kAccessHeaderNamesExtra: ['X-Gateway-Key'],
        },
      );

      expect(
        accessCredentialsSent(request, AccessGatewayKind.signInPage),
        isTrue,
      );
      expect(
        accessCredentialsSent(request, AccessGatewayKind.cloudflareAccess),
        isFalse,
      );
    });
  });

  group('the words', () {
    AccessGatewayAnswer gateway(AccessGatewayKind kind, {bool sent = false}) =>
        AccessGatewayAnswer(
          kind: kind,
          credentialsSent: sent,
          gatewayHost: 'cupola-home.cloudflareaccess.com',
          serviceHost: 'radarr.example.com',
        );

    test('amber, and Retry cannot help', () {
      expect(
        failureTone(ServiceFailureReason.accessGateway),
        StatusTone.warning,
      );
      expect(failureRetryHelps(ServiceFailureReason.accessGateway), isFalse);
      expect(
        failureRetryHelps(
          ServiceFailureReason.accessGateway,
          credential: kRefusedSignIn,
        ),
        isFalse,
      );
    });

    final cases = <(AccessGatewayAnswer, String, String, String, String)>[
      (
        gateway(AccessGatewayKind.cloudflareAccess),
        'Behind Cloudflare Access',
        'Cloudflare Access answered instead of Radarr',
        'Radarr is behind Cloudflare Access. Cupola needs a service token '
            'to reach it.',
        'Add a service token',
      ),
      (
        gateway(AccessGatewayKind.cloudflareAccess, sent: true),
        'Service token not accepted',
        'Cloudflare Access did not accept the service token',
        'Add a Service Auth policy for it on radarr.example.com, or make a '
            'new token if it expired.',
        'Check the token',
      ),
      (
        gateway(AccessGatewayKind.signInPage),
        'Behind a sign-in page',
        'A sign-in page answered instead of Radarr',
        'Something in front of Radarr asks for a sign-in that Cupola '
            'cannot complete.',
        'Add access',
      ),
      (
        gateway(AccessGatewayKind.passwordPrompt),
        'Behind a password prompt',
        'A password prompt answered instead of Radarr',
        'Something in front of Radarr asks for a username and password.',
        'Add the password',
      ),
      (
        gateway(AccessGatewayKind.passwordPrompt, sent: true),
        'Password not accepted',
        'The proxy did not accept the password',
        'Something in front of Radarr asked for a username and password, '
            'and refused the ones Cupola sent.',
        'Check the password',
      ),
    ];

    for (final (answer, label, headline, sentence, remedy) in cases) {
      test(headline, () {
        final words = describeFailure(
          ServiceKey.radarr,
          ServiceFailureReason.accessGateway,
          gateway: answer,
        );

        expect(words.tone, StatusTone.warning);
        expect(words.label, label);
        expect(words.headline, headline);
        expect(words.remedy, remedy);
        expect(
          connectionFailureMessage(
            ServiceKey.radarr,
            ServiceFailureReason.accessGateway,
            gateway: answer,
          ),
          sentence,
        );
        // Every word of it is the registry's name, never a hard-coded one.
        expect(
          describeFailure(
            ServiceKey.sonarr,
            ServiceFailureReason.accessGateway,
            gateway: answer,
          ).headline,
          headline.replaceAll('Radarr', 'Sonarr'),
        );
      });
    }

    test('without a service, the sentence names the address', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/'),
        error: gateway(AccessGatewayKind.cloudflareAccess),
      );

      expect(
        connectionFailureSentence(error),
        'radarr.example.com is behind Cloudflare Access. Cupola needs a '
        'service token to reach it.',
      );
      expect(
        connectionFailureSentence(error, subject: 'Radarr'),
        'Radarr is behind Cloudflare Access. Cupola needs a service token to '
        'reach it.',
      );
    });

    test('a gateway nothing names reads as access, without guessing which', () {
      expect(
        describeFailure(
          ServiceKey.radarr,
          ServiceFailureReason.accessGateway,
        ).headline,
        'Something in front of Radarr answered instead of it',
      );
      expect(failureRemedy(ServiceFailureReason.accessGateway), 'Add access');
    });

    test('the gateway survives a classified summary and a client wrapper', () {
      final answer = gateway(AccessGatewayKind.signInPage);
      final dio = DioException(
        requestOptions: RequestOptions(path: '/'),
        error: answer,
      );

      expect(ClassifiedFailure.of(dio).gateway, same(answer));
      expect(accessGatewayOf(ClassifiedFailure.of(dio)), same(answer));
    });

    test('prints neither header nor host', () {
      final printed = gateway(
        AccessGatewayKind.cloudflareAccess,
        sent: true,
      ).toString();

      expect(printed, isNot(contains('example.com')));
      expect(printed, isNot(contains('cloudflareaccess.com')));
    });
  });
}
