/// One place where a percentage becomes a string.
///
/// Every screen that showed a percentage built it on the spot, and each built
/// it a little differently: `.round()` here, `.floor()` there (so a torrent at
/// 99.6% would not read `100%` while it was still copying), `toStringAsFixed(0)`
/// on a scan, a tenth on one detail page. The same transfer read `63%` on one
/// row and `62%` on the next. There is one rule now, and this is the only file
/// that applies it.
///
/// The rule:
///
///  * **Glued, `62%`.** No space between the figure and the sign, and never a
///    no-break space either: the English convention, and how the services' own
///    screens print it. (The no-break space belongs between a figure and a unit
///    *word or symbol* (`4.4 GB`, `9 h`); the sign is part of the figure.)
///  * **The scale is 0 to 100.** A fraction is multiplied by the caller:
///    `formatPercent(progress * 100)`.
///  * **Nearest whole percent, halves away from zero** (`62.5` reads `63%`,
///    `62.4` reads `62%`), the way `num.round` does.
///  * **`100%` is a claim.** A value short of 100 never reads `100%`: 99.6
///    reads `99%` (and `99.9%` with a tenth), so a transfer that is still
///    copying, a scan still running or a pool with a sliver free is never
///    called complete or full. Only a value of 100 or more reads `100%`. A hair
///    of floating-point noise under 100 (`99.99999999999999`, what a sum of
///    fractions can leave behind) counts as 100.
///  * **A tenth only where the figure is watched at that scale**: the torrent
///    detail page and its file list pass `decimals: 1`, the way qBittorrent's
///    own screen prints them. The ends hold there too: 99.96 reads `99.9%`.
///  * **A figure that is not a number reads `—`**, never `0%`. A caller whose
///    source did not answer prints its own placeholder instead of calling this.
///
/// [wholePercent] is the same rule as an `int`, for a caller that keeps the
/// number (a status that also speaks it, or compares it).
library;

import 'dart:math' as math;

/// The sign that follows the figure. A rating whose scale is a percentage (a
/// Rotten Tomatoes score) carries it as its denominator, and compares against
/// this, so no second file writes a `%` after a number.
const String percentSign = '%';

/// A value within this of 100 counts as 100: floating-point noise, not progress.
const double _noise = 1e-9;

/// The whole percent [percent] reads as: nearest, halves away from zero, and
/// never 100 before 100 (see the library doc).
///
/// [percent] must be finite; [formatPercent] is the one that prints `—` for
/// one that is not.
int wholePercent(num percent) {
  final value = percent.toDouble();
  final rounded = value.round();
  return rounded >= 100 && value < 100 - _noise ? 99 : rounded;
}

/// Renders [percent] (on a 0 to 100 scale) as `62%`, or `62.5%` with
/// [decimals] of 1. See the library doc for the rule.
///
/// Prints `—` when [percent] is not finite.
String formatPercent(num percent, {int decimals = 0}) {
  final value = percent.toDouble();
  if (!value.isFinite) return '—';
  if (decimals <= 0) return '${wholePercent(value)}$percentSign';

  final scale = math.pow(10, decimals).toDouble();
  var shown = (value * scale).round() / scale;
  if (shown >= 100 && value < 100 - _noise) shown = 100 - 1 / scale;
  // `-0.04` rounds to `-0.0`, which prints as `-0.0%`.
  if (shown == 0) shown = 0;
  return '${shown.toStringAsFixed(decimals)}$percentSign';
}
