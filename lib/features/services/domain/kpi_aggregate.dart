/// Folding one service's KPIs across all of its connections.
///
/// The Dashboard's stack card for a multi-connection service draws `×N` and,
/// beside it, the fleet's figures. Before this existed it drew `×N` beside the
/// *lensed* connection's figures — the lens wearing the fleet's clothes, and a
/// number that is wrong by exactly however much the other servers hold.
///
/// **The rule is mostly a refusal to aggregate.** Three clauses, and the second
/// two are the ones that matter:
///
///  * **Counts and byte rates sum.** Two libraries of 900 and 1 138 films are
///    2 038 films, and two clients pulling 2.0 MB/s and 512 KB/s are pulling
///    2.5 MB/s. These are the only units where addition means anything.
///  * **Percentages, ratios and state words do not.** They keep the lens,
///    because the mean of two disk-usage percentages is a number describing no
///    disk, `4/6` plus `3/9` is not a fraction of anything, and `Paused` plus
///    `Downloading` is not a state.
///  * **The aggregate is never partial.** A term that did not answer takes the
///    whole figure to `—`, and a connection that could not be read at all takes
///    the whole fold away. A sum missing a term is worse than no sum: it looks
///    like a sum.
///
/// The arithmetic is done on the *rendered* strings rather than on the numbers
/// behind them, because [ServiceKpi] is where the figures already are and the
/// alternative is threading a second, numeric channel through all seventeen
/// builders. For counts that is exact. For rates it inherits the two
/// significant digits the ladder in `byte_format.dart` prints — which is the
/// resolution the card shows anyway, so the sum is as precise as the thing it
/// is displayed next to.
library;

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/byte_format.dart';

/// Folds the KPI lists of every connection of one service into one list.
///
/// [perConnection] is **lens first**, then the rest in settings order; the lens
/// is what a figure falls back to when its unit cannot be added. A `null` entry
/// means that connection could not be read — see [ServiceKpi.unavailable] for
/// the same rule one level down.
///
/// Returns null when the fold cannot be formed at all:
///
///  * nothing to fold;
///  * any connection unreadable — never partial;
///  * the lists disagree about what they are reporting. Two connections of one
///    service run the same builder, so a mismatch means one of them answered
///    something else entirely, and folding by position would add a film count
///    to a disk percentage.
///
/// One connection folds to itself, so the caller never has to know whether it
/// is looking at one server or six.
List<ServiceKpi>? aggregateServiceKpis(List<List<ServiceKpi>?> perConnection) {
  if (perConnection.isEmpty) return null;
  if (perConnection.any((kpis) => kpis == null)) return null;

  final lists = perConnection.cast<List<ServiceKpi>>();
  final lens = lists.first;
  if (lists.length == 1) return lens;

  for (final other in lists.skip(1)) {
    if (other.length != lens.length) return null;
    for (var i = 0; i < lens.length; i++) {
      if (other[i].label != lens[i].label) return null;
    }
  }

  return [
    for (var i = 0; i < lens.length; i++)
      _foldOne([for (final list in lists) list[i]]),
  ];
}

/// One figure, folded across the connections that reported it. Lens first.
ServiceKpi _foldOne(List<ServiceKpi> terms) {
  final lens = terms.first;

  // A term that did not answer is not a zero, so the sum it belongs to did not
  // answer either. The label survives — the row still says which figure is
  // missing — and the note names what did not answer.
  if (terms.any((term) => term.isUnavailable)) {
    return ServiceKpi.unavailable(
      label: lens.label,
      icon: lens.icon,
      note: _sharedNote(terms),
    );
  }

  // A floor (`200+`) is a count too, and a sum with one in it is a floor: the
  // fleet holds at least that many. Left to the fall-through below, it was a
  // string that is not a count, and the lens's own floor stood in for the
  // fleet's figure.
  final counts = [for (final term in terms) _count(term.value)];
  if (!counts.contains(null)) {
    final sum = counts.fold<int>(0, (sum, count) => sum + count!.value);
    return ServiceKpi(
      label: lens.label,
      value: counts.any((count) => count!.floor) ? Lexicon.floor(sum) : '$sum',
      icon: lens.icon,
      tone: _worstTone(terms),
      note: _sharedNote(terms),
    );
  }

  final rates = [for (final term in terms) _bytesPerSecond(term.value)];
  if (!rates.contains(null)) {
    return ServiceKpi(
      label: lens.label,
      value: formatBytesPerSecond(
        rates.fold<double>(0, (sum, rate) => sum + rate!),
      ),
      icon: lens.icon,
      tone: _worstTone(terms),
      note: _sharedNote(terms),
    );
  }

  // A percentage, a ratio, a state word. It keeps the lens, verbatim and with
  // the lens's own tone: it describes one server and says so by being the one
  // the rest of the app is pointed at.
  return lens;
}

/// The tone a summed figure carries.
///
/// The worst any connection reported, because a fault on one server is a fault
/// in the fleet — a fold that averaged the judgement would let a healthy
/// neighbour talk a failing indexer out of its amber. It cannot be recomputed
/// from the sum: the predicate that decided `_faultIf(...)` lives in the
/// builder, next to the data, and that is where it belongs.
StatusTone? _worstTone(List<ServiceKpi> terms) {
  StatusTone? worst;
  for (final term in terms) {
    if (_severity(term.tone) > _severity(worst)) worst = term.tone;
  }
  return worst;
}

/// The order the fold ranks judgements in.
///
/// Only three of the six ever reach a KPI — `_backlogIf`, `_activityIf` and
/// `_faultIf` in `service_kpi_provider.dart` are the whole vocabulary — but the
/// switch stays exhaustive so a builder that starts using a fourth cannot land
/// silently below the one it should outrank.
int _severity(StatusTone? tone) => switch (tone) {
  null => 0,
  StatusTone.neutral => 1,
  StatusTone.primary => 2,
  StatusTone.success => 3,
  StatusTone.info => 4,
  StatusTone.warning => 5,
  StatusTone.error => 6,
};

/// The note, only where every connection says the same thing.
///
/// A note is *the reason this number is not what you expect*. Two connections
/// with two different reasons have no single reason, and printing the lens's
/// under a summed figure would attribute one server's excuse to the fleet.
String? _sharedNote(List<ServiceKpi> terms) {
  final note = terms.first.note;
  return terms.every((term) => term.note == note) ? note : null;
}

/// `12` or the floor `200+` back into a count, or null if it is neither.
({int value, bool floor})? _count(String value) {
  final floor = value.endsWith('+');
  final count = int.tryParse(
    floor ? value.substring(0, value.length - 1) : value,
  );
  return count == null ? null : (value: count, floor: floor);
}

/// `2.0 MB/s` back into bytes per second, or null if it is not a rate.
///
/// Deliberately anchored to what `formatBytesPerSecond` prints — one space, the
/// binary ladder, the `/s` suffix — rather than to anything more forgiving: a
/// loose parser here would quietly start adding up strings that only look like
/// rates.
double? _bytesPerSecond(String value) {
  final match = _rate.firstMatch(value);
  if (match == null) return null;
  final magnitude = double.tryParse(match.group(1)!);
  if (magnitude == null) return null;
  final unit = _rateUnits.indexOf(match.group(2)!);
  var bytes = magnitude;
  for (var step = 0; step < unit; step++) {
    bytes *= 1024;
  }
  return bytes;
}

const List<String> _rateUnits = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

final RegExp _rate = RegExp(r'^(-?\d+(?:\.\d+)?) (B|KB|MB|GB|TB|PB)/s$');
