import 'package:flutter/material.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';

/// A single key metric shown in a [ServiceKpiPeek] rail.
///
/// Kept transport-agnostic: each service builds its own list of KPIs from
/// whatever data it already has loaded, so the peek stays a pure presentation
/// concern.
@immutable
class ServiceKpi {
  /// Short uppercase-friendly label (e.g. "Missing", "Down").
  final String label;

  /// Preformatted value string (e.g. "128", "2.4 MB/s", "94%").
  final String value;

  /// Small leading icon.
  final IconData icon;

  /// How this figure reads, and whether it reads at all.
  ///
  /// `null` is the resting state: an ordinary metric that nobody needs to look
  /// at, drawn in the service accent like its three neighbours. A non-null tone
  /// means the builder that computed this number decided it is the reason you
  /// would open the service, and says in the same breath *which kind* of
  /// reason, which is the part the old `Color? accent` could not carry:
  ///
  ///  * [StatusTone.neutral]: backlog. 34 films are missing. Worth surfacing,
  ///    not worth colouring; this is the normal resting state of an \*arr.
  ///  * [StatusTone.warning]: a fault. An indexer is failing, a pool is at 80%.
  ///    A stopped stack is backlog, not a fault: Dockge cannot say why it stopped.
  ///  * [StatusTone.info]: activity. Bytes are moving, someone is watching.
  ///
  /// It used to be a raw `Color?`, which conflated *noteworthy* with *amber*:
  /// every flagged metric was painted `AppColors.warning`, so a library with a
  /// backlog and a server with a dying disk were the same colour, and the tone
  /// the matrix cell showed had to be re-derived downstream by matching the
  /// label against a set of strings. Now the judgement travels with the number.
  final StatusTone? tone;

  /// A second line under the figure, in the figure's own words.
  ///
  /// Only ever the *reason* a number is not what you expect: `client not
  /// answering` under an unavailable queue. Not a trend, not a unit, not a
  /// restatement of the label.
  final String? note;

  /// The titles a library count counts, by an identity every connection of
  /// the service agrees on: a film's TMDB id, a series' TVDB id, an artist's
  /// MusicBrainz id. Null for a figure that is not a count of titles.
  ///
  /// What lets a fold across two libraries count once a film both hold: an
  /// HD and a 4K Radarr usually hold the same films, and the sum of their two
  /// film counts is a count of copies, stated as a count of films. A title
  /// with no shared identity stands for itself, so it is never merged with
  /// another.
  final Set<Object>? members;

  /// Whether this figure is the reason you would look at the service.
  bool get isNoteworthy => tone != null;

  const ServiceKpi({
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
    this.note,
    this.members,
  });

  /// A figure whose source did not answer.
  ///
  /// Reads **`—`**, and this is the rule the whole constructor exists to
  /// enforce: a number that could not be fetched is not zero. The builders used
  /// to write `_statInt(map) ?? 0`, so a download client that was down drew
  /// `Queue 0`: indistinguishable from a queue that had just drained, and the
  /// reading the user would act on is the opposite one. The other outcome was
  /// worse: letting the sub-fetch throw took the entire rail into `AsyncError`
  /// and lost the eight figures the service *could* still answer.
  ///
  /// [note] names what did not answer, because "—" on its own is a shrug.
  /// Pair it with `FaultBand.section`, which carries the same fact in a
  /// sentence for the page as a whole.
  ///
  /// Deliberately untoned. The absence is not this service's fault and not a
  /// backlog either; colouring it would make a neighbour's outage look like a
  /// condition of the service you are looking at.
  const ServiceKpi.unavailable({
    required this.label,
    required this.icon,
    this.note,
  }) : value = unavailableValue,
       tone = null,
       members = null;

  /// What an unanswered figure prints. An em dash, never `0` and never blank:
  /// a blank cell reads as a layout bug.
  static const String unavailableValue = '—';

  /// Whether this figure's source did not answer.
  bool get isUnavailable => value == unavailableValue;

  /// What a screen reader hears for the whole card.
  ///
  /// The em dash is the one character on the rail that assistive technology
  /// cannot render usefully: VoiceOver reads it as "dash" or skips it, so the
  /// figure that matters most is the figure that announced worst. Spelled out,
  /// with the reason attached. A floor (`200+`) says `at least 200` for the
  /// same reason ([Lexicon.spokenFigure]).
  String get semanticLabel {
    final spoken = isUnavailable ? 'unavailable' : Lexicon.spokenFigure(value);
    return note == null ? '$label: $spoken' : '$label: $spoken, $note';
  }
}
