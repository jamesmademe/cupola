import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
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

  /// The non-secret half, for the services that authenticate on a pair.
  /// Empty for the API-key services, which have none.
  String username,
  String? pin,

  /// Which connection this transport describes. Not used to reach the server —
  /// it is here so a client rebuilds when the lens moves to a *different*
  /// instance that happens to share an address, which is a real shape while
  /// someone is mid-edit adding the second one.
  String instanceId,
});

/// The lens: which instance of each service the app is currently looking
/// through, as `{service: instanceId}`.
///
/// Absent for a service means "the first one". An id that no longer names one
/// of that service's instances also means "the first one" — resolved at read
/// time by [watchTransport] rather than pruned on write, so a removal cannot
/// race the load order and silently discard a choice.
final activeInstancesProvider =
    NotifierProvider<ActiveInstancesNotifier, Map<ServiceKey, String>>(
      ActiveInstancesNotifier.new,
    );

/// The lens map as it was on disk at launch, overridden in `main.dart`.
///
/// Defaults to empty rather than throwing, which is the opposite of
/// [initialSettingsProvider] and deliberately so. Losing settings is data loss;
/// losing a lens means every service opens on its first instance, which is the
/// documented default and what a fresh install does anyway. Making this throw
/// would put the whole `SharedPreferences` bootstrap between any consumer and
/// the question "which server does this talk to" — a test that overrides only
/// the settings would have to stand up storage to ask it.
final initialActiveInstancesProvider = Provider<Map<ServiceKey, String>>(
  (ref) => const {},
);

class ActiveInstancesNotifier extends Notifier<Map<ServiceKey, String>> {
  @override
  Map<ServiceKey, String> build() => ref.watch(initialActiveInstancesProvider);

  /// Points [service] at [instanceId], and remembers it for next launch.
  ///
  /// Reads [settingsServiceProvider] here rather than watching it in [build]:
  /// the write needs storage, the read does not, and pulling the dependency
  /// into `build` would make every reader pay for it.
  Future<void> select(ServiceKey service, String instanceId) async {
    if (state[service] == instanceId) return;
    final updated = {...state, service: instanceId};
    state = updated;
    await ref.read(settingsServiceProvider).saveActiveInstances(updated);
  }

  /// Forgets the choice for [service], which puts it back on the first one.
  Future<void> clear(ServiceKey service) async {
    if (!state.containsKey(service)) return;
    final updated = {...state}..remove(service);
    state = updated;
    await ref.read(settingsServiceProvider).saveActiveInstances(updated);
  }
}

/// The connection [service] is currently seen through, as a `select`-able
/// record.
///
/// Two watches rather than one, and both are narrow on purpose: the lens map
/// is selected down to this service's entry, and the settings model down to the
/// four values that decide which server is reached. A client here owns a live
/// `Dio` and is closed on dispose, so a rebuild costs real connections —
/// switching theme, editing another service, or moving another service's lens
/// must not trigger one.
ServiceTransport watchTransport(Ref ref, ServiceKey service) {
  final lensId = ref.watch(
    activeInstancesProvider.select((lenses) => lenses[service]),
  );

  return ref.watch(
    currentSettingsProvider.select((s) {
      final instances = s.instancesOf(service);
      final instance =
          instances.where((candidate) => candidate.id == lensId).firstOrNull ??
          (instances.isEmpty ? null : instances.first);

      if (instance == null) {
        return (
          configured: false,
          url: '',
          apiKey: '',
          username: '',
          pin: null,
          instanceId: '',
        );
      }
      return (
        configured: instance.isConfigured,
        url: instance.url,
        apiKey: instance.credential,
        username: instance.username,
        pin: s.pinForUrl(instance.url),
        instanceId: instance.id,
      );
    }),
  );
}

/// The instance [service] is currently seen through, or null when it has none.
///
/// The naming counterpart of [watchTransport], for the surfaces that show a
/// label rather than open a socket.
ServiceInstance? watchActiveInstance(Ref ref, ServiceKey service) {
  final lensId = ref.watch(
    activeInstancesProvider.select((lenses) => lenses[service]),
  );
  final instances = ref.watch(
    currentSettingsProvider.select((s) => s.instancesOf(service)),
  );
  return instances.where((candidate) => candidate.id == lensId).firstOrNull ??
      (instances.isEmpty ? null : instances.first);
}

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
  final transport = watchTransport(ref, service);
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
