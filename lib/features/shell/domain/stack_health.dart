import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The one-line answer to "is my stack all right", derived once.
///
/// Every surface that prints an aggregate — the Home's line, Stack's header,
/// the services alert band's own headline —
/// reads this, so they cannot disagree about how many services are answering.
/// Four widgets each counting for themselves is how a window ends up saying
/// `14 of 16` in one corner and `2 unreachable` next to `all clear` in another.
///
/// It counts **connections folded per service**, never the lensed summary. With
/// two Radarr and one dark, the lens answers about whichever one it happens to
/// point at and the headline inherits that coin flip. Folding is also the only
/// way this sentence can say the word the design needs:
///
///  * **degraded** — a service whose connections disagree. The service still
///    answers, so calling it unreachable is false, and calling it answering
///    hides the half that is not.
///
/// The arithmetic is deliberate: a degraded service is counted inside
/// [answering] (it *does* answer), so `answering + unreachable == configured`
/// always holds and [degraded] is a qualifier on top rather than a third bucket
/// that stops the numbers adding up. `14 of 16 answering · 1 degraded ·
/// 2 unreachable` is 16 services, not 17.
///
/// This used to be two classes — this one, lens-scoped and unable to say
/// *degraded* or age itself, and a `StackReadout` the Dashboard derived beside
/// it. Two derivations of one sentence is the classic way two surfaces come to
/// disagree the first time one of them is wrong.
///
/// [unreachableServicesProvider] is the same fold projected as *names* instead
/// of a count, and it lives here for the same reason: the alert band used to
/// pick its offenders off the **lensed** summary while this counted the fold,
/// so a two-connection Radarr with the lens on the dark one had the header
/// saying `1 of 1 answering · 1 degraded` and the band directly beneath it
/// saying `Radarr did not answer.` about the service the header had just called
/// answering.
@immutable
class StackHealth {
  const StackHealth({
    required this.configured,
    required this.answering,
    required this.degraded,
    required this.unreachable,
    required this.checking,
    required this.notSetUp,
    this.faulted = 0,
    this.signedOut = 0,
    this.checkedAt,
  });

  /// Services whose only connection is a Seerr account that signed out. Set
  /// up, so never among [notSetUp]; asked nothing, so not in [configured]
  /// either; and not a fault: the person's step.
  final int signedOut;

  /// Services that answered, with at least one connection answering with a
  /// refusal or a fault — a refused key, a 5xx — and none dark. Counted inside
  /// [answering] (they did answer) and named as a qualifier, like [degraded]:
  /// a refused key is not an outage, and the header must not say it is.
  final int faulted;

  /// Services with at least one connection set up. The denominator.
  final int configured;

  /// Services where at least one connection answered. Includes [degraded].
  final int answering;

  /// Services whose connections disagree — some answered, some did not.
  ///
  /// A service with one connection can never land here: the state means
  /// *disagreement*, and one opinion cannot disagree with itself.
  final int degraded;

  /// Services whose every connection is dark.
  final int unreachable;

  /// Services still being asked. **Not a fault**, and never counted as one —
  /// this is what stops the readout crying wolf for the first second of every
  /// cold open.
  final int checking;

  /// Services in the registry nobody has set up. Also not a fault: a stack
  /// without Readarr is not a stack missing Readarr.
  final int notSetUp;

  /// When the last probe settled, for the bucketed age. Null while the first
  /// answers are still coming in — there is no age to print for a reading that
  /// has not happened.
  final DateTime? checkedAt;

  /// Nothing is wrong. Deliberately *not* "everything is green": the header is
  /// neutral when clear, because a badge that is green on almost every open is
  /// one nobody reads on the day it turns red.
  bool get allClear => unreachable == 0 && degraded == 0 && faulted == 0;

  /// `14 of 16 answering`, or `16 of 16 answering` when nothing is wrong.
  ///
  /// Null when nothing set up is asked anything: a stack whose only connection
  /// is a signed-out Seerr read "0 of 0 answering · 1 signed out", a figure
  /// that counts nothing. The qualifiers then carry the line alone.
  String? get headline =>
      configured == 0 ? null : '$answering of $configured answering';

