/// The one live figure a service contributes to the stack matrix on
/// `/services`.
///
/// Resolved here rather than in the cell because of the Closed Tone Rule: a
/// widget renders a status, it never derives one.
library;

import 'package:flutter/widgets.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/status/media_status.dart';

/// A service's headline metric, already reduced to something paintable.
///
/// Exactly one of these per cell. It answers "what is this service doing right
/// now", which is a different question from "is it reachable" — the summary
/// answers that.
@immutable
class ServiceSignal {
  /// The metric named in the matrix's own words, e.g. `missing`, `pending`,
  /// `incoming`. Lower case and already singular or plural to match [value].
  ///
  /// Empty when [value] is itself a state word: SABnzbd's paused queue arrives
  /// as the KPI `Status: Paused`, and the cell paints value-then-label, so
  /// carrying the label would print "Paused status" — a column header for a
  /// table this surface does not have.
  ///
  /// Not uppercased, and no longer set in the eyebrow style: casing is the
  /// cell's typography, and screen readers spell out short all-caps tokens they
  /// do not recognise. See [_matrixLabel] for why these words are not simply
  /// the KPI's own.
  final String label;

  /// Preformatted figure, e.g. `12`, `2.4 MB/s`, `94%`.
  final String value;

  /// Small leading glyph, carried over from the source KPI.
  final IconData icon;

  /// How the figure should read. [StatusTone.neutral] means "nothing is asking
  /// for you" and is the resting state of a healthy stack.
  final StatusTone tone;

  const ServiceSignal({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });

  /// Whether this figure is the reason you would look at the cell.
  bool get needsAttention => tone != StatusTone.neutral;

  /// The signal spoken after the service name and its reachability.
  ///
  /// Reads as a sentence rather than as the two visual fragments: the cell
  /// paints `12 missing`, which spoken back in that order is "twelve missing"
  /// only by luck of English word order and becomes nonsense for `2.4 MB/s
  /// incoming`.
  ///
  /// Capitalised because it opens a clause of its own after the reachability
  /// word, and reduced to the bare [value] when there is no label — "Paused"
  /// is already the whole fact.
  String get spoken {
    if (label.isEmpty) return value;
    return '${label[0].toUpperCase()}${label.substring(1)} $value';
  }
}

/// The matrix's word for a metric, where the KPI's own label is wrong *here*.
///
/// A KPI label is written for the per-service peek, where four of them sit in a
/// row and read as column headings. The matrix uses one of them as a phrase
/// beside its figure, in a grid of up to thirteen cells whose other possible
/// live line is the word "Offline" — and that context breaks three of them:
///
///  * **`Down`** is the download *rate*. Beside `Up` on a peek it cannot be
///    misread; on a reachability instrument `2.4 MB/s down` says the service is
///    down. It is the one word this screen cannot borrow, and the KPI builder
///    already knew as much — it flags the rate as *activity*, never as a fault.
///    `incoming` rather than `downloading` because the cell has to fit a rate,
///    an icon and a word into 168pt: measured, `2.4 MB/s downloading` ellipsises
///    to "downloa…" at the *default* reading size, and a truncated word is a
///    worse label than a shorter one.
///  * **`Fails`** is Prowlarr's own truncation, and it is not a noun. The figure
///    counts failed queries.
///  * **`Status`** names a field, not a fact. Its value is already the state
///    word, so the label is dropped entirely rather than printed after it.
///
/// Everything else keeps the service's own vocabulary lower-cased, including
/// terms the audience genuinely knows — Bazarr's `Wanted`, Docker's `Exited`.
/// Plain-languaging those would flatten terminology, not clarify it.
const Map<String, String> _matrixLabelOverrides = {
  'Down': 'incoming',
  'Up': 'outgoing',
  'Fails': 'failures',
  'Status': '',
  // `Streams` is a fine column heading on a four-KPI peek and a poor phrase
  // beside a figure: "2 streams" describes a plural noun the user never thinks
  // in, where "2 streaming" states what the server is doing. It also stays
  // correct at one — "1 streaming" needs no depluralisation, which is why the
  // gerund is chosen over `stream`.
  'Streams': 'streaming',
};

/// Labels that already read the same for one and for many.
const Set<String> _invariantLabels = {'series'};

