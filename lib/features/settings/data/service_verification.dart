import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/npm/data/npm_client.dart';
import 'package:cupola/features/nzbget/data/nzbget_client.dart';
import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_status_probe.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/probe_identity.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/unraid/data/unraid_client.dart';

/// Where a service's connection is checked, and how the result is described.
///
/// Onboarding grew a verifier that classifies *why* a connection failed while
/// settings kept a separate reachability-only check, so the same instance could
/// say "rejected the API key" during setup and a shrugging "could not reach it"
/// afterwards. Both now run through this file, and the health-endpoint table
/// lives once on the registry, as `ServiceKey.statusEndpoint`.

/// The outcome of a connection attempt: the status, why it failed, and the
/// certificate that explains the failure when one does.
///
/// Reachability alone leaves every failure looking identical, so the reason is
/// what lets the UI say "credentials rejected" instead of "check everything".
class ServiceDiagnosis {
  const ServiceDiagnosis(
    this.status, [
    this.reason,
    this.certificateProbe,
    this.detail,
  ]) : serverVersion = null;

  /// The full form, for the places that set a field the positional list cannot
  /// reach — Dart allows optional positionals or optional named, not both, and
  /// the positional shape above is what every call site already uses.
  const ServiceDiagnosis._all({
    required this.status,
    this.reason,
    this.certificateProbe,
    this.detail,
    this.serverVersion,
  });

  const ServiceDiagnosis.connected() : this(ServiceConnectionStatus.connected);

  /// The service answered, and named its own version on the way.
  ///
  /// Worth carrying because a green tick can still be the wrong answer: a
  /// TrueNAS older than the minimum authenticates, replies, and then leaves
  /// half the console empty. The version is what lets the test say so at the
  /// moment it is read, rather than leaving the user to find out inside the hub.
  const ServiceDiagnosis.connectedAs(String version)
    : this._all(
        status: ServiceConnectionStatus.connected,
        serverVersion: version,
      );

  const ServiceDiagnosis.notConfigured()
    : this(ServiceConnectionStatus.notConfigured);

  const ServiceDiagnosis.checking() : this(ServiceConnectionStatus.checking);

  /// The service answered, but could not be reached again to confirm.
  const ServiceDiagnosis.dropped()
    : this(
        ServiceConnectionStatus.disconnected,
        ServiceFailureReason.unreachable,
      );

  /// The OS refused to let Cupola onto the local network, so the request never
  /// left the device. Not derived from an error — see
  /// [ServiceFailureReason.localNetworkBlocked].
  const ServiceDiagnosis.localNetworkBlocked()
    : this(
        ServiceConnectionStatus.disconnected,
        ServiceFailureReason.localNetworkBlocked,
      );

  ServiceDiagnosis.failed(
    Object error, {
    ServiceFailureReason fallback = ServiceFailureReason.unknown,
  }) : this(
         ServiceConnectionStatus.disconnected,
         classifyConnectionFailure(error, fallback: fallback),
         null,
         connectionFailureDetail(error),
       );

  final ServiceConnectionStatus status;

  /// Null unless [status] is `disconnected`.
  final ServiceFailureReason? reason;

  /// Non-null only when the connection failed specifically because the server
  /// presents a certificate not trusted by the platform and not yet pinned —
  /// [UntrustedCertificateProbe.rotated] is what tells the UI whether this is
  /// a first-time trust or this origin's pin no longer matches (ADR-6).
  final UntrustedCertificateProbe? certificateProbe;

  /// The verbatim sentence the failure carried, when it carried one.
  ///
  /// Almost always null: a [ServiceFailureReason] plus the service's name is
  /// enough to write a better sentence than a client library would. The
  /// exception is a component that knows something the closed vocabulary cannot
  /// hold — `SameOriginRedirectInterceptor` refusing a cross-origin redirect
  /// knows *which* origin it was sent to, and `redirected` alone can only say
  /// "a redirect Cupola will not follow". Rendered in place of
  /// [connectionFailureMessage] when present, never alongside it.
  final String? detail;

  /// The version string the server reported during the test, for the services
  /// that say — null everywhere else. Raw and unparsed: turning it into words,
  /// and into a caveat where the version matters, is `describeServerVersion`'s
  /// job, so both surfaces that report a test say the same thing about it.
  final String? serverVersion;

