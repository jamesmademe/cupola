/// What a Retry on the Dashboard has to drop for a service to be asked again.
///
/// Every Retry on this page used to re-read an answer already in the cache.
/// The region Retry invalidated `serviceSummaryProvider`, which only delegates
/// to the probe it awaits, and the merge, which awaits client providers that
/// keep a failure until somebody drops them (`retry: noProviderRetry`); the
/// alert band re-probed the connection and left every region's sources where
/// they were. So the probe could come back answering while "did not answer"
/// stayed under In flight, the qBittorrent rows stayed missing and the card
/// stayed at `—` — recovery only showed after a pull-to-refresh.
///
/// One function, so the band, the regions and the refresh drop the same set.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The providers the Dashboard's merged regions read from [service] and that
/// keep an answer of their own — what has to be dropped for that service's
/// part of In flight and of Needs a decision to be read again.
///
/// The \*arrs are absent on purpose: their queue and their history are read
/// straight off their clients inside [servicesQueueProvider] and
/// [servicesArrHistoryProvider], so dropping those merges is their re-read.
List<ProviderOrFamily> dashboardSourcesOf(ServiceKey service) =>
    switch (service) {
      ServiceKey.qbittorrent => [allTorrentsProvider],
      ServiceKey.sabnzbd => [sabnzbdQueueProvider],
      ServiceKey.nzbget => [nzbgetQueueProvider],
      // The lens's list, and every other Seerr's, which the region reads too.
      ServiceKey.seerr => [servicesRequestsProvider, requestsForProvider],
      // The status list *is* the failing-indexer list; the indexers name them.
      ServiceKey.prowlarr => [
        prowlarrIndexerStatusProvider,
        prowlarrIndexersProvider,
      ],
      ServiceKey.dockge => [dockgeStackListProvider],
      ServiceKey.nginxProxyManager => [npmCertificatesProvider],
      ServiceKey.radarr ||
      ServiceKey.sonarr ||
      ServiceKey.lidarr ||
      ServiceKey.readarr ||
      ServiceKey.transmission ||
      ServiceKey.bazarr ||
      ServiceKey.truenas ||
      ServiceKey.unraid ||
      ServiceKey.jellyfin ||
      ServiceKey.plex => const [],
    };

/// Asks [services] again, everywhere the Dashboard shows them: the probe of
/// each connection, the stack card's figures and the sources those figures
/// fold, and every region that reads them.
///
/// Only [services]. Re-checking the whole stack would throw away a dozen good
/// answers to re-fetch the ones that failed.
void retryDashboardServices(WidgetRef ref, Iterable<ServiceKey> services) {
  final asked = services.toSet();
  if (asked.isEmpty) return;
  for (final service in asked) {
    // The probe itself, one entry per connection. `serviceSummaryProvider`
    // only delegates to these, so invalidating it alone rebuilt a wrapper that
    // awaited the same cached answer.
    for (final id in ref.read(serviceInstanceIdsProvider(service))) {
      ref.invalidate(
        instanceSummaryProvider((service: service, instanceId: id)),
      );
    }
    ref.invalidate(serviceSummaryProvider(service));
    ref.invalidate(serviceKpiProvider(service));
    ref.invalidate(serviceSignalProvider(service));
    ref.invalidate(serviceSignalPairProvider(service));
    ref.invalidate(foldedServiceKpisProvider(service));
    ref.invalidate(foldedServiceSignalPairProvider(service));
    // What the card's figures fold: without these the KPI rebuilt from the
    // failure its source was still holding.
    for (final source in serviceKpiSources(service)) {
      ref.invalidate(source);
    }
    for (final source in dashboardSourcesOf(service)) {
      ref.invalidate(source);
    }
  }
  // Keyed on the connection, so it cannot be narrowed to these services by
  // key — and a retry that left the fleet's figures cached would redraw the
  // recovered card with the numbers from the outage.
  ref.invalidate(serviceKpiForProvider);

  // The merges that read the \*arrs off their clients, and the decision
  // sources that read anything else, each only when it reads one of these.
  bool reads(DecisionSource source) => source.services.any(asked.contains);
  if (reads(DecisionSource.queue)) ref.invalidate(servicesQueueProvider);
  if (reads(DecisionSource.history)) {
    ref.invalidate(servicesArrHistoryProvider);
  }
  for (final source in DecisionSource.values) {
    if (reads(source)) ref.invalidate(dashboardDecisionSourceProvider(source));
  }
}
