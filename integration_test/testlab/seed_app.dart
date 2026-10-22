@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_service.dart';

/// The app's configuration for a profile, saved with the app's own code.
///
/// The lab writes the configuration of a profile into its state directory,
/// in the app's own storage: the addresses, the names and the roster in
/// `SharedPreferences`, the keys, the passwords, the tokens and the sessions
/// in the secure storage, with the keys `SettingsService` derives from the id
/// of every connection. This entry point hands that file to the app's own
/// stores, so the app on the device or in the simulator reads the lab's real
/// connections, and reads them back to prove it.
///
/// Nothing secret is compiled in: the configuration is read at run time, from
/// the file the lab wrote or, for a sandboxed app that cannot reach the
/// lab's state directory, from the lab's control API with its token.
///
/// Run it with the lab's profile:
///
/// ```bash
/// CUPOLA_TESTLAB_APP_CONFIG=.ai/scratch/zz_testlab/state/app/P1.json \
///   flutter test integration_test/testlab/seed_app.dart -d <device>
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the configuration of a profile reaches the app', (tester) async {
    final document = await _configuration();
    final prefs = await SharedPreferences.getInstance();
    final secure = createSecureSettingsStore();

    for (final entry in (document['prefs'] as Map).entries) {
      final key = entry.key as String;
      final value = entry.value;
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is List) {
        await prefs.setStringList(key, value.cast<String>());
      } else {
        await prefs.setString(key, value as String);
      }
    }

    for (final entry in (document['secure'] as Map).entries) {
      await secure.write(
        key: entry.key as String,
        value: entry.value as String,
      );
    }

    // What the app reads, with the app's own reader.
    final settings = await SettingsService(prefs, secure).loadSettings();
    final expected = (document['connections'] as List).cast<Map>();
    expect(
      settings.instances.map((instance) => instance.id),
      expected.map((row) => row['id']),
      reason: 'the app reads the connections the lab wrote',
    );
    for (final instance in settings.instances) {
      final row = expected.firstWhere((row) => row['id'] == instance.id);
      expect(instance.url, row['url'], reason: '${instance.id} at its address');
      expect(
        instance.away?.url ?? '',
        row['away'],
        reason: '${instance.id} at its address away from home',
      );
      expect(
        instance.isConfigured,
        isTrue,
        reason: '${instance.id} is set up: the lab gave it its key',
      );
    }

    // The names, never the secrets.
    debugPrint(
      '[testlab] the app reads ${settings.instances.length} connections: '
      '${settings.instances.map((instance) => instance.id).join(', ')}',
    );
    expect(settings.instances, isNotEmpty);
  });
}

/// The configuration of the profile, as the lab wrote it.
Future<Map<String, dynamic>> _configuration() async {
  final path = Platform.environment['CUPOLA_TESTLAB_APP_CONFIG'];
  if (path != null && path.isNotEmpty) {
    final file = File(path);
    try {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } on FileSystemException {
      // A sandboxed app cannot reach the lab's state directory: the control
      // API serves the same file, with the lab's token.
    }
  }
  return await _fromControlApi();
}

/// The configuration of the profile, from the lab's control API.
Future<Map<String, dynamic>> _fromControlApi() async {
  final base = Platform.environment['CUPOLA_TESTLAB_CONTROL_URL'];
  final token = Platform.environment['CUPOLA_TESTLAB_CONTROL_TOKEN'];
  final profile = Platform.environment['CUPOLA_TESTLAB_PROFILE'] ?? 'P1';
  if (base == null || base.isEmpty || token == null || token.isEmpty) {
    fail(
      'The configuration is not reachable: point '
      'CUPOLA_TESTLAB_APP_CONFIG at the file the lab wrote, or pass '
      'CUPOLA_TESTLAB_CONTROL_URL and CUPOLA_TESTLAB_CONTROL_TOKEN.',
    );
  }
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('$base/app-config?profile=$profile'),
    );
    request.headers.set('Authorization', 'Bearer $token');
    final response = await request.close();
    final text = await response
        .transform(const SystemEncoding().decoder)
        .join();
    if (response.statusCode != 200) {
      fail('The lab refused the configuration: ${response.statusCode} $text');
    }
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}
