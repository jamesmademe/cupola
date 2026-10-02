import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

/// A Seerr connection signed in with an account keeps its session in secure
/// storage and the rest beside the address, never a password, and leaves
/// nothing behind when it goes.
void main() {
  late SharedPreferences prefs;
  late FakeSecureSettingsStore secureStore;
  late SettingsService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    secureStore = FakeSecureSettingsStore();
    service = SettingsService(prefs, secureStore);
  });

  const session = 's%3Asentinel-session.signature';
  final checkedAt = DateTime.utc(2026, 10, 1, 20, 41);
  final anna = SeerrAccountSignIn(
    kind: SeerrAccountKind.local,
    login: 'anna@home.arpa',
    userId: 2,
    displayName: 'Anna',
    session: session,
    permissions: 32,
    checkedAt: checkedAt,
  );
  final annasSeerr = ServiceInstance(
    id: 'seerr',
    service: ServiceKey.seerr,
    url: 'http://nas.home.arpa:5055',
    account: anna,
  );
  final friendsSeerr = ServiceInstance(
    id: 'seerr-00000a1',
    service: ServiceKey.seerr,
    label: 'Sara',
    url: 'https://seerr.example.net',
    account: anna.copyWith(userId: 4, displayName: 'Matt'),
  );

  Future<SettingsModel> saveAndReload(List<ServiceInstance> instances) async {
    await service.saveSettings(SettingsModel(instances: instances));
    return SettingsService(prefs, secureStore).loadSettings();
  }

  String everythingInPrefs() =>
      [for (final key in prefs.getKeys()) '$key=${prefs.get(key)}'].join('\n');

  test(
    'an account survives a restart, on the first Seerr and a second',
    () async {
      final settings = await saveAndReload([annasSeerr, friendsSeerr]);

      expect(settings.instanceById('seerr')?.account, anna);
      expect(
        settings.instanceById('seerr-00000a1')?.account?.displayName,
        'Matt',
      );
      expect(settings.instanceById('seerr')?.credential, isEmpty);
      expect(settings.instanceById('seerr')?.isConfigured, isTrue);
    },
  );

  test(
    'the session goes to secure storage, the rest beside the address',
    () async {
      await saveAndReload([annasSeerr]);

      expect(secureStore.entries['secure_seerr_session'], session);
      expect(secureStore.entries.containsKey('secure_seerr_api_key'), isFalse);
      final stored = jsonDecode(prefs.getString('seerr_account')!) as Map;
      expect(stored, {
        'kind': 'local',
        'login': 'anna@home.arpa',
        'userId': 2,
        'displayName': 'Anna',
        'permissions': 32,
        'checkedAt': '2026-10-01T20:41:00.000Z',
      });
      expect(everythingInPrefs(), isNot(contains('sentinel-session')));
    },
  );

  test('a connection saved before accounts reads as its key', () async {
    await prefs.setString('seerr_url', 'http://nas.home.arpa:5055');
    await secureStore.write(key: 'secure_seerr_api_key', value: 'seerr-key');

    final settings = await service.loadSettings();
    final seerr = settings.primaryOf(ServiceKey.seerr)!;

    expect(seerr.account, isNull);
    expect(seerr.seerrSignIn, const SeerrApiKeySignIn('seerr-key'));
    expect(seerr.isConfigured, isTrue);
  });

  test('signed out, the account stays and the session goes', () async {
    final settings = await saveAndReload([
      annasSeerr.copyWith(account: anna.signedOut),
    ]);
    final seerr = settings.instanceById('seerr')!;

    expect(seerr.account?.login, 'anna@home.arpa');
    expect(seerr.account?.session, isEmpty);
    expect(seerr.isSignedOut, isTrue);
    // Signed out reads as not set up until it signs in again.
    expect(seerr.isConfigured, isFalse);
    expect(settings.isServiceConfigured(ServiceKey.seerr), isFalse);
    expect(secureStore.entries.containsKey('secure_seerr_session'), isFalse);
  });

  test('a removed connection takes its account and session with it', () async {
    await saveAndReload([annasSeerr, friendsSeerr]);

    await saveAndReload([annasSeerr]);

    expect(prefs.getString('seerr-00000a1_account'), isNull);
    expect(
      secureStore.entries.containsKey('secure_seerr-00000a1_session'),
      isFalse,
    );
    expect(secureStore.entries['secure_seerr_session'], session);
  });

  test('going back to the key forgets the account', () async {
    await saveAndReload([annasSeerr]);

    final settings = await saveAndReload([
      annasSeerr.copyWith(clearAccount: true, credential: 'seerr-key'),
    ]);

    expect(settings.instanceById('seerr')?.account, isNull);
    expect(prefs.getString('seerr_account'), isNull);
    expect(secureStore.entries.containsKey('secure_seerr_session'), isFalse);
    expect(secureStore.entries['secure_seerr_api_key'], 'seerr-key');
  });

  test('clearing everything clears the account', () async {
    await saveAndReload([annasSeerr]);

    await service.clearAll();

    expect(prefs.getString('seerr_account'), isNull);
    expect(secureStore.entries, isEmpty);
  });

  test(
    'an account a later build wrote costs the account, not the address',
    () async {
      await prefs.setString('seerr_url', 'http://nas.home.arpa:5055');
      await prefs.setString('seerr_account', '{"kind":"passkey"}');

      final settings = await service.loadSettings();

      expect(
        settings.primaryOf(ServiceKey.seerr)?.url,
        'http://nas.home.arpa:5055',
      );
      expect(settings.primaryOf(ServiceKey.seerr)?.account, isNull);
    },
  );

  test('nothing secret, and no login, in what an account prints', () {
    for (final text in ['$anna', '$annasSeerr', '${annasSeerr.seerrSignIn}']) {
      expect(text, isNot(contains('sentinel-session')));
      expect(text, isNot(contains('anna@home.arpa')));
    }
    expect(
      '${const SeerrApiKeySignIn('sentinel-key')}',
      isNot(contains('sentinel')),
    );
  });

  group('after it signed in', () {
    ProviderContainer containerWith(
      SettingsModel settings, {
      List<Override> overrides = const [],
    }) {
      final container = ProviderContainer(
        overrides: [
          ...overrides,
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureSettingsStoreProvider.overrideWithValue(secureStore),
          initialSettingsProvider.overrideWithValue(settings),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('an ended session empties the saved one and keeps the rest', () async {
      final container = containerWith(SettingsModel(instances: [annasSeerr]));

      await container.read(seerrAccountsProvider).sessionEnded('seerr');

      final account = container
          .read(currentSettingsProvider)
          .instanceById('seerr')!
          .account!;
      expect(account.session, isEmpty);
      expect(account.login, 'anna@home.arpa');
      expect(account.permissions, 32);
      expect(secureStore.entries.containsKey('secure_seerr_session'), isFalse);
    });

    test(
      '/auth/me writes the permissions back, and nothing else of it',
      () async {
        final later = DateTime.utc(2026, 10, 2, 9);
        final container = containerWith(
          SettingsModel(instances: [annasSeerr]),
          overrides: [
            seerrAccountsProvider.overrideWith(
              (ref) => SeerrAccounts(ref, now: () => later),
            ),
          ],
        );

        await container.read(seerrAccountsProvider).recordWhoAmI('seerr', {
          'id': 2,
          'email': 'anna@home.arpa',
          'displayName': 'Anna',
          'permissions': 32 | 128,
        });

        final account = container
            .read(currentSettingsProvider)
            .instanceById('seerr')!
            .account!;
        expect(account.permissions, 160);
        expect(account.checkedAt, later);
        expect(account.session, session);
      },
    );

    test('a new session rebuilds the client; new permissions do not', () async {
      final container = containerWith(SettingsModel(instances: [annasSeerr]));
      final transport = Provider(
        (ref) => watchTransport(ref, ServiceKey.seerr),
      );
      final first = container.read(transport);

      Future<ServiceTransport> write(SeerrAccountSignIn account) async {
        await container
            .read(settingsProvider.notifier)
            .updateSettings(
              SettingsModel(instances: [annasSeerr.copyWith(account: account)]),
            );
        return container.read(transport);
      }

      // The stamp a client is rebuilt on: the same record, no rebuild.
      expect(await write(anna.copyWith(permissions: 160)), first);
      expect(
        await write(anna.copyWith(session: 's%3Aanother.signature')),
        isNot(first),
      );
    });

    test('a learned refusal is forgotten when the session changes', () async {
      final container = containerWith(SettingsModel(instances: [annasSeerr]));
      final scope = container.read(capabilityScopeProvider.notifier);
      scope.record('seerr', CapabilityScope.readOnly);

      await container
          .read(settingsProvider.notifier)
          .updateSettings(
            SettingsModel(
              instances: [
                annasSeerr.copyWith(account: anna.copyWith(session: 'other')),
              ],
            ),
          );

      expect(container.read(capabilityScopeProvider)['seerr'], isNull);
    });
  });
}
