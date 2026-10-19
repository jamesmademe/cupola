import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/features/npm/data/npm_upstream_probe.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_access.dart';
import 'package:cupola/features/npm/presentation/npm_advanced_config_screen.dart';
import 'package:cupola/features/npm/presentation/npm_capability.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/npm/presentation/npm_screen.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

NpmProxyHost _host(int id, String domain) => NpmProxyHost(
  id: id,
  domainNames: [domain],
  forwardScheme: 'http',
  forwardHost: '10.0.0.$id',
  forwardPort: 8080,
  enabled: true,
  sslForced: false,
  certificateId: 0,
  accessListId: 0,
  cachingEnabled: false,
  blockExploits: false,
  allowWebsocketUpgrade: false,
  configLoaded: true,
  errorText: '',
  advancedConfig: '',
);

NpmCertificate _cert(int id) => NpmCertificate(
  id: id,
  provider: 'letsencrypt',
  niceName: 'cert-$id.lan',
  domainNames: ['cert-$id.lan'],
  expiresOn: DateTime.now().add(const Duration(days: 200)),
);

NpmSimpleHost _other(int id) => NpmSimpleHost(
  id: id,
  label: 'redirect-$id.lan',
  detail: 'to elsewhere',
  enabled: true,
  configLoaded: true,
);

/// A view-only account: every control on either tab is attenuated, and the
/// permission band is the sentence that says why.
const _viewOnly = NpmAccount(
  id: 2,
  name: 'read-only',
  isAdmin: false,
  permissions: {},
);

const _admin = NpmAccount(id: 1, name: 'admin', isAdmin: true, permissions: {});

