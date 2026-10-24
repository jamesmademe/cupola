/// Radarr's blocked imports: catalogue M-07 and M-11.
///
/// A real release reaches Radarr's queue through the lab (scenarios
/// `import-not-upgrade` and `import-sample-only`, L13 phase 0), Radarr's own
/// download handling refuses to take it by itself, and the person finishes the
/// job from Activity's Needs you. Each case starts from the `l13-golden`
/// snapshot: a grab stays in Radarr's history, and `Add it anyway` replaces a
/// movie's file, neither of which an API call can undo.
///
/// ~~~bash
/// flutter test integration_test/journeys/manual_import_queue_radarr_journey_test.dart \
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
  Future<({LabApp app, ManualImportDriver wizard, ImportReadings radarr})> open(
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
      services: const {ServiceKey.radarr, ServiceKey.qbittorrent},
    );
    addTearDown(() => app.command(['scenario', 'teardown', scenario]));
    await app.go(tester, ServiceRoutes.activity);
    return (
      app: app,
      wizard: ManualImportDriver(tester, app),
      radarr: ImportReadings(lab.arrKeys[ServiceKey.radarr] ?? ''),
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
    // The page is titled `Review`, like the button that opened it; its
    // `Why?` or its spent state say it is the blocked import's.
    await wizard.need(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data == 'Why?' || widget.data == 'Nothing left to import'),
      ),
      'the blocked import page never opened',
    );
  }

  testWidgets(
    'M-07 · a worse file Radarr refused goes in anyway and replaces the better',
    (tester) async {
      final (:app, :wizard, :radarr) = await open(tester, 'import-not-upgrade');
      final before = ImportReadings.fileOf(
        await radarr.movie('Big Buck Bunny', 2008),
      );
      expect(before.quality, 'WEBDL-1080p');

      await review(tester, wizard);
      await tester.tap(find.text('Why?').first);
      await settle(tester, const Duration(milliseconds: 600));
      await app.surface.seePart(
        'Radarr keeps the file it has unless the new one is better.',
      );
      await app.surface.seePart('What Radarr says');

      await app.surface.see(
        "It's no better than the file Radarr already has, so Radarr won't "
        'replace it.',
      );
      await app.surface.see(
        'Radarr refused it. It goes in only if you add it.',
      );
      // The refused file's row opens on its choices.
      await app.tapIn(tester, find.textContaining('Big.Buck.Bunny.20').last);
      await settle(tester, const Duration(milliseconds: 600));
      await wizard.need(find.text('Add it anyway'), 'no Add it anyway');
      await app.tapIn(tester, find.text('Add it anyway').first);
      await settle(tester, const Duration(milliseconds: 600));
      await app.surface.see('Leave it out');
      await app.tapIn(tester, find.text('Import 1 selected'));

      final end = DateTime.now().add(const Duration(minutes: 2));
      var after = before;
      while (DateTime.now().isBefore(end) && after.quality == before.quality) {
        await settle(tester, const Duration(seconds: 2));
        after = ImportReadings.fileOf(
          await radarr.movie('Big Buck Bunny', 2008),
        );
      }
      expect(after.quality, 'WEBDL-480p', reason: 'Radarr kept the 1080p');
      expect(after.path, contains('480p'));
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );

  testWidgets(
    'M-11 · a download holding only a sample: nothing to import, it is removed',
    (tester) async {
      final (:app, :wizard, :radarr) = await open(tester, 'import-sample-only');

      await review(tester, wizard);
      await app.surface.see('Nothing left to import');
      await app.tapIn(tester, find.text('Remove download'));
      await settle(tester, const Duration(seconds: 1));
      await app.surface.see("Remove Elephants Dream's download?");
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
      final end = DateTime.now().add(const Duration(minutes: 1));
      var queue = await radarr.queueTitles();
      while (DateTime.now().isBefore(end) &&
          queue.any((title) => title.startsWith('Elephants.Dream'))) {
        await settle(tester, const Duration(seconds: 2));
        queue = await radarr.queueTitles();
      }
      expect(
        queue.where((title) => title.startsWith('Elephants.Dream')),
        isEmpty,
        reason: 'Radarr still holds the download',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
    // Everything up to the confirmation passes; closing the page after the
    // removal trips Riverpod 3.2.1's paused-subscription assertion every
    // time (`pausedActiveSubscriptionCount`), in the dashboard decisions'
    // provider. Riverpod 3.3.2 fixes an unpause assertion: the upgrade is
    // its own lot, and this case runs again with it.
    skip: true,
  );
}
