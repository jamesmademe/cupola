/// Accessible strings for the `/services` tab.
///
/// Pure and Flutter-free on purpose: a label composed inside a `build` method
/// and asserted in a test is two strings that drift. Everything a screen reader
/// says on this tab is built here, so the widget and the test read one source.
library;

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/percent_format.dart';

/// Joins the non-empty parts with the comma both screen readers read as a short
/// pause.
///
/// Delegates to [joinDisplayParts]: the same trimming and empty-dropping the
/// visible strings already get, with a separator meant for the ear rather than
/// the eye. A part that arrives as a visible figure (`62%`) is spelled out
/// (`62 percent`) on the way: units are words in anything a screen reader says.
String joinSpokenParts(Iterable<String?> parts) => joinDisplayParts([
  for (final part in parts) part == null ? null : spokenPercents(part),
], separator: ', ');

/// Re-separates a visually dot-joined string for speech.
///
/// `·` is decoration: iOS reads it as "middle dot" or drops it depending on the
/// user's punctuation verbosity, and neither is what the layout meant.
String spokenFromDotted(String visual) => joinSpokenParts(visual.split('·'));

/// What one cell in the stack matrix announces after its service name.
///
/// Reachability first because it gates everything else, then the live signal:
/// the reason the cell is worth reading, then the host to disambiguate two
/// instances of the same service.
///
/// [signalSpoken] arrives already phrased as `label value` ("Missing 12") rather
/// than in the cell's visual order ("12 MISSING"): the cell leads with the figure
/// because the eye scans a column of numbers, but read aloud that order only
/// happens to work in English for counts and collapses entirely for a rate
/// ("2.4 MB/s Down"). It is null while the KPI is still resolving, and on an
/// unreachable service that has no signal to report.
/// [secondarySpoken] is the card's second figure, which exists for the same
/// reason the first does and is spoken in the same breath: a screen-reader user
/// who hears only "34 missing" has been told the fault and not the scale.
///
/// [instanceLabel] is the `×2` the card draws for a multi-connection service,
/// spoken as words: "×2" is read as "times two" or skipped entirely depending on
/// the reader's punctuation verbosity, and neither is "two connections".
String serviceMatrixCellValue({
  required String statusLabel,
  required String? signalSpoken,
  required String host,
  String? secondarySpoken,
  String? instanceLabel,
}) => joinSpokenParts([
  statusLabel,
  signalSpoken,
  secondarySpoken,
  instanceLabel,
  host,
]);

/// `two connections`: the spoken form of the card's `×N` chip.
String serviceInstanceCountLabel(int count) {
  if (count <= 1) return '';
  final word = switch (count) {
    2 => 'two',
    3 => 'three',
    4 => 'four',
    _ => '$count',
  };
  return '$word connections';
}

/// The cell for a service nobody has set up: `Readarr: Not set up · Add it`.
///
/// An unconfigured service is a **cell in the band**, not a footnote under the
/// matrix. The footnote it replaces was dismissible, which meant the stack could
/// permanently claim to be everything the user runs while hiding one of its own
/// rows; and it was one line for all of them, so it could not say *which*. A
/// dimmed cell in the domain it belongs to says both, and leads somewhere.
const String servicesNotSetUpCellLabel = 'Not set up · Add it';

/// What a stack card says when the service answered and its figures did not.
/// The card shows an em dash; this is the spoken form of it.
const String servicesFiguresUnavailableLabel = 'figures unavailable';

/// The STACK region header: `Stack · 16 · 1 more to set up`.
///
/// The count is the whole registry, not the configured subset, which is the
/// point: the region is the inventory of what this app can talk to, and the
/// trailing clause is how many of them are still dark.
String servicesStackHeaderValue({
  required int registrySize,
  required int notSetUp,
}) => joinSpokenParts([
  '$registrySize services',
  if (notSetUp > 0)
    notSetUp == 1 ? '1 more to set up' : '$notSetUp more to set up',
]);

