import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/core/lifecycle/poll_probe.dart';

/// The only place in `lib/` allowed to construct repeating work.
///
/// Enforced by `test/core/no_ungated_polling_test.dart`. A `Timer.periodic`
/// anywhere else is a poller with no gate, which is how a hidden tab ends up
/// talking to the network — and it is invisible in review, because the timer and
/// the page that should own it live in different files.
extension GatedPoll on Ref {
  /// Repeating work for the page that is on screen.
  ///
  /// Belongs in the body of a `Provider.autoDispose`, whose lifetime *is* the
  /// gate: the screen watches it through [PageGatedWatch.watchWhileLive], so
  /// losing visibility drops the last listener and disposal cancels the timer.
  ///
  /// On creation the poller catches up. Due already — or never run — means one
  /// tick now, otherwise a one-shot for the remainder and then the steady
  /// cadence. That catch-up tick is deferred to a microtask because [onTick]
  /// invalidates providers, and doing that inside a provider's build is illegal.
  ///
  /// The stop is one frame plus a microtask behind the page going away: the
  /// rebuild drops the watch, dropping the last listener schedules disposal, and
  /// disposal cancels the timer. Against a multi-second interval that window
  /// never contains a tick in practice — but a test that fast-forwards the clock
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

/// The same contract for a page that owns its timer directly.
///
/// Two screens do: the TrueNAS dashboard drives a WebSocket rather than a
/// provider, and the manual-import Track station stops on a command result rather
/// than on visibility. Both need to start and stop from `build`, so [setLive] is
/// safe to call there — it never runs [onTick] synchronously.
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

  bool get isLive => _live;

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
