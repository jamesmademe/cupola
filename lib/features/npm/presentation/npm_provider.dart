import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/npm/data/npm_client.dart';
import 'package:cupola/features/npm/data/npm_upstream_probe.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Nginx Proxy Manager client bound to the current settings.
///
/// Throws if NPM is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.nginxProxyManager)` first.
///
/// One long-lived client per configuration, and here that is not just an
/// optimisation: the bearer token lives on the instance and nowhere else, so a
/// fresh client per call would mean a fresh login per call — against a server
/// with no rate limiting, on an account whose password is the key to every
/// route on the box.
final npmClientProvider = Provider<NpmClient>((ref) {
  return _npmClient(ref, instanceId: null);
});

/// NPM client bound to one named connection, independent of the lens.
final npmClientForProvider = Provider.family<NpmClient, String>((
  ref,
  instanceId,
) {
  final lens =
      ref.read(activeInstanceProvider(ServiceKey.nginxProxyManager))?.id ?? '';
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(npmClientProvider);
  }
  return _npmClient(ref, instanceId: instanceId);
});

NpmClient _npmClient(Ref ref, {required String? instanceId}) {
  // `watchTransport` rather than a hand-written select, and here the narrowness
  // matters twice over: a rebuild closes the live Dio AND throws away the
  // bearer token, so watching every field meant a theme change forced a fresh
  // login. It also follows the lens, which the hand-written version could not:
  // the fields it read were `npmUrl` and friends, always the first connection.
  final transport = watchTransport(
    ref,
    ServiceKey.nginxProxyManager,
    instanceId: instanceId,
  );
  if (!transport.configured) {
    throw Exception('Nginx Proxy Manager not configured');
  }
  final client = NpmClient(
    url: transport.url,
    identity: transport.username.isEmpty ? null : transport.username,
    secret: transport.apiKey.isEmpty ? null : transport.apiKey,
    certFingerprint: transport.pin,
    accessHeaders: transport.access.headers(),
  );
  ref.onDispose(() => client.close());
  return client;
}

/// The hostnames NPM fronts.
final npmProxyHostsProvider = FutureProvider<List<NpmProxyHost>>((ref) async {
  return ref.watch(npmClientProvider).proxyHosts();
}, retry: noProviderRetry);

/// Certificates, for expiry watching.
final npmCertificatesProvider = FutureProvider<List<NpmCertificate>>((
  ref,
) async {
  return ref.watch(npmClientProvider).certificates();
}, retry: noProviderRetry);

/// [npmCertificatesProvider] for one named connection, whatever the lens is
/// on. The lens's own id, and the empty one, read that provider, so the lens
/// is asked once; another id asks its own server. What Home's expiring
/// certificates are read through, one source per connection.
final npmCertificatesForProvider =
    FutureProvider.family<List<NpmCertificate>, String>((ref, instanceId) {
      final lens = ref.watch(
        activeInstanceProvider(ServiceKey.nginxProxyManager),
      );
      if (instanceId.isEmpty || instanceId == lens?.id) {
        return ref.watch(npmCertificatesProvider.future);
      }
      return ref.watch(npmClientForProvider(instanceId)).certificates();
    }, retry: noProviderRetry);

final npmAccessListsProvider = FutureProvider<List<NpmAccessList>>((ref) async {
  return ref.watch(npmClientProvider).accessLists();
}, retry: noProviderRetry);

final npmAuditLogProvider = FutureProvider<List<NpmAuditEntry>>((ref) async {
  return ref.watch(npmClientProvider).auditLog();
}, retry: noProviderRetry);

/// Redirections, 404 hosts and streams, fetched together because the dashboard
/// shows them as one "other hosts" band and none of them is worth a round trip
/// of its own.
final npmOtherHostsProvider = FutureProvider<List<NpmSimpleHost>>((ref) async {
  final client = ref.watch(npmClientProvider);
  final results = await Future.wait([
    client.redirectionHosts(),
    client.deadHosts(),
    client.streams(),
  ]);
  return results.expand((hosts) => hosts).toList(growable: false);
}, retry: noProviderRetry);

/// The unauthenticated health document — version, and whether this install is
/// old enough to still carry NPM's hard-coded default administrator.
final npmServerInfoProvider = FutureProvider<NpmServerInfo>((ref) async {
  return ref.watch(npmClientProvider).serverInfo();
}, retry: noProviderRetry);

/// What is actually answering behind each proxy host, measured from this
/// device.
///
/// Keyed off the loaded hosts rather than off the client, so a pull-to-refresh
/// re-probes with the same gesture that re-reads, and a host added on the
/// server gets a verdict without a second control to press.
///
/// It cannot fail as a screen: a probe that throws is still a probe, and the
/// column it feeds degrades to "unchecked" rather than taking the table down
/// with it.
final npmUpstreamReportProvider = FutureProvider<NpmUpstreamReport>((
  ref,
) async {
  final hosts = await ref.watch(npmProxyHostsProvider.future);
  return const NpmUpstreamProbe().run(hosts);
}, retry: noProviderRetry);