  /// What the UI should actually say about this outcome.
  ///
  /// One accessor rather than `detail ?? connectionFailureMessage(...)` repeated
  /// at each surface — the settings screen and the onboarding walk both report
  /// the same test, and them disagreeing is exactly the drift this codebase
  /// keeps paying for elsewhere.
  String messageFor(ServiceKey service) =>
      detail ?? connectionFailureMessage(service, reason);

  bool get isConnected => status == ServiceConnectionStatus.connected;

  bool get isDisconnected => status == ServiceConnectionStatus.disconnected;

  bool get isConfigured => status != ServiceConnectionStatus.notConfigured;

  ServiceDiagnosis withCertificateProbe(UntrustedCertificateProbe? probe) =>
      ServiceDiagnosis._all(
        status: status,
        reason: reason,
        certificateProbe: probe,
        detail: detail,
        serverVersion: serverVersion,
      );
}

/// Verifies [service] against the credentials passed in, rather than the saved
/// ones, so a form can test what is typed before committing it.
///
/// [clientIdentifier] is Plex's persisted `X-Plex-Client-Identifier` and is
/// ignored by every other service. It is read from settings rather than minted
/// here because Plex registers a new device row against the user's server for
/// each distinct value it sees.
Future<ServiceDiagnosis> diagnoseCredentials(
  ServiceKey service, {
  required String url,
  String apiKey = '',
  String username = '',
  String password = '',
  String certFingerprint = '',
  String clientIdentifier = '',
}) async {
  final pin = certFingerprint.trim().isEmpty ? null : certFingerprint.trim();
  final user = username.trim().isEmpty ? null : username.trim();
  final pass = password.isEmpty ? null : password;
  final urlTrimmed = url.trim();

  if (service == ServiceKey.dockge) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = DockgeClient(
      baseUrl: urlTrimmed,
      username: user,
      password: pass,
      certFingerprint: pin,
    );
    try {
      final ok = await client.ping().timeout(const Duration(seconds: 8));
      // A rejected login throws with `unauthorized`, so `false` here means the
      // socket dropped after authenticating — a connection fault, not a wrong
      // password. Reporting it as "credentials rejected" sent users to re-type a
      // password that was fine.
      return ok
          ? const ServiceDiagnosis.connected()
          : const ServiceDiagnosis.dropped();
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      await client.close();
    }
  }

  if (service == ServiceKey.nzbget) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = NzbgetClient(
      url: urlTrimmed,
      username: user,
      password: pass,
      certFingerprint: pin,
    );
    return _probe(
      client.testConnection,
      timeout: const Duration(seconds: 6),
      close: client.close,
    );
  }

  if (service == ServiceKey.nginxProxyManager) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = NpmClient(
      url: urlTrimmed,
      identity: user,
      secret: pass,
      certFingerprint: pin,
    );
    // Checks both halves: `GET /api/` proves an NPM is there, and the login
    // proves the credential. Only the first would go green for a wrong
    // password, since the admin port answers 200 with its SPA for almost any
    // request.
    return _probe(
      client.testConnection,
      timeout: const Duration(seconds: 10),
      close: client.close,
    );
  }

  if (service == ServiceKey.transmission) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = TransmissionClient(
      url: urlTrimmed,
      username: user,
      password: pass,
      certFingerprint: pin,
    );
    // `session-get` in one round trip forces the CSRF handshake, validates
    // the Basic credentials, and proves the rpc/host whitelists admit this
    // device — the three ways a reachable Transmission still refuses to talk.
    return _probe(
      client.testConnection,
      timeout: const Duration(seconds: 8),
      close: client.close,
    );
  }

  // Named, not inferred. This used to read `if (!service.usesApiKey)`, which is
  // a *negative capability* rather than an identity — so every future
  // credential-authenticated service was silently routed here, and Transmission
  // would have had its password POSTed as form data to
  // `/api/v2/auth/login` on the Transmission host. It 404s, so the failure
  // would have looked like a broken client rather than a broken dispatcher.
  // `_diagnoseOverApiClient` now fails closed for anything that reaches it
  // unrouted, which is the other half of that guard.
  if (service == ServiceKey.qbittorrent) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = QbittorrentClient(
      url: urlTrimmed,
      username: user,
      password: pass,
      certFingerprint: pin,
    );
    // Two round trips (login + version), so allow more than a single hop.
    return _probe(
      client.getVersion,
      timeout: const Duration(seconds: 8),
      close: client.close,
    );
  }

  if (urlTrimmed.isEmpty || apiKey.trim().isEmpty) {
    return const ServiceDiagnosis.notConfigured();
  }

  if (service == ServiceKey.seerr) {
    final client = ApiClient(
      baseUrl: urlTrimmed,
      apiKey: apiKey.trim(),
      pinnedCertFingerprint: pin,
    );
    try {
      await SeerrService(
        client,
      ).testConnection().timeout(const Duration(seconds: 5));
      // Then who answered, read the way the Dashboard's probe reads it.
      await readServiceStatus(client, service, url: urlTrimmed);
      return const ServiceDiagnosis.connected();
    } catch (e) {
      return ServiceDiagnosis.failed(
        probeFailureOf(service, e, url: urlTrimmed),
      );
    } finally {
      client.close();
    }
  }

  if (service == ServiceKey.sabnzbd) {
    final client = SabnzbdClient(
      url: urlTrimmed,
      apiKey: apiKey.trim(),
      certFingerprint: pin,
    );
    return _probe(
      client.testConnection,
      timeout: const Duration(seconds: 6),
      close: client.close,
    );
  }

  if (service == ServiceKey.unraid) {
    final client = UnraidClient(
      url: urlTrimmed,
      apiKey: apiKey.trim(),
      certFingerprint: pin,
    );
    return _probe(
      client.testConnection,
      timeout: const Duration(seconds: 6),
      close: client.close,
    );
  }

  if (service == ServiceKey.truenas) {
    final client = TrueNasWsClient(
      baseUrl: urlTrimmed,
      apiKey: apiKey.trim(),
      certFingerprint: pin,
    );
    try {
      // `core.ping` stays the verdict: it is the cheapest call that proves the
      // socket, the login and the API key all at once.
      await client.call('core.ping').timeout(const Duration(seconds: 6));
      // The version is a second hop on the socket that is already open and
      // authenticated, and it is deliberately *not* allowed to change the
      // verdict — a server that pings is connected whether or not it will name
      // itself. Hence the swallowed failure: the outcome loses one line, not
      // its green tick.
      String? version;
      try {
        version = stringOrNull(
          await client
              .call('system.version')
              .timeout(const Duration(seconds: 4)),
        );
      } catch (_) {
        version = null;
      }
      return version == null || version.trim().isEmpty
          ? const ServiceDiagnosis.connected()
          : ServiceDiagnosis.connectedAs(version.trim());
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      await client.close();
    }
  }

  // The two media servers authenticate with a header the shared `ApiClient`
  // does not send — `Authorization: MediaBrowser Token=` for Jellyfin,
  // `X-Plex-Token` for Plex — and both health endpoints in the table above are
  // anonymous. Verified through the generic branch, *any* non-empty string
  // therefore came back 2xx and the tile went green while every real call 401ed.
  // Their own clients are what actually present the credential.
  if (service == ServiceKey.jellyfin) {
    final client = JellyfinClient(
      baseUrl: urlTrimmed,
      apiKey: apiKey.trim(),
      pinnedCertFingerprint: pin,
    );
    bool accepted;
    try {
      // `/System/Info` — the authenticated twin of the public probe. Swallows
      // its own errors and answers false for all of them, which is why the
      // refusal still has to be explained below rather than reported as-is.
      accepted = await client.verifyCredential().timeout(
        const Duration(seconds: 6),
      );
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      client.close();
    }
    if (accepted) return const ServiceDiagnosis.connected();
    return _explainCredentialRefusal(service, url: urlTrimmed, pin: pin);
  }

  if (service == ServiceKey.plex) {
    final client = PlexClient(
      url: urlTrimmed,
      token: apiKey.trim(),
      clientIdentifier: clientIdentifier.trim(),
      pinnedCertFingerprint: pin,
    );
    try {
      // Unlike Jellyfin's, this one already separates the two questions: it
      // answers false only for an actual refusal and rethrows a `PlexException`
      // carrying its own `ServiceFailureReason` for anything else — including
      // the JWT it refuses to send at all, which is an unauthorized the user has
      // to fix by pasting a different *kind* of token. So no second probe.
      final accepted = await client.verifyCredential().timeout(
        const Duration(seconds: 6),
      );
      return accepted
          ? const ServiceDiagnosis.connected()
          : const ServiceDiagnosis(
              ServiceConnectionStatus.disconnected,
              ServiceFailureReason.unauthorized,
            );
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      client.close();
    }
  }

  return _diagnoseOverApiClient(
    service,
    url: urlTrimmed,
    apiKey: apiKey,
    pin: pin,
  );
}

