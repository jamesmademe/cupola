/// The Nginx Proxy Manager rows of the catalog, I-04 to I-06 and I-08.
///
/// The world: the `npm-lab` scenario, which leaves two real proxy hosts on the
/// lab's own NPM. `cupola-lab.test` answers for Radarr, carries the expiring
/// certificate and a working custom block; `cupola-alt.test` answers for
/// Dockge through an access list, and starts with an empty custom block.
///
/// What each journey proves, in the app's own words:
///
/// - **I-04**: the Proxy hosts tab draws the two hosts serving, the host menu
///   takes `cupola-lab.test` down only after the domain is typed, and brings it
///   back. The row reads `disabled` in between, and neither step asks again on
///   the way back up.
/// - **I-05**: the Advanced editor saves a valid block and nginx reloads it;
///   a block nginx refuses is stored anyway and the page says so in amber,
///   without pretending the request failed; an empty block restores the host.
/// - **I-06**: the custom certificate is 14 days out, so the app draws it in
///   amber and offers no Renew at all. That is the app's rule, not a missing
///   control: Let's Encrypt is the only provider it renews.
/// - **I-08**: the access list the scenario wrote is the one the app draws,
///   with its IP rule count, and the audit log is not empty on a used box.
///
/// Two limits are declared rather than simulated:
///
/// * **I-06's `Renew`.** NPM renews only Let's Encrypt certificates, and one
///   cannot exist without an ACME endpoint and a domain the lab does not own.
///   The success and refusal arms are the API's, in
///   `test/e2e/testlab_npm_e2e_test.dart`; this journey proves what the screen
///   does with the certificate the lab can hold.
/// * **I-08's empty copies.** The audit log of a used lab is never empty and the
///   scenario keeps one access list on purpose, so `No access lists
///   configured.` and `No audit entries reported.` are the screen's own widget
///   states, not lab states.
///
/// The scenario is applied before the app opens and torn down after, so a
/// failed run leaves neither a stopped host nor a broken nginx block behind.
@Tags(['e2e'])
@Timeout(Duration(minutes: 15))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'testlab_journey_harness.dart';

/// The block the scenario itself uses for the working custom config: four
/// lines, answered by nginx without the upstream.
const _validAdvanced =
    'location = /cupola-testlab {\n'
    '    default_type text/plain;\n'
    '    return 200 "advanced-config\\n";\n'
    '}';

