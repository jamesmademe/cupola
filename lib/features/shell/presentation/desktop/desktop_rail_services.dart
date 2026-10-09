import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/home/data/stack_lights.dart';
import 'package:cupola/features/home/domain/stack_lights.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_nav_rail.dart';

/// The services of the window's sidebar: every configured one in Stack's
/// order, the light of Stack health where it needs a look, and Seerr's blue
/// while requests wait for an answer.
///
/// A light that is green says nothing a glance needs, so it is not drawn: a
/// sidebar of sixteen green dots buries the one amber one.
final desktopRailServicesProvider =
    Provider.autoDispose<List<DesktopRailService>>((ref) {
      final lights = ref.watch(stackLightsProvider);
      final waiting = ref.watch(pendingRequestCountProvider).value;
      return [for (final row in lights.rows) _serviceOf(row, waiting)];
    });

DesktopRailService _serviceOf(
  StackLightRow row,
  ({int count, bool floor})? waiting,
) => switch (row.light) {
  StackLight.silent => (
    service: row.service,
    tone: StatusTone.error,
    state: 'did not answer',
  ),
  StackLight.fault => (
    service: row.service,
    tone: StatusTone.warning,
    state: 'a fault',
  ),
  _ when row.service == ServiceKey.seerr && (waiting?.count ?? 0) > 0 => (
    service: row.service,
    tone: StatusTone.info,
    state: switch (waiting!) {
      (count: 1, floor: false) => '1 request waits for approval',
      (:final count, :final floor) =>
        '$count${floor ? '+' : ''} requests wait for approval',
    },
  ),
  _ => (service: row.service, tone: null, state: null),
};