/// Nine certificates and nine other hosts, because the caps under test are
/// eight and ten: a section tab has to draw all nine and the whole-service page
/// has to stop at eight.
Future<void> _pump(
  WidgetTester tester, {
  required Widget screen,
  NpmAccount? account,
  int certificates = 9,
  NpmSection? failingSection,
}) async {
  // Tall, so a list of nine rows is laid out rather than being cut off. The
  // counts below are the whole point of two of these cases.
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...await settingsScopeOverrides(
          configured: const [ServiceKey.nginxProxyManager],
        ),
        // The client is never built: every provider that would reach it is
        // answered here. That is also the shape of the screen's own rule:
        // nothing asks NPM anything until the service is configured.
        npmProxyHostsProvider.overrideWith(
          (ref) async => [_host(1, 'jellyfin.lan'), _host(2, 'immich.lan')],
        ),
        npmCertificatesProvider.overrideWith(
          (ref) async => [for (var i = 1; i <= certificates; i++) _cert(i)],
        ),
        npmOtherHostsProvider.overrideWith(
          (ref) async => [for (var i = 1; i <= 9; i++) _other(i)],
        ),
        npmAccessListsProvider.overrideWith((ref) async {
          if (failingSection == NpmSection.accessLists) {
            throw Exception('offline');
          }
          return const [
            NpmAccessList(
              id: 1,
              name: 'LAN only',
              satisfyAny: false,
              passAuth: false,
              proxyHostCount: 2,
              clients: [
                NpmAccessClient(address: '192.168.1.0/24', directive: 'allow'),
              ],
            ),
          ];
        }),
        npmAuditLogProvider.overrideWith((ref) async {
          if (failingSection == NpmSection.auditLog) {
            throw Exception('offline');
          }
          return const [
            NpmAuditEntry(
              id: 1,
              objectType: 'proxy-host',
              objectId: 2,
              action: 'updated',
              summary: 'photos.example.net',
            ),
          ];
        }),
        // Nothing probed. The column it feeds reads "unchecked" rather than
        // claiming every upstream is up, which is the one thing a fabricated
        // report here could quietly assert.
        npmUpstreamReportProvider.overrideWith(
          (ref) async => NpmUpstreamReport.empty,
        ),
        npmServerInfoProvider.overrideWith(
          (ref) async => const NpmServerInfo(
            status: 'OK',
            version: '2.11.3',
            setupComplete: true,
            major: 2,
            minor: 11,
          ),
        ),
        npmAccountProvider.overrideWith((ref) async => account),
        // One real figure rather than an empty list: the peek draws nothing at
        // all when it has nothing to say, and a test that could not tell those
        // two apart would pass on a page that had lost the rail.
        serviceKpiProvider(ServiceKey.nginxProxyManager).overrideWith(
          (ref) async => const [
            ServiceKpi(label: 'Hosts', value: '2', icon: Icons.dns_outlined),
          ],
        ),
        serviceSummaryProvider(ServiceKey.nginxProxyManager).overrideWith(
          (ref) async => const ServiceSummary(
            service: ServiceKey.nginxProxyManager,
            status: ServiceSummaryStatus.online,
            host: 'npm.test',
            version: '2.11.3',
          ),
        ),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

/// How the page was split across NPM's bar, asserted on the screen itself.
///
/// `router_test.dart` proves each tab mounts the constructor it names. This
/// file proves the constructors draw what the split decided they draw, which
/// is the half a route assertion cannot see, and the half that is a design
/// decision rather than a wiring one.
void main() {
  testWidgets('the Proxy hosts tab draws every kind of host and no '
      'certificates', (tester) async {
    // Redirections, 404s and streams ride this tab rather than getting one of
    // their own: NPM files all four kinds under Hosts and the bar has exactly
    // one Hosts entry.
    await _pump(tester, screen: const NpmScreen.proxyHosts(showAppBar: false));

    expect(find.text('Proxy hosts'), findsOneWidget);
    expect(find.text('Redirections, 404s and streams'), findsOneWidget);
    expect(find.text('jellyfin.lan'), findsOneWidget);
    expect(find.text('Certificates'), findsNothing);
    expect(find.text('cert-1.lan'), findsNothing);
  });

  testWidgets('the Certificates tab draws certificates and no hosts', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const NpmScreen.certificates(showAppBar: false),
    );

    expect(find.text('Certificates'), findsOneWidget);
    expect(find.text('cert-1.lan'), findsOneWidget);
    expect(find.text('Proxy hosts'), findsNothing);
    expect(find.text('jellyfin.lan'), findsNothing);
    expect(find.text('Redirections, 404s and streams'), findsNothing);
  });

  testWidgets('Access lists and Audit log draw their real documents', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const NpmScreen.accessLists(showAppBar: false),
      account: _admin,
    );
    expect(find.text('LAN only'), findsOneWidget);
    expect(find.textContaining('2 hosts'), findsOneWidget);

    await _pump(
      tester,
      screen: const NpmScreen.auditLog(showAppBar: false),
      account: _admin,
    );
    // NPM's API words, said as a sentence: `updated` and `proxy-host`.
    expect(find.text('Updated\u00A0· photos.example.net'), findsOneWidget);
    expect(find.textContaining('Proxy host'), findsOneWidget);
  });

  testWidgets('Audit log explains the server-side admin capability', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const NpmScreen.auditLog(showAppBar: false),
      account: _viewOnly,
    );
    expect(find.textContaining('administrators only'), findsOneWidget);
    expect(find.textContaining('photos.example.net'), findsNothing);
  });

  testWidgets('Access lists and Audit log expose remote-error states', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const NpmScreen.accessLists(showAppBar: false),
      failingSection: NpmSection.accessLists,
    );
    expect(
      find.text(
        'The request to Nginx Proxy Manager did not complete, so the access '
        'lists are not shown.',
      ),
      findsOneWidget,
    );

    await _pump(
      tester,
      screen: const NpmScreen.auditLog(showAppBar: false),
      account: _admin,
      failingSection: NpmSection.auditLog,
    );
    expect(
      find.text(
        'The request to Nginx Proxy Manager did not complete, so the audit '
        'log is not shown.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a section tab lists every row it names', (tester) async {
    // Nine certificates, all nine drawn. The single page capped them at eight,
    // which is right for a peek and wrong for a tab called Certificates: eight
    // of nine, with nothing saying so, is a count the reader has no way to
    // doubt.
    await _pump(
      tester,
      screen: const NpmScreen.certificates(showAppBar: false),
    );

    expect(find.text('cert-9.lan'), findsOneWidget);
  });

  testWidgets('the whole-service page keeps its peek caps', (tester) async {
    // The other half of the same decision: on [NpmSection.everything] the lists
    // are a dashboard peek under one another, and the ninth certificate is
    // below the cut.
    await _pump(tester, screen: const NpmScreen(showAppBar: false));

    expect(find.text('cert-8.lan'), findsOneWidget);
    expect(find.text('cert-9.lan'), findsNothing);
  });

  testWidgets('the whole-service page still draws all three sections and the '
      'readouts', (tester) async {
    await _pump(tester, screen: const NpmScreen(showAppBar: false));

    expect(find.text('Proxy hosts'), findsOneWidget);
    expect(find.text('Certificates'), findsOneWidget);
    expect(find.text('Redirections, 404s and streams'), findsOneWidget);
    // The readouts belong to the Overview under the tab model, so they are on
    // this variant and nowhere else.
    expect(find.byType(ServiceKpiPeek), findsOneWidget);
  });

  testWidgets('the readouts are not repeated on a section tab', (tester) async {
    await _pump(tester, screen: const NpmScreen.proxyHosts(showAppBar: false));

    expect(find.byType(ServiceKpiPeek), findsNothing);
  });

  testWidgets('the permission band is on both tabs, not just the one with the '
      'menu', (tester) async {
    // Both tabs carry a gated control: Enable/Disable in the host menu on one,
    // Renew on a certificate on the other, so leaving the sentence that
    // explains the attenuation on one tab would be the failure
    // `npm_write_gate.dart` exists to prevent.
    for (final screen in const [
      NpmScreen.proxyHosts(showAppBar: false),
      NpmScreen.certificates(showAppBar: false),
      NpmScreen.accessLists(showAppBar: false),
      NpmScreen.auditLog(showAppBar: false),
    ]) {
      await _pump(tester, screen: screen, account: _viewOnly);
      expect(
        find.byType(CapabilityBanner),
        findsOneWidget,
        reason: '$screen must carry the band',
      );
      expect(
        find.textContaining('view-only'),
        findsOneWidget,
        reason: 'the band says which fact it is reporting, in words',
      );
    }
  });

  testWidgets('the default-admin warning is on every variant', (tester) async {
    // A fact about the box rather than about a section: on an install that
    // still ships `admin@example.com` it outranks everything else on either
    // tab, and the fixture above is 2.11, inside that window.
    for (final screen in const [
      NpmScreen(showAppBar: false),
      NpmScreen.proxyHosts(showAppBar: false),
      NpmScreen.certificates(showAppBar: false),
      NpmScreen.accessLists(showAppBar: false),
      NpmScreen.auditLog(showAppBar: false),
    ]) {
      await _pump(tester, screen: screen);
      expect(
        find.textContaining('admin@example.com'),
        findsOneWidget,
        reason: '$screen must carry the warning',
      );
    }
  });

  testWidgets('an unconfigured NPM draws the placeholder on every variant', (
    tester,
  ) async {
    // Configuration is checked before any provider is read, so nothing here is
    // overridden: a variant that reached `npmClientProvider` would throw, and a
    // provider that throws schedules a retry for a condition no waiting
    // changes, which this test would report as a pending timer.
    for (final screen in const [
      NpmScreen(showAppBar: false),
      NpmScreen.proxyHosts(showAppBar: false),
      NpmScreen.certificates(showAppBar: false),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: await settingsScopeOverrides(),
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
    }
  });

  group('the gate on a view-only account', () {
    testWidgets('the host menu item is reachable, hinted, and answers', (
      tester,
    ) async {
      await _pump(
        tester,
        screen: const NpmScreen.proxyHosts(showAppBar: false),
        account: _viewOnly,
      );
      await tester.tap(
        find
            .byWidgetPredicate(
              (w) =>
                  w is Tooltip && (w.message ?? '').startsWith('Actions for '),
            )
            .first,
      );
      await tester.pumpAndSettle();

      final item = find.ancestor(
        of: find.text('Disable…'),
        matching: find.byType(PopupMenuItem<String>),
      );
      expect(tester.widget<PopupMenuItem<String>>(item).enabled, isTrue);
      expect(
        tester.getSemantics(find.text('Disable…')),
        containsSemantics(hint: 'requires an admin account', isEnabled: true),
      );

      await tester.tap(find.text('Disable…'));
      await tester.pumpAndSettle();
      // The toast, not the typed confirmation: the gate is at the tap that
      // opens the flow, never after the domain is typed.
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text(npmBlockedMessage(NpmResource.proxyHosts)),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SnackBarAction, 'Change account'),
        findsOneWidget,
      );
    });

    testWidgets('Renew is dimmed but tappable, and toasts', (tester) async {
      await _pump(
        tester,
        screen: const NpmScreen.certificates(showAppBar: false),
        account: _viewOnly,
      );
      final renew = find.widgetWithText(TextButton, 'Renew').first;
      expect(tester.widget<TextButton>(renew).onPressed, isNotNull);
      expect(
        tester.getSemantics(renew),
        containsSemantics(
          label: 'Renew',
          hint: 'requires an admin account',
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        find.descendant(of: renew, matching: find.byType(Opacity)),
        findsOneWidget,
      );

      // The client is never built in this harness; a tap that reached it would
      // throw "not configured" instead of raising the toast.
      await tester.tap(renew);
      await tester.pumpAndSettle();
      expect(
        find.text(npmBlockedMessage(NpmResource.certificates)),
        findsOneWidget,
      );
    });
  });

  group('a scoped account', () {
    const hostsOnly = NpmAccount(
      id: 3,
      name: 'hosts',
      isAdmin: false,
      permissions: {'proxy_hosts': 'manage', 'certificates': 'view'},
    );

    testWidgets('Certificates names what it cannot change there', (
      tester,
    ) async {
      await _pump(
        tester,
        screen: const NpmScreen.certificates(showAppBar: false),
        account: hostsOnly,
      );
      expect(find.byType(CapabilityBanner), findsOneWidget);
      expect(
        find.text(
          'This Nginx Proxy Manager account can read certificates but not '
          'change them. Changing them needs an account that can manage '
          'certificates.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Proxy hosts, which it manages, has no band and live menus', (
      tester,
    ) async {
      await _pump(
        tester,
        screen: const NpmScreen.proxyHosts(showAppBar: false),
        account: hostsOnly,
      );
      expect(find.byType(CapabilityBanner), findsNothing);
      await tester.tap(
        find
            .byWidgetPredicate(
              (w) =>
                  w is Tooltip && (w.message ?? '').startsWith('Actions for '),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.getSemantics(find.text('Disable…')).hint, isEmpty);
    });
  });

  testWidgets('an admin gets no band anywhere', (tester) async {
    for (final screen in const [
      NpmScreen(showAppBar: false),
      NpmScreen.proxyHosts(showAppBar: false),
      NpmScreen.certificates(showAppBar: false),
    ]) {
      await _pump(tester, screen: screen, account: _admin);
      expect(find.byType(CapabilityBanner), findsNothing, reason: '$screen');
    }
  });

  testWidgets('the advanced config save is gated and names the block', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const NpmAdvancedConfigScreen(hostId: 1),
      account: _viewOnly,
    );
    // One banner, first, above the editor.
    expect(find.byType(CapabilityBanner), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'client_max_body_size 0;');
    await tester.pump();

    final save = find.widgetWithText(FilledButton, 'Save changes…');
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();
    // The toast, not the typed confirmation.
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text(npmBlockedMessage(NpmResource.proxyHosts)),
      findsOneWidget,
    );
  });

  testWidgets('the advanced page reads its host from the id in the path', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const NpmAdvancedConfigScreen(hostId: 2),
      account: _admin,
    );
    expect(
      find.text('The custom Nginx block for immich.lan\u00A0· 0 lines'),
      findsOneWidget,
    );

    // One line is a line.
    await tester.enterText(find.byType(TextField), 'client_max_body_size 0;');
    await tester.pump();
    expect(
      find.text('The custom Nginx block for immich.lan\u00A0· 1 line'),
      findsOneWidget,
    );
  });

  testWidgets('a host gone from NPM says so instead of an empty editor', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const NpmAdvancedConfigScreen(hostId: 99),
      account: _admin,
    );
    expect(
      find.text('This proxy host is no longer on Nginx Proxy Manager.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
  });
}
