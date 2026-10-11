/// Stack health: the Stack tab folded into one slab of the Home, every
/// configured service as its mark with one light.
///
/// The marks stay monochrome, since a service is known by its shape; only the
/// light takes a tone, by the five-arm rule: green answering, amber a fault,
/// red did not answer, and a hollow light while a service has not answered
/// yet. Faults are counted in groups, as Needs you counts them: eighteen
/// blocked imports are one fault, a refused key another.
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What one connection's probe said.
enum StackProbe {
  /// Still being asked.
  checking,

  /// It answered, and nothing in the answer is wrong.
  answered,

  /// It answered with a fault: a refused key, a server error.
  fault,

  /// It did not answer.
  silent,
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

  /// Every connection did not answer: red.
  silent,
}

/// One mark of the slab.
typedef StackLightRow = ({ServiceKey service, StackLight light});

/// The slab: its marks in the Stack's order and what its line says.
@immutable
class StackLights {
  const StackLights({required this.rows, required this.faults});

  /// One per configured service, in the Stack's order.
  final List<StackLightRow> rows;

  /// The faults, counted in groups.
  final int faults;

  /// The services asked.
  int get configured => rows.length;

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

  /// The services with an amber light.
  List<ServiceKey> get faulted => [
    for (final row in rows)
      if (row.light == StackLight.fault) row.service,
  ];

  /// The line beside the slab's name: `12 of 12 answering · 3 faults`, or
  /// `Checking 12` before anything has answered.
  String get line {
    if (checking) return 'Checking $configured';
    final parts = [
      '$answering of $configured answering',
      if (faults > 0) '$faults ${faults == 1 ? 'fault' : 'faults'}',
      if (stillChecking > 0) '$stillChecking checking',
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
        (StackLight.silent, 'Did not answer'),
        (StackLight.checking, 'Checking'),
      ])
        if (names(light) case final list when list.isNotEmpty) '$word: $list.',
    ].join(' ');
  }

  /// `Faults: Sonarr, qBittorrent, TrueNAS`, or null when no light is amber.
  String? get faultLine => faulted.isEmpty
      ? null
      : 'Faults: ${[for (final service in faulted) service.title].join(', ')}';
}

/// The light of one service, from what each of its connections said and
/// whether a fault of it waits for the person.
StackLight stackLightOf(List<StackProbe> probes, {bool needsYou = false}) {
  final heard = [
    for (final probe in probes)
      if (probe != StackProbe.checking) probe,
  ];
  if (heard.isEmpty) return StackLight.checking;
  if (heard.every((probe) => probe == StackProbe.silent)) {
    return StackLight.silent;
  }
  if (needsYou || heard.any((probe) => probe != StackProbe.answered)) {
    return StackLight.fault;
  }
  return StackLight.answering;
}

/// The slab, given each configured service's probes in the Stack's order and
/// the stack's faults ([DashboardDecision.isFault]).
///
/// A fault group counts once; a service amber for its answer alone (a refused
/// key, a connection that did not answer beside one that did) counts once
/// more, since no group stands for it.
StackLights stackLightsOf({
  required List<({ServiceKey service, List<StackProbe> probes})> services,
  required List<DashboardDecision> faults,
}) {
  // A health check folded across \*arrs is amber on each of them.
  final withFaults = {
    for (final fault in faults) ...[
      fault.service,
      for (final member in fault.members) member.service,
    ],
  };
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
  final groups = faults.length;
  final unnamed = rows
      .where(
        (row) =>
            row.light == StackLight.fault && !withFaults.contains(row.service),
      )
      .length;
  return StackLights(rows: rows, faults: groups + unnamed);
}
