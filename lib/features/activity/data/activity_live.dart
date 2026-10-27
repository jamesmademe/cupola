/// What Activity reads again while it is on screen, and what a pull drops.
///
/// One poll for the page, whichever view is open: the queues, the clients
/// and who is watching every [activityLiveInterval] on the views that show
/// them, the requests every [activityRequestsInterval]. History is read on
/// open, on pull and on return: a week does not change by the second.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/features/activity/data/acted_faults.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/activity/data/household_requests.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// How often the downloads and who is watching are read again.
const activityLiveInterval = Duration(seconds: 15);

/// How often the requests are read again: they change when somebody asks,
/// and Seerr follows its own downloads once a minute.
const activityRequestsInterval = Duration(seconds: 60);

/// The requests a view draws: the lens's list, every Seerr's, and the
/// waiting ones Needs you reads.
void _invalidateRequests(Ref ref) {
  for (final source in dashboardSourcesOf(ServiceKey.seerr)) {
    ref.invalidate(source);
  }
  ref.invalidate(pendingRequestCountProvider);
  ref.invalidate(dashboardDecisionSourceProvider(DecisionSource.requests));
}

/// Whether any of the requests a view draws is being read now: a slow Seerr
/// is asked once, never a second time on top of the first.
bool _requestsInFlight(Ref ref) =>
    ref.read(requestsProvider).isLoading ||
    ref
        .read(dashboardDecisionSourceProvider(DecisionSource.requests))
        .isLoading;

/// The poll of [tab], for the page to watch while it is the page on screen
/// (`watchWhileLive`). History has none.
final activityLivePollProvider = Provider.autoDispose.family<void, ActivityTab>(
  (ref, tab) {
    final queues = tab == ActivityTab.all || tab == ActivityTab.downloads;
    final requests = tab == ActivityTab.all || tab == ActivityTab.requests;
    if (queues) {
      ref.gatedPoll(
        id: 'activity.live',
        interval: activityLiveInterval,
        // As the Home's: a queue still being read is left to answer.
        onTick: () {
          ref.readAgainUnlessInFlight([
            ...homeDownloadsSources,
            dashboardDecisionSourceProvider(DecisionSource.queue),
          ]);
          if (tab == ActivityTab.all) {
            ref.readAgainUnlessInFlight(homeSessionsSources);
          }
        },
      );
    }
    if (requests) {
      ref.gatedPoll(
        id: 'activity.requests',
        interval: activityRequestsInterval,
        onTick: () {
          if (_requestsInFlight(ref)) return;
          _invalidateRequests(ref);
        },
      );
    }
  },
);

/// What the desktop sidebar's "In flight" reads again while it is on screen,
/// to watch with `watchWhileLive`.
///
/// The same sources as the Home's Downloads, on the Home's clock: the glance
/// is that module folded to two lines, and it must not disagree with it, nor
/// go stale on a window that never visits the Home.
final sidebarInFlightPollProvider = Provider.autoDispose<void>((ref) {
  ref.gatedPoll(
    id: 'sidebar.inflight',
    interval: homeLiveInterval,
    onTick: () => ref.readAgainUnlessInFlight(homeDownloadsSources),
  );
});

/// Drops what [tab] draws, so it is read again: a pull, a second tap on the
/// tab, a return after a while.
void invalidateActivity(WidgetRef ref, ActivityTab tab) {
  switch (tab) {
    case ActivityTab.all || ActivityTab.downloads:
      for (final source in homeDownloadsSources) {
        ref.invalidate(source);
      }
      ref.invalidate(servicesArrivalsProvider);
      ref.invalidate(servicesArrHistoryProvider);
      ref.invalidate(releaseSearchJobsProvider);
      if (tab == ActivityTab.all) {
        // The rows answered here give way to Seerr's list, and the notes of
        // the downloads acted on to the queue's.
        ref.read(answeredRequestsProvider.notifier).clear();
        ref.read(actedFaultsProvider.notifier).clear();
        for (final source in homeSessionsSources) {
          ref.invalidate(source);
        }
        invalidateSeerrRequestsOf(ref.container, '');
        ref.invalidate(dashboardDecisionSourceProvider);
        for (final service in ServiceKey.values) {
          for (final source in dashboardSourcesOf(service)) {
            ref.invalidate(source);
          }
        }
      }
    case ActivityTab.requests:
      ref.read(answeredRequestsProvider.notifier).clear();
      invalidateSeerrRequestsOf(ref.container, '');
      for (final source in dashboardSourcesOf(ServiceKey.seerr)) {
        ref.invalidate(source);
      }
    case ActivityTab.history:
      ref.invalidate(servicesArrivalsProvider);
      ref.invalidate(servicesFailuresSinceProvider);
  }
}

/// [invalidateActivity], then the spinner held until what [tab] draws has
/// come back. Failures are swallowed: each section paints its own.
Future<void> refreshActivity(WidgetRef ref, ActivityTab tab) async {
  invalidateActivity(ref, tab);
  Future<void> settle(Future<Object?> pending) async {
    try {
      await pending;
    } catch (_) {}
  }

  await Future.wait([
    if (tab == ActivityTab.all || tab == ActivityTab.downloads)
      settle(ref.read(servicesQueueProvider.future)),
    if (tab == ActivityTab.all) ...[
      settle(ref.read(servicesArrivalsProvider.future)),
      for (final source in DecisionSource.values)
        settle(ref.read(dashboardDecisionSourceProvider(source).future)),
    ],
    if (tab == ActivityTab.requests)
      for (final source in ref.read(householdRequestsProvider(null)))
        settle(
          ref.read(
            requestsForProvider(source.isLens ? '' : source.instanceId).future,
          ),
        ),
    if (tab == ActivityTab.history) ...[
      settle(ref.read(servicesArrivalsProvider.future)),
      settle(ref.read(servicesFailuresSinceProvider.future)),
    ],
  ]);
}
