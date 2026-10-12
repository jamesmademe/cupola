import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// When each download client's queue last **came back with data**.
///
/// A queue page that keeps its last read under a fault band prints rows whose
/// figures stopped moving when the connection failed. The row (`DownloadQueueTile`)
/// already knows what to do about that: given a `sampleAge` it trades its
/// counting-down line for `as of 6 min ago`. What it could not be given was the
/// age, because no client knew when it last read its queue. This is where that
/// is kept.
///
/// ## Why it is noted where the data lands
///
/// A request leaving says nothing: a poll that fires every few seconds into a
/// dead socket would report itself perfectly fresh forever. Only the code that
/// holds the answer knows it arrived, so the provider that awaits the read
/// notes it **after** the await, and a failed read notes nothing. This is the
/// same argument `GatedPollTimer.lastSuccessAt` makes for a page that owns its
/// own timer (`lib/core/lifecycle/gated_poll.dart`).
///
/// ## Why it is keyed by connection
///
/// A service can have two connections, and the queue on screen belongs to the
/// one the lens was on when the request went out. The key therefore names the
/// connection the provider resolved *before* it awaited ([queueReadKey]), so a
/// read that lands after the lens moved is filed under the connection it came
/// from, and the page that now shows the other one does not inherit its age.
///
/// A plain object and not provider state, on purpose: noting a read must never
/// rebuild anything. The pages that print an age ask for the time through
/// `watchQueueReadAge` (`read_age.dart`), which owns the rebuilds.
class ReadClock {
  /// [now] is the clock's own reading of the time, replaceable so a test can
  /// state an age instead of sleeping for one. A seam rather than a dependency
  /// on the `clock` package: the fake async a widget test runs under advances
  /// timers but not [DateTime.now].
  ReadClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, DateTime> _at = {};

  /// The time as this clock reads it.
  DateTime now() => _now();

  /// Records that [key] came back with data, at [at] or now.
  void note(String key, [DateTime? at]) => _at[key] = at ?? _now();

  /// When [key] last came back with data, or null if it never has in this
  /// session: a cold open, which is loading and not stale.
  DateTime? at(String key) => _at[key];
}

/// App-lifetime on purpose: the record has to outlive the page that shows the
/// queue, which comes and goes with its tab.
final readClockProvider = Provider<ReadClock>((ref) => ReadClock());

/// The key a queue read is filed under: the service and the connection it came
/// from. An empty [connectionId] is a service with no connection, which never
/// has a read to file.
String queueReadKey(ServiceKey service, String connectionId) =>
    '${service.name}:$connectionId';

extension QueueReadNote on Ref {
  /// Starts the record of one queue read and returns the call that closes it.
  ///
  /// Called **before** the request goes out, from the body of the provider that
  /// makes it, and the returned function called right after the successful
  /// await:
  ///
  /// ```dart
  /// final noteRead = ref.queueReadNoter(ServiceKey.sabnzbd);
  /// final queue = await ref.watch(sabnzbdClientProvider).getQueue();
  /// noteRead();
  /// return queue;
  /// ```
  ///
  /// Both halves of the arrangement are load-bearing. The connection is
  /// resolved here, by the same `watchTransport` the provider's client is built
  /// from, so it is the one the request is about to go to and never "the active
  /// one" read again later. And the clock is captured here too: a provider that
  /// was invalidated while its request was in flight is disposed by the time
  /// the answer lands, and a disposed `ref` can no longer be read. The answer
  /// is still a read that came back, and is still noted.
  void Function() queueReadNoter(ServiceKey service) {
    final key = queueReadKey(service, watchTransport(this, service).instanceId);
    final clock = read(readClockProvider);
    return () => clock.note(key);
  }
}
