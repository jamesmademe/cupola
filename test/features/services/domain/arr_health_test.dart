import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/arr_health.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

DashboardDecision _check(
  ServiceKey service,
  String check,
  String message, {
  String? name,
}) {
  final arr = name ?? service.title;
  return DashboardDecision(
    kind: DecisionKind.serviceHealth,
    id: 'health-${service.routeParam}-$check',
    service: service,
    title: arrHealthWords(check)?.headline ?? message,
    detail: arr,
    reason: message,
    subject: check,
    occurredAt: null,
    instanceId: service.routeParam,
  );
}

/// An \*arr's failing health checks in the app's words, and the same check on
/// several \*arrs as one fault.
void main() {
  test('names are said as a sentence lists them', () {
    expect(namesSaid(const ['Radarr']), 'Radarr');
    expect(namesSaid(const ['Radarr', 'Sonarr']), 'Radarr and Sonarr');
    expect(
      namesSaid(const ['Radarr', 'Sonarr', 'Lidarr']),
      'Radarr, Sonarr and Lidarr',
    );
  });

  test('a known check in the app\'s words, naming no arr', () {
    expect(arrHealthWords('IndexerRssCheck'), (
      headline: 'No indexer is watching for new releases',
      explanation:
          "New releases aren't grabbed on their own until an indexer has RSS "
          'sync on.',
    ));
    expect(arrHealthWords('SomeNewCheck'), isNull);
  });

  test('the same check on three arrs is one fault, each one its member, and '
      'their own words kept once each', () {
    const rss = 'IndexerRssCheck';
    final folded = foldArrHealth([
      _check(
        ServiceKey.radarr,
        rss,
        'No indexers available with RSS sync enabled, Radarr will not grab '
        'new releases automatically',
      ),
      _check(
        ServiceKey.sonarr,
        rss,
        'No indexers available with RSS sync enabled, Sonarr will not grab '
        'new releases automatically',
      ),
      _check(ServiceKey.radarr, 'RootFolderCheck', 'Missing root folder: /x'),
      _check(
        ServiceKey.lidarr,
        rss,
        'No indexers available with RSS sync enabled, Lidarr will not grab '
        'new releases automatically',
      ),
    ]);

    expect(folded, hasLength(2));
    final group = folded.first;
    expect(group.title, 'No indexer is watching for new releases');
    expect(group.detail, 'Radarr, Sonarr and Lidarr');
    expect(group.count, 1);
    expect(group.members.map((member) => member.service), [
      ServiceKey.radarr,
      ServiceKey.sonarr,
      ServiceKey.lidarr,
    ]);
    expect(group.reason!.split('\n\n'), hasLength(3));
    expect(folded.last.title, 'A library folder is missing');
    expect(folded.last.members, isEmpty);
  });

  test('a check the app has no words for folds only the same sentence', () {
    final folded = foldArrHealth([
      _check(ServiceKey.radarr, 'SomeNewCheck', 'Something broke'),
      _check(ServiceKey.sonarr, 'SomeNewCheck', 'Something broke'),
      _check(ServiceKey.lidarr, 'SomeNewCheck', 'Something else broke'),
    ]);
    expect(folded.map((decision) => decision.detail), [
      'Radarr and Sonarr',
      'Lidarr',
    ]);
    expect(folded.first.title, 'Something broke');
  });
}