/// The envelope every single-call probe above shares: run it under this
/// service's own deadline, turn anything thrown into a classified failure, and
/// close the client whichever way it went.
///
/// [timeout] is a parameter rather than a constant because the deadlines are
/// per-service and deliberate — a client that logs in before it can answer
/// needs more than one hop's worth of headroom.
///
/// [close] is a `FutureOr` so the one asynchronous `close` (TrueNAS, which has a
/// socket to shut down) and the synchronous Dio ones share this path without
/// either being rewritten: awaiting a non-future would still be correct, but the
/// explicit test keeps the sync branches exactly as they were.
Future<ServiceDiagnosis> _probe(
  Future<void> Function() run, {
  required Duration timeout,
  required FutureOr<void> Function() close,
}) async {
  try {
    await run().timeout(timeout);
    return const ServiceDiagnosis.connected();
  } catch (e) {
    return ServiceDiagnosis.failed(e);
  } finally {
    final closing = close();
    if (closing is Future) await closing;
  }
}

/// Reachability and status classification over the shared [ApiClient], which
/// has been pin-aware since ADR-6 — this is the branch the pinning scope used
/// to carve out. [pin] threads straight through; when it is null this is
/// byte-identical to the pre-ADR-6 unpinned client.
Future<ServiceDiagnosis> _diagnoseOverApiClient(
  ServiceKey service, {
  required String url,
  required String apiKey,
  required String? pin,
}) async {
  // Fails closed on a routing bug. An empty entry in
  // [ServiceKey.statusEndpoint] means "this service is verified through its own
  // client", and every one of those has a branch above. If a new service
  // reaches here without one, the request below would be `GET ''` — a plain
  // fetch of the base URL — which most of these servers answer 200 for with
  // their own web UI, *whatever* credential was supplied. That is a green
  // "Answering" tile for a wrong password: the exact bug that shipped once for
  // Jellyfin and Plex. Reporting the service as unreachable is wrong too, but
  // it is wrong in the direction that gets noticed and cannot mislead anyone
  // into thinking a bad credential works.
  final endpoint = service.statusEndpoint;
  if (endpoint.isEmpty) {
    return const ServiceDiagnosis(
      ServiceConnectionStatus.disconnected,
      ServiceFailureReason.unknown,
    );
  }

  final client = ApiClient(
    baseUrl: url,
    apiKey: apiKey.trim(),
    pinnedCertFingerprint: pin,
  );
  try {
    // The Dashboard probe's own reading: the status route, and who answered
    // it. A 2xx from something that is not the service is not a pass.
    await readServiceStatus(client, service, url: url);
    return const ServiceDiagnosis.connected();
  } catch (e) {
    return ServiceDiagnosis.failed(e);
  } finally {
    client.close();
  }
}

