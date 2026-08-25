import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Last-tick bookkeeping that outlives the poller it belongs to.
///
/// A gated poller is `autoDispose`: leaving its page destroys it, and with it any
/// memory of when it last ran. Without this, coming back would either refetch
/// instantly — wasteful on a two-second glance at another tab — or wait out a
/// whole interval, which is stale after a two-minute absence. The clock is what
/// lets a poller tell those two cases apart.
///
/// App-lifetime on purpose: it is the one piece of a poller that must *not* be
/// disposed with the page.
final pollClockProvider = Provider<PollClock>((ref) => PollClock());

class PollClock {
  final Map<String, DateTime> _last = {};

  /// The clock's own reading of the time, replaceable in tests.
  ///
  /// A seam rather than a `Clock` dependency: `fakeAsync` advances timers but not
  /// [DateTime.now], so a test that elapses an hour would otherwise see a poller
  /// that believes no time has passed.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  void note(String id) => _last[id] = now();

  /// How long until [id] is due. [Duration.zero] when it is due already, or has
  /// never run at all.
  Duration timeUntilDue(String id, Duration interval) {
    final last = _last[id];
    if (last == null) return Duration.zero;
    final remaining = interval - now().difference(last);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Whether [id] has ever ticked — the signal a stale-on-return check reads.
  bool hasRun(String id) => _last.containsKey(id);

  @visibleForTesting
  void reset() => _last.clear();
}
