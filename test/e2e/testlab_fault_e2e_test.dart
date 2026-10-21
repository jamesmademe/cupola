@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';

/// The fault layer, read through the app's own client and words.
///
/// Radarr is reached at its Toxiproxy port, the same one the journeys use. The
/// test turns the proxy off, proves the app classifies the failure as a host
/// that did not answer (never as a refused key or a certificate), clears the
/// fault, and reads the library again. The control token comes from the
/// chmod-600 credentials file and is never printed.
void main() {
  final credentials = _credentials();
  final controlUrl =
      credentials['CUPOLA_TESTLAB_CONTROL_URL'] ?? 'http://127.0.0.1:8799';
  final token = credentials['CUPOLA_TESTLAB_CONTROL_TOKEN'];
  final proxyPort = credentials['CUPOLA_TESTLAB_RADARR_PROXY_PORT'] ?? '27878';
  Process? server;

  setUpAll(() async {
    if (await _healthy(controlUrl)) return;
    server = await Process.start('python3', [
      'test/e2e/testlab/testlab.py',
      'serve',
    ], workingDirectory: Directory.current.path);
    server!.stdout.drain<void>();
    server!.stderr.drain<void>();
    for (var attempt = 0; attempt < 40; attempt++) {
      if (await _healthy(controlUrl)) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    fail('the control API did not start at $controlUrl');
  });

  tearDownAll(() {
    server?.kill();
  });

  Future<void> command(String name, List<String> arguments) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$controlUrl/command'));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final payload = utf8.encode(
        jsonEncode({'command': name, 'arguments': arguments}),
      );
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      expect(
        response.statusCode,
        200,
        reason: 'control API $name $arguments answered $body',
      );
    } finally {
      client.close(force: true);
    }
  }

  test('a fault makes Radarr read as a host that did not answer, and clear '
      'brings it back', () async {
    expect(token, isNotNull, reason: 'the control token is missing');
    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:$proxyPort',
      apiKey: 'test-key',
    );
    addTearDown(client.close);
    final service = RadarrService(client);

    await command('fault', ['radarr', 'down']);
    addTearDown(() => command('fault', ['radarr', 'clear']));

    Object? failure;
    try {
      await service.getMoviesOrThrow();
    } catch (error) {
      failure = error;
    }
    expect(failure, isNotNull, reason: 'Radarr answered with the proxy down');
    final reason = classifyConnectionFailure(failure);
    expect(reason, ServiceFailureReason.unreachable);
    expect(failureHeadline(reason, subject: 'Radarr'), 'Radarr did not answer');

    await command('fault', ['radarr', 'clear']);
    expect(await service.getMoviesOrThrow(), isA<List>());
  });
}

Future<bool> _healthy(String controlUrl) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
  try {
    final request = await client.getUrl(Uri.parse('$controlUrl/health'));
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode == 200;
  } on SocketException {
    return false;
  } finally {
    client.close(force: true);
  }
}

Map<String, String> _credentials() {
  final path =
      Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE'] ??
      '${Directory.current.path}/.ai/scratch/zz_testlab/state/credentials.env';
  final file = File(path);
  if (!file.existsSync()) {
    fail('CUPOLA_TESTLAB_CREDENTIALS_FILE is not set and $path is missing');
  }
  final values = <String, String>{};
  for (final line in File(path).readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#') || !line.contains('=')) {
      continue;
    }
    final separator = line.indexOf('=');
    values[line.substring(0, separator)] = line.substring(separator + 1);
  }
  return values;
}
