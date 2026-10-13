/// What Stack health reads: the probe of every connection, the one the
/// header's `12 of 12 answering` comes from, and the stack's faults.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/home/domain/stack_lights.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The slab, in the Stack's order: its domains, then the registry's order
/// inside each.
///
/// A probe read again keeps its last answer until the new one lands, so a
/// pull or a return does not put every light out: they switch on once.
final stackLightsProvider = Provider.autoDispose<StackLights>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  final faults = [
    for (final decision in ref.watch(dashboardDecisionsProvider).decisions)
      if (decision.isFault) decision,
  ];
  return stackLightsOf(
    services: [
      for (final domain in ServiceDomain.values)
        for (final service in domain.services)
          // A Seerr account that signed out was asked nothing: the person's
          // step, as the header counts it, not a light.
          if (settings.isServiceConfigured(service))
            (
              service: service,
              probes: [
                for (final id in ref.watch(serviceInstanceIdsProvider(service)))
                  _probeOf(
                    ref.watch(
                      instanceSummaryProvider((
                        service: service,
                        instanceId: id,
                      )),
                    ),
                  ),
              ],
            ),
    ],
    faults: faults,
  );
});

StackProbe _probeOf(AsyncValue<ServiceSummary> summary) {
  if (summary.value case final answer?) {
    if (answer.isOnlyAtHome) return StackProbe.onlyAtHome;
    if (answer.didNotAnswer) return StackProbe.silent;
    if (answer.isStuck) return StackProbe.stuck;
    // A Seerr account that signed out beside a working one: no fault.
    if (answer.isFault &&
        answer.failureReason != ServiceFailureReason.sessionEnded) {
      return StackProbe.fault;
    }
    return StackProbe.answered;
  }
  if (summary.hasError) {
    return switch (classifyConnectionFailure(summary.error!)) {
      final reason when failureDidNotAnswer(reason) => StackProbe.silent,
      ServiceFailureReason.timeout => StackProbe.stuck,
      _ => StackProbe.fault,
    };
  }
  return StackProbe.checking;
}