/// A directive nginx does not know. NPM stores it and answers 200; the reload
/// is what refuses it.
const _refusedAdvanced = 'cupola_bogus_directive on;';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder hostMenu(String domain) => find.byTooltip('Actions for $domain');

  Finder dialogField() => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );

  /// Types [phrase] into the open typed confirmation and taps [label].
  Future<void> confirmTyped(
    WidgetTester tester,
    String phrase,
    String label,
  ) async {
    await tester.enterText(dialogField(), phrase);
    await settle(tester, const Duration(milliseconds: 400));
    await tester.tap(find.text(label));
    await settle(tester, const Duration(milliseconds: 800));
  }

  /// Opens the proxy host menu for [domain], scrolled into view first.
  Future<void> openHostMenu(WidgetTester tester, String domain) async {
    final menu = hostMenu(domain);
    await tester.ensureVisible(menu);
    await settle(tester, const Duration(milliseconds: 300));
    await tester.tap(menu);
    await settle(tester, const Duration(milliseconds: 500));
  }

  /// Saves the open advanced editor with [block], through the typed
  /// confirmation, and waits for the toast.
  Future<void> saveAdvanced(
    WidgetTester tester,
    LabSurface surface,
    String domain,
    String block,
  ) async {
    final editor = find.byType(TextField).first;
    await tester.ensureVisible(editor);
    await settle(tester, const Duration(milliseconds: 300));
    await tester.enterText(editor, block);
    await settle(tester, const Duration(milliseconds: 500));

    final save = find.text('Save changes…');
    await tester.ensureVisible(save);
    await settle(tester, const Duration(milliseconds: 300));
    await tester.tap(save);
    await settle(tester, const Duration(milliseconds: 600));
    await surface.see('Save the advanced config?');
    await confirmTyped(tester, domain, 'Save and reload');
  }

  testWidgets('I-04 · a proxy host disabled and enabled', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final lab = Lab.load();
    await lab.command(['scenario', 'apply', 'npm-lab']);
    addTearDown(() => lab.command(['scenario', 'teardown', 'npm-lab']));
    final app = await LabApp.asOperator(
      tester,
      lab: lab,
      services: const {ServiceKey.nginxProxyManager},
    );

    await app.go(tester, ServiceRoutes.npmProxyHosts);
    await app.surface.see('cupola-lab.test');
    await app.surface.seePart('serving');

    // Taking a hostname off the internet asks for the domain, not a tap.
    await openHostMenu(tester, 'cupola-lab.test');
    await tester.tap(find.text('Disable…'));
    await settle(tester, const Duration(milliseconds: 500));
    await app.surface.see('Stop serving cupola-lab.test?');
    await confirmTyped(tester, 'cupola-lab.test', 'Stop serving');
    await app.surface.see('cupola-lab.test is no longer served');
    await app.surface.seePart('disabled');

    // The recoverable direction has no typed gate, and the list is the server's
    // answer after the action, not the menu's own optimism.
    await openHostMenu(tester, 'cupola-lab.test');
    await tester.tap(find.text('Enable'));
    await settle(tester, const Duration(seconds: 1));
    await app.surface.see('cupola-lab.test enabled');
    await settle(tester, const Duration(seconds: 2));
    expect(
      app.surface.drawsPart('disabled'),
      isFalse,
      reason: 'the host should read as serving again',
    );
  });

  testWidgets('I-05 · the advanced Nginx block saved, refused and restored', (
    tester,
  ) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final lab = Lab.load();
    await lab.command(['scenario', 'apply', 'npm-lab']);
    addTearDown(() => lab.command(['scenario', 'teardown', 'npm-lab']));
    final app = await LabApp.asOperator(
      tester,
      lab: lab,
      services: const {ServiceKey.nginxProxyManager},
    );

    await app.go(tester, ServiceRoutes.npmProxyHosts);
    await app.surface.see('cupola-alt.test');
    await openHostMenu(tester, 'cupola-alt.test');
    // Empty at apply, but a failed previous run may have left lines: the entry
    // is the same either way, only its suffix changes.
    await tester.tap(find.textContaining('Advanced'));
    await settle(tester, const Duration(seconds: 1));
    await app.surface.seePart('The custom Nginx block for cupola-alt.test');

    await saveAdvanced(tester, app.surface, 'cupola-alt.test', _validAdvanced);
    await app.surface.seePart('nginx reloaded');
    expect(
      app.surface.drawsPart('nginx refused this block'),
      isFalse,
      reason: 'a block nginx accepts should leave no verdict',
    );

    await saveAdvanced(
      tester,
      app.surface,
      'cupola-alt.test',
      _refusedAdvanced,
    );
    await app.surface.seePart('nginx refused this block');
    final verdict = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(verdict.data, contains('cupola_bogus_directive'));

    // The editor's undo point is the block it opened, not the server's latest:
    // an empty block typed into this same editor would be "no change" and the
    // Save button would stay disabled. Reopen the editor so the empty block is
    // a change from the refused one, then save it like any other.
    await tester.pageBack();
    await settle(tester, const Duration(seconds: 1));
    await app.surface.see('cupola-alt.test');
    await openHostMenu(tester, 'cupola-alt.test');
    await tester.tap(find.textContaining('Advanced'));
    await settle(tester, const Duration(seconds: 1));
    await app.surface.seePart('The custom Nginx block for cupola-alt.test');

    await saveAdvanced(tester, app.surface, 'cupola-alt.test', '');
    await app.surface.seePart('nginx reloaded');
    await settle(tester, const Duration(seconds: 2));
    expect(
      app.surface.drawsPart('nginx refused this block'),
      isFalse,
      reason: 'the empty block should have reloaded',
    );
  });

  testWidgets('I-06 · an expiring custom certificate offers no Renew', (
    tester,
  ) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final lab = Lab.load();
    await lab.command(['scenario', 'apply', 'npm-lab']);
    addTearDown(() => lab.command(['scenario', 'teardown', 'npm-lab']));
    final app = await LabApp.asOperator(
      tester,
      lab: lab,
      services: const {ServiceKey.nginxProxyManager},
    );

    await app.go(tester, ServiceRoutes.npmCertificates);
    await app.surface.see('Cupola testlab expiring');
    await app.surface.seePart('Expires in');

    // Renewal is Let's Encrypt's, so a custom certificate has no button at
    // all: the absence is the flow's limit, not a control left half-built.
    expect(find.text('Renew'), findsNothing);

    final tile = find
        .ancestor(
          of: find.text('Cupola testlab expiring'),
          matching: find.byType(Material),
        )
        .first;
    final lock = find.descendant(
      of: tile,
      matching: find.byIcon(Icons.lock_outline_rounded),
    );
    expect(lock, findsOneWidget);
    final icon = tester.widget<Icon>(lock);
    final scheme = Theme.of(tester.element(tile)).colorScheme;
    expect(
      icon.color,
      statusToneColor(scheme, StatusTone.warning),
      reason: 'an expiring certificate is the amber arm',
    );
  });

  testWidgets('I-08 · the access list and the audit log', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final lab = Lab.load();
    await lab.command(['scenario', 'apply', 'npm-lab']);
    addTearDown(() => lab.command(['scenario', 'teardown', 'npm-lab']));
    final app = await LabApp.asOperator(
      tester,
      lab: lab,
      services: const {ServiceKey.nginxProxyManager},
    );

    await app.go(tester, ServiceRoutes.npmAccessLists);
    await app.surface.see('Cupola testlab docker');
    await app.surface.seePart('2 IP rules');
    expect(
      app.surface.draws('No access lists configured.'),
      isFalse,
      reason: 'the scenario keeps one access list on purpose',
    );

    await app.go(tester, ServiceRoutes.npmAuditLog);
    await app.surface.see('Audit log');
    await app.surface.seePart('Proxy host');
    expect(
      app.surface.draws('No audit entries reported.'),
      isFalse,
      reason: 'the scenario writes both hosts and NPM logs every write',
    );
  });
}
