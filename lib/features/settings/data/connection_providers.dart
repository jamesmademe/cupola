import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderFamily;

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The two providers every service client has, built once: the **lens**'s
/// client, and the client of a **named connection**.
///
/// [lens] is the client of the connection the app is looking through. A
/// non-active connection gets [forConnection]: for the work that belongs to a
/// *connection* rather than to a screen (a release search runs on the server
/// it was started against, and the lens can move while it is queued; the
/// dashboard's folded matrix asks a second Plex for its own figures). The empty
/// id and the lens's own collapse onto [lens], so the app keeps one live `Dio`
/// per connection, and an override of the plain provider, which is how every
/// test supplies a fake, is not quietly bypassed on the path that names a
/// connection. An id naming nothing throws "not configured" rather than
/// answering about some other server.
///
/// **Both fields are made here, once, and never by a getter**: the identity of
/// a provider is the key of its overrides and of its cache, so a getter that
/// built a new `Provider` on every call would be a different provider each
/// time. Declare the pair as top-level aliases (`final xClientProvider =
/// _x.lens;`) so every name callers and tests use stays.
///
/// The lens is `read`, never watched, by [forConnection]: watching it would
/// rebuild EVERY entry of the family whenever the lens moved, entries for
/// connections that did not change, and a rebuild closes the outgoing client. A
/// release search running against the seedbox would have its `Dio` shut under it
/// because the user tapped a badge on another screen. The cost of reading is
/// that an entry minted before the lens landed on its id keeps a client of its
/// own until it is disposed: one extra connection, rather than a request that
/// fails. Not `autoDispose` for the same reason: a caller reads a client,
/// awaits a request on it, and a disposal scheduled at the end of the read would
/// close the `Dio` under the request.
class ConnectionProviders<C> {
  ConnectionProviders._(this.lens, this.forConnection);

  /// A pair over [build], which gets the connection it is building for: null
  /// for the lens's. [retry] is the policy of both, for a client a service's
  /// providers are derived from (`noProviderRetry`).
  factory ConnectionProviders(
    ServiceKey service, {
    required C Function(Ref ref, String? instanceId) build,
    Duration? Function(int retryCount, Object error)? retry,
  }) {
    final lens = Provider<C>((ref) => build(ref, null), retry: retry);
    final forConnection = Provider.family<C, String>((ref, instanceId) {
      final activeId = ref.read(activeInstanceProvider(service))?.id ?? '';
      if (instanceId.isEmpty || instanceId == activeId) {
        return ref.watch(lens);
      }
      return build(ref, instanceId);
    }, retry: retry);
    return ConnectionProviders._(lens, forConnection);
  }

  /// A client built off the connection's **transport** (address, access, pin,
  /// credentials), the shape of every download client, media server, NPM,
  /// Dockge, Unraid and TrueNAS.
  ///
  /// [create] is the one place a client is constructed, which is where ADR-6
  /// wants it: two copies of the six arguments are two places to forget the pin,
  /// and a client built without one silently stops trusting the certificate the
  /// user accepted for that origin. It must hand the client `certFingerprint:
  /// transport.pin`, `accessHeaders: transport.access.headers()` and
  /// `onlyAtHome: transport.onlyAtHomeOf(service)`
  /// (`test/core/network/route_reach_guard_test.dart` and
  /// `access_headers_guard_test.dart` read it there). It may watch what else the
  /// client is built from (Plex's client id, Jellyfin's viewer): a rebuild is
  /// what that buys.
  ///
  /// The transport is `watchTransport`'s, selected narrowly: the client owns a
  /// live `Dio` and is closed by [close] on dispose, so an unrelated settings
  /// write must not rebuild it.
  factory ConnectionProviders.transport(
    ServiceKey service, {
    required C Function(Ref ref, ServiceTransport transport) create,
    required void Function(C client) close,
    Duration? Function(int retryCount, Object error)? retry,
  }) => ConnectionProviders(
    service,
    retry: retry,
    build: (ref, instanceId) {
      final transport = watchTransport(ref, service, instanceId: instanceId);
      transport.ensureConfigured(service);
      final client = create(ref, transport);
      ref.onDispose(() => close(client));
      return client;
    },
  );

  /// A service over an `ApiClient` (the \*arr, Bazarr, Prowlarr), which
  /// `watchApiClient` builds, pins and closes.
  factory ConnectionProviders.apiClient(
    ServiceKey service, {
    required C Function(ApiClient client) create,
    Duration? Function(int retryCount, Object error)? retry,
  }) => ConnectionProviders(
    service,
    retry: retry,
    build: (ref, instanceId) =>
        create(watchApiClient(ref, service, instanceId: instanceId)),
  );

  /// The client of the connection the app is looking through.
  final Provider<C> lens;

  /// The client of a named connection, by id.
  final ProviderFamily<C, String> forConnection;
}
