@Tags(['e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/prowlarr/data/prowlarr_service.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';

/// Prowlarr's five rows of the flow catalogue, A-13 to A-17, read through the
/// app's own client against the real container on 127.0.0.1:9696.
///
/// The lab is arranged by three scenarios, which this file applies in
/// `setUpAll` and takes apart again in `tearDownAll`:
///
/// ```
/// python3 test/e2e/testlab/testlab.py scenario apply prowlarr-indexers
/// python3 test/e2e/testlab/testlab.py scenario apply prowlarr-apps
/// python3 test/e2e/testlab/testlab.py scenario apply prowlarr-history
/// python3 test/e2e/testlab/testlab.py scenario teardown prowlarr-history
/// python3 test/e2e/testlab/testlab.py scenario teardown prowlarr-apps
/// python3 test/e2e/testlab/testlab.py scenario teardown prowlarr-indexers
/// ```
///
/// Each scenario is idempotent, so running this file twice in a row is safe.
/// The A-15 test deletes the scenario's throwaway indexer itself: the delete is
/// the flow, and `tearDownAll`'s scenario teardown then only reconciles Radarr,
/// which is where Prowlarr's own deletion stops.
void main() {
  const seeded = 'Cupola testlab';
  const throwaway = 'Cupola testlab throwaway';
  const syncProbe = 'Cupola testlab sync probe';
  const appProbe = 'Cupola testlab app';
  const e2eTag = 'cupola-testlab-e2e';
  const suffix = ' (Prowlarr)';

  ApiClient? client;
  late ProwlarrService service;

  setUpAll(() async {
    await _scenario('apply', 'prowlarr-indexers');
    await _scenario('apply', 'prowlarr-apps');
    await _scenario('apply', 'prowlarr-history');
    client = ApiClient(baseUrl: 'http://127.0.0.1:9696', apiKey: 'test-key');
    service = ProwlarrService(client!);
    final status = await client!.get('/api/v1/system/status');
    expect(status.statusCode, 200, reason: 'Prowlarr is not answering');
  });

  tearDownAll(() async {
    client?.close();
    await _scenario('teardown', 'prowlarr-history');
    await _scenario('teardown', 'prowlarr-apps');
    await _scenario('teardown', 'prowlarr-indexers');
  });

  test('A-13: an indexer is added, tested and read back', () async {
    final added = (await service.getIndexers())
        .where((indexer) => indexer.name == throwaway)
        .toList(growable: false);
    expect(added, hasLength(1), reason: 'the scenario adds exactly one');

    final indexer = added.single;
    expect(indexer.implementation, 'Torznab');
    expect(indexer.protocol, 'torrent');
    expect(indexer.enable, isTrue);
    expect(indexer.priority, 2, reason: 'the bulk edit of A-15');
    expect(indexer.indexerUrls, contains('http://testlab-indexer:8088'));

    // Prowlarr masks the key it stores, and the app never holds it in the
    // clear: what comes back is the mask, not the credential.
    final key = indexer.fields.where((field) => field.name == 'apiKey');
    expect(key, hasLength(1));
    expect(key.single.value, '********');

    // "Test": a 2xx is the tracker's own answer.
    await service.testIndexer(indexer.toPayload());

    // The same test against an address nothing answers on: Prowlarr refuses
    // with 400 and the reason, which the app shows as "Test failed".
    final broken = indexer.toPayload();
    for (final field in (broken['fields'] as List).cast<Map>()) {
      if (field['name'] == 'baseUrl') {
        field['value'] = 'http://testlab-indexer:1';
      }
    }
    await expectLater(
      service.testIndexer(broken),
      throwsA(
        predicate(
          (error) => error.toString().toLowerCase().contains('onnect'),
          'a refusal that says it could not connect',
        ),
      ),
    );
  });

  test(
    'A-14: every indexer is tested and the report is the tracker\'s',
    () async {
      final indexers = await service.getIndexers();
      final report = await service.testAllIndexers();

      expect(report, isNotEmpty);
      expect(
        report.where((result) => !result.isValid).map((result) => result.id),
        isEmpty,
        reason: 'an indexer failed its own test',
      );
      expect(
        report.map((result) => result.id).toSet(),
        containsAll(
          indexers.where((indexer) => indexer.enable).map((i) => i.id),
        ),
        reason: 'testall skipped an enabled indexer',
      );
      expect(
        report.map((result) => result.id).toSet(),
        containsAll([indexers.firstWhere((i) => i.name == throwaway).id]),
      );
    },
  );

  test('A-15: an indexer is disabled, edited in bulk and deleted', () async {
    final indexer = (await service.getIndexers()).firstWhere(
      (item) => item.name == throwaway,
    );

    await service.bulkUpdateIndexers(ids: [indexer.id], enable: false);
    expect(await _named(service, throwaway), isFalse, reason: 'still enabled');

    await service.bulkUpdateIndexers(
      ids: [indexer.id],
      enable: true,
      priority: 3,
    );
    final edited = await _indexer(service, throwaway);
    expect(edited.enable, isTrue);
    expect(edited.priority, 3, reason: 'the bulk edit did not land');

    await service.bulkDeleteIndexers([indexer.id]);
    expect(
      (await service.getIndexers()).where((item) => item.name == throwaway),
      isEmpty,
      reason: 'the deleted indexer is still listed',
    );
  });

  test('A-16: a tag is added, read back and deleted', () async {
    final created = await service.createTag(e2eTag);
    expect(created.id, greaterThan(0));
    addTearDown(() async {
      try {
        await service.deleteTag(created.id);
      } on Exception {
        // already gone: the test deleted it
      }
    });

    final details = await service.getTagDetails();
    expect(details.where((detail) => detail.label == e2eTag), hasLength(1));

    await service.deleteTag(created.id);
    expect(
      (await service.getTagDetails()).where((detail) => detail.label == e2eTag),
      isEmpty,
    );

    // The scenario's own tag is the one tied to an indexer, which is what the
    // tag manager's "used by" column reads.
    final scenarioTag = (await service.getTags()).firstWhere(
      (tag) => tag.label == 'cupola-testlab',
    );
    final tagged = (await service.getTagDetails()).firstWhere(
      (detail) => detail.id == scenarioTag.id,
    );
    expect(tagged.indexerIds, isNotEmpty);
  });

  test(
    'A-16: an app is tested and the sync carries the indexer to Radarr',
    () async {
      final app = (await service.getApplications()).firstWhere(
        (item) => item.name == appProbe,
      );
      expect(app.id, greaterThan(0));
      expect(app.isActive, isTrue, reason: 'the added app does not sync');

      // "Test" on an app Prowlarr already holds: the saved key is resolved
      // server side, so the masked one in the payload is not sent as a key.
      await service.testProvider(
        ProwlarrProviderKind.application,
        app.toPayload(),
      );

      final queued = await service.syncAppIndexers();
      var command = queued;
      for (var attempt = 0; attempt < 30 && !command.isFinished; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        command = await service.getCommand(queued.id);
      }
      expect(command.isFinished, isTrue, reason: 'the sync never finished');
      expect(command.isFailed, isFalse, reason: command.message);

      final radarr = await _arrIndexerNames('http://127.0.0.1:7878/api/v3');
      expect(radarr, contains('$syncProbe$suffix'));
      expect(
        radarr,
        contains('$seeded$suffix'),
        reason: 'the sync dropped the lab\'s own indexer',
      );

      // The fake indexer advertises Movies only, so the three apps whose sync
      // categories do not intersect it receive nothing.
      for (final root in const [
        'http://127.0.0.1:8989/api/v3',
        'http://127.0.0.1:8686/api/v1',
        'http://127.0.0.1:8787/api/v1',
      ]) {
        expect(
          await _arrIndexerNames(root),
          isNot(contains('$syncProbe$suffix')),
          reason: '$root received a movie-only indexer',
        );
      }

      await service.deleteProvider(ProwlarrProviderKind.application, app.id);
      expect(
        (await service.getApplications()).where(
          (item) => item.name == appProbe,
        ),
        isEmpty,
      );
    },
  );

  test(
    'A-17: history, statistics and failure state are the server\'s',
    () async {
      // The page the History screen's "All" tab reads. Which events sit on the
      // first page depends on how long the lab has been polling RSS, so the
      // event types themselves are proved by the scenario's numeric filters;
      // here the page is read for its envelope and its rows.
      final page = await service.getHistory(pageSize: 100);
      expect(page.totalRecords, greaterThan(0));
      expect(page.records, isNotEmpty);
      expect(page.page, 1);
      expect(page.pageSize, 100);
      for (final record in page.records) {
        expect(record.id, greaterThan(0));
        expect(record.eventType, isNotNull);
        expect(record.date, isNotNull);
        expect(record.data, isA<Map<String, dynamic>>());
      }

      // The History screen's tabs filter on the server. Prowlarr binds
      // eventType to its numeric enum, so the app's names must arrive
      // translated; a name would be a 400 and an empty tab.
      final queries = await service.getHistory(
        eventType: 'indexerQuery',
        pageSize: 100,
      );
      expect(queries.records, isNotEmpty);
      expect(
        queries.records.every((record) => record.eventType == 'indexerQuery'),
        isTrue,
      );
      final grabs = await service.getHistory(
        eventType: 'releaseGrabbed',
        pageSize: 100,
      );
      expect(grabs.records, isNotEmpty);
      expect(
        grabs.records.every((record) => record.eventType == 'releaseGrabbed'),
        isTrue,
      );

      final seededId = (await service.getIndexers())
          .firstWhere((indexer) => indexer.name == seeded)
          .id;
      final stats = await service.getIndexerStats();
      expect(stats.indexers, isNotEmpty);
      final seededStats = stats.indexers.firstWhere(
        (stat) => stat.indexerId == seededId,
      );
      expect(seededStats.numberOfQueries, greaterThan(0));
      expect(seededStats.numberOfGrabs, greaterThan(0));
      expect(
        stats.totalQueries,
        greaterThanOrEqualTo(seededStats.numberOfQueries),
      );
      expect(stats.totalGrabs, greaterThanOrEqualTo(seededStats.numberOfGrabs));

      // Only indexers Prowlarr has disabled after failures are listed: the lab
      // keeps its own healthy, so the list is empty or names a real indexer.
      final status = await service.getIndexerStatus();
      final known = (await service.getIndexers()).map((indexer) => indexer.id);
      for (final entry in status) {
        expect(known, contains(entry.indexerId));
      }

      final perIndexer = await service.getIndexerHistory(seededId);
      expect(perIndexer, isNotEmpty);
      expect(perIndexer.every((item) => item.indexerId == seededId), isTrue);
    },
  );

  test('the lab\'s own indexer and apps are left alone', () async {
    final indexer = (await service.getIndexers()).firstWhere(
      (item) => item.name == seeded,
    );
    expect(indexer.enable, isTrue);
    expect(indexer.priority, 1);
    expect(indexer.tags, isEmpty);

    final names = (await service.getApplications())
        .map((app) => app.name)
        .toSet();
    expect(
      names,
      containsAll(<String>['Radarr', 'Sonarr', 'Lidarr', 'Readarr']),
    );
    expect(names, isNot(contains(appProbe)));
  });
}

Future<void> _scenario(String action, String name) async {
  final result = await Process.run('python3', [
    'test/e2e/testlab/testlab.py',
    'scenario',
    action,
    name,
  ], workingDirectory: Directory.current.path);
  if (result.exitCode != 0) {
    fail(
      'testlab.py scenario $action $name failed: '
      '${result.stderr}\n${result.stdout}',
    );
  }
}

Future<ProwlarrIndexer> _indexer(ProwlarrService service, String name) async {
  return (await service.getIndexers()).firstWhere((item) => item.name == name);
}

Future<bool> _named(ProwlarrService service, String name) async {
  return (await _indexer(service, name)).enable;
}

Future<List<String>> _arrIndexerNames(String apiRoot) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('$apiRoot/indexer'));
    request.headers.set('X-Api-Key', 'test-key');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      fail('$apiRoot/indexer answered ${response.statusCode}: $body');
    }
    return (jsonDecode(body) as List)
        .cast<Map>()
        .map((indexer) => '${indexer['name']}')
        .toList(growable: false);
  } finally {
    client.close(force: true);
  }
}
