import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Initialize this in main.dart');
});

final secureSettingsStoreProvider = Provider<SecureSettingsStore>((ref) {
  return createSecureSettingsStore();
});

final initialSettingsProvider = Provider<SettingsModel>((ref) {
  throw UnimplementedError('Initialize this in main.dart');
});

final settingsServiceProvider = Provider<SettingsService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final secureStore = ref.watch(secureSettingsStoreProvider);
  return SettingsService(prefs, secureStore);
});

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsModel>(
  SettingsNotifier.new,
);

final currentSettingsProvider = Provider<SettingsModel>((ref) {
  return ref.watch(settingsProvider);
});

final regionProvider = Provider<String>((ref) {
  return ref.watch(currentSettingsProvider).region;
});

final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(currentSettingsProvider).resolvedThemeMode;
});

/// The [ApiClient] for [service], built from [settings].
///
/// The one place the seven `X-Api-Key` services turn a [SettingsModel] into a
/// client. Each of them used to spell out the same twelve lines with its own
/// field names substituted, which is three chances per service to disagree with
/// the registry: whether "configured" means url-and-key, which URL the
/// certificate pin is looked up against, and what the thrown message says.
///
/// Throws `Exception('<Service> not configured')` when [service] is not
/// configured. The exact `'not configured'` wording is load-bearing —
/// `AsyncValueWidget` string-matches it to render `NotConfiguredPlaceholder`
/// rather than an error — and the service name comes from
/// [ServiceKeyExtension.title] so it stays the name the rest of the app uses.
///
/// A plain function rather than a provider: the callers are already inside a
/// `Provider` body watching [currentSettingsProvider], and a second provider
/// layer would add a rebuild edge without adding an answer.
ApiClient apiClientFor(SettingsModel settings, ServiceKey service) {
  if (!settings.isServiceConfigured(service)) {
    throw Exception('${service.title} not configured');
  }
  final url = settings.urlFor(service);
  return ApiClient(
    baseUrl: url,
    apiKey: settings.apiKeyFor(service),
    pinnedCertFingerprint: settings.pinForUrl(url),
  );
}

class SettingsNotifier extends Notifier<SettingsModel> {
  late final SettingsService _service;

  @override
  SettingsModel build() {
    _service = ref.watch(settingsServiceProvider);
    return ref.watch(initialSettingsProvider);
  }

  Future<void> updateSettings(SettingsModel newSettings) async {
    await _service.saveSettings(newSettings);
    state = newSettings;
  }

  Future<void> resetSettings() async {
    await _service.clearAll();
    state = const SettingsModel();
  }
}
