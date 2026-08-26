import 'package:flutter/foundation.dart';

/// Tick and stop counters, so "nothing polls from a hidden page" is a number
/// rather than a belief.
///
/// Every gated poller reports here. In profile mode each state change prints one
/// line on the same `ZZ` channel as a device profiling session, which is what
/// makes the claim checkable by eye: switch away from a tab and the log goes
/// silent. In release every method short-circuits, so this costs nothing in a
/// shipped build.
class PollProbe {
  PollProbe._();

  static final PollProbe instance = PollProbe._();

  /// Ticks per poller id, since the last [reset].
  final Map<String, int> ticks = {};

  void noteTick(String id) {
    if (kReleaseMode) return;
    final count = (ticks[id] ?? 0) + 1;
    ticks[id] = count;
    if (kProfileMode) debugPrint('ZZPOLL tick $id #$count');
  }

  void noteStop(String id) {
    if (kReleaseMode) return;
    if (kProfileMode) debugPrint('ZZPOLL stop $id');
  }

  int countFor(String id) => ticks[id] ?? 0;

  @visibleForTesting
  void reset() => ticks.clear();
}
