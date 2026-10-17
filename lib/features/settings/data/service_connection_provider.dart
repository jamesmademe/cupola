import 'dart:async';

import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/utils/url_utils.dart';

/// Represents the reachability state of a configured service.
///
/// *Why* a service is disconnected lives in `ServiceDiagnosis` alongside this,
/// in `service_verification.dart`: this enum answers only "is it up".
enum ServiceConnectionStatus {
  notConfigured,
  checking,
  connected,
  disconnected,
}

/// The outcome of probing an origin for a certificate the platform does not
/// already trust.
///
/// [rotated] is the one field that changes how the caller must present this:
/// true means this origin already had a *different* pin, so the certificate
/// presented today is not the one the user trusted before. That is the
/// shape a real interception would take, and it must read as an escalation,
/// never as a routine first-time trust prompt (see ADR-6).
typedef UntrustedCertificateProbe = ({
  ServerCertificate certificate,
  bool rotated,
});

/// What probing a failed `https://` address found: a certificate to offer,
/// or a port that is not TLS at all.
sealed class TlsFinding {
  const TlsFinding();
}

/// A certificate the platform does not trust and no pin covers, for the
/// person to look at and trust (trust-on-first-use).
final class UntrustedCertificate extends TlsFinding {
  const UntrustedCertificate(this.probe);

  final UntrustedCertificateProbe probe;
}

/// The port answered a plain http request: the address says https, and the
/// port serves http (`answersPlainHttp`). There is no certificate to offer.
final class PlainHttpPort extends TlsFinding {
  const PlainHttpPort();
}

/// The shape of [probeUntrustedCertificate], so a caller that reaches it from
/// a widget can accept one as an optional constructor parameter and default
/// to the real function.
///
/// Exists because under ADR-6 *every* disconnected, probe-worthy failure
/// reaches this, not just the rare TrueNAS/Dockge case ADR-5 confined it
/// to, and the probe opens a real [SecureSocket], which `flutter_test`
/// cannot intercept the way it does an `HttpClient` (the framework's own
/// warning about raw sockets is not idle: this is exactly the socket it
/// means). A widget test now needs a fake here to stay offline and
/// deterministic; production code never passes one.
typedef CertificateProber =
    Future<TlsFinding?> Function(String rawUrl, {String pinnedFingerprint});

/// Probes [rawUrl]'s origin after a failed test: for a TLS certificate that
/// is not trusted by the platform and not already pinned as
/// [pinnedFingerprint], so the UI can offer to trust it (trust-on-first-use),
/// and for a port that answers plain http, which no certificate explains.
/// Null when the URL is not TLS, the certificate already validates, it
/// matches the current pin, or nothing at the port says anything. Never
/// trusts anything itself.
///
/// The two questions go out together. A port that serves http answers the
/// plain one in milliseconds, while its TLS handshake can only wait for its
/// deadline (qBittorrent and Bazarr wait for a request line a TLS hello never
/// sends), so its answer is taken at once. A port that serves https never
/// answers it as an http server (`isPlainHttpAnswer`), and the certificate
/// is then waited for.
Future<TlsFinding?> probeUntrustedCertificate(
  String rawUrl, {
  String pinnedFingerprint = '',
}) async {
  final endpoint = tlsEndpointFor(rawUrl);
  if (endpoint == null) return null;
  final certificate = _untrustedCertificateAt(
    endpoint.host,
    endpoint.port,
    pinnedFingerprint: pinnedFingerprint,
  );
  // Settled either way, so the one not waited for never surfaces an error.
  unawaited(certificate.then((_) {}, onError: (_) {}));
  if (await answersPlainHttp(endpoint.host, endpoint.port)) {
    return const PlainHttpPort();
  }
  return certificate;
}

Future<TlsFinding?> _untrustedCertificateAt(
  String host,
  int port, {
  required String pinnedFingerprint,
}) async {
  try {
    final validates = await certificateValidatesByDefault(host, port);
    // Certificate is fine; any failure is unrelated (auth, wrong URL, …).
    if (validates) return null;
    final cert = await probeServerCertificate(host, port);
    if (cert == null) return null;
    final pin = pinnedFingerprint.trim().toLowerCase();
    if (cert.fingerprint.toLowerCase() == pin) {
      // Already pinned: the failure is something else.
      return null;
    }
    return UntrustedCertificate((certificate: cert, rotated: pin.isNotEmpty));
  } catch (_) {
    // Server unreachable / DNS / refused / a handshake that broke off: no
    // certificate to show.
    return null;
  }
}

/// Resolves [rawUrl] to the host/port a TLS probe or a pinned client should
/// connect to, or null when it cannot carry a certificate at all.
///
/// Thin wrapper around [UrlUtils.certOrigin]. That is the single place the
/// scheme/default-port rule lives; this just unpacks its canonical
/// `https://host:port` string back into the parts a socket call needs.
({String host, int port})? tlsEndpointFor(String rawUrl) {
  final origin = UrlUtils.certOrigin(rawUrl);
  if (origin == null) return null;
  final uri = Uri.parse(origin);
  return (host: uri.host, port: uri.port);
}