/// Turns "the credential was not accepted" into a verdict, for a service whose
/// own client cannot say *why* it said no.
///
/// Asks the credential-free endpoint whether the box is even there. If it
/// answers, the address is right and the credential is the thing that was
/// refused; if it does not, the original failure was never about the key and
/// the reachability verdict — unreachable, TLS, wrong base path — is the honest
/// one to report. Costs a second round trip only on the failure path.
Future<ServiceDiagnosis> _explainCredentialRefusal(
  ServiceKey service, {
  required String url,
  required String? pin,
}) async {
  final reachability = await _diagnoseOverApiClient(
    service,
    url: url,
    apiKey: '',
    pin: pin,
  );
  if (!reachability.isConnected) return reachability;
  return const ServiceDiagnosis(
    ServiceConnectionStatus.disconnected,
    ServiceFailureReason.unauthorized,
  );
}

/// Verifies **every** configured connection of [service] and reports the worst
/// answer among them.
///
/// Folded rather than answered off the first instance, and that is the whole of
/// what this function had to learn: the surfaces that read it — the Connections
/// row, the Settings home list — speak in services and now also print how many
/// connections a service has. "Answering · radarr.lan · 2 connections" while the
/// second Radarr is switched off is a green row for a stack with a dead server
/// in it, and it is green on the one screen the user would go to in order to fix
/// it. `ServiceMatrixCell` already folds its pip the same way, through
/// [foldedServiceHealthProvider].
///
/// The cost is one probe per connection instead of one per service. That is the
/// honest price of the count beside it: before, the second connection was never
/// asked at all.
Future<ServiceDiagnosis> diagnoseService(
  ServiceKey service,
  SettingsModel settings,
) async {
  final instances = settings.configuredInstancesOf(service);
  if (instances.isEmpty) return const ServiceDiagnosis.notConfigured();

  final results = await Future.wait([
    for (final instance in instances) diagnoseInstance(instance, settings),
  ]);
  return worstDiagnosis(results);
}

