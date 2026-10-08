/// Needs you: the one line at the top of the operator's Home that says what is
/// wrong, how many more things are, and the way in.
///
/// It reads what the Home already holds: the services whose every connection
/// stayed silent, and the decisions the stack is waiting on, less the requests.
/// A request is somebody waiting politely, blue and never amber; it has its own
/// module. What is left is a fault, something that was working and stopped.
///
/// **Who leads.** A service that did not answer first, because its own faults
/// cannot be seen while it is silent; then the largest group of equal faults,
/// because eighteen downloads that need the same import are the most work
/// waiting in one place. Equal sizes keep the order the decisions were ranked in
/// (`rankDecisions`: worst kind, then oldest).
///
/// **The way in.** The line never runs a remedy itself. Silence leads to Retry,
/// the one thing a person can do about a service that did not answer from here;
/// a fault leads to Review, which opens the place the fault is fixed today.
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

@immutable
class NeedsYou {
  const NeedsYou._({
    required this.line,
    required this.more,
    this.silent = const [],
    this.lead,
  });

  /// The services that did not answer, when they lead. Empty when a fault does.
  final List<ServiceKey> silent;

  /// The fault that leads, when no service is silent.
  final DashboardDecision? lead;

  /// What the line says: `18 downloads need a manual import`, `Radarr did not
  /// answer at 20:53`.
  final String line;

  /// How many more things need the person, after the lead: the chip's `+2`.
  final int more;

  /// Whether a silent service leads: red, and Retry.
  bool get leadsWithSilence => silent.isNotEmpty;

  /// The control's word.
  String get action =>
      leadsWithSilence ? servicesRetryLabel(silent.length) : 'Review';

  /// The one sentence a screen reader hears: `18 downloads need a manual
  /// import, and 2 more things need you. Review`.
  String get spoken {
    final rest = switch (more) {
      0 => '',
      1 => ', and 1 more thing needs you',
      _ => ', and $more more things need you',
    };
    return '$line$rest. $action';
  }
}

/// What Needs you says, or null when nothing does.
///
/// [silent] are the services whose every connection did not answer, found
/// silent by the probe that settled at [silentAt]. [decisions] are the stack's,
/// already folded and ranked; [floor] when a walk stopped before the queue's
/// end, so a group's count is at least what it says. [now] dates a
/// certificate's expiry.
NeedsYou? needsYouOf({
  required List<ServiceKey> silent,
  required List<DashboardDecision> decisions,
  required DateTime now,
  DateTime? silentAt,
  bool floor = false,
}) {
  final faults = [
    for (final decision in decisions)
      if (decision.isFault) decision,
  ];
  if (silent.isNotEmpty) {
    return NeedsYou._(
      silent: silent,
      line: servicesDidNotAnswer([
        for (final service in silent) service.title,
      ], at: silentAt),
      more: faults.length,
    );
  }
  if (faults.isEmpty) return null;

  // Largest group first; the sort is decorated with the rank, because
  // `List.sort` is not stable and equal groups would trade places between
  // builds.
  final ranked =
      List.generate(
        faults.length,
        (index) => (index: index, decision: faults[index]),
        growable: false,
      )..sort((a, b) {
        final bySize = b.decision.count.compareTo(a.decision.count);
        return bySize != 0 ? bySize : a.index.compareTo(b.index);
      });
  final lead = ranked.first.decision;
  return NeedsYou._(
    lead: lead,
    line: needsYouLine(lead, now: now, floor: floor),
    more: faults.length - 1,
  );
}

/// The sentence one fault leads Needs you with.
///
/// A sentence and not a row's title and detail: the line is read once, in one
/// breath, and `Big Buck Bunny · Stuck · qBittorrent` is a row's way of
/// speaking. A group says how many and what they share.
String needsYouLine(
  DashboardDecision decision, {
  required DateTime now,
  bool floor = false,
}) {
  final count = floor ? Lexicon.floor(decision.count) : '${decision.count}';
  if (decision.count > 1) {
    return switch (decision.kind) {
      DecisionKind.importBlocked => '$count downloads need a manual import',
      DecisionKind.stalledDownload =>
        decision.transferFailed
            ? '$count downloads failed'
            : '$count downloads are stuck',
      // Never grouped (see `groupDecisions`); said anyway, so the switch is
      // total.
      DecisionKind.failedImport => '$count imports failed',
      DecisionKind.failingIndexer => '$count indexers are failing',
      DecisionKind.stoppedStack => '$count stacks stopped',
      DecisionKind.expiringCertificate => '$count certificates are expiring',
      DecisionKind.pendingRequest => '$count requests wait for approval',
    };
  }
  final title = decision.title;
  return switch (decision.kind) {
    DecisionKind.importBlocked => '$title needs a manual import',
    DecisionKind.stalledDownload =>
      decision.transferFailed ? 'Could not download $title' : '$title is stuck',
    DecisionKind.failedImport => 'Could not import $title',
    DecisionKind.failingIndexer => 'The $title indexer is failing',
    DecisionKind.stoppedStack => 'The $title stack stopped',
    DecisionKind.expiringCertificate => _certificateLine(
      title,
      decision.occurredAt,
      now,
    ),
    DecisionKind.pendingRequest => '$title waits for approval',
  };
}

/// `The certificate for nas.home.arpa expires in 6 days`. The decision dates
/// a certificate by its expiry.
String _certificateLine(String host, DateTime? expiresOn, DateTime now) {
  final subject = 'The certificate for $host';
  if (expiresOn == null) return '$subject is expiring';
  final days = expiresOn.difference(now).inDays;
  if (days < 0) return '$subject expired';
  if (days == 0) return '$subject expires today';
  if (days == 1) return '$subject expires tomorrow';
  return '$subject expires in $days days';
}
