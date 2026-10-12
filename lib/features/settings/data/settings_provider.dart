import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';
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

/// The settings fields that decide which server an [ApiClient] talks to and
/// how it authenticates, to the service and to whatever stands in front of it. A record so it compares structurally, which is
/// what makes it usable as a `select` key.
typedef ServiceTransport = ({
  bool configured,
  String url,
  String apiKey,

  /// The non-secret half, for the services that authenticate on a pair.
  /// Empty for the API-key services, which have none.
  String username,
  String? pin,

  /// What the connection presents to a gateway in front of the service, on
  /// every request. Part of the key, so a client rebuilds when it changes.
  ConnectionAccess access,

  /// A Seerr account's session, empty for every other connection. Part of
  /// the key, so signing in again rebuilds the client and what it answered;
  /// the account's permissions are not, because reading them again must not
  /// cut a request in flight.
  String session,

  /// Which connection this transport describes. Not used to reach the server;
  /// it is here so a client rebuilds when the lens moves to a *different*
  /// instance that happens to share an address, which is a real shape while
  /// someone is mid-edit adding the second one.
  String instanceId,
});

/// The lens: which instance of each service the app is currently looking
/// through, as `{service: instanceId}`.
///
/// Absent for a service means "the first one". An id that no longer names one
/// of that service's instances also means "the first one", resolved at read
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
/// the question "which server does this talk to". A test that overrides only
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
/// `Dio` and is closed on dispose, so a rebuild costs real connections:
/// switching theme, editing another service, or moving another service's lens
/// must not trigger one.
///
/// [instanceId] names a connection explicitly and skips the lens. Null or empty
/// means "whichever one this service is being read through", which is what
/// every caller meant before a service could have two. A **non-empty id that
/// names nothing** is reported as not configured rather than falling back to
/// the lens: the caller asked for one specific server, and quietly answering
/// about a different one is how a background job started against the seedbox
/// finishes against the box at home. The lens is not consulted at all in that
/// case, so this does not rebuild when the lens moves.
ServiceTransport watchTransport(
  Ref ref,
  ServiceKey service, {
  String? instanceId,
}) {
  final pinned = instanceId != null && instanceId.isNotEmpty;
  final lensId = pinned
      ? instanceId
      : ref.watch(activeInstancesProvider.select((lenses) => lenses[service]));

  return ref.watch(
    currentSettingsProvider.select((s) {
      final instances = s.instancesOf(service);
      final named = instances
          .where((candidate) => candidate.id == lensId)
          .firstOrNull;
      final instance = pinned
          ? named
          : named ?? (instances.isEmpty ? null : instances.first);

      if (instance == null) {
        return (
          configured: false,
          url: '',
          apiKey: '',
          username: '',
          pin: null,
          access: const NoAccess(),
          session: '',
          instanceId: '',
        );
      }
      return (
        configured: instance.isConfigured,
        url: instance.url,
        apiKey: instance.credential,
        username: instance.username,
        pin: s.pinForUrl(instance.url),
        access: instance.access,
        session: instance.account?.session ?? '',
        instanceId: instance.id,
      );
    }),
  );
}

/// The instance [service] is currently seen through, or null when it has none.
///
/// The naming counterpart of [watchTransport], for the surfaces that show a
/// label rather than open a socket.
///
/// Selects the resolved instance rather than the list it came out of.
/// `instancesOf` builds a fresh `List` on every call and lists compare by
/// identity, so selecting one would never match its previous value and every
/// consumer would rebuild on every unrelated settings write. [ServiceInstance]
/// compares structurally, so this settles.
final activeInstanceProvider = Provider.family<ServiceInstance?, ServiceKey>((
  ref,
  service,
) {
  final lensId = ref.watch(
    activeInstancesProvider.select((lenses) => lenses[service]),
  );
  return ref.watch(
    currentSettingsProvider.select((s) {
      final instances = s.instancesOf(service);
      return instances
              .where((candidate) => candidate.id == lensId)
              .firstOrNull ??
          (instances.isEmpty ? null : instances.first);
    }),
  );
});

