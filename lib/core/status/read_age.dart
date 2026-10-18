import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The time as of the last minute, renewed every minute for as long as
/// something listens to it.
///
/// An age is bucketed to the minute (`formatDurationAge`), so a figure that is
/// recomputed any faster repaints a page for an answer that did not change.
/// `autoDispose`, so its timer exists only while a page is printing an age: a
/// healthy page never watches it and never rebuilds on a clock.
///
/// The repeating work goes through `Ref.gatedPoll` because that is the only
/// place the app is allowed to construct it (`test/core/no_ungated_polling_test.dart`);
/// the page decides when it is listening, and [ReadAgeWatch.watchQueueReadAge]
/// listens only while the page is on screen.
///
/// Renewing is an invalidation of this provider itself, which re-reads the
/// time from the [ReadClock], so the clock a test hands the app is the clock
/// the age is measured by.
final minuteNowProvider = Provider.autoDispose<DateTime>((ref) {
  ref.gatedPoll(
    id: 'read_age.minute',
    interval: const Duration(minutes: 1),
    onTick: ref.invalidateSelf,
  );
  return ref.read(readClockProvider).now();
});

/// How long a queue page that is on screen waits for a read to come back
/// before it says the figures stopped coming back (`FaultBand.stale`).
///
/// One number for the four download clients, which all poll every three
/// seconds. Four poll intervals, for two reasons that pull opposite ways:
///
///  * **Above a slow answer.** A request in flight holds its tick back
///    (`readAgainUnlessInFlight`), so two answers from a server that takes `r`
///    seconds to answer land at most `r` plus one tick apart. A read of four
///    seconds every three leaves six seconds between answers, and a server
///    that needs eight leaves eleven: neither may look stopped.
///  * **Below the transport's own deadline.** A connection that takes the
///    request and never answers is failed after fifteen seconds
///    (`redirect_guard.dart`), and from then on the page's fault band says so.
///    The band for a poll that stopped coming back is for the seconds before
///    that, and for a read that neither lands nor fails; a threshold above the
///    deadline would never be seen.
const Duration queueStaleAfter = Duration(seconds: 12);

/// How often a live queue page asks whether it has crossed [queueStaleAfter].
/// Short beside the threshold, so the band comes up within two seconds of it
/// and before the transport's deadline hands the page to its fault band.
const Duration _staleCheckEvery = Duration(seconds: 2);

/// When the page showing the queue filed under a key (`queueReadKey`) began to
/// be watched, which is when it began to be on screen.
///
/// `autoDispose`, so leaving the page forgets it and coming back starts afresh:
/// a page that returns after a minute elsewhere has not been *waiting* a
/// minute for an answer. Its read is old because nothing asked for one, and
/// the catch-up read that its poll starts on return is about to answer. It is
/// given [queueStaleAfter] of its own before it says otherwise, so a tab that
/// is switched back to does not flash a band over a read that is already on
/// its way.
final _queueWatchedSinceProvider = Provider.autoDispose
    .family<DateTime, String>((ref, queueKey) {
      return ref.read(readClockProvider).now();
    });

/// Whether the queue filed under a key has waited longer than
/// [queueStaleAfter] for an answer, as of the last time it was asked.
///
/// A hint rather than the answer: it is renewed every [_staleCheckEvery]
/// through `Ref.gatedPoll`, and only *changes* when the page crosses the
/// threshold, so a healthy page is rebuilt by nothing here. The page confirms
/// it against the clock at its own build ([ReadAgeWatch.watchQueueStaleAge]),
/// so an answer that lands between two checks takes the band down at once and
/// not at the next one.
///
/// `autoDispose`: it lives only while a page that is on screen watches it, so
/// the timer is the page's, as every other poll is.
final _queueStalledProvider = Provider.autoDispose.family<bool, String>((
  ref,
  queueKey,
) {
  ref.gatedPoll(
    id: 'read_age.stale.$queueKey',
    interval: _staleCheckEvery,
    onTick: ref.invalidateSelf,
  );
  return _waitedTooLong(
    ref.read(readClockProvider),
    queueKey,
    ref.watch(_queueWatchedSinceProvider(queueKey)),
  );
});

/// Whether [queueKey] has gone [queueStaleAfter] without a read coming back,
/// counted from the later of that read and [watchedSince].
///
/// False when nothing was ever read in this session: a cold open is loading,
/// and a row never claims an age nobody measured.
bool _waitedTooLong(ReadClock clock, String queueKey, DateTime watchedSince) {
  final at = clock.at(queueKey);
  if (at == null) return false;
  final waitingSince = at.isAfter(watchedSince) ? at : watchedSince;
  return clock.now().difference(waitingSince) > queueStaleAfter;
}

