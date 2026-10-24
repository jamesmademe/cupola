import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// The testlab build's marker, compiled in by the lab's `--dart-define`.
const _testlabMarker = String.fromEnvironment('CUPOLA_TESTLAB');

/// The only bundle the seed writes into. A literal, not a `--dart-define`: a
/// define naming the house's bundle would otherwise turn every check below
/// into a check that the app Matt uses is the app Matt uses.
const testlabBundleId = 'com.matthwlabs.cupola.testlab';

/// The configuration of [profile], from the lab's control API.
Future<Map<String, dynamic>> fetchProfile({
  required String controlUrl,
  required String controlToken,
  required String profile,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('$controlUrl/app-config?profile=$profile'),
    );
    request.headers.set('Authorization', 'Bearer $controlToken');
    final response = await request.close();
    final text = await response
        .transform(const SystemEncoding().decoder)
        .join();
    if (response.statusCode != 200) {
      throw StateError(
        'The lab refused the configuration: ${response.statusCode} $text',
      );
    }
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

/// Replaces the whole app configuration with [document], using the app's own
/// stores and cleanup, then reads it back and proves every part of it.
///
/// [clearAll] is the app's own "wipe everything" procedure. Calling it first is
/// what makes a profile application a replacement rather than a merge: a
/// connection, an access secret, a Seerr account, a pin or a persisted choice
/// the previous profile had cannot survive into the next one.
Future<SettingsModel> replaceAppConfiguration({
  required Map<String, dynamic> document,
  required SharedPreferences prefs,
  required SecureSettingsStore secure,
  required String expectedProfile,
  required String expectedBundleId,
}) async {
  final profile = document['profile'];
  if (profile != expectedProfile) {
    throw StateError(
      'The lab wrote profile $profile, but the app was told $expectedProfile.',
    );
  }
  final bundleId = document['bundleId'];
  if (bundleId != expectedBundleId) {
    throw StateError(
      'The lab wrote the configuration for $bundleId, but this build is '
      '$expectedBundleId.',
    );
  }

  final service = SettingsService(prefs, secure);
  await service.clearAll();

  final expectedPrefs = (document['prefs'] as Map).cast<String, dynamic>();

  // `clearAll` knows the app's settings, not every key a screen may have
  // written (hint flags, journey counters). A profile is the whole store, so
  // anything the document does not name goes too; the Plex client id is the
  // one install-scoped value that must survive.
  const installKeys = {'plex_client_id'};
  for (final key in prefs.getKeys().toList()) {
    if (!expectedPrefs.containsKey(key) && !installKeys.contains(key)) {
      await prefs.remove(key);
    }
  }

  for (final entry in expectedPrefs.entries) {
    final value = entry.value;
    if (value is bool) {
      await prefs.setBool(entry.key, value);
    } else if (value is List) {
      await prefs.setStringList(entry.key, value.cast<String>());
    } else {
      await prefs.setString(entry.key, value as String);
    }
  }

  final expectedSecure = (document['secure'] as Map).cast<String, dynamic>();
  for (final entry in expectedSecure.entries) {
    await secure.write(key: entry.key, value: entry.value as String);
  }

  // The readback starts from a new reader, so nothing is proved from the
  // objects that just wrote.
  final read = await SettingsService(prefs, secure).loadSettings();
  _verify(
    read,
    document: document,
    prefs: prefs,
    expectedPrefs: expectedPrefs,
    expectedSecure: expectedSecure,
    profile: expectedProfile,
  );
  return read;
}

/// Refuses to touch a store unless this is the testlab build, running in the
/// testlab bundle's own container and using the testlab keychain and App Group.
///
/// The identity comes from the running process (`cupola/testlab`), not from an
/// inherited environment: iOS reports an empty `HOME` to Dart, and a path
/// copied from a shell proves nothing about the app the seed is writing into.
/// Called before [replaceAppConfiguration], before the first write.
Future<void> requireTestlabIdentity({
  required String bundleId,
  required String keychainService,
  required String appGroup,
}) async {
  if (bundleId != testlabBundleId) {
    throw StateError(
      'Refusing to write: the seed only writes into $testlabBundleId, not '
      '$bundleId.',
    );
  }
  if (_testlabMarker != '1') {
    throw StateError(
      'Refusing to write: this app was not compiled as the testlab build. '
      'The lab passes CUPOLA_TESTLAB=1 together with the testlab identity.',
    );
  }
  if (keychainService.isEmpty || keychainService != bundleId) {
    throw StateError(
      'Refusing to write: the testlab keychain service is '
      '${keychainService.isEmpty ? 'empty' : keychainService}, not $bundleId. '
      'The seed would write into the wrong keychain.',
    );
  }

  final channel = MethodChannel('cupola/testlab');
  final identity = await channel.invokeMapMethod<String, dynamic>('identity');
  if (identity == null) {
    throw StateError(
      'Refusing to write: the app did not report its native identity.',
    );
  }

  final actualBundle = identity['bundle'] as String? ?? '';
  if (actualBundle != bundleId) {
    throw StateError(
      'Refusing to write: this process is running as '
      '${actualBundle.isEmpty ? 'an unknown bundle' : actualBundle}, not '
      '$bundleId. The seed never touches the app Matt uses.',
    );
  }

  final home = identity['home'] as String? ?? '';
  if (home.isEmpty || !Directory(home).existsSync()) {
    throw StateError(
      'Refusing to write: the app reported no container ($home).',
    );
  }

  final preferences = identity['preferences'] as String? ?? '';
  if (!preferences.endsWith('/$bundleId.plist')) {
    throw StateError(
      'Refusing to write: the app reports its preferences at $preferences, '
      'not under $bundleId.',
    );
  }

  if (Platform.isMacOS) {
    // The testlab Mac build cannot be sandboxed (no provisioning profile for
    // a new bundle id), so its destination is the preferences file named by
    // its own bundle id, never the app Matt uses.
    return;
  }

  // On iOS the data container is a UUID; its metadata is what names the app
  // that owns it. This is the destination SharedPreferences and the Keychain
  // will use, checked before the first write.
  final metadata = File(
    '$home/.com.apple.mobile_container_manager.metadata.plist',
  );
  if (!metadata.existsSync()) {
    throw StateError(
      'Refusing to write: $home has no container metadata naming its app.',
    );
  }
  final text = latin1.decode(metadata.readAsBytesSync(), allowInvalid: true);
  if (!text.contains(bundleId)) {
    throw StateError(
      'Refusing to write: the container at $home does not belong to '
      '$bundleId.',
    );
  }

  final actualGroup = identity['group'] as String? ?? '';
  final groupFolder = identity['groupFolder'] as String? ?? '';
  if (appGroup.isEmpty || actualGroup != appGroup) {
    throw StateError(
      'Refusing to write: the running app uses the App Group '
      '${actualGroup.isEmpty ? '(none)' : actualGroup}, not $appGroup.',
    );
  }
  if (groupFolder.isEmpty || !Directory(groupFolder).existsSync()) {
    throw StateError(
      'Refusing to write: the testlab App Group has no container '
      '($groupFolder).',
    );
  }
}

void _verify(
  SettingsModel read, {
  required Map<String, dynamic> document,
  required SharedPreferences prefs,
  required Map<String, dynamic> expectedPrefs,
  required Map<String, dynamic> expectedSecure,
  required String profile,
}) {
  final connections = (document['connections'] as List).cast<Map>();
  final wanted = connections.map((row) => row['id'] as String).toList();
  final found = read.instances.map((instance) => instance.id).toList();
  _same(found, wanted, '$profile connections');

  // The roster and every persisted choice the profile names are exactly the
  // document's, not a merge with what was there before.
  //
  // `plex_client_id` is not profile state: it names this installation to
  // Plex and is minted once, deliberately surviving every settings save and
  // every clear (SettingsModel.clear keeps it for the same reason). Treating
  // it as stale would make a correct replacement look like a merge, and
  // clearing it would register a new device row on the user's Plex server.
  const installKeys = {'plex_client_id'};
  final stale = prefs.getKeys().difference({
    ...expectedPrefs.keys,
    ...installKeys,
  });
  if (stale.isNotEmpty) {
    throw StateError(
      '$profile left ${stale.join(', ')} from the previous profile in '
      'SharedPreferences.',
    );
  }
  for (final entry in expectedPrefs.entries) {
    final value = entry.value;
    final actual = value is bool
        ? prefs.getBool(entry.key)
        : value is List
        ? prefs.getStringList(entry.key)
        : prefs.getString(entry.key);
    _same(actual, value, '$profile preference ${entry.key}');
  }

  for (final row in connections) {
    final id = row['id'] as String;
    final instance = read.instances.firstWhere((instance) => instance.id == id);
    _same(instance.url, row['url'], '$profile $id address');
    _same(instance.label, row['label'] ?? '', '$profile $id label');
    _same(instance.away?.url ?? '', row['away'] ?? '', '$profile $id away');
    final access = row['access'] as String? ?? 'none';
    _same(instance.access.kind.name, access, '$profile $id access');
    if (access != 'none' && instance.access.headers().isEmpty) {
      throw StateError('$profile $id has an access with nothing to send.');
    }

    if (row['credential'] == 'account') {
      final account = instance.account;
      if (account == null) {
        throw StateError(
          '$profile $id was written as an account, but read '
          'without one.',
        );
      }
      final stored =
          jsonDecode(expectedPrefs[instance.accountStorageKey]!)
              as Map<String, dynamic>;
      _same(account.kind.name, stored['kind'], '$profile $id account kind');
      _same(account.login, stored['login'], '$profile $id account login');
      _same(account.userId, stored['userId'], '$profile $id account user');
      _same(
        account.session,
        expectedSecure[instance.sessionStorageKey],
        '$profile $id session',
      );
    } else {
      if (instance.account != null) {
        throw StateError('$profile $id read with an account it was not given.');
      }
      _same(
        instance.credential,
        expectedSecure[instance.credentialStorageKey],
        '$profile $id credential',
      );
    }
    if (expectedPrefs.containsKey(instance.usernameStorageKey)) {
      _same(
        instance.username,
        expectedPrefs[instance.usernameStorageKey],
        '$profile $id username',
      );
    }
    if (expectedPrefs.containsKey(instance.viewerIdStorageKey)) {
      _same(
        instance.viewerId,
        expectedPrefs[instance.viewerIdStorageKey],
        '$profile $id viewer',
      );
    }
  }

  final pins = expectedSecure['secure_trusted_certificates'];
  final wantedPins = pins == null
      ? const <String, dynamic>{}
      : jsonDecode(pins as String) as Map<String, dynamic>;
  _same(read.trustedCertificates, wantedPins, '$profile pins');

  // Nothing outside the profile's own secure keys is readable through the
  // names the previous profile could have used: a replacement must not leave
  // a service's secret behind for the app to read on the next launch.
  for (final key in expectedSecure.keys) {
    if (!key.startsWith('secure_')) {
      throw StateError('$profile wrote a non-secure key $key to the keychain.');
    }
  }
  if (expectedSecure.isEmpty && pins != null) {
    throw StateError('$profile pins were not written to secure storage.');
  }
}

void _same(Object? actual, Object? wanted, String what) {
  if (wanted is Map && actual is Map) {
    final a = actual.map((key, value) => MapEntry('$key', '$value'));
    final b = wanted.map((key, value) => MapEntry('$key', '$value'));
    if (a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && b[key] == a[key])) {
      return;
    }
    throw StateError('$what: wrote "$b", read "$a".');
  }
  final a = actual is List ? actual.join('\u0000') : '$actual';
  final b = wanted is List ? wanted.join('\u0000') : '$wanted';
  if (a != b) {
    throw StateError('$what: wrote "$b", read "$a".');
  }
}
