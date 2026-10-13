import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_known_arr.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_candidate.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// What the connection [id] (a Seerr or a Prowlarr) knows of other services,
/// as candidates, without the ones Cupola is connected to already.
///
/// **Asked of whoever can answer, and never of anyone else.** A Seerr
/// connection is asked only when its account may read the server's settings
/// ([SeerrAbility.readSettings]: the API key, or an administrator): a
/// household member's account is told no by the server, and asking would only
/// learn that. It reads as an empty list here, because this provider answers
/// "which services can this connection offer", and for such an account the
/// answer is none. A Prowlarr connection is always asked, and gives no keys
/// (`ProwlarrKnownApplication`). Every other service knows nothing about the
/// rest of the stack, and is not asked.
///
/// A source that fails to answer throws, classified as any read of it is: an
/// empty list is an answer ("knows none") and never stands in for a silence.
///
/// **Free of any first-run business.** Which candidates are still to be added
/// follows the saved connections (see [withoutConnected]) but the read itself
/// does not: adding a connection re-filters the list without asking the source
/// again, so a surface that keeps this provider after a candidate joined
/// (Set up next, Connections) sees one fewer and costs no request.
///
/// The keys in the candidates are secrets: nothing here prints one, and
/// `ConnectionCandidate.toString` says only that one came.
final knownCandidatesProvider = FutureProvider.autoDispose
    .family<List<ConnectionCandidate>, String>((ref, id) async {
      final settings = ref.watch(currentSettingsProvider);
      final all = await ref.watch(_knownByConnectionProvider(id).future);
      return withoutConnected(all, settings);
    }, retry: noProviderRetry);

/// What the source says, before anything is dropped: the one read of the
/// network. Watches the source connection alone (its address, its way in), so
/// a change to another connection does not ask again.
final _knownByConnectionProvider = FutureProvider.autoDispose
    .family<List<ConnectionCandidate>, String>((ref, id) async {
      final source = ref.watch(
        currentSettingsProvider.select((settings) => settings.instanceById(id)),
      );
      if (source == null) {
        throw StateError('No connection $id to ask what it knows.');
      }
      switch (source.service) {
        case ServiceKey.seerr:
          return withoutRepeats(await _fromSeerr(ref, source));
        case ServiceKey.prowlarr:
          return _fromProwlarr(ref, source);
        default:
          return const [];
      }
    }, retry: noProviderRetry);

Future<List<ConnectionCandidate>> _fromSeerr(
  Ref ref,
  ServiceInstance source,
) async {
  final grant = ref.watch(seerrGrantProvider(source.id));
  if (grant == null || !grant.may(SeerrAbility.readSettings)) return const [];
  final answer = await ref
      .watch(seerrServiceForProvider(source.id))
      .knownServers();
  return switch (answer) {
    SeerrKnownArrsRead(:final servers) => [
      for (final server in servers) ?server.toCandidate(source),
    ],
    // The grant said it may and the server said it may not: the account
    // changed under the saved permissions. Nothing to offer, as for any
    // account that may not.
    SeerrKnownArrsNotAllowed() => const [],
  };
}

Future<List<ConnectionCandidate>> _fromProwlarr(
  Ref ref,
  ServiceInstance source,
) async {
  final applications = await ref
      .watch(prowlarrServiceForProvider(source.id))
      .knownApplications();
  return [
    for (final application in applications) ?application.toCandidate(source),
  ];
}

/// [candidates] with a server listed once.
///
/// A Seerr household often adds one Radarr twice, as its default server and as
/// its 4K one, with different quality profiles and the same address and key.
/// That is one server for Cupola to connect to: the first listing is kept. A
/// candidate with no key (Prowlarr gives none) is never taken for a repeat:
/// nothing but a key says two listings are one server.
List<ConnectionCandidate> withoutRepeats(List<ConnectionCandidate> candidates) {
  final seen = <(ServiceKey, String)>{};
  return [
    for (final candidate in candidates)
      if (candidate.apiKey == null ||
          candidate.apiKey!.isEmpty ||
          seen.add((candidate.service, candidate.apiKey!)))
        candidate,
  ];
}

/// [candidates] without the ones [settings] holds a connection for.
///
/// A candidate is connected already when a connection of its service has:
///
/// - **the same key**, which says the same server whatever the address it is
///   reached at (a household that set one Radarr up by its domain and finds it
///   again through Seerr by its Docker name); or
/// - **the same address**: the one the source reported, or, for a candidate
///   with no key to tell servers apart (Prowlarr gives none), also the one
///   proposed for it. A keyed candidate's *proposed* address does not count:
///   two Radarrs can end on one proposed address (Radarr 4K listening on 7878
///   inside its container and published on 7879), and its own key is what
///   tells it from the one connected there.
///
/// An empty connection (a form half filled) holds neither an address nor a key
/// and matches nothing.
List<ConnectionCandidate> withoutConnected(
  List<ConnectionCandidate> candidates,
  SettingsModel settings,
) => [
  for (final candidate in candidates)
    if (!_isConnected(candidate, settings)) candidate,
];

bool _isConnected(ConnectionCandidate candidate, SettingsModel settings) {
  final key = candidate.apiKey;
  final reported = _addressKey(candidate.reportedUrl);
  final proposed = key == null || key.isEmpty
      ? _addressKey(candidate.proposal?.url)
      : null;
  for (final connection in settings.instancesOf(candidate.service)) {
    if (key != null && key.isNotEmpty && connection.credential == key) {
      return true;
    }
    for (final address in connection.addresses) {
      final held = _addressKey(address);
      if (held == null) continue;
      if (held == reported || held == proposed) return true;
    }
  }
  return false;
}

/// Whether [a] and [b] are one address: the same scheme, host, port and path,
/// whatever the case of the first two, a default port written out or left
/// off, and a trailing slash. False when either names no host.
bool isSameAddress(String? a, String? b) {
  final first = _addressKey(a);
  return first != null && first == _addressKey(b);
}

/// [raw] as one comparable string: scheme, host, explicit port and path, with
/// the case of the first two and a trailing slash taken out. Null for an
/// address that names no host.
String? _addressKey(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final trimmed = raw.trim();
  final uri = Uri.tryParse(
    trimmed.contains('://') ? trimmed : 'https://$trimmed',
  );
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  final port = uri.hasPort ? uri.port : (scheme == 'http' ? 80 : 443);
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return '$scheme://${uri.host.toLowerCase()}:$port$path';
}
