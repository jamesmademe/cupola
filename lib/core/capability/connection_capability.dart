/// Asking a saved credential what it may do, once per credential.
///
/// The probe half of the capability layer. `capability_scope.dart` says what
/// an answer looks like and remembers what the app learned by acting; this
/// file asks. The questions themselves belong to the features — the endpoint,
/// the field and the failure shape are service knowledge — and are registered
/// in [capabilityProbesProvider].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/npm/presentation/npm_capability.dart';
import 'package:cupola/features/unraid/presentation/unraid_capability.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One service's probe: what may the credential saved for `connectionId` do?
///
/// **Never throws.** A transport error, a timeout, an unparseable body or an
/// unknown shape is [CapabilityGrant.unanswered] — the restrictive fallback —
/// and a credential the service refuses to *read* with is `unanswered` too:
/// that connection is broken, not read-only, and the connection's own health
/// path is what reports it. The banner never claims "read-only" for a key that
/// cannot read.
typedef CapabilityProbe =
    Future<CapabilityGrant> Function(Ref ref, String connectionId);

/// Which probe answers for which service.
///
/// A provider rather than a `switch` so a test can count calls on a fake probe
/// — the "asked once per credential" promise is otherwise untestable. Only the
/// services whose [ServiceKeyExtension.hasScopedCredential] is true appear.
final capabilityProbesProvider = Provider<Map<ServiceKey, CapabilityProbe>>(
  (ref) => const {
    ServiceKey.unraid: probeUnraidCapability,
    ServiceKey.nginxProxyManager: probeNpmCapability,
  },
);

/// What the saved credential of `connectionId` may do.
///
/// **Asked lazily**: the first time a banner or a gated control for the
/// connection builds. Nothing probes at launch — the launch diagnosis already
/// runs unattended for every service and deliberately avoids extra round
/// trips, and an answer nobody is looking at buys nothing.
///
/// **Not autoDispose.** Re-probing on every page open is the flicker the
/// `unknown` state exists to avoid. It rebuilds by itself when that
/// connection's address, credential, username or pinned certificate changes —
/// the stamp watched below — and *only* then: switching the theme or editing
/// another service does not re-ask.
///
/// `retry: noProviderRetry`, because a failed probe is an answer
/// (`unanswered`), not a transient to back off on.
final connectionCapabilityProvider =
    FutureProvider.family<CapabilityGrant, String>((ref, connectionId) async {
      final ServiceKey? service;
      try {
        service = ref
            .watch(
              currentSettingsProvider.select((settings) {
                final instance = settings.instanceById(connectionId);
                if (instance == null) return null;
                // Watched as one stamp so a new credential re-asks and nothing
                // else does. The service rides along because it picks the probe.
                return (
                  service: instance.service,
                  url: instance.url,
                  credential: instance.credential,
                  username: instance.username,
                  pin: settings.pinForUrl(instance.url),
                );
              }),
            )
            ?.service;
      } catch (_) {
        // No settings to read: nothing is configured, so there is nothing to
        // gate. Live, like any connection with nothing to ask.
        return const CapabilityGrant.unknown();
      }

      if (service == null || !service.hasScopedCredential) {
        return const CapabilityGrant.unknown();
      }
      final probe = ref.watch(capabilityProbesProvider)[service];
      if (probe == null) return const CapabilityGrant.unknown();
      try {
        return await probe(ref, connectionId);
      } catch (_) {
        // Every probe folds its own failures already; this is the guarantee
        // for one that does not.
        return const CapabilityGrant.unanswered();
      }
    }, retry: noProviderRetry);

/// The connection a page of [service] is reading through — the lens.
///
/// Every page of the three gated services reads through its lens client, so
/// this is the id every banner and gated control on those pages asks about.
/// Empty when the service has no connection, which resolves to
/// [CapabilityGrant.unknown]: live, and correct for a service that is not set
/// up — the screens check `isServiceConfigured` before reaching any of this.
String capabilityConnectionId(WidgetRef ref, ServiceKey service) =>
    ref.watch(activeInstanceProvider(service))?.id ?? '';

/// Asks the probe for [connectionId] again — pull-to-refresh on a page with
/// writes, and the banner's *Check again*.
///
/// Does **not** clear a learned refusal: that is newer evidence than any probe,
/// and only a credential change retires it.
void recheckCapability(WidgetRef ref, String connectionId) =>
    ref.invalidate(connectionCapabilityProvider(connectionId));