/// A domain band's permanent health line: `4 of 5 clean · Bazarr degraded`.
///
/// Permanent, where the line it replaces appeared only while the band was folded,
/// so retiring the fold would have deleted the one place a band said anything
/// about itself. `clean` counts the services in the band that are answering and
/// have nothing flagged; the qualifiers name the ones that do, at most two,
/// because a band header is not a list. [notSetUp] is said after them, never
/// folded into their `1 other`: a service not set up is not one that needs a
/// look.
String serviceDomainHealthLine({
  required int clean,
  required int total,
  List<String> qualifiers = const [],
  int onlyAtHome = 0,
  int notSetUp = 0,
  int maxNamed = 2,
}) {
  final named = qualifiers.where((q) => q.trim().isNotEmpty).toList();
  final shown = named.length <= maxNamed
      ? named
      : [
          ...named.take(maxNamed),
          named.length - maxNamed == 1
              ? '1 other'
              : '${named.length - maxNamed} others',
        ];
  return [
    '$clean of $total clean',
    ...shown,
    // Counted, never named: away from home, not asked.
    if (onlyAtHome > 0) '$onlyAtHome ${StateWord.onlyAtHome.inline}',
    if (notSetUp > 0) '$notSetUp not set up',
  ].join(' · ');
}

/// What one decision row announces after its title.
///
/// Composed here, like every other string on this tab, so the row and the test
/// read one source. The action verb is last because it is what the user does
/// *after* deciding the row is the one they want.
String decisionRowSpokenValue({
  required String serviceTitle,
  required String detail,
  required String actionLabel,
}) => joinSpokenParts([serviceTitle, spokenFromDotted(detail), actionLabel]);

/// The × that acknowledges an outage notice.
///
/// Names the outage rather than the gesture: the row holds a Retry and a
/// dismiss, and "Dismiss" alone leaves a screen-reader user to guess which of
/// the two they are on: where one re-checks the connection and the other
/// hides the notice.
String servicesDismissAlertLabel(
  List<String> offlineServiceTitles, {
  SilenceScope scope = SilenceScope.asked,
}) =>
    'Dismiss: ${servicesAlertBandMessage(offlineServiceTitles, scope: scope)}';

/// What a folded domain band announces, after its name.
///
/// Just the size of the group. A folded band used to replace its cells with a
/// strip of bare glyphs, so this had to carry the health those unlit tiles
/// showed silently; the compact cards that replaced the strip are labelled
/// nodes of their own, each announcing its own service, reachability and
/// figure. Repeating "Lidarr isn't answering" on the header as well would make
/// a screen reader say it twice on the way into the band.
String serviceDomainBandValue({required int serviceCount}) {
  final noun = serviceCount == 1 ? 'service' : 'services';
  return '$serviceCount $noun';
}

/// The alert band's sentence, used **both** on screen and by the screen reader.
///
/// One string for both because this is the one place a paraphrase would be a
/// real defect: the band exists to name which services stopped answering, so a
/// visible list and a spoken count that disagree would each be a different bug
/// report.
///
/// Names at most [maxNamed] services and folds the rest into "and n others": a
/// stack where nine services are down would otherwise produce a band taller than
/// the grid it is warning about.
///
/// Uses "and" rather than [joinSpokenParts]'s comma: a trailing comma list read
/// aloud ("Dockge, TrueNAS") sounds truncated, as though the sentence lost its
/// last item.
String servicesAlertBandMessage(
  List<String> offlineServiceTitles, {
  int maxNamed = 3,
  SilenceScope scope = SilenceScope.asked,
}) {
  final clause = servicesDidNotAnswer(
    offlineServiceTitles,
    maxNamed: maxNamed,
    scope: scope,
  );
  return clause.isEmpty ? '' : '$clause.';
}

/// Where the silent services were asked, which the silence's sentence says.
enum SilenceScope {
  /// At the address in use: `Radarr and Sonarr did not answer`.
  asked,

  /// Every one of them at both of its addresses, at home and away:
  /// `Radarr did not answer at home or away`.
  atBoth,

  /// Every service is silent, and at least one was asked at both of its
  /// addresses: the phone is offline, or the server is down. `No service
  /// answered, at home or away`.
  nothingAnywhere,
}