/// The diagnosis a folded readout should show: the one the user most needs to
/// act on.
///
/// Ordered by how much attention the state wants rather than by enum order, so
/// a single unreachable connection is never hidden behind a sibling that is up.
ServiceDiagnosis worstDiagnosis(List<ServiceDiagnosis> results) {
  var worst = results.first;
  for (final result in results.skip(1)) {
    if (_attention(result.status) > _attention(worst.status)) worst = result;
  }
  return worst;
}

int _attention(ServiceConnectionStatus status) => switch (status) {
  ServiceConnectionStatus.disconnected => 3,
  ServiceConnectionStatus.notConfigured => 2,
  ServiceConnectionStatus.checking => 1,
  ServiceConnectionStatus.connected => 0,
};

/// Diagnoses one specific connection.
///
/// The form that matters once a service can have more than one: [diagnoseService]
/// folds every connection into one answer, which is right for a row that names
/// the service and wrong for a form that is editing exactly one of them.
/// [settings] is still
/// needed for the two values that are not the instance's own — the pin, which
/// belongs to a TLS origin, and the Plex client id, which belongs to the install.
Future<ServiceDiagnosis> diagnoseInstance(
  ServiceInstance instance,
  SettingsModel settings,
) {
  if (!instance.isConfigured) {
    return Future.value(const ServiceDiagnosis.notConfigured());
  }
  final service = instance.service;
  return diagnoseCredentials(
    service,
    url: instance.url,
    // The credential sits in one slot and which vocabulary it answers to is the
    // registry's call, exactly as it is in storage.
    apiKey: service.usesApiKey ? instance.credential : '',
    username: instance.username,
    password: service.usesApiKey ? '' : instance.credential,
    certFingerprint: settings.pinForUrl(instance.url) ?? '',
    clientIdentifier: settings.plexClientId,
  );
}

/// Whether a blocked local network could still explain this failure.
///
/// The mirror of [certProbeWorthwhile], and it rules out one more: a TLS failure
/// proves the packets reached a server, so the OS was never in the way. What is
/// left — nothing answered, nothing answered in time, or nothing attributable —
/// is exactly how a permission the user has not granted looks from the socket.
bool localNetworkCouldExplain(ServiceFailureReason? reason) => switch (reason) {
  ServiceFailureReason.unauthorized ||
  ServiceFailureReason.notFound ||
  ServiceFailureReason.redirected ||
  ServiceFailureReason.serverError ||
  ServiceFailureReason.invalidResponse ||
  ServiceFailureReason.tls ||
  // Refused before dialling: the OS was never asked for anything.
  ServiceFailureReason.insecureTransport ||
  // Already attributed; asking again would only re-confirm it.
  ServiceFailureReason.localNetworkBlocked => false,
  _ => true,
};

