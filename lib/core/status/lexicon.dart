import 'package:cupola/core/status/media_status.dart';

/// The product's state words: one word per state, the same on every screen.
///
/// The brand book's lexicon (`design/system/README.md`, *Words*) as code, so
/// a screen reaches for the state rather than spelling it. The tone is the
/// one the word carries under the tone rule, and null for a word that carries
/// no state. The failure words — `Did not answer`, `Radarr answered but
/// refused the key` and the rest — are the classification's
/// (`failureLabel`, `failureHeadline` in `core/network/connection_failure.dart`),
/// which spells [StateWord.didNotAnswer] from here.
///
/// `test/core/theme/lexicon_guard_test.dart` scans `lib/` for the words the
/// brand book's *Never* list bans, so a variant cannot come back unnoticed.
enum StateWord {
  /// The service replied to the last check.
  answering('Answering', StatusTone.success),

  /// Nothing replied at its address. The only red words, never contracted.
  didNotAnswer('Did not answer', StatusTone.error),

  /// No address or key yet. The control stays tappable and names the service
  /// ([Lexicon.setUp]).
  notSetUp('Not set up', null),

  /// The group of faults and approvals waiting for the operator.
  needsYou('Needs you', StatusTone.warning),

  /// Nothing has arrived for a while.
  stuck('Stuck', StatusTone.warning),

  /// It ended and cannot finish by itself.
  failed('Failed', StatusTone.warning),

  /// Someone stopped it on purpose. Not a fault, never "stuck".
  stopped('Stopped', StatusTone.neutral),

  /// The backlog: released and not on disk.
  missing('Missing', StatusTone.neutral),

  /// The backlog: still looked for.
  wanted('Wanted', StatusTone.neutral),

  /// The backlog: below its profile.
  cutoffUnmet('Cutoff unmet', StatusTone.neutral),

  /// The backlog: an episode not aired yet.
  notAired('Not aired', StatusTone.neutral),

  /// The backlog: a film not out yet.
  notOutYet('Not out yet', StatusTone.neutral),

  /// A request nobody has approved yet.
  waitingForApproval('Waiting for approval', StatusTone.info),

  /// Away, with no away address: nothing was asked.
  homeOnly('Home only', StatusTone.neutral);

  const StateWord(this.label, this.tone);

  /// The word as a label or a chip reads it: `Stuck`.
  final String label;

  /// The tone it carries, or null for a word with no state.
  final StatusTone? tone;

  /// The word inside a sentence or after a count: `3 stuck`,
  /// `Big Buck Bunny is stuck`, `2 did not answer`.
  String get inline => Lexicon.inline(label);
}

/// The verbs and fixed phrases that have one spelling.
abstract final class Lexicon {
  /// Send the same request again, offered only where the same request can
  /// still succeed (`failureRetryHelps`): never after a refused key, and never
  /// beside an `http://` address nothing was sent to. `Run again` is a
  /// different action: it re-runs a scheduled task.
  static const retry = 'Retry';

  /// A figure whose source did not answer. Never `0`.
  static const noFigure = '—';

  /// A count that is only the least there is: `200+`. A walk across pages
  /// that stopped on a full page with no total to say whether another
  /// followed has counted rows, not the set, and a figure taken from them is
  /// a floor, never the total.
  static String floor(int count) => '$count+';

  /// A figure as the ear should hear it: a floor (`200+`) is `at least 200`,
  /// where a screen reader says "200 plus" or drops the mark. Anything else
  /// is left as it is.
  static String spokenFigure(String figure) {
    final match = _floorFigure.firstMatch(figure);
    return match == null ? figure : 'at least ${match.group(1)}';
  }

  static final _floorFigure = RegExp(r'^(\d[\d,]*)\+$');

  /// An empty answer, and only after the source answered.
  static const noResults = 'No results';

  /// A film's three dated events, as every screen that dates one names them:
  /// the calendar's `Sprite Fright · on digital` and the Radarr home's Coming
  /// up, `on digital · monitored`. Coming up used to say `digital release`
  /// and `physical release` for the same two dates.
  static const inCinemas = 'in cinemas';
  static const onDigital = 'on digital';
  static const onDisc = 'on disc';

  /// The way into a service's setup form — the one verb every "not set up"
  /// row, button and toast carries: `Set up Plex`.
  static String setUp(String service) => 'Set up $service';

  /// A service with no address or key yet, as a sentence: `Plex is not set
  /// up`.
  static String isNotSetUp(String service) => '$service is not set up';

  /// Names in a sentence: `Radarr`, `Radarr and Sonarr`, `Radarr, Sonarr and
  /// Seerr`.
  static String names(Iterable<String> names) {
    final all = names.toList(growable: false);
    if (all.length < 2) return all.join();
    return '${all.sublist(0, all.length - 1).join(', ')} and ${all.last}';
  }

  /// A label as it reads inside a sentence or after a count — `Refused the
  /// key` → `refused the key` — leaving an acronym alone (`API not at this
  /// address`).
  static String inline(String label) {
    if (label.length < 2) return label.toLowerCase();
    final second = label[1];
    if (second.toUpperCase() == second && second.toLowerCase() != second) {
      return label;
    }
    return label[0].toLowerCase() + label.substring(1);
  }
}
