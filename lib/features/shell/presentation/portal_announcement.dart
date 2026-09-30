/// What the Portal says when it opens.
///
/// One sentence, once: how many services its floor holds and how many of them
/// are in a fault. A screen reader never needs the drag — the tab bar carries an
/// action that opens the Portal — and an open Portal that says nothing leaves
/// the reader on the tab it just activated, with no word that a floor of
/// services is now in front of it.
///
/// Counted from the floor itself, never from the Dashboard's aggregate: the
/// header folds connections per service, the floor gives each connection a cell
/// of its own, and a sentence that counted the fold would announce a number of
/// services the reader cannot find by swiping.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/services/presentation/service_matrix.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The Portal's floor, counted the way it is drawn.
@immutable
class PortalFloorCensus {
  const PortalFloorCensus({
    required this.services,
    required this.faults,
    required this.checking,
  });

  /// Cells on the floor: one per configured connection, as the picker draws
  /// them — so two Radarr connections are two.
  final int services;

  /// Cells the floor draws in a fault: a connection that did not answer (the
  /// red pip) and one that answered but refused (the amber pip). Only what the
  /// floor shows is counted, since a fault the reader cannot find on the floor
  /// would send them looking for it; a pending request is never a fault, and
  /// the picker does not show one either.
  final int faults;

  /// Cells whose probe has not come back. Not a fault, and never counted as
  /// one — but while any is out, "none with a fault" is not yet true.
  final int checking;
}

/// The census, from the same cells and the same probes the floor paints.
///
/// [pickerSubjectsOf] and [serviceReachabilityOf] are the floor's own; the
/// switch is exhaustive, so a state the floor learns to draw has to be placed
/// here too before this compiles.
final portalFloorCensusProvider = Provider<PortalFloorCensus>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  var services = 0;
  var faults = 0;
  var checking = 0;

  for (final service in ServiceKey.values) {
    for (final subject in pickerSubjectsOf(settings, service)) {
      services++;
      switch (serviceReachabilityOf(
        ref.watch(instanceSummaryProvider(subject)),
      )) {
        case ServiceReachability.online:
          break;
        case ServiceReachability.checking:
          checking++;
        // A refused key and a service that did not answer are both faults
        // the floor paints, amber and red.
        case ServiceReachability.fault:
        case ServiceReachability.offline:
          faults++;
      }
    }
  }

  return PortalFloorCensus(
    services: services,
    faults: faults,
    checking: checking,
  );
});

/// `Portal open. 12 services, 3 with a fault.`
///
/// A count and a verb, in the lexicon's words: *checking* is said as checking,
/// and "none with a fault" is said only once every probe has answered — a
/// sentence that asserts a clean floor while probes are still out is the zero
/// that should have been a dash.
String portalOpenedAnnouncement(PortalFloorCensus census) {
  final PortalFloorCensus(:services, :faults, :checking) = census;
  if (services == 0) return 'Portal open. No services are set up.';

  final parts = <String>[
    services == 1 ? '1 service' : '$services services',
    if (faults > 0)
      '$faults with a fault'
    else if (checking == 0)
      'none with a fault',
    if (checking > 0) '$checking checking',
  ];
  return 'Portal open. ${parts.join(', ')}.';
}