/// The sentence the stale band of a download client's queue adds to its age:
/// what did not come back, without claiming the service is gone (`FaultBand.stale`
/// is for a poll that stopped coming back, not for a service that did not
/// answer).
String queueStaleDetail(ServiceKey service) =>
    "${service.title}'s queue has not returned.";

extension ReadAgeWatch on WidgetRef {
  /// How old the queue of [service] is, as the page draws it, or null when the
  /// rows are not stale.
  ///
  /// [underBand] is the page's own fact: it is showing the last queue it read
  /// beneath a band that says why it is old, a fault band or the stale band
  /// [watchQueueStaleAge] decides. Anywhere else the answer is null and the
  /// rows print the figures they were given, so a healthy page costs nothing
  /// and watches nothing here.
  ///
  /// Also null when there is no recorded read for the connection the page is
  /// reading: a row never claims an age nobody measured.
  ///
  /// The page rebuilds once a minute through [minuteNowProvider] while it is
  /// the page on screen; behind another tab or a pushed page it does not, and
  /// reads the time afresh when it comes back, which rebuilds it anyway.
  ///
  /// Must be called from `build`, for the dependencies it registers.
  Duration? watchQueueReadAge(
    BuildContext context,
    ServiceKey service, {
    required bool underBand,
  }) {
    if (!underBand) return null;
    final clock = read(readClockProvider);
    final at = clock.at(_queueKey(service));
    if (at == null) return null;
    final now = watchPageActivity(context, this).isLive
        ? watch(minuteNowProvider)
        : clock.now();
    final age = now.difference(at);
    // A read stamped after the page's reading of the time (the two were taken
    // a frame apart) is not a negative age.
    return age.isNegative ? Duration.zero : age;
  }

  /// How old the queue of [service] is when the page has **no fault band** and
  /// its read has stopped coming back, or null.
  ///
  /// The case [watchQueueReadAge] cannot see by itself: the service has not
  /// failed, so nothing bands the rows, yet the read the page waits for has
  /// not landed for [queueStaleAfter] (a request stuck in flight, a poll that
  /// stopped coming back). The rows keep their speeds and times left and look
  /// live while nothing moves. A page that gets an age here raises
  /// `FaultBand.stale` with it, and hands its rows the age through
  /// [watchQueueReadAge] (`underBand: true`).
  ///
  /// [underBand] is the page's own fact that a fault band is showing, which
  /// wins: the answer is null then, so the two bands are never up together,
  /// and the page pays for nothing here. [hasQueue] is its fact that it holds a
  /// queue to draw: a page that is still loading one has no figures to call
  /// old.
  ///
  /// Null too while the page is not the one on screen, and for
  /// [queueStaleAfter] after it becomes it: a page that was elsewhere was not
  /// waiting for an answer (see `_queueWatchedSinceProvider`). A cold open,
  /// which has read nothing, is loading and is never stale.
  ///
  /// A healthy page is rebuilt by nothing here: it holds one cheap check on its
  /// own timer that changes the page only when the threshold is crossed, and
  /// reads the clock itself at every build it already makes, so the band goes
  /// the moment an answer lands.
  ///
  /// Must be called from `build`, for the dependencies it registers.
  Duration? watchQueueStaleAge(
    BuildContext context,
    ServiceKey service, {
    required bool underBand,
    required bool hasQueue,
  }) {
    if (underBand || !hasQueue) return null;
    if (!watchPageActivity(context, this).isLive) return null;
    final key = _queueKey(service);
    final clock = read(readClockProvider);
    // Nothing read, nothing to call old, and no timer for a page that is
    // still loading: it starts watching once its first read has landed.
    if (clock.at(key) == null) return null;
    if (!watch(_queueStalledProvider(key))) return null;
    // The hint is up to one check old. The clock is read afresh, so an answer
    // that landed since is not called stale for the rest of the check.
    if (!_waitedTooLong(clock, key, watch(_queueWatchedSinceProvider(key)))) {
      return null;
    }
    return watchQueueReadAge(context, service, underBand: true);
  }

  /// The key the queue this page reads is filed under: its service and the
  /// connection the lens rests on, by the same lens the provider that read it
  /// resolved.
  String _queueKey(ServiceKey service) =>
      queueReadKey(service, effectiveInstanceId(this, service, null));
}
