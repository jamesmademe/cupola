import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase, ProviderOrFamily;

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/core/lifecycle/poll_probe.dart';

/// The only place in `lib/` allowed to construct repeating work.
///
/// Enforced by `test/core/no_ungated_polling_test.dart`. A `Timer.periodic`
/// anywhere else is a poller with no gate, which is how a hidden tab ends up
/// talking to the network, and it is invisible in review, because the timer and
/// the page that should own it live in different files.
extension GatedPoll on Ref {
  /// Repeating work for the page that is on screen.
  ///
  /// Belongs in the body of a `Provider.autoDispose`, whose lifetime *is* the
  /// gate: the screen watches it through [PageGatedWatch.watchWhileLive], so
  /// losing visibility drops the last listener and disposal cancels the timer.
  ///
  /// On creation the poller asks the clock when it is next due: a full interval
  /// if it has never run; the page has just loaded what it shows, or whatever
  /// is left of one, which can be nothing at all after a long absence. Only that
  /// last case ticks straight away, and it is deferred to a microtask because
  /// [onTick] invalidates providers, which is illegal inside a provider's build.
  ///
  /// The stop is one frame plus a microtask behind the page going away: the
  /// rebuild drops the watch, dropping the last listener schedules disposal, and
  /// disposal cancels the timer. Against a multi-second interval that window
  /// never contains a tick in practice, but a test that fast-forwards the clock
  /// without pumping that frame first will see the old timer fire, which is the
  /// test skipping the stop rather than the stop failing.
  void gatedPoll({
    required String id,
    required Duration interval,
    required void Function() onTick,
  }) {
    final clock = read(pollClockProvider);
    var disposed = false;
    Timer? timer;

    void tick() {
      if (disposed) return;
      clock.note(id);
      PollProbe.instance.noteTick(id);
      onTick();
    }

    void startPeriodic() {
      if (disposed) return;
      timer = Timer.periodic(interval, (_) => tick());
    }

    final due = clock.timeUntilDue(id, interval);
    if (due == Duration.zero) {
      scheduleMicrotask(() {
        tick();
        startPeriodic();
      });
    } else {
      timer = Timer(due, () {
        tick();
        startPeriodic();
      });
    }

    onDispose(() {
      disposed = true;
      timer?.cancel();
      PollProbe.instance.noteStop(id);
    });
  }
}

/// What a poll's tick reads again.
extension ReadAgainUnlessInFlight on Ref {
  /// Invalidates [sources] as one, unless any of them is still being read:
  /// then none is, and the tick after the read answers reads them again.
  ///
  /// A tick that invalidates a read in flight throws it away before it can
  /// answer or fail. Against servers that take the connection and then say
  /// nothing (a NAS asleep behind a port forward, a VPN half up), the Home's
  /// queue read is two receive deadlines long, as long as its tick: every
  /// tick restarted it, Downloads never left loading and its fault never
  /// landed (13/10). The group is skipped whole because its parts read one
  /// another: the queue reads the clients' lists, and invalidating an idle
  /// list restarts the queue that is reading it.
  ///
  /// Only a provider that already exists is inspected, so a tick never
  /// creates one just to ask about it. A family cannot be asked and is read
  /// again with its group. Returns whether the group was read again.
  bool readAgainUnlessInFlight(Iterable<ProviderOrFamily> sources) {
    final inFlight = sources.any(
      (source) =>
          source is ProviderBase<AsyncValue<Object?>> &&
          exists(source) &&
          read(source).isLoading,
    );
    if (inFlight) return false;
    for (final source in sources) {
      invalidate(source);
    }
    return true;
  }
}

/// The same contract for a page that owns its timer directly.
///
/// Two screens do: the TrueNAS dashboard drives a WebSocket rather than a
/// provider, and the manual-import Track station stops on a command result rather
/// than on visibility. Both need to start and stop from `build`, so [setLive] is
/// safe to call there; it never runs [onTick] synchronously.
class GatedPollTimer {
  GatedPollTimer({
    required this.id,
    required this.interval,
    required this.onTick,
    required this.clock,
  });

  final String id;
  final Duration interval;
  final void Function() onTick;
  final PollClock clock;

  Timer? _timer;
  bool _live = false;
  bool _disposed = false;
  DateTime? _lastSuccessAt;

  bool get isLive => _live;