  /// The qualifiers that follow the headline, already in reading order and
  /// omitted when they are zero.
  List<String> get qualifiers => [
    if (degraded > 0) '$degraded degraded',
    // The lexicon's group word for faults (`3 faults`), kept apart from the
    // red count below: a refusal answered.
    if (faulted > 0) '$faulted fault${faulted == 1 ? '' : 's'}',
    if (unreachable > 0) '$unreachable did not answer',
    // Ahead of "not set up" because a probe in flight is about to change the
    // headline and an unconfigured service never will.
    if (checking > 0) '$checking checking',
    if (signedOut > 0) '$signedOut signed out',
    if (notSetUp > 0) '$notSetUp not set up',
  ];

  /// The whole line, spoken and printed the same way.
  String get sentence => [?headline, ...qualifiers].join(' · ');

  /// The line with its age, which is what the Dashboard header draws.
  String sentenceAt(DateTime now) {
    final age = ageLabel(now);
    return [?headline, ...qualifiers, ?age].join(' · ');
  }

  /// `refreshed just now`, `refreshed 6 minutes ago` — **never** seconds.
  ///
  /// A readout that counts seconds invites the reader to watch it count, and the
  /// probes behind this are minutes apart. Null while a probe is still out: the
  /// age of a reading that is being taken right now is not a fact.
  String? ageLabel(DateTime now) {
    final at = checkedAt;
    if (at == null) return null;
    final elapsed = now.difference(at);
    if (elapsed.isNegative || elapsed.inMinutes < 1) {
      return 'refreshed just now';
    }
    final minutes = elapsed.inMinutes;
    if (minutes == 1) return 'refreshed 1 minute ago';
    if (minutes < 60) return 'refreshed $minutes minutes ago';
    final hours = elapsed.inHours;
    if (hours == 1) return 'refreshed 1 hour ago';
    return 'refreshed $hours hours ago';
  }
}

/// How one service's connections folded, as the headline counts them.
///
/// A plain enum rather than a bool pair, so the four states cannot be combined
/// into a fifth that means nothing.
enum StackServiceState {
  /// Every connection answered.
  answering,

  /// Every connection answered, at least one with a refusal or a fault.
  fault,

  /// Some answered and some did not.
  degraded,

  /// None answered.
  unreachable,

  /// The probe has not come back.
  checking,
}

/// Folds one service's connection counts into a single state.
///
/// Pure, and separate from the provider that feeds it, because this is the rule
/// the header is arguing about and a rule inside a provider is a rule nobody can
/// test without a container.
StackServiceState foldServiceState({
  required int total,
  required int offline,
  required int checking,
  int faulted = 0,
}) {
  if (total <= 0) return StackServiceState.checking;
  // Asked before "unreachable": with one answer outstanding we do not yet know
  // whether the disagreement is real, and an unreachable count that flickers on
  // every cold open is the wolf this whole file is avoiding.
  if (checking >= total) return StackServiceState.checking;
  // `offline` counts only what did not answer; a refused key is `faulted`,
  // and it answered.
  if (offline <= 0) {
    return faulted > 0 ? StackServiceState.fault : StackServiceState.answering;
  }
  if (offline >= total) return StackServiceState.unreachable;
  // Reachable here only when `0 < offline < total`, which is why a service with
  // a single connection can never be degraded.
  return StackServiceState.degraded;
}

/// Builds the aggregate from per-service folded states.
///
/// Takes the already-folded states rather than the raw summaries so the counting
/// rule is testable without Riverpod, and so the provider stays the thin part.
StackHealth stackHealthFrom({
  required Iterable<StackServiceState> states,
  required int registrySize,
  int signedOut = 0,
  DateTime? checkedAt,
}) {
  var answering = 0;
  var degraded = 0;
  var faulted = 0;
  var unreachable = 0;
  var checking = 0;
  var configured = 0;

  for (final state in states) {
    configured++;
    switch (state) {
      case StackServiceState.answering:
        answering++;
      case StackServiceState.fault:
        // Counted in `answering` too: a refusal is an answer.
        answering++;
        faulted++;
      case StackServiceState.degraded:
        // Counted in `answering` as well: it answers, partially. See the class
        // doc for why the sum has to close.
        answering++;
        degraded++;
      case StackServiceState.unreachable:
        unreachable++;
      case StackServiceState.checking:
        checking++;
    }
  }

  return StackHealth(
    configured: configured,
    answering: answering,
    degraded: degraded,
    faulted: faulted,
    unreachable: unreachable,
    checking: checking,
    signedOut: signedOut,
    notSetUp: registrySize - configured - signedOut,
    checkedAt: checkedAt,
  );
}

