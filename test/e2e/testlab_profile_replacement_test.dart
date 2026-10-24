import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_service.dart';

import '../../integration_test/testlab/seed_writer.dart';
import '../test_helpers/fake_secure_settings_store.dart';

/// A profile is a replacement, not a merge.
///
/// P1 is a household with two connections, an address away, a gateway's access,
/// a pin and a persisted route. P2 is one Seerr connection signing in with a
/// household account. Applying P2 over P1 must leave no key, secret, certificate
/// or route of P1 behind; applying P1 again must restore exactly P1.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bundle = 'com.matthwlabs.cupola.testlab';

  test('P1 to P2 to P1 leaves only the profile that was applied', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final secure = FakeSecureSettingsStore();

    await _apply(_p1(bundle), prefs, secure);

    // P1 read back.
    expect(prefs.getString('radarr_url'), 'http://127.0.0.1:27878');
    expect(prefs.getString('radarr_away_url'), 'http://127.0.0.1:27879');
    expect(prefs.getString('radarr_access'), isNotNull);
    expect(prefs.getString('connection_routes'), jsonEncode(['radarr']));
    expect(secure.entries, contains('secure_radarr_api_key'));
    expect(secure.entries, contains('secure_radarr_access_secret'));
    expect(secure.entries, contains('secure_trusted_certificates'));

    await _apply(_p2(bundle), prefs, secure);

    // P2 read back: the account, and nothing of P1.
    final p2 = await SettingsService(prefs, secure).loadSettings();
    expect(p2.instances.map((instance) => instance.id), ['seerr']);
    final seerr = p2.instances.single;
    expect(seerr.account?.kind.name, 'local');
    expect(seerr.account?.login, 'requester@example.com');
    expect(seerr.account?.session, 'session-p2');
    expect(seerr.credential, isEmpty);
    expect(seerr.away, isNull);
    expect(seerr.access.kind.name, 'none');
    expect(p2.trustedCertificates, isEmpty);
    expect(prefs.getString('radarr_url'), isNull);
    expect(prefs.getString('radarr_away_url'), isNull);
    expect(prefs.getString('radarr_access'), isNull);
    expect(prefs.getString('connection_routes'), isNull);
    expect(secure.entries.keys, ['secure_seerr_session']);

    await _apply(_p1(bundle), prefs, secure);

    // P1 again, whole: the operator key, the address away, the access, the pin.
    final back = await SettingsService(prefs, secure).loadSettings();
    expect(back.instances.map((instance) => instance.id), ['seerr', 'radarr']);
    final radarr = back.instances.firstWhere(
      (instance) => instance.id == 'radarr',
    );
    expect(radarr.url, 'http://127.0.0.1:27878');
    expect(radarr.away?.url, 'http://127.0.0.1:27879');
    expect(radarr.access.kind.name, 'cloudflare');
    expect(radarr.credential, 'radarr-key');
    expect(
      back.instances
          .firstWhere((instance) => instance.id == 'seerr')
          .credential,
      'seerr-key',
    );
    expect(
      back.trustedCertificates['https://127.0.0.1:8444'],
      'fingerprint-p1',
    );
    expect(prefs.getString('connection_routes'), jsonEncode(['radarr']));
    expect(secure.entries.keys.toSet(), {
      'secure_seerr_api_key',
      'secure_radarr_api_key',
      'secure_radarr_access_secret',
      'secure_trusted_certificates',
    });
  });
}

Future<void> _apply(
  Map<String, dynamic> document,
  SharedPreferences prefs,
  SecureSettingsStore secure,
) {
  return replaceAppConfiguration(
    document: document,
    prefs: prefs,
    secure: secure,
    expectedProfile: document['profile'] as String,
    expectedBundleId: document['bundleId'] as String,
  );
}

Map<String, dynamic> _p1(String bundle) => {
  'profile': 'P1',
  'bundleId': bundle,
  'prefs': <String, Object>{
    'onboarding_complete': true,
    'region': 'IT',
    'theme_mode': 'dark',
    'service_instances': jsonEncode([
      {'id': 'seerr', 'service': 'seerr', 'label': ''},
      {'id': 'radarr', 'service': 'radarr', 'label': ''},
    ]),
    'connection_routes': jsonEncode(['radarr']),
    'seerr_url': 'http://127.0.0.1:25055',
    'radarr_url': 'http://127.0.0.1:27878',
    'radarr_away_url': 'http://127.0.0.1:27879',
    'radarr_access': jsonEncode({
      'kind': 'cloudflare',
      'clientId': 'client-id',
    }),
  },
  'secure': <String, Object>{
    'secure_seerr_api_key': 'seerr-key',
    'secure_radarr_api_key': 'radarr-key',
    'secure_radarr_access_secret': 'client-secret',
    'secure_trusted_certificates': jsonEncode({
      'https://127.0.0.1:8444': 'fingerprint-p1',
    }),
  },
  'connections': [
    {
      'id': 'seerr',
      'service': 'seerr',
      'label': '',
      'url': 'http://127.0.0.1:25055',
      'away': '',
      'access': 'none',
      'credential': 'yes',
    },
    {
      'id': 'radarr',
      'service': 'radarr',
      'label': '',
      'url': 'http://127.0.0.1:27878',
      'away': 'http://127.0.0.1:27879',
      'access': 'cloudflare',
      'credential': 'yes',
    },
  ],
};

Map<String, dynamic> _p2(String bundle) => {
  'profile': 'P2',
  'bundleId': bundle,
  'prefs': <String, Object>{
    'onboarding_complete': true,
    'region': 'IT',
    'theme_mode': 'dark',
    'service_instances': jsonEncode([
      {'id': 'seerr', 'service': 'seerr', 'label': ''},
    ]),
    'seerr_url': 'http://127.0.0.1:25055',
    'seerr_account': jsonEncode({
      'kind': 'local',
      'login': 'requester@example.com',
      'userId': 2,
      'displayName': 'requester',
      'permissions': 32,
      'checkedAt': '2026-10-22T15:12:37.846930+00:00',
    }),
  },
  'secure': <String, Object>{'secure_seerr_session': 'session-p2'},
  'connections': [
    {
      'id': 'seerr',
      'service': 'seerr',
      'label': '',
      'url': 'http://127.0.0.1:25055',
      'away': '',
      'access': 'none',
      'credential': 'account',
    },
  ],
};
