import 'package:flutter/material.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';

/// A connection state resolved into everything the UI needs to render it: a
/// tone from the closed vocabulary, a glyph, and words.
///
/// Resolved here rather than inside the rows and banners that draw it, so the
/// settings home, the connections list and the service form cannot describe the
/// same failure three different ways.
class ConnectionPresentation {
  const ConnectionPresentation({
    required this.tone,
    required this.icon,
    required this.label,
    required this.needsAttention,
  });

  /// From the shared [StatusTone] vocabulary; resolve to a colour with
  /// `statusToneColor`.
  final StatusTone tone;

  final IconData icon;

  /// A few words naming the state, short enough for a list row.
  final String label;

  /// Whether this state is worth promoting to the user. False for healthy and
  /// for never-configured services — the settings home stays quiet unless
  /// something is actually wrong.
  final bool needsAttention;
}

/// The words a connection's label gains when it answers with a credential
/// narrower than the service's writes: `read-only key`, `view-only account`,
/// `limited key`, `shared account`. Null when there is nothing to add.
///
/// Only answers the service gave (or a refusal it made) qualify the label. A
/// probe that could not ask says nothing here: "Answering · read-only key"
/// would state a fact nobody established. Green stays green — a narrow
/// credential is configuration, not a fault — so this changes the words and
/// never the tone.
String? credentialScopeQualifier(ServiceKey service, CapabilityGrant grant) {
  if (!service.hasScopedCredential) return null;
  if (grant.basis == CapabilityBasis.unanswered) return null;
  final noun = service.capabilityCredentialNoun;
  if (grant.scopeFor(null).isRestricted) {
    return service == ServiceKey.nginxProxyManager
        ? 'view-only $noun'
        : 'read-only $noun';
  }
  if (grant.writable != null) {
    // A Plex token that reads the server and not who is watching belongs to
    // an account the owner shared the server with, and Plex users know that
    // as a shared account rather than as a narrower token.
    return service == ServiceKey.plex ? 'shared account' : 'limited $noun';
  }
  return null;
}

/// Describes a connection state for [service].
///
/// The split between `warning` and `error` is triage, not decoration, and it is
/// the five-arm tone rule applied to reachability: amber is a **fault** — the
/// host was reached, so there is one concrete thing to go and fix — and red is
/// reserved for a host that did not answer at all. Everything that got a reply,
/// however bad the reply was, is amber; red is the one word the user cannot act
/// on from the form, so spending it on a fault costs the distinction.
///
/// The label vocabulary is closed and deliberately small. "Slow" is not in it:
/// a request that ran out of time is reported as timed out, because "slow"
/// invites the user to wait rather than to look at the server.
ConnectionPresentation describeConnection(
  ServiceKey service, {
  required ServiceConnectionStatus status,
  ServiceFailureReason? reason,
  AccessGatewayAnswer? gateway,
}) {
  switch (status) {
    case ServiceConnectionStatus.notConfigured:
      return ConnectionPresentation(
        tone: StatusTone.neutral,
        icon: Icons.add_link_rounded,
        label: StateWord.notSetUp.label,
        needsAttention: false,
      );
    case ServiceConnectionStatus.checking:
      return const ConnectionPresentation(
        tone: StatusTone.neutral,
        icon: Icons.cloud_sync_rounded,
        label: 'Checking',
        needsAttention: false,
      );
    case ServiceConnectionStatus.connected:
      return ConnectionPresentation(
        tone: StatusTone.success,
        icon: Icons.cloud_done_rounded,
        label: StateWord.answering.label,
        needsAttention: false,
      );
    case ServiceConnectionStatus.disconnected:
      // A disconnection nobody attributed is the host that did not answer:
      // that is what the state meant before it carried reasons at all.
      final failure = describeFailure(
        service,
        reason ?? ServiceFailureReason.unreachable,
        gateway: gateway,
      );
      return ConnectionPresentation(
        tone: failure.tone,
        icon: failure.icon,
        label: failure.label,
        needsAttention: true,
      );
  }
}

/// What a refusal of [service]'s credential names as the thing refused:
/// `key`, `token` (Plex), or `sign-in` for the services that take a username
/// and a password.
String refusedCredentialOf(ServiceKey service) {
  if (!service.usesApiKey) return kRefusedSignIn;
  return service == ServiceKey.plex ? 'token' : kRefusedCredential;
}