/// Runs [diagnose] and, when it fails the way a blocked local network fails,
/// asks the OS whether that is what happened.
///
/// The order is the whole design. Cupola never asks first: on iOS the *failing
/// connection is what raises the system alert*, so by the time this asks, the
/// alert the user must answer is already on screen — and asking only after a
/// failure means a public server timing out can never raise a Local Network
/// prompt out of nowhere. Three outcomes, three different truths:
///
/// * `justGranted` — the user allowed it while we were asking. The failed
///   connection was dialled through a closed gate, so its verdict is void and
///   the test is simply run again. This is the retest the user used to have to
///   work out for themselves.
/// * `denied` — report the permission, not the address. The old copy sent people
///   to re-check a hostname and port that were right all along.
/// * anything else — keep the original failure untouched. Claiming a permission
///   problem on a hunch would be the same bug in the other direction.
///
/// [timeout] is how long the OS gets to answer. Pass something generous where a
/// human is watching (they are reading an alert), and something short on a
/// background refresh, where the only answer worth having is one the OS already
/// holds.
Future<ServiceDiagnosis> diagnoseThroughLocalNetworkGate(
  Future<ServiceDiagnosis> Function() diagnose, {
  required String url,
  Duration timeout = const Duration(seconds: 20),
  LocalNetworkProbe probe = probeLocalNetworkAccess,
}) async {
  final first = await diagnose();
  if (!first.isDisconnected || !localNetworkCouldExplain(first.reason)) {
    return first;
  }
  final access = await probe(url, timeout: timeout);
  return switch (access) {
    LocalNetworkAccess.justGranted => await diagnose(),
    LocalNetworkAccess.denied => const ServiceDiagnosis.localNetworkBlocked(),
    LocalNetworkAccess.granted ||
    LocalNetworkAccess.unrestricted ||
    LocalNetworkAccess.unknown => first,
  };
}

/// Whether a certificate probe could still explain this failure.
///
/// An untrusted certificate surfaces as `tls`, and as `unreachable`/`unknown`
/// when the handshake fails before a reason can be attributed. Anything the
/// server answered — a rejected key, a 404, a 500, a redirect nobody could
/// follow — rules the certificate out: the response proves the handshake
/// already completed, so probing for an untrusted certificate costs a round
/// trip to learn nothing.
bool certProbeWorthwhile(ServiceFailureReason? reason) => switch (reason) {
  ServiceFailureReason.unauthorized ||
  ServiceFailureReason.notFound ||
  ServiceFailureReason.redirected ||
  ServiceFailureReason.serverError ||
  ServiceFailureReason.invalidResponse ||
  // Nothing left the device, so there is no handshake to inspect: the probe
  // opens its own socket to the same blocked address and can only time out.
  ServiceFailureReason.localNetworkBlocked ||
  // Refused before dialling, and the probe would dial the very address the
  // refusal was protecting the key from.
  ServiceFailureReason.insecureTransport => false,
  _ => true,
};

/// Verifies one connection against [settings] and, when it fails in a way a
/// certificate could explain, attaches the probe so the UI can offer to trust
/// it. Every service can reach this since ADR-6 — there is no
/// pinning-capability gate left to check. Never trusts anything itself.
///
/// Takes the instance rather than the service: the caller is a form editing one
/// connection, and probing the origin of a *different* one would put the trust
/// prompt in front of the user for a certificate they were not asked about.
Future<ServiceDiagnosis> diagnoseInstanceWithCertProbe(
  ServiceInstance instance,
  SettingsModel settings, {
  CertificateProber probe = probeUntrustedCertificate,
}) async {
  final diagnosis = await diagnoseInstance(instance, settings);
  if (!diagnosis.isDisconnected || !certProbeWorthwhile(diagnosis.reason)) {
    return diagnosis;
  }
  final url = instance.url;
  final certProbe = await probe(
    url,
    pinnedFingerprint: settings.pinForUrl(url) ?? '',
  );
  return diagnosis.withCertificateProbe(certProbe);
}

