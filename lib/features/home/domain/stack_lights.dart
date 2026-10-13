/// Stack health: the Stack tab folded into one slab of the Home, every
/// configured service as its mark with one light.
///
/// The marks stay monochrome, since a service is known by its shape; only the
/// light takes a tone, by the five-arm rule: green answering, amber a fault
/// or a server reached that never replied, red did not answer, and a hollow
/// light while a service has not answered yet. Faults are counted as the
/// slab shows them, one per amber light, so the count, the lights and the
/// names under them are one figure: Needs you is where the faults themselves
/// are counted.
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// How many services the line under the marks names before it counts the
/// rest: as many as the slab's width holds on the phone.
const _faultNames = 5;

/// What one connection's probe said.
enum StackProbe {
  /// Still being asked.
  checking,

  /// It answered, and nothing in the answer is wrong.
  answered,

  /// It answered with a fault: a refused key, a server error.
  fault,

  /// It was reached and never replied in time.
  stuck,

  /// It did not answer.
  silent,

  /// Not asked: away from home, with no address away.
  onlyAtHome,
}

/// What one service's light says.
enum StackLight {
  /// No connection has answered yet: a hollow light.
  checking,

  /// Answered, nothing wrong: green.
  answering,

  /// Answered, and something is wrong: a fault in the answer, a connection
  /// that did not answer beside one that did, or a fault the person has to
  /// see to. Amber.
  fault,

  /// No connection replied, and at least one was reached: amber, and not
  /// answering.
  stuck,

  /// Every connection did not answer: red.
  silent,

  /// Not asked: the app is away from home and no connection has an address
  /// away. Neutral, and out of the count.
  onlyAtHome,
}

/// One mark of the slab.
typedef StackLightRow = ({ServiceKey service, StackLight light});

/// The slab: its marks in the Stack's order and what its line says.
@immutable
class StackLights {
  const StackLights({required this.rows});

  /// One per configured service, in the Stack's order.
  final List<StackLightRow> rows;

  /// The services amber for a fault: the count the line says, and the names
  /// under the marks. Counted in groups, as Needs you counts them, it read
  /// `3 faults` above five names: one health check failing on three \*arrs
  /// is one fault and three amber lights, and the reader is left to work out
  /// which figure the lights are.
  int get faults => faulted.length;

  /// The services asked: not the ones only at home, away from it.
  int get configured => rows.length - onlyAtHome.length;

  /// The services not asked, away from home.
  List<ServiceKey> get onlyAtHome => [
    for (final row in rows)
      if (row.light == StackLight.onlyAtHome) row.service,
  ];

  /// The services that answered, a fault among them: a refused key is an
  /// answer.
  int get answering => rows
      .where(
        (row) =>
            row.light == StackLight.answering || row.light == StackLight.fault,
      )
      .length;

  /// Services not answered yet.
  int get stillChecking =>
      rows.where((row) => row.light == StackLight.checking).length;

  /// Whether no service has answered yet: every light hollow.
  bool get checking => rows.isNotEmpty && stillChecking == rows.length;

  /// The services whose every connection did not answer.
  List<ServiceKey> get silent => [
    for (final row in rows)
      if (row.light == StackLight.silent) row.service,
  ];

  /// The services with an amber light for a fault.
  List<ServiceKey> get faulted => [
    for (final row in rows)
      if (row.light == StackLight.fault) row.service,
  ];

  /// The services reached that never replied.
  List<ServiceKey> get stuck => [
    for (final row in rows)
      if (row.light == StackLight.stuck) row.service,
  ];

  /// The line beside the slab's name: `12 of 12 answering · 3 faults`, or
  /// `Checking 12` before anything has answered.
  String get line {
    if (checking) return 'Checking $configured';
    final parts = [
      '$answering of $configured answering',
      // In the header's order: the faults, then what was reached and never
      // replied.
      if (faults > 0) '$faults ${faults == 1 ? 'fault' : 'faults'}',
      if (stuck.isNotEmpty) '${stuck.length} timed out',
      if (stillChecking > 0) '$stillChecking checking',
      if (onlyAtHome.isNotEmpty)
        '${onlyAtHome.length} ${StateWord.onlyAtHome.inline}',
    ];
    return parts.join(' · ');
  }

  /// The marks as a screen reader hears them, grouped by light: `Answering:
  /// Radarr, Seerr. Faults: Sonarr. Did not answer: TrueNAS.`
  String get spoken {
    String names(StackLight light) => [
      for (final row in rows)
        if (row.light == light) row.service.title,
    ].join(', ');
    return [
      for (final (light, word) in const [
        (StackLight.answering, 'Answering'),
        (StackLight.fault, 'Faults'),
        (StackLight.stuck, 'Timed out'),
        (StackLight.silent, 'Did not answer'),
        (StackLight.checking, 'Checking'),
        (StackLight.onlyAtHome, 'Only at home'),
      ])
        if (names(light) case final list when list.isNotEmpty) '$word: $list.',
    ].join(' ');
  }

  /// `Faults: Sonarr, qBittorrent and TrueNAS`, or null when no light is
  /// amber for a fault. Past [_faultNames] names, the rest counted: `Faults:
  /// Seerr, Radarr, Sonarr, Lidarr, Prowlarr and 2 others`, still the line's
  /// figure.
  String? get faultLine => faulted.isEmpty
      ? null
      : 'Faults: ${servicesNamed([for (final service in faulted) service.title], maxNamed: _faultNames)}';
}

/// The light of one service, from what each of its connections said and
/// whether a fault of it waits for the person.
StackLight stackLightOf(List<StackProbe> probes, {bool needsYou = false}) {
  // Not asked is not an answer: a service whose every connection is only at
  // home is that, and one with another connection reads by the other.
  if (probes.isNotEmpty &&
      probes.every((probe) => probe == StackProbe.onlyAtHome)) {
    return StackLight.onlyAtHome;
  }
  final heard = [
    for (final probe in probes)
      if (probe != StackProbe.checking && probe != StackProbe.onlyAtHome) probe,
  ];
  if (heard.isEmpty) return StackLight.checking;
  if (heard.every((probe) => probe == StackProbe.silent)) {
    return StackLight.silent;
  }
  if (heard.every(
    (probe) => probe == StackProbe.silent || probe == StackProbe.stuck,
  )) {
    return StackLight.stuck;
  }
  if (needsYou || heard.any((probe) => probe != StackProbe.answered)) {
    return StackLight.fault;
  }
  return StackLight.answering;
}

/// The slab, given each configured service's probes in the Stack's order and
/// the stack's faults ([DashboardDecision.isFault]), which light the services
/// they belong to.
StackLights stackLightsOf({
  required List<({ServiceKey service, List<StackProbe> probes})> services,
  required List<DashboardDecision> faults,
}) {
  // A health check folded across \*arrs is amber on each of them.
  final withFaults = faultedServices(faults);
  final rows = [
    for (final entry in services)
      (
        service: entry.service,
        light: stackLightOf(
          entry.probes,
          needsYou: withFaults.contains(entry.service),
        ),
      ),
  ];
  return StackLights(rows: rows);
}