  /// When a tick last came back with data.
  ///
  /// Deliberately **not** recorded by [_tick]. A tick firing means a request
  /// went out, which is the one thing that is still true when the queue
  /// endpoint has stopped answering; a timer that fires every ten seconds into
  /// a dead socket would report itself perfectly healthy forever. Only the
  /// owner knows whether the answer arrived, so the owner reports it.
  ///
  /// `null` until the first success, which is the cold-open state: nothing has
  /// answered yet, and that is loading, not stale.
  DateTime? get lastSuccessAt => _lastSuccessAt;

  /// How long since a tick last came back, or `null` before the first one.
  Duration? sinceLastSuccessAt(DateTime now) {
    final at = _lastSuccessAt;
    return at == null ? null : now.difference(at);
  }

  /// Records that the work this timer drives has answered.
  ///
  /// Call it where the data lands, not where the request leaves. See
  /// [lastSuccessAt].
  void noteSuccess([DateTime? at]) {
    if (_disposed) return;
    _lastSuccessAt = at ?? DateTime.now();
  }

  /// Whether the figures this timer feeds should be read as stale.
  ///
  /// [tolerance] is a multiple of [interval] rather than a constant, because
  /// "old" is only meaningful relative to how often the page expected an
  /// answer: a two-second import poll is in trouble after six seconds, a
  /// sixty-second dashboard poll is not. Three intervals is the default: one
  /// missed answer is a slow network, three is a pattern.
  ///
  /// False before the first success: a page that has not loaded yet is loading.
  bool isStaleAt(DateTime now, {double tolerance = 3}) {
    final elapsed = sinceLastSuccessAt(now);
    if (elapsed == null) return false;
    return elapsed > interval * tolerance;
  }

  /// Idempotent: call it from `build` with `activity.isLive && <own condition>`.
  ///
  /// Going live re-applies the same catch-up rule `gatedPoll` uses, so returning
  /// to a page after a long absence refreshes at once while a glance elsewhere
  /// costs nothing.
  void setLive(bool live) {
    if (_disposed || live == _live) return;
    _live = live;
    _timer?.cancel();
    _timer = null;
    if (!live) {
      PollProbe.instance.noteStop(id);
      return;
    }
    final due = clock.timeUntilDue(id, interval);
    if (due == Duration.zero) {
      // Never synchronously inside build: the caller is mid-build and onTick
      // typically invalidates providers or calls setState.
      scheduleMicrotask(() {
        if (!_live || _disposed) return;
        _tick();
        _startPeriodic();
      });
    } else {
      _timer = Timer(due, () {
        _tick();
        _startPeriodic();
      });
    }
  }

  void _tick() {
    if (_disposed || !_live) return;
    clock.note(id);
    PollProbe.instance.noteTick(id);
    onTick();
  }

  void _startPeriodic() {
    if (_disposed || !_live) return;
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  void dispose() {
    _disposed = true;
    _live = false;
    _timer?.cancel();
    _timer = null;
    PollProbe.instance.noteStop(id);
  }
}

/// Declarative wrapper for the common case: repeating work that runs while its
/// page is on screen and [enabled] agrees.
///
/// ```dart
/// VisibilityPoller(
///   id: 'import.command',
///   interval: const Duration(seconds: 2),
///   enabled: command?.isActive ?? true,
///   onTick: _poll,
///   child: body,
/// )
/// ```
class VisibilityPoller extends ConsumerStatefulWidget {
  const VisibilityPoller({
    super.key,
    required this.id,
    required this.interval,
    required this.onTick,
    required this.child,
    this.enabled = true,
  });

  final String id;
  final Duration interval;
  final VoidCallback onTick;
  final Widget child;

  /// The page's own condition, ANDed with visibility.
  final bool enabled;

  @override
  ConsumerState<VisibilityPoller> createState() => _VisibilityPollerState();
}

class _VisibilityPollerState extends ConsumerState<VisibilityPoller> {
  GatedPollTimer? _poller;

  @override
  void dispose() {
    _poller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activity = watchPageActivity(context, ref);
    final poller = _poller ??= GatedPollTimer(
      id: widget.id,
      interval: widget.interval,
      onTick: widget.onTick,
      clock: ref.read(pollClockProvider),
    );
    poller.setLive(activity.isLive && widget.enabled);
    return widget.child;
  }
}