/// The configured services whose **every** connection is dark, by name.
///
/// The band, the inspector card and the sections that print "… did not answer"
/// in place of their empty copy all read this, and it is
/// [StackHealth.unreachable] with the names kept: `length` equals that count by
/// construction, because both walk [foldServiceState] over the same fold. A
/// surface that picked its own offenders off [serviceSummaryProvider] would be
/// asking the *lens* — one connection's opinion standing in for a service — and
/// that is how the header and the line under it came to contradict each other.
///
/// A **degraded** service is deliberately absent: it answered, so naming it here
/// would print "did not answer" about a service that did. Its half-dark state is
/// the header's `degraded` qualifier and its own matrix cell, which reports the
/// worst connection it contains.
///
/// A service still being probed is absent too, for the reason the whole file
/// exists: a band that appears during the first second of every cold open is a
/// band that cried wolf.
final unreachableServicesProvider = Provider<List<ServiceKey>>((ref) {
  final settings = ref.watch(currentSettingsProvider);

  return ServiceKey.values
      .where(settings.isServiceConfigured)
      .where((service) {
        final folded = ref.watch(foldedServiceHealthProvider(service));
        return foldServiceState(
              total: folded.total,
              offline: folded.offline,
              faulted: folded.faulted,
              checking: folded.checking,
            ) ==
            StackServiceState.unreachable;
      })
      .toList(growable: false);
});

/// The live aggregate. Rebuilds when any *connection's* reachability moves.
///
/// A `Notifier` rather than a plain `Provider` for one reason: the timestamp.
/// The counts are derived from the summaries and would recompute happily in a
/// `Provider`, but the *age* of the reading is a fact about when the probes
/// settled, and a `Provider` that called `DateTime.now()` in its body would
/// restamp itself every time any unrelated dependency moved — a readout that
/// claims to have been refreshed "just now" because a theme toggle rebuilt it.
/// A notifier instance survives its own `build`, so it can remember when the
/// last probe actually landed.
final stackHealthProvider = NotifierProvider<StackHealthNotifier, StackHealth>(
  StackHealthNotifier.new,
);

class StackHealthNotifier extends Notifier<StackHealth> {
  DateTime? _checkedAt;

  /// Whether a probe was outstanding the last time this rebuilt. The stamp is
  /// taken on the *transition* to settled, not on every settled build, so a
  /// rebuild caused by something else does not restate the age.
  bool _wasChecking = true;

  @override
  StackHealth build() {
    final settings = ref.watch(currentSettingsProvider);
    final configured = ServiceKey.values
        .where(settings.isServiceConfigured)
        .toList(growable: false);

    final states = <StackServiceState>[];
    for (final service in configured) {
      final folded = ref.watch(foldedServiceHealthProvider(service));
      states.add(
        foldServiceState(
          total: folded.total,
          offline: folded.offline,
          faulted: folded.faulted,
          checking: folded.checking,
        ),
      );
    }

    final checking = states
        .where((state) => state == StackServiceState.checking)
        .length;
    if (checking > 0) {
      _wasChecking = true;
    } else if (_wasChecking || _checkedAt == null) {
      _wasChecking = false;
      _checkedAt = configured.isEmpty ? null : DateTime.now();
    }

    return stackHealthFrom(
      states: states,
      registrySize: ServiceKey.values.length,
      signedOut: ServiceKey.values
          .where(
            (service) =>
                !settings.isServiceConfigured(service) &&
                settings.hasServiceConnection(service),
          )
          .length,
      checkedAt: _checkedAt,
    );
  }
}
