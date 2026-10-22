/// Nginx Proxy Manager's Needs attention leads to the tab that lists the fault:
/// refused hosts open Proxy hosts, lapsed and lapsing certificates open
/// Certificates, and several of a kind are one row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/npm/data/npm_upstream_probe.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_access.dart';
import 'package:cupola/features/npm/presentation/npm_overview_screen.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/overview_shell.dart';
import '../../../test_helpers/settings_scope.dart';

NpmProxyHost _host(int id, String domain, {bool refused = false}) =>
    NpmProxyHost(
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
      configLoaded: !refused,
      errorText: refused ? 'nginx: [emerg] invalid port' : '',
      advancedConfig: '',
    );

NpmCertificate _cert(int id, String name, Duration expiresIn) => NpmCertificate(
  id: id,
  provider: 'letsencrypt',
  niceName: name,
  domainNames: [name],
  expiresOn: DateTime.now().add(expiresIn),
);

Future<OverviewShell> _pump(
  WidgetTester tester, {
  required List<NpmProxyHost> hosts,
  required List<NpmCertificate> certificates,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final shell = OverviewShell(
    ServiceKey.nginxProxyManager,
    const NpmOverviewScreen(topPadding: 0),
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => settingsWith(
            npmUrl: 'http://npm.test:81',
            npmUsername: 'admin@npm.test',
            npmPassword: 'secret',
          ),
        ),
        npmProxyHostsProvider.overrideWith((ref) async => hosts),
        npmCertificatesProvider.overrideWith((ref) async => certificates),
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
        npmAccountProvider.overrideWith((ref) async => null),
        serviceKpiProvider(ServiceKey.nginxProxyManager).overrideWith(
          (ref) async => const [
            ServiceKpi(label: 'Hosts', value: '3', icon: Icons.dns_outlined),
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
      child: shell.app,
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}

void main() {
  testWidgets('one refused host opens the Proxy hosts tab that lists it', (
    tester,
  ) async {
    final shell = await _pump(
      tester,
      hosts: [
        _host(1, 'photos.example.net', refused: true),
        _host(2, 'ok.lan'),
      ],
      certificates: [_cert(1, 'wildcard', const Duration(days: 200))],
    );

    expect(
      find.semantics.byLabel(RegExp(r'^nginx refused, photos\.example\.net')),
      isSemantics(
        isButton: true,
        hasTapAction: true,
        hint: 'opens the Nginx Proxy Manager Proxy hosts tab',
      ),
    );

    await tester.tap(find.text('nginx refused\u00A0· photos.example.net'));
    await tester.pumpAndSettle();
    expect(shell.tab, ServiceTab.proxyHosts);
  });

  testWidgets('three refused hosts are one row, and the header still counts '
      'three', (tester) async {
    final shell = await _pump(
      tester,
      hosts: [
        _host(1, 'a.example.net', refused: true),
        _host(2, 'b.example.net', refused: true),
        _host(3, 'c.example.net', refused: true),
      ],
      certificates: [_cert(1, 'wildcard', const Duration(days: 200))],
    );

    expect(find.text('3 hosts refused by nginx'), findsOneWidget);
    expect(find.textContaining('nginx refused\u00A0· '), findsNothing);
    expect(
      tester
          .widget<SectionHeader>(
            find.widgetWithText(SectionHeader, 'Needs attention'),
          )
          .subtitle,
      '3',
    );

    await tester.tap(find.text('3 hosts refused by nginx'));
    await tester.pumpAndSettle();
    expect(shell.tab, ServiceTab.proxyHosts);
  });

  testWidgets('a lapsing certificate opens the Certificates tab, where Renew '
      'and its confirmation are', (tester) async {
    final shell = await _pump(
      tester,
      hosts: [_host(1, 'ok.lan')],
      certificates: [_cert(1, 'seerr.example.net', const Duration(days: 9))],
    );

    expect(
      find.semantics.byLabel(RegExp(r'^1 certificate expiring, ')),
      isSemantics(
        isButton: true,
        hint: 'opens the Nginx Proxy Manager Certificates tab',
      ),
    );
    // Renew reaches Let's Encrypt: not one tap from a row.
    expect(find.text('Renew'), findsNothing);

    await tester.tap(find.textContaining('1 certificate expiring'));
    await tester.pumpAndSettle();
    expect(shell.tab, ServiceTab.certificates);
  });
}
