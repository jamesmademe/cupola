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

/// The three settings fields that decide which server an [ApiClient] talks to
/// and how it authenticates. A record so it compares structurally, which is
/// what makes it usable as a `select` key.
typedef ServiceTransport = ({
  bool configured,
  String url,
  String apiKey,
  String? pin,
});

/// Watches only [service]'s transport identity and returns an [ApiClient] bound
/// to it, closed when the provider is disposed.
///
/// The one place the seven `X-Api-Key` services turn settings into a client.
/// Each of them used to spell out the same twelve lines with its own field
/// names substituted, which is three chances per service to disagree with the
/// registry: whether "configured" means url-and-key, which URL the certificate
/// pin is looked up against, and what the thrown message says.
///
/// **Watches a `select` rather than the whole [SettingsModel] on purpose.** An
/// `ApiClient` owns a `Dio`, and this function registers `onDispose(close)`, so
/// a rebuild is not free — it tears down live connections. Watching the whole
/// model meant *any* settings write rebuilt every service client: switching the
/// theme, editing a different service's URL, completing onboarding. Selecting
/// the record means the client survives everything except a change to its own
/// URL, its own key, or the certificate pinned for its own origin.
///
/// Throws `Exception('<Service> not configured')` when [service] is not
/// configured. The exact `'not configured'` wording is load-bearing —
/// `AsyncValueWidget` string-matches it to render `NotConfiguredPlaceholder`
/// rather than an error — and the service name comes from
/// [ServiceKeyExtension.title] so it stays the name the rest of the app uses.
///
/// A plain function taking [ref] rather than a provider: the callers already
/// are providers, and a second provider layer would add a rebuild edge without
/// adding an answer.
ApiClient watchApiClient(Ref ref, ServiceKey service) {
  final transport = ref.watch(
    currentSettingsProvider.select(
      (s) => (
        configured: s.isServiceConfigured(service),
        url: s.urlFor(service),
        apiKey: s.apiKeyFor(service),
        pin: s.pinForUrl(s.urlFor(service)),
      ),
    ),
  );
  if (!transport.configured) {
    throw Exception('${service.title} not configured');
  }
  final client = ApiClient(
    baseUrl: transport.url,
    apiKey: transport.apiKey,
    pinnedCertFingerprint: transport.pin,
  );
  // Rebuilt whenever the transport identity changes; close the outgoing Dio so
  // its connections are not leaked.
  ref.onDispose(client.close);
  return client;
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
