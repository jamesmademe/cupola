import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/home/domain/needs_you.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Needs you: who leads, how many more, and the sentence it leads with.
void main() {
  final now = DateTime(2026, 9, 29, 20, 53);

  DashboardDecision decision(
    DecisionKind kind,
    String title, {
    int count = 1,
    DateTime? at,
    ServiceKey service = ServiceKey.radarr,
    bool failed = false,
  }) => DashboardDecision(
    kind: kind,
    id: '${kind.name}-$title',
    service: service,
    title: title,
    detail: 'detail',
    occurredAt: at,
    count: count,
    transferFailed: failed,
  );

  group('who leads', () {
    test('nothing silent and no fault: nothing to say', () {
      expect(
        needsYouOf(silent: const [], decisions: const [], now: now),
        isNull,
      );
    });

    test('a request waiting is not a fault and never leads, nor counts', () {
      final requests = [
        decision(DecisionKind.pendingRequest, 'Charge'),
        decision(DecisionKind.pendingRequest, 'Metropolis'),
      ];
      expect(
        needsYouOf(silent: const [], decisions: requests, now: now),
        isNull,
      );

      final needs = needsYouOf(
        silent: const [],
        decisions: [
          ...requests,
          decision(DecisionKind.stalledDownload, 'Big Buck Bunny'),
        ],
        now: now,
      )!;
      expect(needs.line, 'Big Buck Bunny is stuck');
      expect(needs.more, 0);
    });

    test('a service that did not answer leads, with its time, and every '
        'fault counts after it', () {
      final needs = needsYouOf(
        silent: const [ServiceKey.radarr],
        decisions: [
          decision(DecisionKind.importBlocked, 'x', count: 18),
          decision(DecisionKind.stalledDownload, 'Big Buck Bunny'),
          decision(DecisionKind.failingIndexer, 'NZBgeek'),
          decision(DecisionKind.pendingRequest, 'Charge'),
        ],
        now: now,
        silentAt: DateTime(2026, 9, 29, 20, 53),
      )!;
      expect(needs.leadsWithSilence, isTrue);
      expect(needs.silent, [ServiceKey.radarr]);
      expect(needs.line, 'Radarr did not answer at 20:53');
      expect(needs.more, 3);
      expect(needs.action, 'Retry');
      expect(needs.lead, isNull);
    });

    test('two silent services are one line and one Retry for both', () {
      final needs = needsYouOf(
        silent: const [ServiceKey.radarr, ServiceKey.sonarr],
        decisions: const [],
        now: now,
      )!;
      expect(needs.line, 'Radarr and Sonarr did not answer');
      expect(needs.action, 'Retry both');
      expect(needs.more, 0);
    });

    test('the largest group of equal faults leads, whatever its kind', () {
      // Ranked worst kind first: the stall comes first in the list, but the
      // eighteen imports are the most work waiting in one place.
      final stall = decision(DecisionKind.stalledDownload, 'Big Buck Bunny');
      final imports = decision(
        DecisionKind.importBlocked,
        'Cosmos Laundromat',
        count: 18,
        service: ServiceKey.sonarr,
      );
      final needs = needsYouOf(
        silent: const [],
        decisions: [stall, imports],
        now: now,
      )!;
      expect(needs.lead, same(imports));
      expect(needs.line, '18 downloads need a manual import');
      expect(needs.more, 1);
      expect(needs.action, 'Review');
    });

    test('equal sizes keep the order the decisions were ranked in', () {
      final first = decision(DecisionKind.stalledDownload, 'Sintel');
      final second = decision(DecisionKind.failingIndexer, 'NZBgeek');
      final needs = needsYouOf(
        silent: const [],
        decisions: [first, second],
        now: now,
      )!;
      expect(needs.lead, same(first));
    });

    test('a walk cut short makes a group\'s count a floor', () {
      final needs = needsYouOf(
        silent: const [],
        decisions: [decision(DecisionKind.importBlocked, 'x', count: 50)],
        now: now,
        floor: true,
      )!;
      expect(needs.line, '50+ downloads need a manual import');
    });
  });

  group('the sentence each fault leads with', () {
    String line(DashboardDecision d) => needsYouLine(d, now: now);

    test('one of each kind', () {
      expect(
        line(decision(DecisionKind.stalledDownload, 'Big Buck Bunny')),
        'Big Buck Bunny is stuck',
      );
      expect(
        line(
          decision(
            DecisionKind.stalledDownload,
            'Big Buck Bunny',
            failed: true,
          ),
        ),
        'Could not download Big Buck Bunny',
      );
      expect(
        line(decision(DecisionKind.importBlocked, 'Sintel')),
        'Sintel needs a manual import',
      );
      expect(
        line(decision(DecisionKind.failedImport, 'Sintel')),
        'Could not import Sintel',
      );
      expect(
        line(decision(DecisionKind.failingIndexer, 'NZBgeek')),
        'The NZBgeek indexer is failing',
      );
      expect(
        line(decision(DecisionKind.stoppedStack, 'media')),
        'The media stack stopped',
      );
      // Titles that are already sentences, and the arr's own words with its
      // name before them.
      expect(
        line(
          decision(
            DecisionKind.storageAlert,
            'Disk sdd reports 8 uncorrectable errors',
          ),
        ),
        'Disk sdd reports 8 uncorrectable errors',
      );
      expect(
        line(
          decision(
            DecisionKind.connectionFault,
            'qBittorrent answered but refused the sign-in',
          ),
        ),
        'qBittorrent answered but refused the sign-in',
      );
      expect(
        line(
          decision(DecisionKind.serviceHealth, 'Missing root folder: /movies'),
        ),
        'Radarr: Missing root folder: /movies',
      );
    });

    test('a group says how many and what they share', () {
      expect(
        line(decision(DecisionKind.stalledDownload, 'x', count: 3)),
        '3 downloads are stuck',
      );
      expect(
        line(
          decision(DecisionKind.stalledDownload, 'x', count: 3, failed: true),
        ),
        '3 downloads failed',
      );
      expect(
        line(decision(DecisionKind.importBlocked, 'x', count: 18)),
        '18 downloads need a manual import',
      );
    });

    test('a certificate says when it lapses, from its expiry', () {
      DashboardDecision cert(DateTime? at) => decision(
        DecisionKind.expiringCertificate,
        'nas.home.arpa',
        at: at,
        service: ServiceKey.nginxProxyManager,
      );
      expect(
        line(cert(now.add(const Duration(days: 6, hours: 2)))),
        'The certificate for nas.home.arpa expires in 6 days',
      );
      expect(
        line(cert(now.add(const Duration(days: 1, hours: 2)))),
        'The certificate for nas.home.arpa expires tomorrow',
      );
      expect(
        line(cert(now.add(const Duration(hours: 3)))),
        'The certificate for nas.home.arpa expires today',
      );
      expect(
        line(cert(now.subtract(const Duration(days: 2)))),
        'The certificate for nas.home.arpa expired',
      );
      expect(line(cert(null)), 'The certificate for nas.home.arpa is expiring');
    });
  });

  test('a screen reader hears one sentence, the way in at its end', () {
    final needs = needsYouOf(
      silent: const [],
      decisions: [
        decision(DecisionKind.importBlocked, 'x', count: 18),
        decision(DecisionKind.stalledDownload, 'Big Buck Bunny'),
        decision(DecisionKind.stoppedStack, 'media'),
      ],
      now: now,
    )!;
    expect(
      needs.spoken,
      '18 downloads need a manual import, and 2 more things need you. Review',
    );

    final one = needsYouOf(
      silent: const [],
      decisions: [decision(DecisionKind.stoppedStack, 'media')],
      now: now,
    )!;
    expect(one.spoken, 'The media stack stopped. Review');

    final floor = needsYouOf(
      silent: const [],
      decisions: [decision(DecisionKind.importBlocked, 'x', count: 50)],
      now: now,
      floor: true,
    )!;
    expect(floor.spoken, 'at least 50 downloads need a manual import. Review');
  });

  test('a read that stopped short makes the count after the lead a floor, '
      'not the lead from a queue read whole', () {
    final needs = needsYouOf(
      silent: const [],
      decisions: [
        decision(DecisionKind.importBlocked, 'x', count: 18),
        decision(DecisionKind.failedImport, 'Sintel'),
        decision(DecisionKind.failedImport, 'Spring'),
      ],
      now: now,
      moreFloor: true,
    )!;
    expect(needs.line, '18 downloads need a manual import');
    expect(needs.moreLabel, '2+ more');
    expect(
      needs.spoken,
      '18 downloads need a manual import, and at least 2 more things need '
      'you. Review',
    );
    final exact = needsYouOf(
      silent: const [],
      decisions: [
        decision(DecisionKind.importBlocked, 'x', count: 18),
        decision(DecisionKind.failedImport, 'Sintel'),
      ],
      now: now,
    )!;
    expect(exact.moreLabel, '+1');
  });
}
