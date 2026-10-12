/// How old a reading is, in the one vocabulary the whole app uses to say it.
///
/// Five surfaces had already answered this question privately and none of them
/// agreed: the desktop status bar (since gone) bucketed to `just now / N min ago / N h ago`,
/// the Activity feed spelled out seconds, the Prowlarr history rounded
/// differently again, and two more rolled their own on the spot. A figure whose
/// age is printed in four vocabularies on four screens is a figure the user
/// cannot compare across them, which is the whole reason to read an age at all.
///
/// ## Why it buckets
///
/// The precision is deliberately thrown away. A dashboard polls on a timer, so
/// a live-to-the-second age is a number that changes under the reader's eye and
/// forces a repaint of the whole band every second for information nobody acts
/// on. What the operator needs from an age is one of three judgements: *this
/// is current*, *this is minutes old*, *this is stale enough to distrust*, and
/// three buckets carry all three. Under a minute the answer is "just now",
/// because the difference between four seconds and fifty is not a difference
/// anyone makes a decision on.
///
/// Hours never roll up into days on purpose. A reading eleven hours old is not
/// "yesterday", it is *broken*, and printing `1 d ago` would round a failure
/// into a habit.
library;

import 'package:cupola/core/utils/unit_space.dart';

/// The age of [sampledAt] as of [now], bucketed: `just now`, `N min ago`,
/// `N h ago`.
///
/// [now] is injectable so a test can state an age instead of sleeping for one.
/// A timestamp in the future: a host whose clock runs ahead, which self-hosted
/// stacks produce constantly; clamps to `just now` rather than printing a
/// negative minute count.
String formatSampleAge(DateTime sampledAt, {DateTime? now}) {
  return formatDurationAge((now ?? DateTime.now()).difference(sampledAt));
}

/// [formatSampleAge] over an elapsed duration that the caller already holds.
String formatDurationAge(Duration elapsed) {
  final minutes = elapsed.inMinutes;
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '${withUnit(minutes, 'min')} ago';
  return '${withUnit(minutes ~/ 60, 'h')} ago';
}

/// The same age as a *span*, for a sentence that reads "no response for …"
/// rather than "… ago".
///
/// Separate from [formatDurationAge] because English will not let one string do
/// both jobs: "No response for 6 min ago" is not a sentence, and neither is
/// "last answer 6 minutes". The two forms are the same buckets with different
/// grammar, which is exactly the kind of near-duplication that ends up
/// diverging when it is left to the call site.
///
/// Returns `null` under a minute: a service that stopped answering forty
/// seconds ago has not yet earned a duration in a sentence, and the caller
/// prints the age-free form instead.
String? formatElapsedSpan(Duration elapsed) {
  final minutes = elapsed.inMinutes;
  if (minutes < 1) return null;
  if (minutes < 60) return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  final hours = minutes ~/ 60;
  return '$hours ${hours == 1 ? 'hour' : 'hours'}';
}
