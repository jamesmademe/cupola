/// Where this device should try a service another service told it about.
///
/// Seerr and Prowlarr record the arrs they talk to as **they** reach them. In
/// a Docker stack that is a container name (`http://radarr:7878`), which only
/// the containers on that network resolve; on a single machine it can be
/// `localhost`. Neither means anything from this device. What does is the
/// host Cupola already reaches the source at, with the port and path the
/// source reported: "Seerr's own host, with Radarr's port".
///
/// Pure: the address alone decides, never a lookup. It is a proposal and
/// nothing more. A port Docker republished under another number (Radarr 4K
/// listening on 7878 inside its container and published on 7879) proposes
/// the address where the *other* Radarr answers, and two found services can
/// end on the same proposed address. Which one is there, nothing here can
/// know: only the service accepting its own key at that address can say.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:cupola/core/utils/url_utils.dart';

/// Why a found address is proposed as it is.
enum FoundAddressBasis {
  /// The host is already an address this device may reach (a name with a
  /// domain, an IP address of a real network): proposed as the source
  /// reported it.
  asReported,

  /// The host means something only on the source's own machine or its
  /// container network (a container or Compose name, any single-label host,
  /// `localhost`, a loopback or unspecified address, Docker's and Podman's
  /// names for their own host): proposed on the host Cupola reaches the
  /// source at, with the scheme, port and path the source reported.
  sourceHost,
}

/// The address a found service is proposed at, and why.
@immutable
class ProposedAddress {
  const ProposedAddress({required this.url, required this.basis});

  /// Scheme, host, port and path: `http://nas.home.arpa:7878`.
  final String url;
  final FoundAddressBasis basis;

  /// The host and port, as a sentence names the address:
  /// `nas.home.arpa:7878`. The port is there even when it is the scheme's
  /// own.
  String get hostAndPort {
    final uri = Uri.parse(url);
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    return '$host:${uri.port}';
  }

  /// Trying the found key here would send it in the clear to a host off the
  /// local network (`UrlUtils.cleartextWarning`, which reads the one answer
  /// to whether a host is local). A surface does not try a key at such an
  /// address without the person's say.
  bool get sendsKeyInClear => UrlUtils.cleartextWarning(url) != null;

  @override
  bool operator ==(Object other) =>
      other is ProposedAddress && other.url == url && other.basis == basis;

  @override
  int get hashCode => Object.hash(url, basis);

  @override
  String toString() => 'ProposedAddress($url, ${basis.name})';
}

/// The address this device should try a service at that a source reported
/// at [reported], when Cupola reaches the source at [sourceUrl]. Null when
/// [reported] names no host at all.
///
/// A host that only the source's own machine or network resolves (see
/// [foundHostIsLocalToSource]) moves to the source's host, keeping the
/// reported scheme, port and path. Any other host stays as reported. So does
/// everything when [sourceUrl] names no host: there is nothing to move to.
///
/// A credential written into either address is left out of the answer.
ProposedAddress? proposeFoundAddress(
  String reported, {
  required String sourceUrl,
}) {
  final found = _parse(reported);
  if (found == null) return null;
  final source = _parse(sourceUrl);
  if (source == null || !foundHostIsLocalToSource(found.host)) {
    return ProposedAddress(
      url: found.toString(),
      basis: FoundAddressBasis.asReported,
    );
  }
  return ProposedAddress(
    url: found.replace(host: source.host, port: found.port).toString(),
    basis: FoundAddressBasis.sourceHost,
  );
}

/// Names that Docker and Podman give, inside a container, to the machine the
/// container runs on. No resolver outside one knows them.
const _containerHostNames = {
  'host.docker.internal',
  'gateway.docker.internal',
  'host.containers.internal',
};

/// Whether [host], as a source recorded it, means something only on the
/// source's own machine or its container network, so this device cannot
/// reach it as written:
///
/// - a single label: a container or Compose service name (`radarr`), or a
///   name only the source's resolver knows;
/// - `localhost`, a name under `.localhost`, a loopback address (`127.0.0.1`,
///   `::1`) or an unspecified one (`0.0.0.0`, `::`): the source's own
///   machine;
/// - Docker's and Podman's names for the machine a container runs on
///   (`host.docker.internal`).
///
/// A name with a domain and an IP address of a real network are real
/// addresses and stay. That includes an address on a Docker bridge
/// (`172.17.0.3`): nothing in the address tells it from a LAN's, and the key
/// test at that address settles it.
bool foundHostIsLocalToSource(String host) {
  var bare = host.trim().toLowerCase();
  if (bare.startsWith('[') && bare.endsWith(']')) {
    bare = bare.substring(1, bare.length - 1);
  }
  while (bare.endsWith('.')) {
    bare = bare.substring(0, bare.length - 1);
  }
  if (bare.isEmpty) return false;
  final literal = InternetAddress.tryParse(bare);
  if (literal != null) {
    return literal.isLoopback ||
        literal == InternetAddress.anyIPv4 ||
        literal == InternetAddress.anyIPv6;
  }
  if (bare == 'localhost' || bare.endsWith('.localhost')) return true;
  if (_containerHostNames.contains(bare)) return true;
  return !bare.contains('.');
}

/// [raw] as a URI with a host, its credentials and trailing slashes left
/// out, or null when it names no host.
Uri? _parse(String raw) {
  final normalized = UrlUtils.normalizeBaseUrl(
    UrlUtils.withoutCredentials(raw),
  );
  if (normalized.isEmpty) return null;
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.isEmpty) return null;
  return uri;
}
