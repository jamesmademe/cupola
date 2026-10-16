import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client_provider.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_refusal_store.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// What every container of the app is built with: the stores, and what was
/// read of them before the first frame. The app's start (`main.dart`) and
/// the run that reads the servers with the app off the screen
/// (`OutsideRun`) build theirs from here, so the two reach the same servers
/// the same way.
List<Override> startupOverrides({
  required SharedPreferences prefs,
  required SecureSettingsStore secureSettingsStore,
  required SettingsModel initialSettings,
  required Map<ServiceKey, String> activeInstances,
  required bool onboardingCompleted,
  required LastKnownStore lastKnown,
}) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  lastKnownStoreProvider.overrideWithValue(lastKnown),
  secureSettingsStoreProvider.overrideWithValue(secureSettingsStore),
  // A refused qBittorrent sign-in outlives the run, so a relaunch does not
  // spend another of the five attempts its ban allows.
  qbittorrentRefusalStoreProvider.overrideWithValue(
    SecureQbittorrentRefusalStore(secureSettingsStore),
  ),
  initialSettingsProvider.overrideWithValue(initialSettings),
  initialActiveInstancesProvider.overrideWithValue(activeInstances),
  initialOnboardingCompletedProvider.overrideWithValue(onboardingCompleted),
];

/// The overrides of a run with no screen: the same stores, read as they
/// are, with nothing migrated (the app's start does that, and two isolates
/// writing the same keys at once is how a key is lost) and the Home's last
/// drawings left alone (`LastKnownStore.memory`): a run that draws nothing
/// keeps none.
Future<List<Override>> readHeadlessStartup() async {
  final prefs = await SharedPreferences.getInstance();
  final secureSettingsStore = createSecureSettingsStore();
  final settingsService = SettingsService(prefs, secureSettingsStore);
  return startupOverrides(
    prefs: prefs,
    secureSettingsStore: secureSettingsStore,
    initialSettings: await settingsService.loadSettings(),
    activeInstances: settingsService.loadActiveInstances(),
    onboardingCompleted: await settingsService.loadOnboardingComplete(),
    lastKnown: LastKnownStore.memory(),
  );
}
