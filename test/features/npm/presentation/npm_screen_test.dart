import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/features/npm/data/npm_upstream_probe.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_access.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/npm/presentation/npm_screen.dart';
import 'package:cupola/features/npm/presentation/npm_write_gate.dart';
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

/// Nine certificates and nine other hosts, because the caps under test are
/// eight and ten: a section tab has to draw all nine and the whole-service page
/// has to stop at eight.
Future<void> _pump(
  WidgetTester tester, {
  required Widget screen,
  NpmAccount? account,
  int certificates = 9,
}) async {
  // Tall, so a list of nine rows is laid out rather than being cut off — the
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
        // answered here. That is also the shape of the screen's own rule —
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
/// file proves the constructors draw what the split decided they draw — which
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
    // Both tabs carry a gated control — Enable/Disable in the host menu on one,
    // Renew on a certificate on the other — so leaving the sentence that
    // explains the attenuation on one tab would be the failure
    // `npm_write_gate.dart` exists to prevent.
    for (final screen in const [
      NpmScreen.proxyHosts(showAppBar: false),
      NpmScreen.certificates(showAppBar: false),
    ]) {
      await _pump(tester, screen: screen, account: _viewOnly);
      expect(
        find.byType(NpmAccessBand),
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
    // tab, and the fixture above is 2.11 — inside that window.
    for (final screen in const [
      NpmScreen(showAppBar: false),
      NpmScreen.proxyHosts(showAppBar: false),
      NpmScreen.certificates(showAppBar: false),
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
    // changes — which this test would report as a pending timer.
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
}
