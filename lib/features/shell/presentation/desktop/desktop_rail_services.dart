import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/home/data/stack_lights.dart';
import 'package:cupola/features/home/domain/stack_lights.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_nav_rail.dart';

/// The services of the window's sidebar: every configured one in Stack's
/// order, with what it needs from the person.
///
/// A number where there is one to say: the things that need fixing in that
/// service, the same decisions Needs you counts, split by service (`18` beside
/// Sonarr for eighteen downloads to import), and in blue the requests waiting
/// in Seerr. A fault the stack holds no count for (a refused key, a server
/// reached that never replied) keeps its light, and a service that did not
/// answer says so in red under its name.
///
/// A light that is green says nothing a glance needs, so it is not drawn: a
/// sidebar of sixteen green dots buries the one amber one.
final desktopRailServicesProvider =
    Provider.autoDispose<List<DesktopRailService>>((ref) {
      final lights = ref.watch(stackLightsProvider);
      final waiting = ref.watch(pendingRequestCountProvider).value;
      final read = ref.watch(dashboardDecisionsProvider);
      final faults = faultCountsByService(read.decisions);
      return [
        for (final row in lights.rows)
          _serviceOf(
            row,
            waiting,
            faults: faults[row.service] ?? 0,
            floor: read.coverage.isFloor,
          ),
      ];
    });

/// Beside Stack in the sidebar: how many services answer, `12/12`, as the
/// Home's header counts them; null before any has answered, or with none set
/// up, when a figure would only say `0/0`.
final desktopStackFigureProvider =
    Provider.autoDispose<({String text, String spoken})?>((ref) {
      final lights = ref.watch(stackLightsProvider);
      if (lights.rows.isEmpty || lights.checking) return null;
      return (
        text: '${lights.answering}/${lights.configured}',
        spoken: '${lights.answering} of ${lights.configured} answering',
      );
    });

/// The things to fix in each service: the faults of [decisions], each
/// weighing its own [DashboardDecision.count], so a group of eighteen imports
/// counts eighteen, as Needs you says it.
Map<ServiceKey, int> faultCountsByService(List<DashboardDecision> decisions) {
  final counts = <ServiceKey, int>{};
  for (final decision in decisions) {
    if (!decision.isFault) continue;
    counts.update(
      decision.service,
      (count) => count + decision.count,
      ifAbsent: () => decision.count,
    );
  }
  return counts;
}

DesktopRailService _serviceOf(
  StackLightRow row,
  ({int count, bool floor})? waiting, {
  required int faults,
  required bool floor,
}) {
  final counted = faults > 0
      ? (
          count: floor ? Lexicon.floor(faults) : '$faults',
          state:
              '${floor ? 'at least $faults' : '$faults'} '
              '${faults == 1 && !floor ? 'needs' : 'need'} you',
        )
      : null;
  return switch (row.light) {
    StackLight.silent => (
      service: row.service,
      tone: StatusTone.error,
      state: 'did not answer',
      count: null,
    ),
    StackLight.fault || StackLight.stuck when counted != null => (
      service: row.service,
      tone: StatusTone.warning,
      state: counted.state,
      count: counted.count,
    ),
    StackLight.fault => (
      service: row.service,
      tone: StatusTone.warning,
      state: 'a fault',
      count: null,
    ),
    StackLight.stuck => (
      service: row.service,
      tone: StatusTone.warning,
      state: 'timed out',
      count: null,
    ),
    _ when row.service == ServiceKey.seerr && (waiting?.count ?? 0) > 0 => (
      service: row.service,
      tone: StatusTone.info,
      state: switch (waiting!) {
        (count: 1, floor: false) => '1 request waits for approval',
        (:final count, :final floor) =>
          '$count${floor ? '+' : ''} requests wait for approval',
      },
      count: waiting.floor ? Lexicon.floor(waiting.count) : '${waiting.count}',
    ),
    // Answering, and still holding things to fix: a light that reads green
    // beside a queue of stuck downloads is the sidebar lying by omission.
    _ when counted != null => (
      service: row.service,
      tone: StatusTone.warning,
      state: counted.state,
      count: counted.count,
    ),
    _ => (service: row.service, tone: null, state: null, count: null),
  };
}
