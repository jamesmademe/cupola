@Tags(['e2e'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/connection_failure.dart';

/// A gateway in front of a service, read by the app's own code.
///
/// The lab's gateway plays every part a gateway can take: Cloudflare Access
/// with its login redirect and its refusal of a request without the service
/// token, a proxy's own password, required custom headers, a sign-in page
/// Cupola cannot complete, and another application answering in the service's
/// place. This suite checks that the app recognises each of them, and walks
/// the six outcomes of "connect a service": answered, refused key, no answer,
/// a certificate it does not trust, plain http where https belongs, and a
/// gateway that refuses the token that was sent.
void main() {
  const gateway = 'http://127.0.0.1:8466';

  Future<Object?> probe(
    String base,
    String path, {
    Map<String, String> headers = const {},
    String apiKey = 'test-key',
  }) async {
    final client = ApiClient(
      baseUrl: base,
      apiKey: apiKey,
      accessHeaders: headers,
    );
    try {
      await client.get(path);
      return null;
    } catch (error) {
      return error;
    } finally {
      client.close();
    }
  }

  test(
    'Cloudflare Access shows its login, and the token opens the way',
    () async {
      final refused = await probe(gateway, '/cf');
      expect(refused, isNotNull);
      final answer = accessGatewayOf(refused);
      expect(answer, isNotNull, reason: 'the login redirect is not recognised');
      expect(answer!.kind, AccessGatewayKind.cloudflareAccess);
      expect(answer.credentialsSent, isFalse);
      expect(answer.gatewayHost, contains('cloudflareaccess.com'));

      final allowed = await probe(
        gateway,
        '/cf',
        headers: {
          'CF-Access-Client-Id': 'cupola-testlab-client-id',
          'CF-Access-Client-Secret': 'cupola-testlab-client-secret',
        },
      );
      expect(allowed, isNull, reason: 'the token did not open the way');
    },
  );

  test('a gateway that refuses the token that was sent says so', () async {
    final error = await probe(
      gateway,
      '/cf-refused',
      headers: {'CF-Access-Client-Id': 'cupola-testlab-client-id'},
    );
    expect(error, isNotNull);
    final answer = accessGatewayOf(error);
    expect(answer, isNotNull, reason: 'the refusal is not recognised');
    expect(answer!.kind, AccessGatewayKind.cloudflareAccess);
    expect(
      answer.credentialsSent,
      isTrue,
      reason: 'the token was sent, and the gateway refused it',
    );
  });

  test(
    'a proxy password is a password prompt, not the service refusing',
    () async {
      final error = await probe(gateway, '/basic');
      expect(error, isNotNull);
      final answer = accessGatewayOf(error);
      expect(
        answer,
        isNotNull,
        reason: 'the password prompt is not recognised',
      );
      expect(answer!.kind, AccessGatewayKind.passwordPrompt);

      final allowed = await probe(
        gateway,
        '/basic',
        headers: {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('cupola:cupola-gateway-pass'))}',
        },
      );
      expect(allowed, isNull, reason: 'the password did not open the way');
    },
  );

  test('a sign-in page Cupola cannot complete is a sign-in page', () async {
    final error = await probe(gateway, '/signin');
    expect(error, isNotNull);
    final answer = accessGatewayOf(error);
    expect(answer, isNotNull, reason: 'the sign-in page is not recognised');
    expect(answer!.kind, AccessGatewayKind.signInPage);
  });

  test('another application in the service\'s place is a web page', () async {
    final error = await probe(gateway, '/other');
    expect(error, isNotNull);
    expect(
      webPageAnswerOf(error),
      isNotNull,
      reason: 'a page where the API should be is not recognised',
    );
  });

  test('the six outcomes of connecting a service', () async {
    // Answered.
    expect(await probe(gateway, '/service'), isNull);

    // No answer: a port where nothing listens.
    final silent = await probe('http://127.0.0.1:9', '/service');
    expect(silent, isNotNull);
    expect(
      classifyConnectionFailure(silent),
      ServiceFailureReason.unreachable,
      reason: 'a closed port is not a mystery',
    );

    // Refused key: the real service, the wrong key.
    final refused = await probe(
      'http://127.0.0.1:7878',
      '/api/v3/movie',
      apiKey: 'wrong-key',
    );
    expect(refused, isNotNull);
    expect(
      classifyConnectionFailure(refused),
      ServiceFailureReason.unauthorized,
    );

    // A certificate the app does not trust: the TrueNAS fixture's own TLS.
    final certificate = await probe('https://127.0.0.1:8460', '/api/v1/ping');
    expect(certificate, isNotNull);
    expect(classifyConnectionFailure(certificate), ServiceFailureReason.tls);

    // Plain http where https belongs.
    final plain = await probe('https://127.0.0.1:8466', '/service');
    expect(plain, isNotNull);
    expect(classifyConnectionFailure(plain), ServiceFailureReason.plainHttp);

    // The gateway refused the token that was sent: above, in its own test.
    expect(
      accessGatewayOf(
        await probe(
          gateway,
          '/cf-refused',
          headers: {'CF-Access-Client-Id': 'cupola-testlab-client-id'},
        ),
      ),
      isNotNull,
    );
  });
}
