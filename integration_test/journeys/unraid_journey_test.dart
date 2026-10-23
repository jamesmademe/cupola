/// The Unraid rows of the catalog, I-16 to I-18.
///
/// The world: the `unraid-state` scenario. The server has four VMs in four
/// libvirt states, three unread notifications, a started array with a disabled
/// disk, fourteen containers and three shares. The scenario resets the world
/// before every test, so a failed run leaves the simulator in its base state.
@Tags(['e2e'])
@Timeout(Duration(minutes: 20))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'testlab_journey_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<LabApp> openUnraid(
    WidgetTester tester, {
    Map<ServiceKey, String>? apiKeys,
  }) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final lab = Lab.load();
    await lab.command(['scenario', 'apply', 'unraid-state']);
    addTearDown(() => lab.command(['scenario', 'teardown', 'unraid-state']));
    return LabApp.asOperator(
      tester,
      lab: lab,
      services: const {ServiceKey.unraid},
      apiKeys: apiKeys,
    );
  }

  testWidgets('I-16 · a VM starts, stops and resumes', (tester) async {
    final app = await openUnraid(tester);
    await app.go(tester, ServiceRoutes.unraidVms);
    await app.surface.see('Virtual machines');
    await app.surface.see('Windows 11 lab');
    // The only guest in this state, and the tooltip whose verb names the
    // action the state offers: together they say which row changed.
    await app.surface.see('stopped');
    expect(find.byTooltip('start Windows 11 lab'), findsOneWidget);

    await tester.tap(find.byTooltip('start Windows 11 lab'));
    await settle(tester, const Duration(seconds: 1));
    await app.surface.unsee('stopped');
    expect(find.byTooltip('stop Windows 11 lab'), findsOneWidget);

    await tester.tap(find.byTooltip('stop Windows 11 lab'));
    await settle(tester, const Duration(milliseconds: 700));
    await app.surface.see('Stop Windows 11 lab?');
    await tester.tap(find.text('Stop VM'));
    await settle(tester, const Duration(seconds: 1));
    await app.surface.see('stopped');
    expect(find.byTooltip('start Windows 11 lab'), findsOneWidget);

    // The paused guest is the one state whose control is Resume; pausing has
    // no control of its own, so the write the screen offers is the one proven.
    await app.surface.see('paused');
    await tester.tap(find.byTooltip('resume NAS backup'));
    await settle(tester, const Duration(seconds: 1));
    await app.surface.unsee('paused');
    expect(find.byTooltip('stop NAS backup'), findsOneWidget);
  });

  testWidgets('I-16/I-17 · a read-only key can read and is told what it '
      'cannot', (tester) async {
    final app = await openUnraid(
      tester,
      apiKeys: const {ServiceKey.unraid: 'cupola-readonly'},
    );

    await app.go(tester, ServiceRoutes.unraidVms);
    await app.surface.see('Virtual machines');
    await app.surface.seePart(
      'This Unraid key can read. Starting and stopping VMs needs a key with '
      'write access to VMs.',
    );
    await app.surface.see('stopped');

    await tester.tap(find.byTooltip('start Windows 11 lab'));
    await settle(tester, const Duration(seconds: 1));
    await app.surface.see("This Unraid key can't start or stop VMs.");
    // The refusal is the answer, and the guest is where it was.
    await app.surface.see('stopped');

    await app.go(tester, ServiceRoutes.unraidNotifications);
    await app.surface.see('Unread notifications');
    await app.surface.seePart(
      'This Unraid key can read. Archiving notifications needs a key with '
      'write access to notifications.',
    );
    await app.surface.seePart('Cache drive temperature is 47 C');
  });

  testWidgets('I-17 · the unread notifications are archived away', (
    tester,
  ) async {
    final app = await openUnraid(tester);
    await app.go(tester, ServiceRoutes.unraidNotifications);
    await app.surface.see('Unread notifications');
    await app.surface.seePart('Cache drive temperature is 47 C');
    await app.surface.seePart('Disk 2 in error state');
    await app.surface.seePart('Parity check finished');

    for (var i = 0; i < 3; i++) {
      final archive = find.byTooltip('Archive notification');
      expect(archive, findsWidgets);
      await tester.tap(archive.first);
      await settle(tester, const Duration(seconds: 1));
    }

    await app.surface.see('No unread notifications.');
  });

  testWidgets('I-18 · the array, the containers and the shares', (
    tester,
  ) async {
    final app = await openUnraid(tester);

    await app.go(tester, ServiceRoutes.unraidOverview);
    await app.surface.see('Array');
    // The overview's headline is a sentence, so its state word is lower case.
    await app.surface.seePart('started');
    await app.surface.seePart('1 slot flagged');
    await app.surface.see('Disk 2');
    await app.surface.see('Disabled');
    await app.surface.see('Docker');
    await app.surface.seePart('14 containers');

    await app.go(tester, ServiceRoutes.unraidArray);
    await app.surface.see('Array disks');
    await app.surface.see('Disk 2');
    await app.surface.see('Disabled');

    await app.go(tester, ServiceRoutes.unraidDocker);
    await app.surface.see('Containers');
    await app.surface.seePart('14 containers');
    await app.surface.see('plex');
    await app.surface.see('readarr');
    await app.surface.see('nzbget');
    await app.surface.seePart('exit 137');
    await app.surface.seePart('4 hours ago');

    await app.go(tester, ServiceRoutes.unraidShares);
    await app.surface.see('Shares');
    await app.surface.see('media');
    await app.surface.seePart('Movies, series and music');
    await app.surface.seePart('60% used');
    await app.surface.see('appdata');
    await app.surface.seePart('cached');
    await app.surface.see('backups');
  });
}
