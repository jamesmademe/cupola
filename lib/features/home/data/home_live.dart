/// What the Home reads again while it is on screen: the downloads and who
/// is watching, every [homeLiveInterval], and the storage every
/// [homeStorageInterval].
///
/// Only those, and only while their modules are on: the rest of the Home is
/// read on open, on pull and on return, and a figure that changes by the
/// minute is not worth a server's time every thirty seconds. One exception:
/// a connection that did not answer is asked again on the same clock, and the
/// first answer reads the whole Home again (`homeRecoveryPollProvider`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/features/home/data/home_layout_provider.dart';
import 'package:cupola/features/home/data/stack_lights.dart';
import 'package:cupola/features/home/data/storage.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

/// How often the Home reads its live modules again while it is seen.
const homeLiveInterval = Duration(seconds: 30);

/// What Downloads draws from: every queue, and the lists the download
/// clients' own pages hold, which the queue reads for the lens's
/// connection and which nothing else drops while their pages are away.
final List<ProviderOrFamily> homeDownloadsSources = [
  allTorrentsProvider,
  transmissionTorrentsProvider,
  sabnzbdQueueProvider,
  nzbgetQueueProvider,
  nzbgetStatusProvider,
  servicesQueueProvider,
];

/// What Now playing draws from, on every connection of both media servers.
final List<ProviderOrFamily> homeSessionsSources = [
  jellyfinSessionsProvider,
  plexSessionsProvider,
  streamSessionsForProvider,
  streamActivityProvider,
];

/// The poll that keeps Downloads and Now playing current, for the Home to
/// watch while it is the page on screen (`watchWhileLive`).
///
/// Asks only for the modules the person keeps on and whose services are set
/// up: with neither there is no timer at all.
final homeLivePollProvider = Provider.autoDispose<void>((ref) {
  final layout = ref.watch(homeLayoutProvider);
  bool live(HomeModule module) =>
      layout.isOn(module) &&
      ref.watch(
        currentSettingsProvider.select(
          (settings) => module.services.any(settings.isServiceConfigured),
        ),
      );
  // The pools change by the minute at most: their own, slower clock.
  if (live(HomeModule.storage)) {
    ref.gatedPoll(
      id: 'home.storage',
      interval: homeStorageInterval,
      onTick: () => ref.invalidate(homeStorageProvider),
    );
  }
  final sources = [
    if (live(HomeModule.downloads)) ...homeDownloadsSources,
    if (live(HomeModule.nowPlaying)) ...homeSessionsSources,
  ];
  if (sources.isEmpty) return;
  ref.gatedPoll(
    id: 'home.live',
    interval: homeLiveInterval,
    onTick: () {
      for (final source in sources) {
        ref.invalidate(source);
      }
    },
  );
});

/// The poll that brings a Home back once its servers answer again, for the
/// Home to watch while it is the page on screen.
///
/// Every [homeLiveInterval], the connections the header counts as silent are
/// probed again, and nothing else: a server that stays down costs one status
/// call a tick. When a round brings one back, the Home reads everything again,
/// once, as a pull would: the modules that failed with it recover on their own
/// (a phone back on its VPN, 11/10), with no pull to find.
final homeRecoveryPollProvider = Provider.autoDispose<void>((ref) {
  // Nothing set up, nothing to hear from: no timer at all.
  final anything = ref.watch(
    currentSettingsProvider.select(
      (settings) => ServiceKey.values.any(settings.isServiceConfigured),
    ),
  );
  if (!anything) return;
  // Held, not watched: the clock outlives every change of the lights, and a
  // round that brings the last server back must still read the Home again.
  final lights = ref.listen(stackLightsProvider, (_, _) {});
  ref.gatedPoll(
    id: 'home.recover',
    interval: homeLiveInterval,
    onTick: () async {
      final silent = [
        for (final service in lights.read().silent)
          for (final id in ref.read(serviceInstanceIdsProvider(service)))
            (service: service, instanceId: id),
      ];
      if (silent.isEmpty) return;
      for (final key in silent) {
        ref.invalidate(instanceSummaryProvider(key));
      }
      final answers = await Future.wait([
        for (final key in silent)
          ref
              .read(instanceSummaryProvider(key).future)
              .then<ServiceSummary?>(
                (summary) => summary,
                onError: (_) => null,
              ),
      ]);
      if (!ref.mounted) return;
      if (answers.any((summary) => summary != null && !summary.didNotAnswer)) {
        ref
            .read(navigationRefreshProvider(NavigationSection.home).notifier)
            .state++;
      }
    },
  );
});