/// A failure resolved into everything a surface draws: its tone, a glyph, the
/// short label, the fault sentence's title and its remedy.
///
/// The one place a failure turns into pixels and words. The Dashboard's cells,
/// a service's header, the settings rows, Activity's band and a page's failure
/// leaf all read this, so one failure is one set of words everywhere (the brand
/// book's twelfth rule) and red is spent on nothing but a host that did not
/// answer.
class FailurePresentation {
  const FailurePresentation({
    required this.reason,
    required this.tone,
    required this.icon,
    required this.label,
    required this.headline,
    required this.remedy,
  });

  final ServiceFailureReason reason;

  /// Red for a host that did not answer, amber for every fault.
  final StatusTone tone;

  final IconData icon;

  /// A few words: `Did not answer`, `Refused the key`.
  final String label;

  /// What happened, naming who: `Radarr answered but refused the key`.
  final String headline;

  /// The verb that fixes it in the connection's form (`Paste the key again`),
  /// or null when `Retry` is the remedy.
  final String? remedy;

  /// Nothing replied — the only red state.
  bool get didNotAnswer => failureDidNotAnswer(reason);
}

/// Describes [reason] for [service]. [subject] names who in the headline, and
/// defaults to the service: pass a connection's name (`Radarr 4K`) when there
/// is more than one.
///
/// The tone split is triage, not decoration. Amber is a **fault** — the host
/// was reached, or the device would not dial, so there is one concrete thing to
/// go and fix — and red is reserved for a host that did not answer at all.
/// Everything that got a reply, however bad the reply was, is amber; red is the
/// one word the user cannot act on from the form, so spending it on a fault
/// costs the distinction. In particular:
///
///  * a **timeout** is amber because it means the host was *reached* and then
///    ran out of time (see [ServiceFailureReason.timeout]); a connection that
///    never completed is `unreachable`, and red;
///  * a **5xx** is the service speaking — reachable, configured and trusted —
///    so red would hide that the address and the key are already right;
///  * a **blocked local network** is amber and never red: nothing is wrong with
///    the address, the server or the credentials, and red would send the user
///    auditing settings that are already correct.
///
/// "Slow" is not in the vocabulary: a request that ran out of time is reported
/// as timed out, because "slow" invites the user to wait rather than to look.
///
/// [gateway] names what answered in front of the service for an
/// [ServiceFailureReason.accessGateway]; [describeFailureOf] reads it, and the
/// reason, off the failure itself.
FailurePresentation describeFailure(
  ServiceKey service,
  ServiceFailureReason reason, {
  String? subject,
  AccessGatewayAnswer? gateway,
}) {
  final credential = refusedCredentialOf(service);
  return FailurePresentation(
    reason: reason,
    tone: failureTone(reason),
    icon: failureIcon(reason),
    label: failureLabel(reason, credential: credential, gateway: gateway),
    headline: failureHeadline(
      reason,
      subject: subject ?? service.title,
      credential: credential,
      gateway: gateway,
    ),
    remedy: failureRemedy(reason, credential: credential, gateway: gateway),
  );
}

/// [describeFailure] for the failure [error] itself: its classification, and
/// the gateway it names when one answered.
FailurePresentation describeFailureOf(
  ServiceKey service,
  Object? error, {
  String? subject,
}) => describeFailure(
  service,
  classifyConnectionFailure(error),
  subject: subject,
  gateway: accessGatewayOf(error),
);

/// A section of a page whose read failed, in one line: what happened, then
/// what the page is without because of it — `Unraid did not answer, so its
/// shares are not shown.`
///
/// The first half is [describeFailure]'s headline, so a refused key reads as
/// a refusal (amber) and only silence reads as silence (red). The sections
/// that draw this used to say "Failed to load shares" in red for every
/// failure, which blamed reachability for a key the service had just refused.
/// Hand the same [error] to the widget that draws it, so its glyph takes the
/// same tone as these words.
String sectionFailureMessage(
  ServiceKey service,
  Object? error, {
  required String consequence,
  String? subject,
}) {
  final headline = describeFailureOf(service, error, subject: subject).headline;
  return '$headline, so $consequence.';
}

/// Why a write to [service] failed, as the second sentence of its toast:
/// `Could not decline this request. Seerr answered but refused the key.
/// Nothing changed.`
///
/// The toasts used to guess — "The service may be unreachable." — for every
/// failure, which blamed reachability for a refusal and sent the user to check
/// a server that had just answered. A refused write says that nothing changed,
/// because that is the one thing the user needs to know about it.
String writeFailureReason(
  ServiceKey service,
  Object? error, {
  String? subject,
}) {
  final reason = classifyConnectionFailure(error);
  final headline = describeFailureOf(service, error, subject: subject).headline;
  return reason == ServiceFailureReason.unauthorized
      ? '$headline. Nothing changed.'
      : '$headline.';
}

