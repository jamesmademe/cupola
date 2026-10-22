@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_access_rules.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The six outcomes of "connect a service", read through the app's first run.
///
/// The catalogue's row G-02 wants the six outcomes of the walk's `Test
/// connection`, and wants them in the app's own words. This suite asks the app
/// the way the first run asks it: the connection probe of
/// [diagnoseCredentials], the gate the OS puts in front of a local network,
/// the certificate probe of [probeUntrustedCertificate] when a failure could
/// be a certificate's fault, and the gateway's own classification for the
/// answers that came from in front of the service. There is no client of its
/// own here: every verdict below is the app's.
///
/// The lab has the pieces: the Seerr that answers, the gateway that plays
/// Cloudflare Access and refuses the token that was sent, the fixture with a
/// certificate of its own, and a closed port for the silence.
///
/// The six cases: the service answered; it answered and refused the key;
/// nothing answered; the certificate is one Cupola does not trust; the port
/// serves plain http where https belongs; the gateway in front refused the
/// service token.
void main() {
  const service = ServiceKey.seerr;
  // The gateway: a process of the host, and the only role that answers 403
  // with the challenge that names the Access team.
  const gateway = 'http://127.0.0.1:8466';
  // The same gateway over https: the port speaks plain http.
  const gatewayOverHttps = 'https://127.0.0.1:8466';
  // The TrueNAS fixture's own TLS: an origin with a certificate of its own,
  // which the lab never rotates.
  const selfSigned = 'https://127.0.0.1:8460';
  // A port where nothing listens.
  const silent = 'http://127.0.0.1:9';

  test('the service answered', () async {
    final diagnosis = await firstRunStep(
      service,
      url: _seerrUrl(),
      apiKey: _operatorKey(),
    );

    expect(diagnosis.status, ServiceConnectionStatus.connected);
    expect(diagnosis.reason, isNull);
    expect(_walkSentence(diagnosis), 'Seerr answered.');
    // The server's own side of the same fact: the status route answers.
    expect(
      await _statusOf(_seerrUrl(), _operatorKey()),
      200,
      reason: 'the service did not answer its status route',
    );
  });

  test('the service answered but refused the key', () async {
    const wrongKey = 'a-key-the-server-does-not-know';
    final diagnosis = await firstRunStep(
      service,
      url: _seerrUrl(),
      apiKey: wrongKey,
    );

    expect(diagnosis.status, ServiceConnectionStatus.disconnected);
    expect(diagnosis.reason, ServiceFailureReason.unauthorized);
    expect(
      describeFailure(service, diagnosis.reason!).headline,
      'Seerr answered but refused the key',
    );
    expect(_walkSentence(diagnosis), contains('does not accept this API key'));
    // The server's own side: the request the app made, with the same key, is
    // refused the same way.
    expect(
      await _statusOf(
        _seerrUrl(),
        wrongKey,
        path: '/api/v1/request?take=1&skip=0&sort=added&filter=all',
      ),
      403,
      reason: 'the service did not refuse the key',
    );
  });

  test('the service did not answer', () async {
    final diagnosis = await firstRunStep(
      service,
      url: silent,
      apiKey: 'test-key',
    );

    expect(diagnosis.status, ServiceConnectionStatus.disconnected);
    expect(diagnosis.reason, ServiceFailureReason.unreachable);
    expect(
      describeFailure(service, diagnosis.reason!).headline,
      'Seerr did not answer',
    );
    expect(
      _walkSentence(diagnosis),
      contains('Nothing answered at this address'),
    );
  });

  test('the service has a certificate Cupola does not trust', () async {
    final diagnosis = await firstRunStep(
      service,
      url: selfSigned,
      apiKey: 'test-key',
    );

    expect(diagnosis.status, ServiceConnectionStatus.disconnected);
    expect(diagnosis.reason, ServiceFailureReason.tls);
    expect(
      describeFailure(service, diagnosis.reason!).headline,
      'Seerr has a certificate Cupola does not trust',
    );
    expect(
      _walkSentence(diagnosis),
      contains('The HTTPS certificate could not be verified'),
    );

    // The certificate the app found, and the one the lab serves: the same
    // SHA-256 of the same DER, read from both sides.
    final probe = diagnosis.certificateProbe;
    expect(probe, isNotNull, reason: 'the app found no certificate to offer');
    expect(probe!.rotated, isFalse, reason: 'the lab serves one certificate');
    expect(probe.certificate.fingerprint, await _selfSignedFingerprint());
  });

  test('the service answered in plain http', () async {
    await _requireGateway();
    // The gateway speaks plain http, and the address says https.
    final diagnosis = await firstRunStep(
      service,
      url: gatewayOverHttps,
      apiKey: 'test-key',
    );

    expect(diagnosis.status, ServiceConnectionStatus.disconnected);
    expect(diagnosis.reason, ServiceFailureReason.plainHttp);
    expect(
      describeFailure(service, diagnosis.reason!).headline,
      'Seerr answered in plain http',
    );
    expect(
      _walkSentence(diagnosis),
      contains('This port serves plain http, not https'),
    );
  });

  test('the gateway did not accept the service token that was sent', () async {
    await _requireGateway();
    // The lab's token, the one the gateway answers with its refusal.
    const access = CloudflareServiceToken(
      clientId: 'cupola-testlab-client-id',
      clientSecret: 'cupola-testlab-client-secret',
    );
    final diagnosis = await firstRunStep(
      service,
      url: '$gateway/cf-refused',
      apiKey: 'test-key',
      access: access,
    );

    expect(diagnosis.status, ServiceConnectionStatus.disconnected);
    expect(diagnosis.reason, ServiceFailureReason.accessGateway);

    // The gateway, as the app classified it: Access, and it refused what was
    // sent, which is what tells this refusal from the service's own.
    final answer = diagnosis.gateway;
    expect(answer, isNotNull, reason: 'the gateway was not recognised');
    expect(answer!.kind, AccessGatewayKind.cloudflareAccess);
    expect(
      answer.credentialsSent,
      isTrue,
      reason: 'the token was sent, and the gateway refused it',
    );
    expect(
      describeFailure(service, diagnosis.reason!, gateway: answer).headline,
      'Cloudflare Access did not accept the service token',
    );
    expect(
      _walkSentence(diagnosis, access: access),
      'Access did not accept the token: add a Service Auth policy for it on '
      '127.0.0.1:8466.',
    );
  });
}

