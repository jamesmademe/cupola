/// Sonarr's blocked imports: catalogue M-11 (an episode picked by hand) and M-13
/// (a download holding only a sample).
///
/// A real release reaches Sonarr's queue through the lab (scenarios
/// `import-sonarr-episode` and `import-sonarr-sample-only`, L13 phase C). Sonarr's
/// own download handling refuses to take it by itself, and the person finishes
/// the job from Activity's Needs you. Each case starts from the `l13-golden`
/// snapshot: a grab stays in Sonarr's history, which an API call cannot undo.
///
/// ~~~bash
/// flutter test integration_test/journeys/manual_import_queue_sonarr_journey_test.dart \
///   -d 403B5E0A-6A4E-4CB4-A151-87A6DA34E55F --tags e2e --run-skipped
/// ~~~
@Tags(['e2e'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'manual_import_driver.dart';
import 'testlab_journey_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The lab back at `l13-golden`, the case applied, the app on Activity.
  Future<({LabApp app, ManualImportDriver wizard, ArrApi sonarr})> open(
    WidgetTester tester,
    String scenario,
  ) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final lab = Lab.load();
    await lab.command(['reset', 'l13-golden']);
    await lab.command(['scenario', 'apply', scenario]);
    final app = await LabApp.asOperator(
      tester,
      lab: lab,
      services: const {ServiceKey.sonarr, ServiceKey.qbittorrent},
    );
    addTearDown(() => app.command(['scenario', 'teardown', scenario]));
    await app.go(tester, ServiceRoutes.activity);
    return (
      app: app,
      wizard: ManualImportDriver(tester, app),
      sonarr: ArrApi(
        'http://127.0.0.1:8989/api/v3',
        lab.arrKeys[ServiceKey.sonarr] ?? '',
      ),
    );
  }

  /// Needs you's card for the blocked download, then its `Review`.
  Future<void> review(WidgetTester tester, ManualImportDriver wizard) async {
    await wizard.need(
      find.textContaining('needs a manual import'),
      'Needs you never asked for the import',
      timeout: const Duration(minutes: 2),
    );
    await wizard.app.tapIn(tester, find.text('Review').first);
    await settle(tester, const Duration(seconds: 2));
  }

  testWidgets(
    'M-11 · a grab for one episode whose file is another: Add it anyway names the episode',
    (tester) async {
      final (:app, :wizard, :sonarr) = await open(
        tester,
        'import-sonarr-episode',
      );

      await review(tester, wizard);
      // Sonarr refused the file (it is another episode). Its row offers
      // `Add it anyway`, and the file then reads as S1 E3: the episode its
      // name names, so no picker is needed.
      await app.tapIn(tester, find.textContaining('Breaking.Bad.S01E').first);
      await settle(tester, const Duration(milliseconds: 800));
      await wizard.need(
        find.text('Add it anyway'),
        'the refused file row offered no Add it anyway',
      );
      await app.tapIn(tester, find.text('Add it anyway').first);
      await settle(tester, const Duration(milliseconds: 800));
      await wizard.need(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data ?? '').startsWith('Added') &&
              (widget.data ?? '').contains('E3'),
        ),
        'the refused file was not matched to S1 E3',
      );
      await app.tapIn(tester, find.text('Import 1 selected'));
      // The import leaves Track for Home once it lands: the library line says so.
      await wizard.need(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data ?? '').contains('is in your library'),
        ),
        'the import never reached the library',
        timeout: const Duration(minutes: 3),
      );

      final episode = await sonarr.episode('Breaking Bad', 1, 3);
      expect(
        await sonarr.episodeFilePath(episode),
        contains('S01E03'),
        reason: 'Sonarr holds no file for S01E03',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );

  testWidgets(
    'M-13 · a download holding only a sample: nothing to import, it is removed',
    (tester) async {
      final (:app, :wizard, :sonarr) = await open(
        tester,
        'import-sonarr-sample-only',
      );

      await review(tester, wizard);
      await app.surface.see('Nothing left to import');
      await app.tapIn(tester, find.text('Remove download'));
      await settle(tester, const Duration(seconds: 1));
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Remove download'),
        ),
      );
      await settle(tester, const Duration(seconds: 2));
      await app.surface.unsee(
        'Nothing left to import',
        timeout: const Duration(minutes: 1),
      );
      // The server answers the screen: the download is gone from Sonarr's queue.
      final end = DateTime.now().add(const Duration(minutes: 1));
      var titles = await sonarr.queueTitles();
      while (DateTime.now().isBefore(end) &&
          titles.any((title) => title.startsWith('Breaking.Bad.S02E01'))) {
        await settle(tester, const Duration(seconds: 2));
        titles = await sonarr.queueTitles();
      }
      expect(
        titles.where((title) => title.startsWith('Breaking.Bad.S02E01')),
        isEmpty,
        reason: 'Sonarr still holds the download',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
