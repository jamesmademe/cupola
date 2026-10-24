/// The manual import wizard on Radarr: catalogue M-01, M-02, M-03, M-08, M-09,
/// M-14 and M-15.
///
/// Every case puts its own folder in the client's downloads through its
/// scenario (`import-*`, `test/e2e/testlab/scenarios/import_wizard_cases.py`),
/// drives the wizard from Activity as a person would, and proves the result on
/// Radarr itself. The scenario's teardown takes the imported files out of the
/// library again, so the cases run in any order and any number of times.
///
/// ~~~bash
/// flutter test integration_test/journeys/manual_import_wizard_radarr_journey_test.dart \
///   -d 403B5E0A-6A4E-4CB4-A151-87A6DA34E55F --tags e2e --run-skipped
/// ~~~
@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

import 'manual_import_driver.dart';
import 'testlab_journey_harness.dart';

const _root = '/downloads/manual-import';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The app as Radarr's operator, the case's folder in the downloads.
  Future<({LabApp app, ManualImportDriver wizard, ImportReadings radarr})> open(
    WidgetTester tester,
    String scenario,
  ) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final app = await LabApp.asOperator(
      tester,
      services: const {ServiceKey.radarr},
    );
    await app.command(['scenario', 'apply', scenario]);
    addTearDown(() => app.command(['scenario', 'teardown', scenario]));
    return (
      app: app,
      wizard: ManualImportDriver(tester, app),
      radarr: ImportReadings(app.lab.arrKeys[ServiceKey.radarr] ?? ''),
    );
  }

  testWidgets(
    'M-01 · a folder is found by its path, browsed into and scanned',
    (tester) async {
      final (:app, :wizard, radarr: _) = await open(tester, 'import-locate');
      const folder = 'Spring.2014.1080p.WEB-DL.DDP5.1.H.264-CUPOLA';

      await wizard.openWizard(ServiceKey.radarr);
      // Locate opens on the server's top folder, already chosen, so the
      // primary reads `Scan "/"` rather than `Choose a folder`.
      await app.surface.see('Scan "/"');
      await app.surface.seePart('Scanning parses and probes every file');
      await wizard.goTo(_root);
      await wizard.openFolder(folder);
      await app.surface.see('No subfolders here');
      await wizard.scan(folder);
      await app.surface.see('Matched files');
      await app.surface.see('Spring');
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets('M-01 · Radarr down: the wizard says it cannot import', (
    tester,
  ) async {
    final (:app, :wizard, radarr: _) = await open(tester, 'import-locate');
    addTearDown(() => app.command(['fault', 'radarr', 'clear']));
    await app.command(['fault', 'radarr', 'down']);

    await wizard.openWizard(ServiceKey.radarr);
    await app.surface.see('Manual import unavailable');
    await app.surface.see('Retry');
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets(
    'M-02 · M-15 · two ready files go in by copy, and the import is tracked',
    (tester) async {
      final (:app, :wizard, :radarr) = await open(tester, 'import-ready');

      await wizard.openWizard(ServiceKey.radarr);
      await wizard.reviewFolder('$_root/l13-ready');
      await app.surface.see('Matched files');
      await app.surface.seePart('2 of 2 selected');
      await wizard.mode('Copy');
      await wizard.confirmImport(2);

      await wizard.waitTrack('Completed');
      await app.surface.see('Started');
      await app.surface.see('Duration');
      await app.surface.see('Files');
      await app.surface.see('Per-file results appear in Activity → History.');

      final sintel = await radarr.movieWithFile(tester, 'Sintel', 2010);
      final tears = await radarr.movieWithFile(tester, 'Tears of Steel', 2012);
      expect(ImportReadings.fileOf(sintel).path, contains('Sintel.2010'));
      expect(ImportReadings.fileOf(tears).path, contains('Tears.of.Steel'));

      // A finished import offers `Done` (to Activity); `Back to review` is
      // the failed import's. The frame's back arrow returns to the Review.
      await tester.tap(find.byTooltip('Back').first);
      await settle(tester, const Duration(seconds: 2));
      // Copied files stay in the folder, so the Review lists them as the
      // batch it sent, each with the command's result.
      await app.surface.see('Sent to import');
      await app.surface.see('2 files were sent to Radarr');
      expect(find.text('Completed'), findsNWidgets(2));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'M-03 · a file no name explains is matched by hand and imported',
    (tester) async {
      final (:app, :wizard, :radarr) = await open(
        tester,
        'import-unrecognised',
      );

      await wizard.openWizard(ServiceKey.radarr);
      await wizard.reviewFolder(
        '$_root/The.Fright.Sprite.2024.1080p.WEB-DL.DDP5.1.H.264-CUPOLA',
      );
      await app.surface.see('Needs attention');
      await app.surface.see('1 needs a match');
      // Radarr's `Unknown Movie` is a permanent rejection: `No match`, not
      // `Needs match`.
      await app.surface.see('No match');
      await wizard.openFix();
      await app.surface.see('Which movie?');
      await wizard.search('Sprite Fright');
      await wizard.matchTo('Sprite Fright');
      await wizard.confirmImport(1);
      await wizard.waitTrack('Completed');

      final movie = await radarr.movieWithFile(tester, 'Sprite Fright', 2024);
      expect(ImportReadings.fileOf(movie).path, contains('Fright.Sprite'));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets('M-08 · the sample is shown, never chosen, and stays out', (
    tester,
  ) async {
    final (:app, :wizard, :radarr) = await open(tester, 'import-sample');

    await wizard.openWizard(ServiceKey.radarr);
    await wizard.reviewFolder(
      '$_root/Elephants.Dream.2006.1080p.WEB-DL.DDP5.1.H.264-CUPOLA',
    );
    await app.surface.see('Sample');
    // The scan chooses the feature and leaves the sample out.
    await wizard.confirmImport(1);
    await wizard.waitTrack('Completed');

    final movie = await radarr.movieWithFile(tester, 'Elephants Dream', 2006);
    expect(ImportReadings.fileOf(movie).path, isNot(contains('sample')));
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('M-09 · a quality and a language chosen by hand reach Radarr', (
    tester,
  ) async {
    final (:app, :wizard, :radarr) = await open(
      tester,
      'import-unknown-quality',
    );

    await wizard.openWizard(ServiceKey.radarr);
    await wizard.reviewFolder('$_root/l13-unknown-quality');
    await app.surface.see('Coffee Run');
    await app.tapIn(tester, find.text('Coffee Run').first);
    await settle(tester, const Duration(milliseconds: 800));

    await app.surface.see('Quality');
    await tester.tap(find.text('Quality'));
    await settle(tester, const Duration(milliseconds: 800));
    await app.surface.see('Select quality');
    await app.tapIn(tester, find.text('WEBDL-720p').last);
    await settle(tester, const Duration(milliseconds: 800));
    // A choice closes the sheet: the row is opened again for the language.
    await app.surface.seePart('WEBDL-720p');
    await app.tapIn(tester, find.text('Coffee Run').first);
    await settle(tester, const Duration(milliseconds: 800));

    await app.surface.see('Languages');
    await tester.tap(find.text('Languages'));
    await settle(tester, const Duration(milliseconds: 800));
    await app.surface.see('Select languages');
    await app.tapIn(tester, find.text('Italian').last);
    await app.tapIn(tester, find.text('English').last);
    // The button closes a long list of languages: brought into view first.
    await app.tapIn(tester, find.text('Apply languages'));
    await settle(tester, const Duration(milliseconds: 800));
    await app.surface.seePart('Italian');

    await wizard.confirmImport(1);
    await wizard.waitTrack('Completed');

    final file = ImportReadings.fileOf(
      await radarr.movieWithFile(tester, 'Coffee Run', 2020),
    );
    expect(file.quality, 'WEBDL-720p');
    expect(file.languages, ['Italian']);
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets(
    'M-14 · the search says when nothing matches, then a match goes in',
    (tester) async {
      final (:app, :wizard, :radarr) = await open(tester, 'import-fix-match');

      await wizard.openWizard(ServiceKey.radarr);
      await wizard.reviewFolder('$_root/l13-fix-match');
      await app.surface.see('Needs attention');
      await wizard.openFix(0);
      await wizard.search('Zzqx');
      await app.surface.see('Nothing called "Zzqx"');
      await wizard.search('Charge');
      await wizard.matchTo('Charge');
      // `Chosen for <file>` belongs to the episode picker (Sonarr); a movie
      // has no such mark, so the Sonarr journey proves it.
      await app.surface.see('1 needs a match');

      await wizard.confirmImport(1);
      await wizard.waitTrack('Completed');
      final movie = await radarr.movieWithFile(tester, 'Charge', 2022);
      expect(ImportReadings.fileOf(movie).path, contains('clip'));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets('M-15 · the Track screen before any import', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final app = await LabApp.asOperator(
      tester,
      services: const {ServiceKey.radarr},
    );
    await app.go(tester, '/import/progress?service=radarr');
    await app.surface.see('Import has not started');
    await app.surface.see('Go back and confirm selected files to begin.');
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('M-15 · a file gone before the import: the import fails', (
    tester,
  ) async {
    final (:app, :wizard, radarr: _) = await open(tester, 'import-failed');

    await wizard.openWizard(ServiceKey.radarr);
    await wizard.reviewFolder('$_root/Jaws.1975.1080p.BluRay.x264-CUPOLA');
    await app.surface.see('Jaws');
    // The file leaves the server between the scan and the confirmation.
    await app.command(['scenario', 'teardown', 'import-failed']);
    await wizard.confirmImport(1);
    await wizard.waitTrack('Failed');
    await app.surface.see('Retry');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