/// The step of the first run, as the app runs it.
///
/// `OnboardingScreen._runTest` asks the service through
/// [diagnoseCredentials], through the gate the OS puts in front of a local
/// network, and then, when the failure could be a certificate's fault, probes
/// the origin with [probeUntrustedCertificate] and lets what it found become
/// the reason. The same three steps, in the same order.
Future<ServiceDiagnosis> firstRunStep(
  ServiceKey service, {
  required String url,
  String apiKey = '',
  ConnectionAccess access = const NoAccess(),
}) async {
  var diagnosis = await diagnoseThroughLocalNetworkGate(
    () =>
        diagnoseCredentials(service, url: url, apiKey: apiKey, access: access),
    url: url,
  );
  if (diagnosis.status == ServiceConnectionStatus.disconnected &&
      certProbeWorthwhile(diagnosis.reason)) {
    diagnosis = diagnosis.withFinding(await probeUntrustedCertificate(url));
  }
  return diagnosis;
}

/// The sentence the walk's outcome card prints under the form.
///
/// Mirrors `onboarding_walk.dart`'s `_Outcome`: the token's own outcome when
/// the connection presents one, the service's title when it answered, and the
/// failure's own sentence otherwise.
String _walkSentence(
  ServiceDiagnosis diagnosis, {
  ConnectionAccess access = const NoAccess(),
}) {
  final tokenOutcome = access is CloudflareServiceToken
      ? cloudflareTokenTestOutcome(
          ServiceKey.seerr,
          answered: diagnosis.status == ServiceConnectionStatus.connected,
          reason: diagnosis.reason,
          gateway: diagnosis.gateway,
        )
      : null;
  if (tokenOutcome != null) return tokenOutcome;
  return switch (diagnosis.status) {
    ServiceConnectionStatus.connected => '${ServiceKey.seerr.title} answered.',
    ServiceConnectionStatus.notConfigured => 'Nothing to send yet.',
    _ => diagnosis.messageFor(ServiceKey.seerr),
  };
}

/// The status code the server answers with, read apart from the app's client:
/// the side of the check the catalogue asks for, a `GET` on the service's
/// own status route.
Future<int> _statusOf(
  String baseUrl,
  String apiKey, {
  String path = '/api/v1/status',
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('$baseUrl$path'));
    request.headers.set('X-Api-Key', apiKey);
    request.headers.set('Accept', 'application/json');
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

/// The fingerprint of the certificate the lab's self-signed origin serves,
/// read by the lab itself: the SHA-256 of the DER, as the app compares it.
Future<String> _selfSignedFingerprint() async {
  final result = await Process.run('bash', [
    'test/e2e/testlab/truenas_cert.sh',
    '--state-dir',
    _stateDir(),
    'fingerprint',
  ], workingDirectory: Directory.current.path);
  expect(
    result.exitCode,
    0,
    reason: 'the lab could not read its certificate: ${result.stderr}',
  );
  return (result.stdout as String).trim();
}

/// The gateway has to be up: the lab's `gateway-lab` scenario starts it, and
/// the two cases that need it say so rather than reporting a silence.
Future<void> _requireGateway() async {
  try {
    final socket = await Socket.connect(
      '127.0.0.1',
      8466,
      timeout: const Duration(seconds: 2),
    );
    socket.destroy();
  } catch (_) {
    fail(
      'The lab gateway is not listening on 8466. Apply the scenario:\n'
      'python3 test/e2e/testlab/testlab.py scenario apply gateway-lab',
    );
  }
}

/// Where the lab keeps its state.
String _stateDir() =>
    Platform.environment['CUPOLA_TESTLAB_STATE_DIR'] ??
    '.ai/scratch/zz_testlab/state';

/// The lab's Seerr as the world file holds it: the address, and the
/// operator's key. Read from the state directory at run time, never from the
/// repository.
Map<String, dynamic> _seerrWorld() {
  final file = File('${_stateDir()}/seerr-world.json');
  if (!file.existsSync()) {
    fail(
      'No Seerr world at ${file.path}. The lab seeds it with:\n'
      'python3 test/e2e/testlab/seerr_world.py --state-dir ${_stateDir()}',
    );
  }
  final json = (jsonDecode(file.readAsStringSync()) as Map)
      .cast<String, dynamic>();
  return (json['seerr'] as Map).cast<String, dynamic>();
}

/// The address of the lab's Seerr.
String _seerrUrl() =>
    (_seerrWorld()['url'] as String?) ?? 'http://127.0.0.1:5055';

/// The operator's key of the lab's Seerr.
String _operatorKey() => (_seerrWorld()['apiKey'] as String?) ?? '';
