import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The downloads the desktop's chrome draws from (the rail's lights, the
/// window's count of decisions), read again every [homeLiveInterval].
///
/// The desktop shell keeps that graph alive whatever page is open, and the
/// queue it draws from used to start again at every three-second tick of a
/// download client's own page, with an arr queue read behind it each time. It
/// now reads the clients' lists as they stand (`services_provider.dart`), and
/// this poll is what keeps the chrome current when no Home or Activity poll is
/// on: those two read the same group on their own clocks, and this one stands
/// aside while either has just run.
///
/// Watched by the desktop shell and nothing else: a phone has no graph that
/// needs it, since nothing there outlives its page.
final desktopDownloadsPollProvider = Provider.autoDispose<void>((ref) {
  final anything = ref.watch(
    currentSettingsProvider.select(
      (settings) => ServiceKey.values.any(settings.isServiceConfigured),
    ),
  );
  if (!anything) return;
  ref.gatedPoll(
    id: 'desktop.downloads',
    interval: homeLiveInterval,
    onTick: () {
      final clock = ref.read(pollClockProvider);
      const standAside = Duration(seconds: 25);
      if (clock.ranWithin('home.live', standAside) ||
          clock.ranWithin('activity.live', standAside)) {
        return;
      }
      ref.readAgainUnlessInFlight(homeDownloadsSources);
    },
  );
});
