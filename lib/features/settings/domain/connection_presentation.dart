import 'package:flutter/material.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
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

/// Describes a connection state for [service].
///
/// The split between `warning` and `error` is triage, not decoration: amber
/// means the server answered and the credentials or the path are wrong — fixable
/// in the form — while red means nothing answered at all.
ConnectionPresentation describeConnection(
  ServiceKey service, {
  required ServiceConnectionStatus status,
  ServiceFailureReason? reason,
}) {
  switch (status) {
    case ServiceConnectionStatus.notConfigured:
      return const ConnectionPresentation(
        tone: StatusTone.neutral,
        icon: Icons.add_link_rounded,
        label: 'Not set up',
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
      return const ConnectionPresentation(
        tone: StatusTone.success,
        icon: Icons.cloud_done_rounded,
        label: 'Answering',
        needsAttention: false,
      );
    case ServiceConnectionStatus.disconnected:
      return switch (reason) {
        ServiceFailureReason.unauthorized => ConnectionPresentation(
          tone: StatusTone.warning,
          icon: Icons.key_off_rounded,
          label: service.usesApiKey ? 'API key rejected' : 'Sign-in rejected',
          needsAttention: true,
        ),
        ServiceFailureReason.notFound => const ConnectionPresentation(
          tone: StatusTone.warning,
          icon: Icons.wrong_location_rounded,
          label: 'API not at this address',
          needsAttention: true,
        ),
        // Amber, not red: the server answered and the handshake succeeded.
        // Kept apart from `notFound` because the thing to go and fix is the
        // proxy in front of the service, not the address in the form.
        ServiceFailureReason.redirected => const ConnectionPresentation(
          tone: StatusTone.warning,
          icon: Icons.alt_route_rounded,
          label: 'Redirected elsewhere',
          needsAttention: true,
        ),
        // Amber, and never red: nothing is wrong with the address, the server
        // or the credentials — the OS simply has not been told Cupola may talk
        // to this network. Red here would send the user auditing settings that
        // are already correct, which is the exact failure this state exists to
        // stop.
        ServiceFailureReason.localNetworkBlocked =>
          const ConnectionPresentation(
            tone: StatusTone.warning,
            icon: Icons.wifi_lock_rounded,
            label: 'Local network blocked',
            needsAttention: true,
          ),
        ServiceFailureReason.tls => const ConnectionPresentation(
          tone: StatusTone.warning,
          icon: Icons.gpp_bad_rounded,
          label: 'Certificate not trusted',
          needsAttention: true,
        ),
        ServiceFailureReason.timeout => const ConnectionPresentation(
          tone: StatusTone.error,
          icon: Icons.timer_off_rounded,
          label: 'Timed out',
          needsAttention: true,
        ),
        ServiceFailureReason.serverError => const ConnectionPresentation(
          tone: StatusTone.error,
          icon: Icons.report_gmailerrorred_rounded,
          label: 'Answered with an error',
          needsAttention: true,
        ),
        ServiceFailureReason.unreachable ||
        ServiceFailureReason.unknown ||
        null => const ConnectionPresentation(
          tone: StatusTone.error,
          icon: Icons.cloud_off_rounded,
          label: 'Unreachable',
          needsAttention: true,
        ),
      };
  }
}

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
        'newer — some sections will be unavailable.',
        isWarning: true,
      );
    }
  }

  return ServerVersionNote('Running $reported.');
}