/// What an address field owes [service] before anything is sent, when the
/// scheme itself is the problem — null when there is nothing specific to say
/// (the general `UrlUtils.cleartextWarning` still applies).
///
/// The form-side half of [ServiceFailureReason.insecureTransport]. Two
/// services have a reason of their own:
///
///  * **TrueNAS** refuses `http://` outright. 25.04 and later revoke a key
///    that arrives over cleartext, so the client never dials it; the field says
///    so while it is typed rather than after a test that sends nothing.
///  * **SABnzbd** carries its key inside the address (`?apikey=`), so over
///    `http://` off the local network the key is not only readable on the way
///    but written into every proxy's access log.
String? transportWarningFor(ServiceKey service, String rawUrl) {
  final value = rawUrl.trim().toLowerCase();
  final cleartext = value.startsWith('http://') || value.startsWith('ws://');
  if (!cleartext) return null;
  if (service == ServiceKey.truenas) {
    return const TrueNasInsecureTransportException().failureDetail;
  }
  if (service == ServiceKey.sabnzbd &&
      UrlUtils.cleartextWarning(rawUrl) != null) {
    return 'This address is off your local network, and SABnzbd sends its '
        'API key inside the address itself: over http:// it can be read on '
        "the way and is kept in every proxy's log. Use https:// if the "
        'instance supports it.';
  }
  return null;
}

/// The glyph beside a failure's words. Its colour is the failure's tone.
IconData failureIcon(ServiceFailureReason reason) => switch (reason) {
  ServiceFailureReason.unreachable => Icons.cloud_off_rounded,
  ServiceFailureReason.unauthorized ||
  ServiceFailureReason.secretUnread => Icons.key_off_rounded,
  // The account's own door, not a broken key: blue, the person's step.
  ServiceFailureReason.sessionEnded => Icons.logout_rounded,
  ServiceFailureReason.csrfRefused => Icons.remove_moderator_rounded,
  ServiceFailureReason.notFound => Icons.wrong_location_rounded,
  // Kept apart from `notFound` because the thing to go and fix is the proxy in
  // front of the service, not the address in the form.
  ServiceFailureReason.redirected => Icons.alt_route_rounded,
  // A lock with someone behind it: access, not the service's own key.
  ServiceFailureReason.accessGateway => Icons.lock_person_rounded,
  ServiceFailureReason.localNetworkBlocked => Icons.wifi_lock_rounded,
  ServiceFailureReason.tls => Icons.gpp_bad_rounded,
  ServiceFailureReason.timeout => Icons.timer_off_rounded,
  ServiceFailureReason.serverError => Icons.report_gmailerrorred_rounded,
  ServiceFailureReason.invalidResponse => Icons.code_off_rounded,
  ServiceFailureReason.insecureTransport =>
    Icons.no_encryption_gmailerrorred_rounded,
  ServiceFailureReason.unknown => Icons.error_outline_rounded,
};

/// The version a service reported during a connection test, resolved into a
/// line to print under the outcome.
///
/// [isWarning] is the whole reason this is a type rather than a string: a
/// version can turn a passing test into a qualified one, and a caveat rendered
/// in the same quiet grey as everything else is a caveat nobody reads.
class ServerVersionNote {
  const ServerVersionNote(this.message, {this.isWarning = false});

  final String message;
  final bool isWarning;
}

/// What the outcome of a test should say about the version the server named,
/// or null when it named nothing.
///
/// Resolved here, beside [describeConnection], for the reason that function
/// exists: the walk and the service form report the same test, and the version
/// is exactly the kind of detail one of them would otherwise learn to phrase
/// differently.
ServerVersionNote? describeServerVersion(ServiceKey service, String? version) {
  final reported = version?.trim();
  if (reported == null || reported.isEmpty) return null;

  if (service == ServiceKey.truenas) {
    final parsed = TrueNasVersion.parse(reported);
    // Only a version that parses *and* falls short earns the warning. An
    // unparseable string fails open, the same way `TrueNasVersion.parse` does
    // everywhere else — guessing "unsupported" from a string we cannot read
    // would put a caveat on a working server.
    if (parsed != null && !parsed.isSupported) {
      return ServerVersionNote(
        'Running $reported. Cupola supports SCALE $kTrueNasMinVersion or '
        'newer, some sections will be unavailable.',
        isWarning: true,
      );
    }
  }

  return ServerVersionNote('Running $reported.');
}
