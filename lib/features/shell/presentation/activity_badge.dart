import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_rail_services.dart'
    show faultCountsByService;

/// The number on Activity, in the phone's bar, the tablet's rail and the
/// desktop's sidebar alike.
typedef ActivityBadge = ({
  int count,

  /// Amber when something needs the person; blue when only requests and
  /// finished searches wait.
  StatusTone tone,

  /// The count is the least there is: a read it comes from stopped short.
  bool floor,

  /// What a screen reader hears after `Activity`: both counts, when both.
  String spoken,
});

/// The number on Activity, or null when nothing waits.
///
/// **Amber** when something needs the person: the faults as Needs you counts
/// them, each group weighing its own count (eighteen imports blocked alike are
/// eighteen), the operator's alone. **Blue** when no fault is left: the
/// requests waiting for an answer this account may give, and the finished
/// searches nobody has opened. Downloads in progress never count: they ask
/// for nothing. A service that did not answer is the sidebar's red, not a
/// number here.
///
/// The spoken words say both counts whichever colour wins: `3 need you, 2
/// requests wait for you`.
ActivityBadge? activityBadgeOf({
  required int faults,
  required bool faultsFloor,
  required int requests,
  required bool requestsFloor,
  required int searches,
}) {
  String figure(int count, bool floor) => floor ? 'at least $count' : '$count';
  final waiting = [
    if (requests > 0)
      '${figure(requests, requestsFloor)} '
          '${requests == 1 ? 'request waits' : 'requests wait'} '
          'for you',
    if (searches > 0)
      '$searches finished search${searches == 1 ? '' : 'es'} to look at',
  ];
  if (faults > 0) {
    return (
      count: faults,
      tone: StatusTone.warning,
      floor: faultsFloor,
      spoken: [
        '${figure(faults, faultsFloor)} '
            '${faults == 1 ? 'needs' : 'need'} you',
        ...waiting,
      ].join(', '),
    );
  }
  final blue = requests + searches;
  if (blue == 0) return null;
  return (
    count: blue,
    tone: StatusTone.info,
    floor: requestsFloor && requests > 0,
    spoken: waiting.join(', '),
  );
}

/// [activityBadgeOf] over what the shell holds: the stack's decisions, the
/// requests waiting, the finished searches. Faults are the operator's only.
final activityBadgeProvider = Provider<ActivityBadge?>((ref) {
  final operator = ref.watch(audienceProvider) == Audience.operator;
  final read = operator ? ref.watch(dashboardDecisionsProvider) : null;
  final faults = read == null
      ? 0
      : faultCountsByService(
          read.decisions,
        ).values.fold<int>(0, (sum, count) => sum + count);
  final waiting = ref.watch(pendingRequestCountProvider).value;
  return activityBadgeOf(
    faults: faults,
    faultsFloor: read?.coverage.isFloor ?? false,
    requests: waiting?.count ?? 0,
    requestsFloor: waiting?.floor ?? false,
    searches: ref.watch(unseenReleaseSearchCountProvider),
  );
});
