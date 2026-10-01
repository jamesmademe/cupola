import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/release_search/domain/release_search_job.dart';

DioException _refusal(
  int status, {
  Object? error,
  Map<String, List<String>> headers = const {},
}) {
  final options = RequestOptions(
    baseUrl: 'https://radarr.example.com',
    path: '/api/v3/release',
  );
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      headers: Headers.fromMap(headers),
    ),
    error: error,
  );
}

ReleaseSearchFailure _classify(DioException error) =>
    classifyReleaseSearchFailure(
      error,
      elapsed: const Duration(seconds: 2),
      configuredTimeout: const Duration(minutes: 5),
    );

void main() {
  test('Cloudflare Access refusing the search is named, never the key', () {
    final failure = _classify(
      _refusal(
        401,
        error: const AccessGatewayAnswer(
          kind: AccessGatewayKind.cloudflareAccess,
          credentialsSent: false,
          gatewayHost: 'cupola-home.cloudflareaccess.com',
          serviceHost: 'radarr.example.com',
        ),
      ),
    );

    expect(failure.kind, ReleaseSearchFailureKind.refused);
    expect(
      failure.headline,
      'Cloudflare Access answered instead of the service.',
    );
    expect(
      failure.diagnosis,
      'radarr.example.com is behind Cloudflare Access. Cupola needs a service '
      'token to reach it. Nothing was searched.',
    );
    expect(failure.headline, isNot(contains('refused the key')));
  });

  test('a token sent and refused says where its policy goes', () {
    final failure = _classify(
      _refusal(
        403,
        error: const AccessGatewayAnswer(
          kind: AccessGatewayKind.cloudflareAccess,
          credentialsSent: true,
          gatewayHost: 'cupola-home.cloudflareaccess.com',
          serviceHost: 'radarr.example.com',
        ),
      ),
    );

    expect(
      failure.headline,
      'Cloudflare Access did not accept the service token.',
    );
    expect(
      failure.diagnosis,
      'Add a Service Auth policy for it on radarr.example.com, or make a new '
      'token if it expired. Nothing was searched.',
    );
  });

  test('the background task\'s answer is read off its headers', () {
    // The native transport keeps the status and the headers, not the body,
    // and none of the in-app guard's verdict.
    final failure = _classify(
      _refusal(
        401,
        headers: {
          'www-authenticate': ['Basic realm="Restricted"'],
        },
      ),
    );

    expect(
      failure.headline,
      'A password prompt answered instead of the service.',
    );
    expect(
      failure.diagnosis,
      'Something in front of radarr.example.com asks for a username and '
      'password. Nothing was searched.',
    );
  });

  test('the search names the service a gateway answered for', () {
    final failure = classifyReleaseSearchFailure(
      _refusal(
        401,
        error: const AccessGatewayAnswer(
          kind: AccessGatewayKind.cloudflareAccess,
          credentialsSent: false,
          gatewayHost: 'cupola-home.cloudflareaccess.com',
          serviceHost: 'radarr.example.com',
        ),
      ),
      elapsed: const Duration(seconds: 2),
      configuredTimeout: const Duration(minutes: 5),
      subject: 'Radarr',
    );

    expect(failure.headline, 'Cloudflare Access answered instead of Radarr.');
    expect(
      failure.diagnosis,
      'Radarr is behind Cloudflare Access. Cupola needs a service token to '
      'reach it. Nothing was searched.',
    );
  });

  test('a 401 from the service itself is still a refused key', () {
    final failure = _classify(_refusal(401));

    expect(failure.kind, ReleaseSearchFailureKind.refused);
    expect(failure.headline, 'The service answered but refused the key.');
  });
}