/// Picks the one KPI worth showing from a service's full KPI list.
///
/// The choice is not a table in this file, and deliberately so. Every KPI
/// builder in `service_kpi_provider.dart` already marks its own noteworthy
/// metric by giving it a non-null [ServiceKpi.tone] — `_backlogIf(missing > 0)`,
/// `_faultIf(activeAlerts > 0)`, `_faultIf(exited > 0)`, and so on. That flag is
/// the domain's own judgment about its own data, written next to the code that
/// computes it — and since it is a [StatusTone] rather than a colour, it also
/// says *what kind* of judgment.
///
/// This file used to re-derive that second half by matching the KPI's label
/// against two sets of strings, with everything unmatched falling through to
/// amber. It was wrong in both directions at once — `Exited` resolved to red
/// and `Missing` to amber — and it was wrong in a way no type could catch,
/// because a service whose builder was added later simply inherited the
/// fallthrough. Reading the tone the builder set is the whole fix.
///
/// So: **the first flagged KPI wins, and the first KPI is the fallback.** A
/// service added to the registry gets a correct live line for free, and the
/// judgment stays in one place instead of being restated here and drifting.
///
/// Returns null only when a service reports no KPIs at all, in which case the
/// cell shows its reachability and nothing else.
/// Kept as the head of [resolveServiceSignalPair] rather than as a second
/// implementation of the same ranking: the deck, the status bar and the picker
/// still ask for one figure, and two functions choosing "the most important KPI"
/// by two rules is how the cell and the deck end up disagreeing about what a
/// service is doing.
ServiceSignal? resolveServiceSignal(List<ServiceKpi> kpis) =>
    resolveServiceSignalPair(kpis)?.primary;

/// The two figures one card carries, each keeping its own tone.
///
/// The card draws two because one was never the whole answer: `2 038 movies` and
/// `34 missing` are a scale and a backlog, and a cell that can only show one has
/// to choose between telling you how big your library is and telling you what is
/// wrong with it. It chose the fault, so a healthy stack's cards all read as
/// bare totals and a stack with a backlog stopped saying how large it was.
///
/// [secondary] is null for a service with one KPI to its name — qBittorrent at
/// `12.4 MB/s incoming` has nothing to put on a second line, and the card keeps
/// its height rather than reserving a slot for an absence.
@immutable
class ServiceSignalPair {
  const ServiceSignalPair({required this.primary, this.secondary});

  /// The headline: the first flagged KPI, or the service's own first metric.
  final ServiceSignal primary;

  /// The next-ranked one, or null when there is no second metric.
  final ServiceSignal? secondary;
}

/// Picks the two figures a stack card shows, in rank order.
///
/// The ranking is the same judgment [resolveServiceSignal] already makes, only
/// written down rather than reduced to its first element: **flagged KPIs first,
/// in the builder's own order, then the rest in the builder's own order.** The
/// primary is therefore exactly what the single-figure card showed, which is
/// what makes this an addition rather than a change — and the secondary is the
/// next thing the builder thought worth computing.
///
/// Each figure keeps *its own* tone. A Radarr with a backlog shows a neutral
/// `2 038 movies` beside a neutral `34 missing`; a Bazarr shows a neutral
/// `47 wanted subs` beside an amber `API key rejected`. Painting both with the
/// worse of the two would be the "one card, one colour" reduction the tone rule
/// exists to prevent.
ServiceSignalPair? resolveServiceSignalPair(List<ServiceKpi> kpis) {
  final ranked = rankServiceKpis(kpis);
  if (ranked.isEmpty) return null;
  return ServiceSignalPair(
    primary: _signalFrom(ranked.first),
    secondary: ranked.length > 1 ? _signalFrom(ranked[1]) : null,
  );
}

/// Flagged first, each group in the builder's own order.
///
/// Exposed rather than inlined because it is the rule both figures are chosen
/// by, and a rule that lives inside a reducer is a rule no test can name.
List<ServiceKpi> rankServiceKpis(List<ServiceKpi> kpis) => [
  ...kpis.where((kpi) => kpi.isNoteworthy),
  ...kpis.where((kpi) => !kpi.isNoteworthy),
];

ServiceSignal _signalFrom(ServiceKpi kpi) => ServiceSignal(
  label: _matrixLabel(kpi.label, kpi.value),
  value: kpi.value,
  icon: kpi.icon,
  // An unflagged KPI is not a judgment, so it resolves to the resting tone
  // rather than borrowing the flagged one's.
  tone: kpi.tone ?? StatusTone.neutral,
);

/// A KPI label as the matrix says it: rewritten where needed, lower case, and
/// agreeing in number with its own figure.
///
/// The plural rule is deliberately mechanical — drop a trailing `s` when the
/// figure parses as exactly 1 — because it has to hold for every service in the
/// registry, including ones added later. `1 alerts` and `1 stacks` were both
/// live before it. A figure that is not a bare integer (`2.4 MB/s`, `85%`,
/// `4/6`, `Paused`) parses to null and is left alone, which is correct: those
/// labels are not counts.
String _matrixLabel(String kpiLabel, String value) {
  final label = _matrixLabelOverrides[kpiLabel] ?? kpiLabel.toLowerCase();
  if (label.isEmpty) return '';
  if (int.tryParse(value) != 1) return label;
  if (_invariantLabels.contains(label) || !label.endsWith('s')) return label;
  return label.substring(0, label.length - 1);
}