/// The connection a screen should read, given what its route said.
///
/// [named] is the `?i=` a link carried, or null when it carried none, which is
/// every link that predates a service being able to have two. Null falls
/// through to the lens, so a page reached the ordinary way behaves exactly as
/// it did.
///
/// A plain function rather than a provider, for the same reason
/// [watchApiClient] is one: the callers are already widgets holding a `ref`,
/// and a provider layer would add a rebuild edge without adding an answer.
String effectiveInstanceId(WidgetRef ref, ServiceKey service, String? named) {
  if (named != null && named.isNotEmpty) return named;
  return ref.watch(activeInstanceProvider(service))?.id ?? '';
}

/// The connection of [service] a page at [location] reads: the one its `?i=`
/// names, when it names one of [service]'s, else the lens.
///
/// For the window's own furniture, which sits above the page and names what
/// it shows: a detail page opened from the 4K's row reads the 4K, whatever
/// the lens is on, and a readout naming the lens over it names the wrong
/// server. An `i` that is another service's (a settings link, a requests
/// list) says nothing about [service].
String locationInstanceId(WidgetRef ref, ServiceKey service, Uri location) {
  final named = location.queryParameters['i'];
  final belongs =
      named != null &&
      named.isNotEmpty &&
      ref.watch(
        currentSettingsProvider.select(
          (s) => s.instanceById(named)?.service == service,
        ),
      );
  return effectiveInstanceId(ref, service, belongs ? named : null);
}

/// What the connection [id] is called beside its siblings, or null when its
/// service has only the one: [SettingsModel.connectionName], watched narrowly.
final connectionNameProvider = Provider.family<String?, String>((ref, id) {
  return ref.watch(currentSettingsProvider.select((s) => s.connectionName(id)));
});

/// Whether [service] has more than one connection: the question every surface
/// asks before it decides to show a label at all.
final hasMultipleInstancesProvider = Provider.family<bool, ServiceKey>((
  ref,
  service,
) {
  return ref.watch(
    currentSettingsProvider.select((s) => s.hasMultipleInstances(service)),
  );
});

/// Watches only [service]'s transport identity and returns an [ApiClient] bound
/// to it, closed when the provider is disposed.
///
/// The one place the `X-Api-Key` services turn settings into a client, Seerr
/// excepted: its client is `seerrClientFor`'s.
/// Each of them used to spell out the same twelve lines with its own field
/// names substituted, which is three chances per service to disagree with the
/// registry: whether "configured" means url-and-key, which URL the certificate
/// pin is looked up against, and what the thrown message says.
///
/// **Watches a `select` rather than the whole [SettingsModel] on purpose.** An
/// `ApiClient` owns a `Dio`, and this function registers `onDispose(close)`, so
/// a rebuild is not free: it tears down live connections. Watching the whole
/// model meant *any* settings write rebuilt every service client: switching the
/// theme, editing a different service's URL, completing onboarding. Selecting
/// the record means the client survives everything except a change to its own
/// URL, its own key, or the certificate pinned for its own origin.
///
/// Throws [ServiceNotConfigured] when [service] is not configured, which
/// `AsyncValueWidget` answers with `NotConfiguredPlaceholder` rather than an
/// error.
///
/// A plain function taking [ref] rather than a provider: the callers already
/// are providers, and a second provider layer would add a rebuild edge without
/// adding an answer.
ApiClient watchApiClient(Ref ref, ServiceKey service, {String? instanceId}) {
  // Seerr signs in two ways and guards its writes with a CSRF token: its
  // client is `watchSeerrClient`'s, never this one.
  assert(service != ServiceKey.seerr, 'Seerr clients come from seerrClientFor');
  final transport = watchTransport(ref, service, instanceId: instanceId);
  if (!transport.configured) {
    throw ServiceNotConfigured(service);
  }
  final client = ApiClient(
    baseUrl: transport.url,
    apiKey: transport.apiKey,
    pinnedCertFingerprint: transport.pin,
    accessHeaders: transport.access.headers(),
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
