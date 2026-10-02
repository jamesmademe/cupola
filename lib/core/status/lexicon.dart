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

  /// The operator put the title on Seerr's blocklist, so Seerr takes no
  /// request for it. A deliberate choice, not a fault. The state, never the
  /// action: the arrs' "blocklist and search" verb stays banned.
  blocklisted('Blocklisted', StatusTone.neutral),

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

  /// A Seerr account's session ended: it went unused for 30 days, it was
  /// signed out elsewhere, or the account was removed. A step that falls to
  /// the person, never a fault, so blue. The operator reads `Signed out of
  /// Seerr`; the requester reads `You were signed out` ([Lexicon.youWereSignedOut]).
  /// The remedy is [Lexicon.signInAgain].
  signedOut('Signed out', StatusTone.info),

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

  /// [StateWord.signedOut] as the requester reads it, a sentence about
  /// themselves.
  static const youWereSignedOut = 'You were signed out';

  /// The remedy of an ended session, and of a refused sign-in.
  static const signInAgain = 'Sign in again';

  /// Who a Seerr connection is signed in as: `Signed in as Anna`. Never
  /// `Connected as`.
  static String signedInAs(String name) => 'Signed in as $name';

  /// Ending an account's session, on the server and on this device.
  static const signOut = 'Sign out';

  // The requester's words: what will happen to a request, never how, and
  // never a service name.

  /// A request that waits on whoever runs the server, under a disabled
  /// Request: [StateWord.waitingForApproval] as a sentence.
  static final requestWaiting = '${StateWord.waitingForApproval.label}.';

  /// Approved, and on its way to the server. Seerr cannot see the download,
  /// so this is all it can say.
  static const onItsWay = 'On its way.';

  /// The last request for a title failed on the stack, and the server takes
  /// no other while it stands. The requester cannot fix it, and is told who
  /// can.
  static const lastRequestFailed =
      "The last request didn't go through. Whoever runs the server can send "
      'it again.';

  /// A title the operator barred: a choice, never a fault.
  static const blockedByOwner =
      'Whoever runs the server has blocked requests for this title.';

  /// Under the request sheet of an account whose requests wait for whoever
  /// runs the server.
  static const approvedByOwner =
      'Requests on this server are approved by its owner.';

  /// Under the request sheet of an account whose requests are approved as
  /// they are made.
  static const startStraightAway = 'Your requests start straight away.';

  /// A request Seerr refused because one is there already.
  static const alreadyRequested = 'Already requested.';

  /// A request for a series Seerr made nothing of: every season is on the
  /// server or asked for already.
  static const noSeasonsLeft =
      'Every season is already on the server or requested.';

  /// A failure as the requester reads it, whatever its cause: the server
  /// ([subject], `the server`, or the player she watches with) and since when
  /// ([time], `20:41`). Never the service's name or the classification.
  static String cantReachSince(String subject, String time) =>
      "Can't reach $subject since $time";

  /// What [youWereSignedOut] asks of the requester.
  static const signInToKeepAsking =
      'Sign in again to keep asking for movies and series.';

  /// Taking back one's own request while it still waits for approval: the
  /// same call as the operator's delete, named for what it is to its owner.
  static const cancelRequest = 'Cancel request';

  /// Seerr's 401 on cancelling a request that is no longer waiting.
  static const noLongerCancellable =
      "It was already approved, so it can't be cancelled here.";

  /// After a write the requester asked for failed: nothing half happened.
  static const nothingChanged = 'Nothing changed.';

  /// The requester's Seerr, where its name would be: the global search's
  /// lane and its filter.
  static const requestsLane = 'Requests';

  /// The search for something to ask for, before a word is typed: the
  /// requester's global search and Discover's own field.
  static const searchToAsk = 'Search movies and series';

  /// What the requester's search finds: titles to ask for, and on [players]
  /// (`Jellyfin`, `Jellyfin or Plex`) titles to watch.
  static String searchToAskHint(String? players) => players == null
      ? 'Enter a title to find something to ask for.'
      : 'Enter a title to find something to ask for, or to watch on '
            '$players.';

  /// The requester's list of requests, while it is empty.
  static const yourRequestsAppearHere = 'Requests you make will appear here.';

  /// A request that failed for a reason the requester cannot act on: what
  /// did not happen, and that nothing half happened.
  static String couldNotAskFor(String? title) =>
      "Could not ask for ${title ?? 'this title'}. Nothing was sent.";

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
