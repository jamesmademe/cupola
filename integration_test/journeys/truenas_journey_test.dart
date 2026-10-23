/// The TrueNAS rows of the catalog, I-09 to I-15.
///
/// The world: the `truenas-state` scenario. The NAS has a healthy `tank` and
/// a degraded `backup`, a dataset tree, shares, users, a stopped NFS service,
/// an app with an upgrade waiting, a stopped VM and active alerts. The
/// scenario is applied before each test and torn down after it, so a failed
/// run leaves the simulator in its base world.
@Tags(['e2e'])
@Timeout(Duration(minutes: 20))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'testlab_journey_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<LabApp> openTrueNas(
    WidgetTester tester, {
    Map<ServiceKey, String>? apiKeys,
  }) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final lab = Lab.load();
    await lab.command(['scenario', 'apply', 'truenas-state']);
    addTearDown(() => lab.command(['scenario', 'teardown', 'truenas-state']));
    return LabApp.asOperator(
      tester,
      lab: lab,
      services: const {ServiceKey.truenas},
      apiKeys: apiKeys,
    );
  }

  Finder rowOf(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(Row)).first;

  Future<void> submit(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    // A form sheet closes, but the software keyboard outlives it and covers
    // the next page's FAB. Drop focus the way a tap outside would.
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester, const Duration(seconds: 1));
  }

  testWidgets('I-09 · a scrub starts from the pool page', (tester) async {
    final app = await openTrueNas(tester);
    await app.go(tester, ServiceRoutes.truenasStorage);
    await app.surface.see('Storage');
    await app.surface.see('tank');

    await tester.tap(find.text('tank'));
    await settle(tester, const Duration(seconds: 1));
    expect(find.byTooltip('Start scrub'), findsOneWidget);

    await tester.tap(find.byTooltip('Start scrub'));
    await settle(tester, const Duration(milliseconds: 700));
    await app.surface.see('Start scrub?');
    await tester.tap(find.text('Start scrub'));
    await app.surface.see('Scrub started on tank');
  });

  testWidgets('I-10 · a dataset, its snapshots and the way back', (
    tester,
  ) async {
    final app = await openTrueNas(tester);
    await app.go(tester, ServiceRoutes.truenasDatasets);
    await app.surface.see('Datasets');

    await tester.tap(find.text('New dataset'));
    await settle(tester, const Duration(seconds: 1));
    final createFields = find.byType(TextField);
    await tester.enterText(createFields.at(0), 'tank/cupola-journey');
    await submit(tester, 'Create');
    await app.surface.see('Created tank/cupola-journey');

    await app.go(tester, ServiceRoutes.truenasDataset('tank/cupola-journey'));
    await app.surface.see('cupola-journey');
    // The title comes from the path; the menu appears with the dataset.
    await app.surface.see('Snapshots');

    // PopupMenuButton has no explicit icon: on iOS its adaptive default is
    // the horizontal dots, so the menu is found by type, not by glyph.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await settle(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Edit'));
    await settle(tester, const Duration(seconds: 1));
    final editFields = find.byType(TextField);
    await tester.enterText(editFields.at(0), 'the journey');
    await submit(tester, 'Save');
    await app.surface.see('Updated cupola-journey');

    await tester.tap(find.text('New'));
    await settle(tester, const Duration(seconds: 1));
    await tester.enterText(find.byType(TextField).first, 'journey-1');
    await submit(tester, 'Create');
    await app.surface.see('Snapshot created');
    await app.surface.see('journey-1');

    await tester.tap(find.byTooltip('Delete snapshot'));
    await settle(tester, const Duration(milliseconds: 500));
    await app.surface.see('Delete snapshot?');
    await submit(tester, 'Delete snapshot');
    await app.surface.see('Snapshot deleted');

    await tester.tap(find.byType(PopupMenuButton<String>));
    await settle(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Delete dataset'));
    await settle(tester, const Duration(milliseconds: 500));
    await app.surface.see('Delete cupola-journey?');
    await submit(tester, 'Delete dataset');
    await app.surface.see('Deleted cupola-journey');
  });

  testWidgets('I-11 · SMB and NFS shares are created and removed', (
    tester,
  ) async {
    final app = await openTrueNas(tester);
    await app.go(tester, ServiceRoutes.truenasShares);
    await app.surface.see('Shares');

    await tester.tap(find.byTooltip('New'));
    await settle(tester, const Duration(seconds: 1));
    await app.surface.see('New SMB share');
    final smbFields = find.byType(TextField);
    await tester.enterText(smbFields.at(0), '/mnt/tank/cupola-journey');
    await tester.enterText(smbFields.at(1), 'cupola-journey');
    await submit(tester, 'Create');
    await app.surface.see('SMB share created');
    await app.surface.see('cupola-journey');

    await tester.tap(
      find.descendant(
        of: rowOf('cupola-journey'),
        matching: find.byType(Switch),
      ),
    );
    await app.surface.see('Disabled');
    await tester.tap(
      find.descendant(
        of: rowOf('cupola-journey'),
        matching: find.byType(Switch),
      ),
    );
    await app.surface.see('Enabled');

    await tester.tap(
      find.descendant(
        of: rowOf('cupola-journey'),
        matching: find.byTooltip('Delete share'),
      ),
    );
    await settle(tester, const Duration(milliseconds: 500));
    await app.surface.see('Delete "cupola-journey"?');
    await submit(tester, 'Delete share');
    await app.surface.see('Deleted "cupola-journey"');
    // The success toast floats above the bar and over the next tab's FAB:
    // let it leave before reaching for the control underneath it.
    await app.surface.unsee('Deleted "cupola-journey"');

    await tester.tap(find.text('NFS'));
    await settle(tester, const Duration(seconds: 1));
    await tester.tap(find.byTooltip('New'));
    await settle(tester, const Duration(seconds: 1));
    await app.surface.see('New NFS export');
    await tester.enterText(find.byType(TextField).first, '/mnt/tank/journey');
    await submit(tester, 'Create');
    await app.surface.see('NFS export created');

    await tester.tap(
      find.descendant(
        of: rowOf('/mnt/tank/journey'),
        matching: find.byTooltip('Delete share'),
      ),
    );
    await settle(tester, const Duration(milliseconds: 500));
    await submit(tester, 'Delete share');
    await app.surface.seePart('Deleted "/mnt/tank/journey"');
  });

  testWidgets('I-12 · users, groups and system services', (tester) async {
    final app = await openTrueNas(tester);
    await app.go(tester, ServiceRoutes.truenasSystemSection('credentials'));
    await app.surface.see('Credentials');

    await tester.tap(find.byTooltip('New'));
    await settle(tester, const Duration(seconds: 1));
    await app.surface.see('New user');
    final userFields = find.byType(TextField);
    await tester.enterText(userFields.at(0), 'cupola-journey');
    await tester.enterText(userFields.at(1), 'Cupola Journey');
    await tester.enterText(userFields.at(2), 'the-journey-password');
    await submit(tester, 'Create');
    await app.surface.see('User created');
    await app.surface.see('cupola-journey');

    await tester.tap(
      find.descendant(
        of: rowOf('cupola-journey'),
        matching: find.byTooltip('Delete user'),
      ),
    );
    await settle(tester, const Duration(milliseconds: 500));
    await app.surface.see('Delete cupola-journey?');
    await submit(tester, 'Delete user');
    await app.surface.see('User deleted');
    await app.surface.unsee('User deleted');

    await tester.tap(find.text('Groups'));
    await settle(tester, const Duration(seconds: 1));
    await tester.tap(find.byTooltip('New'));
    await settle(tester, const Duration(seconds: 1));
    await app.surface.see('New group');
    await tester.enterText(
      find.byType(TextField).first,
      'cupola-journey-group',
    );
    await submit(tester, 'Create');
    await app.surface.see('Group created');

    await app.go(tester, ServiceRoutes.truenasSystemSection('services'));
    await app.surface.see('Services');
    await tester.tap(
      find.descendant(of: rowOf('nfs'), matching: find.byType(Switch)),
    );
    await app.surface.see('Started nfs');
    await tester.tap(
      find.descendant(
        of: rowOf('ssh'),
        matching: find.byTooltip('Enable autostart'),
      ),
    );
    await app.surface.see('Autostart enabled');
  });

  testWidgets('I-13 · apps and the virtualization list', (tester) async {
    final app = await openTrueNas(tester);
    await app.go(tester, ServiceRoutes.truenasApps);
    await app.surface.see('Apps');

    Finder cardOf(String title) => find
        .ancestor(of: find.text(title), matching: find.byType(AppCard))
        .first;

    await tester.tap(
      find.descendant(of: cardOf('Immich'), matching: find.byTooltip('Start')),
    );
    await app.surface.see('Starting Immich');
    await tester.tap(
      find.descendant(of: cardOf('Immich'), matching: find.byTooltip('Stop')),
    );
    await app.surface.see('Stopping Immich');

    await tester.tap(
      find.descendant(
        of: cardOf('Jellyfin'),
        matching: find.byIcon(Icons.more_vert_rounded),
      ),
    );
    await settle(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Upgrade'));
    await app.surface.see('Upgrading Jellyfin');

    await tester.tap(
      find.descendant(
        of: cardOf('Immich'),
        matching: find.byIcon(Icons.more_vert_rounded),
      ),
    );
    await settle(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Delete app'));
    await settle(tester, const Duration(milliseconds: 500));
    await submit(tester, 'Delete app');
    await app.surface.see('Deleting Immich');

    await app.go(tester, ServiceRoutes.truenasVms);
    await app.surface.see('Virtualization');
    await app.surface.see('cupola-vm');
    await tester.tap(find.byTooltip('Start cupola-vm'));
    await app.surface.see('Starting cupola-vm');
    await tester.tap(find.byTooltip('Actions for cupola-vm'));
    await settle(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Restart'));
    await app.surface.see('Restarting');
  });

  testWidgets('I-14 · alerts, the update status and a typed reboot', (
    tester,
  ) async {
    final app = await openTrueNas(tester);
    await app.go(tester, ServiceRoutes.truenasDashboard);
    await app.surface.see('Dashboard');
    // The header alone does not build the alert cards under it: scroll to the
    // first alert's own line, which also brings its Dismiss into the tree.
    await tester.scrollUntilVisible(
      find.textContaining('8 uncorrectable errors'),
      200,
    );

    for (var i = 0; i < 3; i++) {
      final dismiss = find.text('Dismiss');
      if (dismiss.evaluate().isEmpty) break;
      await tester.ensureVisible(dismiss.first);
      await tester.tap(dismiss.first);
      await app.surface.see('Alert dismissed');
      await settle(tester, const Duration(seconds: 1));
    }
    await app.surface.see('No active alerts. 🎉');
    await app.surface.unsee('Alert dismissed');

    await app.go(tester, ServiceRoutes.truenasSystemSection('update'));
    await app.surface.see('Update');
    await app.surface.see('Status');
    await app.surface.see('Update available');

    await app.go(tester, ServiceRoutes.truenasSystem);
    await app.surface.see('System');
    final reboot = find.widgetWithText(OutlinedButton, 'Reboot…');
    // The page has a ListView inside a shell that also owns scrollables: name
    // the list, or the controller refuses to choose one.
    await tester.dragUntilVisible(
      reboot,
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    // ensureVisible stops at the viewport edge, which sits under the floating
    // bar: one more drag puts the button where a finger can reach it.
    await tester.drag(
      find.ancestor(of: reboot, matching: find.byType(ListView)).first,
      const Offset(0, -240),
    );
    await settle(tester, const Duration(milliseconds: 500));
    await tester.tap(reboot);
    await settle(tester, const Duration(milliseconds: 700));
    await app.surface.seePart('Reboot ');
    final phrase = tester
        .widget<SelectableText>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(SelectableText),
          ),
        )
        .data!;
    await tester.enterText(find.byType(TextField), phrase);
    // The confirm stays disabled until the field's listener rebuilds it: let
    // that frame land before reaching for the button.
    await settle(tester, const Duration(milliseconds: 500));
    await submit(tester, 'Reboot server');
    await app.surface.see('Rebooting $phrase…');
  });

  testWidgets('I-15 · a read-only key can read and is told what it cannot', (
    tester,
  ) async {
    final app = await openTrueNas(
      tester,
      apiKeys: const {ServiceKey.truenas: 'test-readonly'},
    );
    await app.go(tester, ServiceRoutes.truenasStorage);
    await app.surface.see('tank');

    await tester.tap(find.text('tank'));
    await settle(tester, const Duration(seconds: 1));
    await app.surface.seePart('This TrueNAS key can read.');
    await tester.tap(find.byTooltip('Start scrub'));
    await settle(tester, const Duration(milliseconds: 700));
    await app.surface.see("This TrueNAS key can't start a scrub.");
    expect(find.text('Start scrub?'), findsNothing);
  });
}
