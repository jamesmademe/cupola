/// The words of a fault's card, for every kind but a stuck download.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/domain/fault_words.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

DashboardDecision _decision(
  DecisionKind kind, {
  ServiceKey service = ServiceKey.sonarr,
  String title = 'Cosmos Laundromat',
  String detail = '',
  int count = 1,
  String? reason,
  String? connectionName,
}) => DashboardDecision(
  kind: kind,
  id: 'x',
  service: service,
  title: title,
  detail: detail,
  occurredAt: null,
  count: count,
  reason: reason,
  connectionName: connectionName,
);

void main() {
  group('a blocked import', () {
    test('one says its title, and that the arr will not', () {
      final words = faultWordsOf(
        _decision(
          DecisionKind.importBlocked,
          reason: 'found matching series via grab history',
        ),
      );
      expect(words.headline, 'Cosmos Laundromat needs a manual import');
      expect(
        words.explanation,
        "Sonarr finished it and won't import it on its own.",
      );
      expect(words.source, 'Sonarr');
      expect(words.why, 'Found matching series via grab history.');
    });

    test('a group says how many, and its fill says Review and the count', () {
      final group = _decision(DecisionKind.importBlocked, count: 18);
      expect(faultWordsOf(group).headline, '18 downloads need a manual import');
      expect(
        faultWordsOf(group).explanation,
        "Sonarr finished them and won't import them on its own.",
      );
      expect(faultActionLabel(group), 'Review 18');
      expect(faultActionLabel(_decision(DecisionKind.importBlocked)), 'Review');
    });

    test('no cause, no Why?', () {
      expect(faultWordsOf(_decision(DecisionKind.importBlocked)).why, isNull);
    });
  });

  test('the source names the connection once there are two', () {
    expect(
      faultWordsOf(
        _decision(DecisionKind.importBlocked, connectionName: 'Anime'),
      ).source,
      'Sonarr Anime',
    );
  });

  test('a failed import, an indexer and a stack say what happened', () {
    expect(
      faultWordsOf(_decision(DecisionKind.failedImport)).headline,
      'Cosmos Laundromat did not import',
    );
    final indexer = faultWordsOf(
      _decision(
        DecisionKind.failingIndexer,
        service: ServiceKey.prowlarr,
        title: 'NZBgeek',
        detail: 'Failing · Prowlarr · disabled for now',
      ),
    );
    expect(indexer.headline, 'NZBgeek is failing');
    expect(indexer.explanation, 'Prowlarr has stopped searching it for now.');
    expect(
      faultWordsOf(
        _decision(
          DecisionKind.stoppedStack,
          service: ServiceKey.dockge,
          title: 'immich',
        ),
      ).headline,
      'immich stopped',
    );
  });

  test('a headline in the service\'s own words loses its full stop', () {
    expect(
      faultWordsOf(
        _decision(
          DecisionKind.serviceHealth,
          service: ServiceKey.radarr,
          title: 'Missing root folder: /movies.',
        ),
      ).headline,
      'Missing root folder: /movies',
    );
  });

  test('the other kinds keep the control the Home row has', () {
    expect(
      faultActionLabel(
        _decision(DecisionKind.stoppedStack, service: ServiceKey.dockge),
      ),
      'Start',
    );
    expect(
      faultActionLabel(
        _decision(DecisionKind.storageAlert, service: ServiceKey.truenas),
      ),
      'Open alert',
    );
  });
}
