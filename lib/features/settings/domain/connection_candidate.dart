import 'package:flutter/foundation.dart';

import 'package:cupola/core/network/found_address.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The service that told Cupola about a candidate, and Cupola's connection
/// to it.
@immutable
class CandidateSource {
  const CandidateSource({
    required this.service,
    required this.connectionId,
    required this.url,
  });

  /// [ServiceKey.seerr] or [ServiceKey.prowlarr].
  final ServiceKey service;

  /// The connection that was asked (`ServiceInstance.id`): two Seerrs can
  /// know two different Radarrs.
  final String connectionId;

  /// The address Cupola reaches the source at: where a host only the source
  /// resolves is proposed instead (`proposeFoundAddress`).
  final String url;

  @override
  bool operator ==(Object other) =>
      other is CandidateSource &&
      other.service == service &&
      other.connectionId == connectionId &&
      other.url == url;

  @override
  int get hashCode => Object.hash(service, connectionId, url);

  @override
  String toString() => 'CandidateSource(${service.name}, $connectionId, $url)';
}

/// A service Cupola has heard of through another one, before it is a
/// connection: one Radarr in Seerr's settings, one Sonarr in Prowlarr's
/// applications.
///
/// **A proposal, never a connection.** It enters Cupola only when it accepts
/// its own key at the address proposed for it ([proposal]), tried from this
/// device. Nothing short of that says which server is there: the source
/// recorded the address as it reaches it, Docker can publish a port under
/// another number (Radarr 4K listening on 7878 inside its container and
/// published on 7879, so "the source's host with the port it knows" is where
/// the other Radarr answers), and two candidates can end on the same proposed
/// address. A candidate whose key is refused at its proposal is the person's
/// to place, by typing its address.
///
/// [apiKey] is a secret: compared, never printed. [toString] says only
/// whether one came.
@immutable
class ConnectionCandidate {
  const ConnectionCandidate({
    required this.service,
    required this.name,
    required this.reportedUrl,
    required this.source,
    this.apiKey,
    this.externalUrl,
    this.is4k = false,
    this.isDefault = false,
  });

  /// What the candidate is.
  final ServiceKey service;

  /// What the source calls it (`Radarr 4K`), or empty when it gave no name.
  final String name;

  /// The address as the source reported it: how the source reaches the
  /// service, not how this device does. `http://radarr:7878`.
  final String reportedUrl;

  /// Where it came from: which service, and which connection to it.
  final CandidateSource source;

  /// The key the source gave for it, or null when it gave none. Seerr gives
  /// the key it uses; Prowlarr never gives one.
  final String? apiKey;

  /// The address the source's admin gave for opening the service in a
  /// browser (Seerr's External URL), or null. Not where the API was found,
  /// and possibly behind a sign-in page; something the person may pick when
  /// the [proposal] is refused.
  final String? externalUrl;

  /// The source sends 4K requests to it (Seerr's 4K server).
  final bool is4k;

  /// The source's default of its kind and resolution.
  final bool isDefault;

  /// The name to show: the source's, or the service's own title when the
  /// source gave none.
  String get displayName => name.isEmpty ? service.title : name;

  /// Whether the source gave a key, so nothing has to be typed if it works.
  bool get hasKey => apiKey != null;

  /// What it is called beside its service once it is a connection, as a label
  /// typed in Connections would be: see [foundLabel].
  String get labelBesideService => foundLabel(service, displayName);

  /// Where it was heard of, and what is left to do: `Seerr knows it · key
  /// found`, or `Prowlarr knows it · paste its key`.
  String get knownLine =>
      '${source.service.title} knows it\u00A0· '
      '${hasKey ? 'key found' : 'paste its key'}';

  /// Where this device should try it: [reportedUrl], or the source's own
  /// host with the reported port when the reported host is one only the
  /// source resolves. Null when the source reported no address that names a
  /// host.
  ProposedAddress? get proposal =>
      proposeFoundAddress(reportedUrl, sourceUrl: source.url);

  @override
  bool operator ==(Object other) =>
      other is ConnectionCandidate &&
      other.service == service &&
      other.name == name &&
      other.reportedUrl == reportedUrl &&
      other.source == source &&
      other.apiKey == apiKey &&
      other.externalUrl == externalUrl &&
      other.is4k == is4k &&
      other.isDefault == isDefault;

  @override
  int get hashCode => Object.hash(
    service,
    name,
    reportedUrl,
    source,
    apiKey,
    externalUrl,
    is4k,
    isDefault,
  );

  /// The service, the name, the address and the source: never the key.
  @override
  String toString() =>
      'ConnectionCandidate(${service.name}, "$name", $reportedUrl, '
      'from ${source.service.name} ${source.connectionId}, '
      'key: ${hasKey ? 'given' : 'none'}'
      '${is4k ? ', 4K' : ''}${isDefault ? ', default' : ''})';
}

/// What a found connection is called beside its service, as a label typed in
/// Connections would be: Seerr's "Radarr 4K" is "4K" next to Radarr, and a
/// name that is only the service's own says nothing to add.
String foundLabel(ServiceKey service, String name) {
  final trimmed = name.trim();
  final title = service.title.toLowerCase();
  final lower = trimmed.toLowerCase();
  if (lower == title) return '';
  if (lower.startsWith('$title ')) {
    return trimmed.substring(title.length).trim();
  }
  return trimmed;
}