/// User-facing copy for a failed verification. Each cause names the thing the
/// user can actually change.
String connectionFailureMessage(
  ServiceKey service,
  ServiceFailureReason? reason,
) {
  switch (reason) {
    case ServiceFailureReason.unreachable:
      return 'Nothing answered at this address. Check the address and port, '
          'and that ${service.title} is running and reachable from this '
          'device.';
    case ServiceFailureReason.timeout:
      return 'The server was reached, then did not answer in time. Retry, or '
          'look at ${service.title} if it is still starting up.';
    case ServiceFailureReason.tls:
      // Never suggest downgrading to http:// here. A certificate that fails
      // to verify is the same signal an interception attack produces, and
      // every service can now offer the right answer (ADR-6): verify again
      // and confirm the certificate when Cupola offers to trust it.
      return 'The HTTPS certificate could not be verified. If '
          '${service.title} uses a self-signed certificate, test again and '
          'confirm the certificate when Cupola offers to trust it.';
    case ServiceFailureReason.unauthorized:
      // The why, not the what again: the title above it already says the key
      // was refused, so this says where the right one comes from.
      return service.usesApiKey
          ? '${service.title} answered, and does not accept this '
                '${service.credentialLabel}. Copy it again from '
                "${service.title}'s own settings."
          : '${service.title} answered, and does not accept this username and '
                'password.';
    case ServiceFailureReason.notFound:
      return 'Reached the server, but the ${service.title} API is not at this '
          'address. Check for a missing or wrong base path.';
    case ServiceFailureReason.redirected:
      // The generic form. A refusal from `SameOriginRedirectInterceptor`
      // carries its own sentence naming the origin it was sent to, and
      // `messageFor` shows that instead; this is what is left when only the
      // reason survived — an unfollowable 3xx from a client that does not
      // explain itself.
      return 'Reached the server, but it answered with a redirect Cupola '
          'will not follow. A reverse proxy in front of ${service.title} is '
          'the usual cause, point Cupola at the address the proxy sends '
          'the request to, or stop it redirecting the API.';
    case ServiceFailureReason.serverError:
      return '${service.title} answered with a server error. Check the '
          'instance and its logs.';
    case ServiceFailureReason.invalidResponse:
      return 'Something answered at this address, but not with anything '
          'Cupola can read as ${service.title}. A reverse proxy page, or '
          'another app on this port, is the usual cause.';
    case ServiceFailureReason.insecureTransport:
      return 'The address starts with http://, so Cupola did not send the '
          '${service.credentialLabel} over it. Change it to https://.';
    case ServiceFailureReason.localNetworkBlocked:
      // Names the device, not the server, and never mentions the address: the
      // request never left this phone, so everything in the form is still
      // unproven rather than wrong. `remedy` spells out the route in the words
      // the running OS uses for it.
      return 'This device is blocking Cupola from reaching your local '
          'network, so ${service.title} was never dialled. '
          '${LocalNetworkPermission.remedy}';
    case ServiceFailureReason.unknown:
    case null:
      return 'The request did not complete. Double-check the address and '
          'credentials.';
  }
}

/// The connection state of one **connection**, refreshed whenever its saved
/// address or credentials change.
///
/// What a form editing a named connection has to read. [serviceDiagnosisProvider]
/// folds every connection of a service into its worst answer, which is right for
/// a row that speaks in services and wrong under a form whose fields belong to
/// exactly one server: it would report "Answering" over the second Radarr's
/// address because the first one is up.
///
/// Carries the same "no local-network gate" caveat as the per-service provider
/// below, and for the same reason.
final instanceDiagnosisProvider =
    FutureProvider.family<ServiceDiagnosis, String>((ref, instanceId) async {
      final settings = ref.watch(currentSettingsProvider);
      final instance = settings.instanceById(instanceId);
      if (instance == null) return const ServiceDiagnosis.notConfigured();
      return diagnoseInstance(instance, settings);
    });

/// The connection state of a single service — folded across every connection it
/// has, so the answer is never better than its worst one. See [diagnoseService].
final serviceDiagnosisProvider =
    FutureProvider.family<ServiceDiagnosis, ServiceKey>((ref, service) async {
      final settings = ref.watch(currentSettingsProvider);
      // Deliberately *not* through `diagnoseThroughLocalNetworkGate`. This runs
      // unattended — on launch, and for every configured service at once — and
      // resolving the permission is not a passive question: on iOS it can put an
      // alert on screen, and it costs a Bonjour round trip per service. Neither
      // belongs in a background refresh nobody asked for.
      //
      // The cost is that a service blocked by the permission reads `Unreachable`
      // in the list rather than naming the permission. It is named the moment the
      // user does the obvious thing — open the service and test it — which is
      // where the fix lives anyway.
      return diagnoseService(service, settings);
    });
