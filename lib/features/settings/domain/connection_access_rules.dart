import 'dart:convert';

import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What a connection's access may hold, so no clash of headers ever reaches
/// the user as a failure: the app prevents it here, or resolves it in the
/// client (Jellyfin moves its token to `X-Emby-Token` when a proxy holds
/// `Authorization`).
///
/// The words are the Access row's, under the field they are about.

/// Headers the transport or the protocol owns, never offered as custom
/// headers: sending one by hand breaks the request, or the upgrade.
const kReservedAccessHeaders = {
  'host',
  'content-length',
  'content-type',
  'accept',
  'connection',
  'transfer-encoding',
  'upgrade',
  'cookie',
};

/// The most a connection's custom headers may add to every request. Proxies
/// commonly refuse a request whose headers pass 8 KB in all.
const kAccessHeadersLimit = 8 * 1024;

/// The choices the Access row offers for [service], in order: Password only
/// where a proxy's password can travel ([ServiceKeyExtension.offersProxyPassword]).
List<AccessKind> accessKindsFor(ServiceKey service) => [
  for (final kind in AccessKind.values)
    if (kind != AccessKind.password || service.offersProxyPassword) kind,
];

/// Whether [name] is one the transport or the protocol owns.
bool isReservedAccessHeader(String name) {
  final lower = name.trim().toLowerCase();
  return kReservedAccessHeaders.contains(lower) ||
      lower.startsWith('sec-websocket-');
}

/// Whether [name] is a header name as RFC 9110 spells one: a token of
/// letters, digits and `!#$%&'*+-.^_`|~`.
bool isHeaderName(String name) => _token.hasMatch(name);

final _token = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

/// Whether a custom header named [name] is the one [service] carries its own
/// credential in: the clash the Access row offers to resolve by moving the
/// value into the credential field.
bool duplicatesCredentialHeader(ServiceKey service, String name) {
  final own = service.credentialHeader;
  return own != null && own.toLowerCase() == name.trim().toLowerCase();
}

/// The line under a custom header that duplicates [service]'s credential.
String credentialHeaderClash(ServiceKey service) =>
    "Cupola already sends ${service.title}'s ${refusedCredentialOf(service)}. "
    'Move it to the ${service.credentialLabel} field?';

