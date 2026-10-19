import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/lifecycle/poll_clock.dart';

/// Refreshes a page that has been away long enough to be showing stale figures.
///
/// This exists because of what the four persistent branches took away. A tab
/// used to be destroyed when you left it, so coming back rebuilt it and every
/// `autoDispose` provider it read fetched again: a refresh nobody wrote,
/// arriving as a side effect of the cost this migration removed. Keeping the tab
/// alive keeps its numbers, including numbers from twenty minutes ago.
///
/// So the refresh becomes explicit, and deliberately meaner than the one it
/// replaces: on returning, and only if what is on screen is older than
/// [maxAge]. A glance at another tab and back costs nothing, which the old
/// behaviour could not manage.
///
/// [onStale] is expected to be the same refresh the tab's own re-tap performs:
/// `triggerNavigationRefresh`, rather than a second path to the same
/// invalidations. It is not announced: a re-tap speaks because the user pressed
/// something.
class RefreshOnReturn extends ConsumerStatefulWidget {
  const RefreshOnReturn({
    super.key,
    required this.id,
    required this.maxAge,
    required this.onStale,
    required this.child,
  });

  /// This page's own key in the [PollClock]. Distinct from any poller's.
  final String id;

  /// How old what is on screen may be before a return is worth a fetch.
  final Duration maxAge;

  final VoidCallback onStale;
  final Widget child;

  @override
  ConsumerState<RefreshOnReturn> createState() => _RefreshOnReturnState();
}

class _RefreshOnReturnState extends ConsumerState<RefreshOnReturn> {
  bool _wasLive = false;

  @override
  Widget build(BuildContext context) {
    final isLive = watchPageActivity(context, ref).isLive;

    if (isLive && !_wasLive) {
      final clock = ref.read(pollClockProvider);
      // A page that has never been marked is not stale, it is new: whatever it
      // is showing, it has just loaded. Marking it now starts the clock for the
      // next return.
      //
      // The clock is the age of what is on screen, so it moves only when
      // something was read: here, or when the refresh below runs. A return that
      // read nothing leaves it where it was, or a page visited every ninety
      // seconds would never get as old as [RefreshOnReturn.maxAge].
      if (!clock.hasRun(widget.id)) {
        clock.note(widget.id);
      } else if (clock.timeUntilDue(widget.id, widget.maxAge) ==
          Duration.zero) {
        clock.note(widget.id);
        // Post-frame: `onStale` invalidates providers, and this runs in build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onStale();
        });
      }
    }
    _wasLive = isLive;

    return widget.child;
  }
}
