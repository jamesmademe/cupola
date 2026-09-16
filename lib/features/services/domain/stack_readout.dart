/// The Dashboard's header line: one sentence for "is everything all right".
///
/// A sibling of `StackHealth` rather than a replacement for it, and the
/// difference is the unit being counted. `StackHealth` counts *services through
/// the lens* — the right answer for the desktop deck, which shows one glyph per
/// service and cannot say anything about the connections behind it. The header
/// on this page counts **connections folded per service**, which is the only way
/// it can say the word this design needs and that one cannot:
///
///  * **degraded** — a service whose connections disagree. Two Radarr, one dark:
///    the service still answers, so calling it unreachable is false, and calling
///    it answering hides the half that is not.
///
/// The arithmetic is deliberate and it is what the fixture asserts: a degraded
/// service is counted inside [answering] (it *does* answer), so
/// `answering + unreachable == configured` always holds and `degraded` is a
/// qualifier on top rather than a third bucket that makes the numbers not add
/// up. `14 of 16 answering · 1 degraded · 2 unreachable` is 16 services, not 17.
library;

/// The one-line answer, already reduced to counts.
class StackReadout {
  const StackReadout({
    required this.configured,
    required this.answering,
    required this.degraded,
    required this.unreachable,
    required this.checking,
    required this.notSetUp,
    this.checkedAt,
  });

  /// Services with at least one configured connection. The denominator.
  final int configured;

  /// Services where at least one connection answered. Includes [degraded].
  final int answering;

  /// Services whose connections disagree — some answered, some did not.
  final int degraded;

  /// Services where every connection is dark.
  final int unreachable;

  /// Services still being asked. **Not a fault**, and never counted as one:
  /// this is what stops the header crying wolf for the first second of every
  /// cold open.
  final int checking;

  /// Registry entries nobody has set up. Also not a fault.
  final int notSetUp;

  /// When the last probe settled, for the bucketed age. Null while the first
  /// answers are still coming in — there is no age to print for a reading that
  /// has not happened.
  final DateTime? checkedAt;

  /// Nothing is wrong. Deliberately *not* "everything is green": the header is
  /// neutral when clear, because a badge that is green on almost every open is
  /// one nobody reads on the day it turns red.
  bool get allClear => unreachable == 0 && degraded == 0;

  String get headline => '$answering of $configured answering';

  /// The qualifiers after the headline, in reading order, omitted at zero.
  List<String> get qualifiers => [
    if (degraded > 0) '$degraded degraded',
    if (unreachable > 0) '$unreachable unreachable',
    // Ahead of "not set up" because a probe in flight is about to change the
    // headline and an unconfigured service never will.
    if (checking > 0) '$checking checking',
    if (notSetUp > 0) '$notSetUp not set up',
  ];

  /// The whole line, printed and spoken the same way.
  String get sentence => [headline, ...qualifiers].join(' · ');

  /// The line with its age, which is what the phone board draws.
  String sentenceAt(DateTime now) {
    final age = ageLabel(now);
    return [headline, ...qualifiers, ?age].join(' · ');
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

/// How one service's connections folded, as the readout counts them.
///
/// A plain enum rather than a bool pair, so the three states cannot be combined
/// into a fourth that means nothing.
enum StackServiceState {
  /// Every connection answered.
  answering,

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
}) {
  if (total <= 0) return StackServiceState.checking;
  // Asked before "unreachable": with one answer outstanding we do not yet know
  // whether the disagreement is real, and an unreachable count that flickers on
  // every cold open is the wolf this whole file is avoiding.
  if (checking >= total) return StackServiceState.checking;
  if (offline <= 0) return StackServiceState.answering;
  if (offline >= total) return StackServiceState.unreachable;
  return StackServiceState.degraded;
}

/// Builds the readout from per-service folded states.
///
/// Takes the already-folded states rather than the raw summaries so the counting
/// rule is testable without Riverpod, and so the provider stays the thin part.
StackReadout stackReadoutFrom({
  required Iterable<StackServiceState> states,
  required int registrySize,
  DateTime? checkedAt,
}) {
  var answering = 0;
  var degraded = 0;
  var unreachable = 0;
  var checking = 0;
  var configured = 0;

  for (final state in states) {
    configured++;
    switch (state) {
      case StackServiceState.answering:
        answering++;
      case StackServiceState.degraded:
        // Counted in `answering` as well: it answers, partially. See the
        // library doc for why the sum has to close.
        answering++;
        degraded++;
      case StackServiceState.unreachable:
        unreachable++;
      case StackServiceState.checking:
        checking++;
    }
  }

  return StackReadout(
    configured: configured,
    answering: answering,
    degraded: degraded,
    unreachable: unreachable,
    checking: checking,
    notSetUp: registrySize - configured,
    checkedAt: checkedAt,
  );
}
