import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import 'fake_secure_settings_store.dart';

/// The pieces needed to make `settingsProvider` readable in a test.
///
/// `sharedPreferencesProvider` and `initialSettingsProvider` throw unless
/// overridden (they are wired in `main.dart`), and `SettingsNotifier.build`
/// watches both — so any screen that asks `settings.isServiceConfigured(...)`
/// needs all of this. The Activity screen does, because it distinguishes "this
/// service is not set up" from "this service did not answer".
///
/// Most tests want [settingsScopeOverrides] instead, which returns the four
/// overrides ready to spread. This record form is for the call sites that also
/// need one of the pieces afterwards — `scope.prefs` to assert on what was
/// persisted, say.
typedef SettingsScope = ({
  SharedPreferences prefs,
  SecureSettingsStore secureStore,
  SettingsModel settings,
});

Future<SettingsScope> settingsScope({
  List<ServiceKey> configured = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  return (
    prefs: prefs,
    secureStore: FakeSecureSettingsStore(),
    settings: settingsWithServices(configured),
  );
}

/// The four startup overrides a settings-reading test needs, ready to spread:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     ...await settingsScopeOverrides(configured: activityServiceKeys),
///     // …the test's own overrides
///   ],
/// );
/// ```
///
/// [customize] runs on the model built from [configured], for the tests that
/// need a specific URL or key rather than the generated placeholders. It exists
/// because a container rejects two overrides of the same provider, so such a
/// test cannot spread these four and then re-override `initialSettingsProvider`.
Future<List<Override>> settingsScopeOverrides({
  List<ServiceKey> configured = const [],
  SettingsModel Function(SettingsModel settings)? customize,
}) async {
  final scope = await settingsScope(configured: configured);
  final settings = customize?.call(scope.settings) ?? scope.settings;

  return [
    sharedPreferencesProvider.overrideWith((ref) => scope.prefs),
    secureSettingsStoreProvider.overrideWith((ref) => scope.secureStore),
    initialSettingsProvider.overrideWith((ref) => settings),
    initialOnboardingCompletedProvider.overrideWith((ref) => true),
  ];
}

/// A [SettingsModel] where each of [configured] has both a URL and an API key,
/// which is what `isServiceConfigured` requires for the API-key services.
///
/// Goes through `copyWithService` rather than a hand-written `switch`, so every
/// service in the registry is covered. The `switch` this replaced knew four of
/// them and silently returned an unconfigured model for the rest, which is how
/// a test could ask for a configured Bazarr, get a not-configured one, and pass
/// for the wrong reason.
///
/// For the credential-authenticated services the generic slot `copyWithService`
/// writes is the password, which is where they keep their credential — and
/// `isServiceConfigured` only requires a URL of them anyway. A test that needs a
/// username as well should reach for `copyWithCredentials`.
SettingsModel settingsWithServices(List<ServiceKey> configured) {
  var settings = const SettingsModel();

  for (final service in configured) {
    settings = settings.copyWithService(
      service,
      url: 'https://${service.name}.test',
      apiKey: '${service.name}-key',
    );
  }

  return settings;
}

/// The four services that can appear in the global Activity feed.
const activityServiceKeys = [
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
  ServiceKey.seerr,
];