/// What is wrong with the custom header name [name] for [service], or null.
///
/// [earlier] are the names above it in the list, so the second of two names
/// that match reads as the one to remove. A name that duplicates the service's
/// credential header is not wrong here: [credentialHeaderClash] offers its fix.
String? customHeaderNameProblem(
  ServiceKey service,
  String name, {
  Iterable<String> earlier = const [],
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Add a name';
  if (!isHeaderName(trimmed)) return 'Use letters, digits and dashes';
  if (duplicatesCredentialHeader(service, trimmed)) return null;
  if (isReservedAccessHeader(trimmed) ||
      service.ownHeaders.contains(trimmed.toLowerCase())) {
    return 'Cupola sets this header itself';
  }
  final lower = trimmed.toLowerCase();
  if (earlier.any((other) => other.trim().toLowerCase() == lower)) {
    return 'This header is already in the list';
  }
  return null;
}

/// What is wrong with the custom header value [value], or null.
String? customHeaderValueProblem(String value) {
  if (value.isEmpty) return 'Add a value';
  if (value.contains('\r') || value.contains('\n')) {
    return 'Keep the value on one line';
  }
  return null;
}

/// Whether [entries] add more than [kAccessHeadersLimit] to every request.
bool exceedsAccessHeadersLimit(List<AccessHeader> entries) {
  var bytes = 0;
  for (final (:name, :value) in entries) {
    // `Name: value` and the line break after it.
    bytes += utf8.encode(name.trim()).length + utf8.encode(value).length + 4;
  }
  return bytes > kAccessHeadersLimit;
}

/// The line under a header list past [kAccessHeadersLimit].
const kAccessHeadersTooLarge =
    'These headers come to more than 8${unitSpace}KB';

/// What is wrong with a proxy username, or null.
String? proxyUsernameProblem(String username) {
  if (username.isEmpty) return 'Add the username';
  // Basic joins the two halves with a colon, so one in the name splits it.
  if (username.contains(':')) return 'A username cannot contain a colon';
  return null;
}

/// Whether [access] can be saved for [service]: complete, and free of every
/// clash above. The form's validators say which field is wrong; this is the
/// whole answer, for a caller with no field to point at.
bool accessIsValid(ServiceKey service, ConnectionAccess access) =>
    switch (access) {
      NoAccess() => true,
      CloudflareServiceToken(:final clientId, :final clientSecret) =>
        clientId.trim().isNotEmpty && clientSecret.trim().isNotEmpty,
      ProxyPassword(:final username) =>
        service.offersProxyPassword && proxyUsernameProblem(username) == null,
      CustomHeaders(:final entries) =>
        entries.isNotEmpty &&
            !exceedsAccessHeadersLimit(entries) &&
            [
              for (final (index, entry) in entries.indexed)
                customHeaderNameProblem(
                      service,
                      entry.name,
                      earlier: [
                        for (final other in entries.take(index)) other.name,
                      ],
                    ) ??
                    customHeaderValueProblem(entry.value),
            ].every((problem) => problem == null) &&
            !entries.any((e) => duplicatesCredentialHeader(service, e.name)),
    };

/// The Access choice a gateway's remedy opens the connection form on:
/// Cloudflare Access for Access, Password for a proxy's password prompt or a
/// sign-in page (Custom headers where a proxy password cannot travel), the
/// same for a gateway the answer did not name.
AccessKind accessKindForGateway(
  ServiceKey service,
  AccessGatewayAnswer? gateway,
) => switch (gateway?.kind) {
  AccessGatewayKind.cloudflareAccess => AccessKind.cloudflare,
  AccessGatewayKind.passwordPrompt ||
  AccessGatewayKind.signInPage ||
  null => service.offersProxyPassword ? AccessKind.password : AccessKind.custom,
};

/// What the connection test says about a Cloudflare service token it sent,
/// or null when the outcome is not about the token (a wrong address, a
/// refused key), which keeps the test's usual words.
///
/// Three outcomes: Access let it through and the service answered; Access
/// refused it, which is a token no Service Auth policy names, or one that
/// expired; nothing reached Access at all.
String? cloudflareTokenTestOutcome(
  ServiceKey service, {
  required bool answered,
  ServiceFailureReason? reason,
  AccessGatewayAnswer? gateway,
}) {
  if (answered) {
    return 'Access let the token through and ${service.title} answered.';
  }
  if (reason == ServiceFailureReason.accessGateway &&
      gateway != null &&
      gateway.kind == AccessGatewayKind.cloudflareAccess &&
      gateway.credentialsSent) {
    return 'Access did not accept the token: add a Service Auth policy for '
        'it on ${UrlUtils.hostInProse(gateway.serviceHost)}.';
  }
  if (reason == ServiceFailureReason.unreachable) {
    return 'Nothing reached Access.';
  }
  return null;
}

/// The Cloudflare Access team a gateway's answer names
/// (`myteam.cloudflareaccess.com`), or null when it names none: a `401`
/// answered on the service's own host does not say whose Access it is.
String? accessTeamOf(AccessGatewayAnswer? gateway) {
  if (gateway == null || gateway.kind != AccessGatewayKind.cloudflareAccess) {
    return null;
  }
  final host = gateway.gatewayHost.toLowerCase();
  return host.endsWith('.cloudflareaccess.com') ? host : null;
}

/// The offer after a token passed its test, to the connections whose last
/// failure was the same Access team: `Use the same token for Sonarr and
/// Seerr?`.
String sharedTokenOffer(List<String> names) =>
    'Use the same token for ${_joined(names)}?';

/// What the offer says once taken.
String sharedTokenSaved(List<String> names) =>
    'Saved the token for ${_joined(names)}';

String _joined(List<String> names) => switch (names.length) {
  0 => '',
  1 => names.single,
  _ => '${names.take(names.length - 1).join(', ')} and ${names.last}',
};
