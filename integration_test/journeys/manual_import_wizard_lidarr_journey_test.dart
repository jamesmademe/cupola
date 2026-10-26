/// The manual import wizard on Lidarr: catalogue M-01, M-02 and M-14.
///
/// Every case puts its own tracks in the client's downloads through its
/// scenario (`import-album-ready`, `import-track-fix`, in
/// `test/e2e/testlab/scenarios/import_wizard_cases.py`), drives the wizard from
/// Activity as a person would, and proves the result on Lidarr itself. The
/// scenario's teardown takes the imported track files out of the library
/// again, so the cases run in any order and any number of times.
///
/// ~~~bash
/// flutter test integration_test/journeys/manual_import_wizard_lidarr_journey_test.dart \
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

  /// The app as Lidarr's operator, the case's folder in the downloads.
  Future<({LabApp app, ManualImportDriver wizard, ArrApi lidarr})> open(
    WidgetTester tester,
    String scenario,
  ) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final app = await LabApp.asOperator(
      tester,
      services: const {ServiceKey.lidarr},
    );
    await app.command(['scenario', 'apply', scenario]);
    addTearDown(() => app.command(['scenario', 'teardown', scenario]));
    return (
      app: app,
      wizard: ManualImportDriver(tester, app),
      lidarr: ArrApi(
        'http://127.0.0.1:8686/api/v1',
        app.lab.arrKeys[ServiceKey.lidarr] ?? '',
      ),
    );
  }

  testWidgets('M-01 · a Lidarr folder is found by browsing and scanned', (
    tester,
  ) async {
    final (:app, :wizard, lidarr: _) = await open(tester, 'import-album-ready');

    await wizard.openWizard(ServiceKey.lidarr);
    await wizard.goTo(_root);
    await wizard.openFolder('l13-album-ready');
    await wizard.scan('l13-album-ready');
    await app.surface.see('Matched files');
    await app.surface.seePart('Moon Safari');
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets(
    'M-02 · an album named well goes in by copy, and Lidarr keeps its tracks',
    (tester) async {
      final (:app, :wizard, :lidarr) = await open(tester, 'import-album-ready');

      await wizard.openWizard(ServiceKey.lidarr);
      await wizard.reviewFolder('$_root/l13-album-ready');
      await app.surface.see('Matched files');
      await app.surface.seePart('3 of 3 selected');
      await wizard.mode('Copy');
      await wizard.confirmImport(3, service: 'Lidarr');
      await wizard.waitTrack('Completed');

      await lidarr.albumTracksWithFiles('Air', 'Moon Safari', [
        'a1',
        'a2',
        'a3',
      ]);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'M-14 · a track whose name says nothing is given an album and a track by hand',
    (tester) async {
      final (:app, :wizard, :lidarr) = await open(tester, 'import-track-fix');

      await wizard.openWizard(ServiceKey.lidarr);
      await wizard.reviewFolder('$_root/l13-track-fix');
      await app.surface.see('Needs attention');
      await wizard.openFix(0);
      await wizard.search('Air', hint: 'Search your artists');
      await app.tapIn(tester, find.text('Air').last);
      await app.surface.see('Which album?');
      await app.tapIn(tester, find.text('Moon Safari').last);
      await app.surface.see('Which track?');
      await wizard.need(
        find.textContaining('Sexy Boy'),
        'the track picker has no Sexy Boy',
      );
      await app.tapIn(tester, find.textContaining('Sexy Boy').last);
      await app.surface.see('Match to track 2');
      await app.tapIn(tester, find.text('Match to track 2'));

      await wizard.confirmImport(1, service: 'Lidarr');
      await wizard.waitTrack('Completed');

      await lidarr.albumTracksWithFiles('Air', 'Moon Safari', ['a2']);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
