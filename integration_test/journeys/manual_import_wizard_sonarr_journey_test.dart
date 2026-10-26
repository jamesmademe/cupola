/// The manual import wizard on Sonarr: catalogue M-01, M-02, M-06 and M-14.
///
/// Every case puts its own folder in the client's downloads through its
/// scenario (`import-series-*`, `import-season-pack`, in
/// `test/e2e/testlab/scenarios/import_wizard_cases.py`), drives the wizard from
/// Activity as a person would, and proves the result on Sonarr itself. The
/// scenario's teardown takes the imported files out of the library again, so
/// the cases run in any order and any number of times.
///
/// ~~~bash
/// flutter test integration_test/journeys/manual_import_wizard_sonarr_journey_test.dart \
///   -d 403B5E0A-6A4E-4CB4-A151-87A6DA34E55F --tags e2e --run-skipped
/// ~~~
@Tags(['e2e'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

import 'manual_import_driver.dart';
import 'testlab_journey_harness.dart';

const _root = '/downloads/manual-import';

/// The picker's row for episode [number] of the season: `E3 · <title>`, with a
/// no-break space before the dot.
Finder _episodeRow(int number) => find.byWidgetPredicate(
  (widget) =>
      widget is Text && RegExp('^E$number[  ]·').hasMatch(widget.data ?? ''),
);

/// Matches the file the sheet is on to [label] (`S1 E3`), once its row is
/// picked: the sheet then offers `Match to <label>`.
Future<void> _matchEpisode(
  WidgetTester tester,
  LabApp app,
  ManualImportDriver wizard,
  String label,
) async {
  final match = find.text('Match to $label');
  await wizard.need(match, 'the sheet never offered Match to $label');
  await app.tapIn(tester, match);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The app as Sonarr's operator, the case's folder in the downloads.
  Future<({LabApp app, ManualImportDriver wizard, ArrApi sonarr})> open(
    WidgetTester tester,
    String scenario,
  ) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final app = await LabApp.asOperator(
      tester,
      services: const {ServiceKey.sonarr},
    );
    await app.command(['scenario', 'apply', scenario]);
    addTearDown(() => app.command(['scenario', 'teardown', scenario]));
    return (
      app: app,
      wizard: ManualImportDriver(tester, app),
      sonarr: ArrApi(
        'http://127.0.0.1:8989/api/v3',
        app.lab.arrKeys[ServiceKey.sonarr] ?? '',
      ),
    );
  }

  testWidgets('M-01 · a Sonarr folder is found by browsing and scanned', (
    tester,
  ) async {
    final (:app, :wizard, sonarr: _) = await open(
      tester,
      'import-series-ready',
    );

    await wizard.openWizard(ServiceKey.sonarr);
    await wizard.goTo(_root);
    await wizard.openFolder('l13-series-ready');
    await wizard.scan('l13-series-ready');
    await app.surface.see('Matched files');
    await app.surface.see('Breaking Bad');
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets(
    'M-02 · two episodes named well go in by copy, and Sonarr keeps them',
    (tester) async {
      final (:app, :wizard, :sonarr) = await open(
        tester,
        'import-series-ready',
      );

      await wizard.openWizard(ServiceKey.sonarr);
      await wizard.reviewFolder('$_root/l13-series-ready');
      await app.surface.see('Matched files');
      await app.surface.seePart('2 of 2 selected');
      await wizard.mode('Copy');
      await wizard.confirmImport(2, service: 'Sonarr');
      await wizard.waitTrack('Completed');

      for (final number in [1, 2]) {
        final episode = await sonarr.episode('Breaking Bad', 1, number);
        expect(
          await sonarr.episodeFilePath(episode),
          contains('S01E0$number'),
          reason: 'Sonarr holds no file for S01E0$number',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets('M-06 · a season pack: the sample is drawn and left out', (
    tester,
  ) async {
    final (:app, :wizard, :sonarr) = await open(tester, 'import-season-pack');
    const folder = 'Breaking.Bad.S01.1080p.WEB-DL.DDP5.1.H.264-CUPOLA';

    await wizard.openWizard(ServiceKey.sonarr);
    await wizard.reviewFolder('$_root/$folder');
    // Four files, three episodes: the sample is drawn as one and the scan
    // leaves it out of the three it chooses.
    await app.surface.see('Sample');
    await app.surface.seePart('3 of 4 selected');
    // Copy, so the folder keeps its files for the second look below.
    await wizard.mode('Copy');
    await wizard.confirmImport(3, service: 'Sonarr');
    await wizard.waitTrack('Completed');

    for (final number in [1, 2, 3]) {
      final episode = await sonarr.episode('Breaking Bad', 1, number);
      expect(
        await sonarr.episodeFilePath(episode),
        allOf(contains('S01E0$number'), isNot(contains('sample'))),
        reason: 'Sonarr holds no episode file for S01E0$number',
      );
    }

    // Measured, not asserted (catalogue M-06, `Imported`): the folder read
    // again now that its episodes are in the library. The log holds what
    // Sonarr says about E3 and what the Review draws for the folder.
    await wizard.openWizard(ServiceKey.sonarr);
    await wizard.reviewFolder('$_root/$folder');
    final taken = await sonarr.episode('Breaking Bad', 1, 3);
    debugPrint(
      'MEASURE M-06 server S01E03 file: '
      '${await sonarr.episodeFilePath(taken)}',
    );
    debugPrint(
      'MEASURE M-06 the Review draws: ${app.surface.texts().join(' | ')}',
    );
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets(
    'M-14 · two files that name no episode are given one each by hand',
    (tester) async {
      final (:app, :wizard, :sonarr) = await open(tester, 'import-series-fix');

      await wizard.openWizard(ServiceKey.sonarr);
      await wizard.reviewFolder('$_root/l13-series-fix');
      await app.surface.see('Needs attention');
      // Each file is opened from the attention list's first row, which leaves
      // the list once matched: series, then episode, then `Match to`.
      for (final number in [3, 4]) {
        await wizard.openFix(0);
        await app.surface.see('Which series?');
        await wizard.search('Breaking Bad', hint: 'Search your series');
        await app.tapIn(tester, find.text('Breaking Bad').last);
        await app.surface.see('Which episode?');
        final row = _episodeRow(number);
        await wizard.need(row, 'the episode picker has no E$number');
        await app.tapIn(tester, row);
        await _matchEpisode(tester, app, wizard, 'S1 E$number');
      }
      await app.surface.seePart('2 of 2 selected');

      await wizard.confirmImport(2, service: 'Sonarr');
      await wizard.waitTrack('Completed');

      for (final number in [3, 4]) {
        final episode = await sonarr.episode('Breaking Bad', 1, number);
        expect(
          await sonarr.episodeFilePath(episode),
          contains('clip'),
          reason: 'Sonarr holds no clip for S01E0$number',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
