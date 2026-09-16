/// The ranking rule, and the two things that depend on it.
///
/// Pure: the region's whole argument is an ordering and a cap, and neither needs
/// a widget to be wrong.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('rankDecisions', () {
    test('faults come before backlog, however old the backlog is', () {
      final ranked = rankDecisions([
        _decision(
          DecisionKind.pendingRequest,
          'request',
          at: DateTime.utc(2020, 1, 1),
        ),
        _decision(
          DecisionKind.stalledDownload,
          'stall',
          at: DateTime.utc(2024, 6, 1),
        ),
      ]);

      expect(ranked.map((d) => d.title), ['stall', 'request']);
    });

    test('oldest first inside a kind', () {
      final ranked = rankDecisions([
        _decision(
          DecisionKind.stalledDownload,
          'new',
          at: DateTime.utc(2024, 6),
        ),
        _decision(
          DecisionKind.stalledDownload,
          'old',
          at: DateTime.utc(2024, 1),
        ),
        _decision(
          DecisionKind.stalledDownload,
          'mid',
          at: DateTime.utc(2024, 3),
        ),
      ]);

      expect(ranked.map((d) => d.title), ['old', 'mid', 'new']);
    });

    test('an undated item sorts last inside its kind, never first', () {
      final ranked = rankDecisions([
        _decision(DecisionKind.stoppedStack, 'undated', at: null),
        _decision(
          DecisionKind.stoppedStack,
          'dated',
          at: DateTime.utc(2024, 6),
        ),
      ]);

      // Dockge dates nothing. An item that cannot be placed honestly loses to
      // one that can — it must not inherit "just now" and outrank a real age.
      expect(ranked.map((d) => d.title), ['dated', 'undated']);
    });

    test('two undated items keep their source order', () {
      final ranked = rankDecisions([
        _decision(DecisionKind.stoppedStack, 'first', at: null),
        _decision(DecisionKind.stoppedStack, 'second', at: null),
      ]);

      // `List.sort` is not stable; rows that shuffle on every rebuild read as a
      // page that cannot make up its mind.
      expect(ranked.map((d) => d.title), ['first', 'second']);
    });

    test('kinds rank worst-first, and the cap cuts from the bottom', () {
      final ranked = rankDecisions([
        _decision(
          DecisionKind.expiringCertificate,
          'cert',
          at: DateTime.utc(2024),
        ),
        _decision(
          DecisionKind.stalledDownload,
          'stall',
          at: DateTime.utc(2024),
        ),
        _decision(DecisionKind.failedImport, 'import', at: DateTime.utc(2024)),
      ], cap: 2);

      expect(ranked.map((d) => d.title), ['stall', 'import']);
    });

    test('a cap larger than the list is not an error', () {
      final ranked = rankDecisions([
        _decision(DecisionKind.stalledDownload, 'one', at: DateTime.utc(2024)),
      ], cap: 4);

      expect(ranked, hasLength(1));
    });
  });

  group('decisionCapFor', () {
    test('three on the phone, four on the desktop, two at compact', () {
      expect(decisionCapFor(desktopShell: false, compact: false), 3);
      expect(decisionCapFor(desktopShell: true, compact: false), 4);
      expect(decisionCapFor(desktopShell: true, compact: true), 2);
    });
  });

  group('the vocabulary', () {
    test('only a pending request is backlog', () {
      for (final kind in DecisionKind.values) {
        expect(
          kind.isFault,
          kind != DecisionKind.pendingRequest,
          reason: '$kind',
        );
      }
    });

    test('the stall control names the client it would open', () {
      expect(
        decisionActionLabel(
          DecisionKind.stalledDownload,
          target: ServiceKey.qbittorrent,
        ),
        'Open in qBittorrent',
      );
      // No target named — the row still offers the act rather than going blank.
      expect(
        decisionActionLabel(DecisionKind.stalledDownload),
        'Open in client',
      );
    });

    test('the eyebrow names the kinds present and no others', () {
      final eyebrow = decisionsEyebrow([
        _decision(DecisionKind.stalledDownload, 'a', at: DateTime.utc(2024)),
        _decision(DecisionKind.pendingRequest, 'b', at: DateTime.utc(2024)),
        _decision(DecisionKind.pendingRequest, 'c', at: DateTime.utc(2024)),
      ]);

      expect(eyebrow, '3 items · stalls, requests');
      expect(eyebrow, isNot(contains('certs')));
    });

    test('an unavailable control says what it needs, and offers a way', () {
      expect(
        decisionUnavailableHint(ServiceKey.qbittorrent),
        'requires qBittorrent',
      );
      expect(
        decisionUnavailableToast(
          DecisionKind.stalledDownload,
          ServiceKey.qbittorrent,
        ),
        'Connect qBittorrent to open this transfer.',
      );
    });
  });
}

DashboardDecision _decision(
  DecisionKind kind,
  String title, {
  required DateTime? at,
}) => DashboardDecision(
  kind: kind,
  id: '$kind-$title',
  service: ServiceKey.radarr,
  title: title,
  detail: 'detail',
  occurredAt: at,
);
