import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Since when each connection has **not answered**.
///
/// A band over a dead service used to say that it did not answer and never
/// since when, which is the difference between a restart and an outage. The
/// widgets that print it (`FaultBand.unreachable`, `ServiceOfflineState`, the
/// requester's `BriefFailureLine`) already knew how, and no caller passed the
/// time, because nothing recorded when a connection stopped answering. This is
/// where that is kept.
///
/// ## What starts a silence, and what ends it
///
/// A silence starts at the **first** probe of a connection that did not answer
/// ([failureDidNotAnswer]) and keeps that time however many probes fail after
/// it: a Retry that fails again is the same silence, six minutes old and not
/// one minute old again.
///
/// Any answer ends it, **a fault included**. A refused key, a 5xx and a reply
/// nobody can read are all the service speaking; a box that answers with an
/// error is up, and the amber that says so must not carry a clock that says it
/// has been dark since the afternoon.
///
/// ## Why it lives in memory only
///
/// Between two runs of the app the service may have answered unseen, so a
/// silence written to disk would claim an outage the app never watched. A cold
/// start into a silent service therefore starts its silence at the first probe
/// of the run, and the span the band prints is dropped until a minute of it has
/// passed (`formatElapsedSpan`), never invented.
///
/// ## Its own namespace
///
/// Not [ReadClock]: a version probe that answers must not refresh a queue's
/// `as of`, and a queue that came back says nothing of whether the box was
/// silent when the probe last asked. The two clocks share a key shape
/// ([silenceKey]) and nothing else.
///
/// A plain object and not provider state, for the reason [ReadClock] is one:
/// noting a probe must never rebuild anything. The pages that print a span
/// ask for it through `watchSilence` (`silence_age.dart`), and they rebuild
/// because the probe they watch completed, which is after it noted.
class SilenceClock {
  /// [now] is the clock's own reading of the time, replaceable so a test can
  /// state a span instead of sleeping for one. [silenceClockProvider] hands it
  /// the [ReadClock]'s, so one fake time answers for both.
  SilenceClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, DateTime> _since = {};

  /// The time as this clock reads it.
  DateTime now() => _now();

  /// Records that the connection [key] did not answer, at [at] or now.
  /// Keeps the first time: a silence already running is not restarted.
  void noteSilent(String key, [DateTime? at]) =>
      _since.putIfAbsent(key, () => at ?? _now());

  /// Records that the connection [key] answered, whatever it said: the
  /// silence, if there was one, is over.
  void noteAnswered(String key) => _since.remove(key);

  /// Records the outcome of one probe of [key]: [reason] is why it failed, or
  /// null when it succeeded. A failure that [failureDidNotAnswer], or a server
  /// reached that never replied ([ServiceFailureReason.timeout]), starts or
  /// keeps a silence: neither said anything. Every other outcome is an
  /// answer, a refusal included.
  void noteProbe(String key, ServiceFailureReason? reason) =>
      reason != null &&
          (failureDidNotAnswer(reason) ||
              reason == ServiceFailureReason.timeout)
      ? noteSilent(key)
      : noteAnswered(key);

  /// When the connection [key] first stopped answering, or null when it is not
  /// known to be silent: it answered last, or it has not been probed in this
  /// run.
  DateTime? since(String key) => _since[key];
}

/// App-lifetime on purpose: the record has to outlive the page that shows it,
/// which comes and goes with its tab. Reads the time through the
/// [ReadClock], so a test that hands the app a clock hands it to both.
final silenceClockProvider = Provider<SilenceClock>(
  (ref) => SilenceClock(now: ref.read(readClockProvider).now),
);

/// The key a silence is filed under: the service and the connection that did
/// not answer. A connection is never "the active one": two connections of one
/// service are two answers.
String silenceKey(ServiceKey service, String connectionId) =>
    '${service.name}:$connectionId';
