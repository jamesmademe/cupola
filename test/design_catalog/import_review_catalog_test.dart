@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';
import 'package:cupola/features/activity/presentation/widgets/import_done_card.dart';
import 'package:cupola/features/import/domain/blocked_import.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/presentation/blocked_import_parts.dart';
import 'package:cupola/features/import/presentation/blocked_import_review_page.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/blocked_import_world.dart';
import 'catalog.dart';

final _clear = [
  for (final (season, episode) in cosmosClearEpisodes)
    ManualImportItem.fromJson(cosmosClearFile(season, episode)),
];

final _replacing = {for (final file in _clear) file.path: 'HDTV-720p'};

ManualImportItem _tape(int n) => ManualImportItem.fromJson(cosmosTapeFile(n));

/// The third tape, placed on S1 E3 by the user.
final _placed = ManualImportItem.fromJson({
  ...cosmosTapeFile(3),
  'seasonNumber': 1,
  'episodes': [
    {'id': 2103, 'seasonNumber': 1, 'episodeNumber': 3, 'title': 'Episode 3'},
  ],
  'rejections': const [],
});

ManualImportCommandStatus _command(String status) =>
    ManualImportCommandStatus.fromJson({
      'id': 41,
      'name': 'ManualImport',
      'status': status,
      if (status == 'failed')
        'exception':
            'Destination already exists. '
            '/mnt/tank/media/series/Cosmos Laundromat/Season 01',
    });

ImportReport _report(String status) => (
  service: ServiceKey.sonarr,
  instanceId: blockedImportConnection,
  command: _command(status),
  endedAt: null,
  files: _clear,
  replacing: _replacing,
);

Widget _needYou({bool openFirst = true}) => ActivitySlab(
  children: [
    BlockedImportNeedYouRow(
      service: ServiceKey.sonarr,
      item: _tape(1),
      kind: NeedYouKind.episode,
      selected: false,
      open: openFirst,
      onOpen: () {},
      onPlaced: () {},
    ),
    BlockedImportNeedYouRow(
      service: ServiceKey.sonarr,
      item: _tape(2),
      kind: NeedYouKind.episode,
      selected: false,
      open: false,
      onOpen: () {},
      onPlaced: () {},
      divided: true,
    ),
    BlockedImportNeedYouRow(
      service: ServiceKey.sonarr,
      item: _placed,
      kind: NeedYouKind.episode,
      selected: true,
      open: false,
      onOpen: () {},
      onPlaced: () {},
      divided: true,
    ),
  ],
);

void main() {
  catalogCard(
    'ImportReview',
    scenes: [
      CatalogScene(
        'BlockedImportReviewPage() · Review 18 imports: the sentence, Why?, '
        'the jump between the two parts, twelve clear matches selected, and '
        'the bar',
        (_) => const BlockedImportReviewPage(
          service: ServiceKey.sonarr,
          instanceId: blockedImportConnection,
        ),
        width: 390,
        height: 844,
        overrides: blockedImportOverrides(FakeBlockedImportService()),
      ),
      CatalogScene(
        'BlockedImportReviewPage() · nothing left to import: Sonarr took what '
        'the pack had and keeps it queued for the rest; Remove download',
        (_) => const BlockedImportReviewPage(
          service: ServiceKey.sonarr,
          instanceId: blockedImportConnection,
        ),
        width: 390,
        height: 844,
        overrides: blockedImportOverrides(
          spentPackService(),
          queue: spentPackQueue(),
        ),
      ),
      CatalogScene(
        'BlockedImportReviewPage() · nothing left to import: a download that '
        'held only a sample, so nothing went in; Remove download',
        (_) => const BlockedImportReviewPage(
          service: ServiceKey.sonarr,
          instanceId: blockedImportConnection,
        ),
        width: 390,
        height: 844,
        overrides: blockedImportOverrides(
          sampleOnlyService(),
          queue: sampleOnlyQueue(),
        ),
      ),
      CatalogScene(
        'BlockedImportReviewPage() · Sonarr grabbed S1 E1 and the file is '
        'S1 E3: the sentence for what Sonarr 4 says',
        (_) => const BlockedImportReviewPage(
          service: ServiceKey.sonarr,
          instanceId: blockedImportConnection,
        ),
        width: 390,
        height: 844,
        overrides: blockedImportOverrides(
          wrongEpisodeService(),
          queue: wrongEpisodeQueue(),
        ),
      ),
      CatalogScene(
        "BlockedImportWhy() · open: what Sonarr says, word for word, and the "
        'same in plain words',
        (_) => BlockedImportWhy(
          service: ServiceKey.sonarr,
          messages: const [cosmosMessage],
          plain: blockedImportPlainWords(
            ServiceKey.sonarr,
            BlockedImportCause.namesDontMatch,
            title: 'Cosmos Laundromat',
            total: 18,
            unnamed: 6,
          ),
        ),
        width: 390,
      ),
      CatalogScene(
        'BlockedImportClearGroup() · the clear files of one title: what they '
        'bring and replace, Clear all, a row per episode in ink',
        (_) => BlockedImportClearGroup(
          service: ServiceKey.sonarr,
          title: 'Cosmos Laundromat',
          files: _clear.take(4).toList(),
          selected: {for (final file in _clear.take(3)) file.path},
          replacing: _replacing,
          onToggle: (_, _) {},
          onAll: (_, _) {},
        ),
        width: 390,
      ),
      CatalogScene(
        'BlockedImportNeedYouRow() · open on its series, season and episode; '
        'one waiting; one the user placed',
        (_) => _needYou(),
        width: 390,
      ),
      CatalogScene(
        'BlockedImportBar() · six left for later, then one picked by the user',
        (_) => const Column(
          children: [
            BlockedImportBar(
              line: '6 left for later',
              label: 'Import 12 clear matches',
              onImport: _noop,
            ),
            SizedBox(height: 12),
            BlockedImportBar(
              line: '12 clear · 1 picked by you',
              label: 'Import 13 selected',
              onImport: _noop,
            ),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'ImportDoneCard() · running: blue, read again every two seconds',
        (_) => ActivitySlab(
          children: [ImportDoneCard(report: _report('started'))],
        ),
        width: 390,
      ),
      CatalogScene(
        'ImportDoneCard(whole: true) · done: what went in, the episodes on a '
        'grid, the step in quality, Open in library',
        (_) => ActivitySlab(
          children: [ImportDoneCard(report: _report('completed'), whole: true)],
        ),
        width: 390,
      ),
      CatalogScene(
        "ImportDoneCard() · failed: a fault, Sonarr's words behind Why?, Retry",
        (_) =>
            ActivitySlab(children: [ImportDoneCard(report: _report('failed'))]),
        width: 390,
      ),
      CatalogScene(
        'Text at 200% · a row open on its choice',
        (_) => _needYou(),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'On the desktop · the clear files and the bar in the page well',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlockedImportClearGroup(
              service: ServiceKey.sonarr,
              title: 'Cosmos Laundromat',
              files: _clear.take(3).toList(),
              selected: {for (final file in _clear.take(3)) file.path},
              replacing: _replacing,
              onToggle: (_, _) {},
              onAll: (_, _) {},
            ),
            const SizedBox(height: 12),
            const BlockedImportBar(
              line: '6 left for later',
              label: 'Import 12 clear matches',
              onImport: _noop,
            ),
          ],
        ),
        width: 560,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}

void _noop() {}