/// The band's sentence as a clause, without its full stop: `Radarr and
/// Sonarr did not answer`, and ` at 20:53` when the probe that found them
/// silent is [at]. The Home's Needs you leads with it.
///
/// [since] is when they stopped answering (`SilenceClock`), the latest of
/// them: from a minute before [at], the clause says that instead, `Radarr
/// has not answered since 20:41`, which tells a restart from an outage. A
/// silence no older than the probe says only when the probe asked.
///
/// [scope] says where they were asked: at both of their addresses, `Radarr
/// did not answer at home or away`, or every service at all, `No service
/// answered, at home or away`. Neither takes the time, which `at home or
/// away` would run into.
String servicesDidNotAnswer(
  List<String> offlineServiceTitles, {
  int maxNamed = 3,
  DateTime? at,
  DateTime? since,
  SilenceScope scope = SilenceScope.asked,
}) {
  final titles = offlineServiceTitles
      .where((t) => t.trim().isNotEmpty)
      .toList();
  if (titles.isEmpty) return '';

  // Past tense, and the settled vocabulary: a probe is a thing that happened,
  // and "isn't answering" claims a present-tense fact about a box nobody has
  // asked in the last minute. `did not answer` is what the States sheet's
  // unreachable leaf says, and this is the sentence the alert band, the section
  // empty states and the screen reader all share.
  const verb = 'did not answer';
  final subject = servicesNamed(titles, maxNamed: maxNamed);

  switch (scope) {
    case SilenceScope.nothingAnywhere:
      return 'No service answered, at home or away';
    case SilenceScope.atBoth:
      return '$subject $verb at home or away';
    case SilenceScope.asked:
      break;
  }
  if (since != null &&
      at != null &&
      at.difference(since) >= const Duration(minutes: 1)) {
    final has = titles.length == 1 ? 'has' : 'have';
    return '$subject $has not answered since ${formatClockTime(since)}';
  }
  return at == null
      ? '$subject $verb'
      : '$subject $verb at ${formatClockTime(at)}';
}

/// [titles] as the subject of one sentence: `Radarr`, `Radarr and Sonarr`,
/// `Radarr, Sonarr and Lidarr`, and past [maxNamed] the rest counted:
/// `Radarr, Sonarr and 6 others`. The band's and a module's failure sentences
/// name their services this way, silent or failing alike.
String servicesNamed(List<String> titles, {int maxNamed = 3}) {
  if (titles.isEmpty) return '';
  if (titles.length <= maxNamed) {
    return titles.length == 1
        ? titles.single
        : '${titles.take(titles.length - 1).join(', ')} and ${titles.last}';
  }
  final hidden = titles.length - maxNamed;
  final others = hidden == 1 ? '1 other' : '$hidden others';
  return '${titles.take(maxNamed).join(', ')} and $others';
}

/// The alert band's second sentence, on a surface wide enough to carry it.
///
/// It is the consequence, which is the part the first sentence leaves the reader
/// to work out: a dark SABnzbd does not just fail to answer, it takes its share
/// of every figure on this page with it. The phone prints the first sentence
/// only: there is one line of room, and the name of the service is the half
/// that cannot be dropped.
const String servicesAlertBandDetail =
    'Anything they hold is missing from this page.';

/// The alert band's retry, which names how many services it re-probes.
///
/// `Retry both` when exactly two are dark, because that is what the button does
/// and "Retry" beside two named services reads as an offer to retry one of them.
/// Above two it goes back to the bare verb: "Retry all four" is a sentence, not
/// a button.
String servicesRetryLabel(int count) => count == 2 ? 'Retry both' : 'Retry';

/// What a dashboard section says when its sources came back empty because they
/// did not answer.
///
/// Shares the alert band's sentence so the two never disagree about the same
/// fact, but names at most two services: this sits inside a 176pt rail, not
/// across the full width, and it is a footnote to a band the user has already
/// scrolled past rather than the primary warning.
///
/// Cross-service sections could not say this at all before. They degrade to `[]`
/// per source, so an unreachable Radarr and an empty library arrived identically
/// and both printed the empty copy: sending the user to look for missing media
/// when the answer was a missing connection. Naming *which* sources are dark is
/// what makes it safe for a merged rail; the old design could only blame a
/// single declared service, so it stayed silent instead.
String servicesSectionOfflineMessage(List<String> offlineServiceTitles) =>
    servicesAlertBandMessage(offlineServiceTitles, maxNamed: 2);

/// What one Downloading row announces after its title.
///
/// Warning first, then the progress the user came for, then the release detail
/// last so it can be interrupted. On screen the progress bar and the "75%" sit
/// in sibling subtrees; here they are one field.
///
/// [percent] is null when the client reports no progress, and is simply absent
/// then, the row paints nothing in that slot either, and the section is already
/// headed "Downloading".
///
/// [warning] is the client's own message ("Download stalled", "Not an upgrade"),
/// spoken in full. It used to be a bool that produced the bare word "Warning",
/// which named that something was wrong without saying what, while the actual
/// reason sat unused in the model. The visible pill is still a scan marker
/// because there is no room for a sentence in it; the reason lives one tap away
/// on `/activity`, and now also in the ear.
String downloadRowValue({
  required String subtitle,
  required int? percent,
  required String? warning,
}) => joinSpokenParts([
  warning,
  percent == null ? null : '${spokenPercent(percent)} downloaded',
  spokenFromDotted(subtitle),
]);
