import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/npm/data/npm_upstream_probe.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_access.dart';
import 'package:cupola/features/npm/presentation/npm_overview_screen.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/npm/presentation/npm_screen.dart'
    show NpmDefaultAdminWarning;
import 'package:cupola/features/npm/presentation/npm_capability.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('draws the regions in the order the mobile board draws them', (
    tester,
  ) async {
    await _pump(tester);

    // Identity and the readouts come before any section, and only this tab
    // carries them. The other two NPM tabs are each a view of one record kind.
    expect(find.byType(ServiceKpiPeek), findsOneWidget);

    // What is wrong, then what is being fronted, then what is about to lapse.
    // `HomeNpmMobile` promotes Needs attention above the host table, and the
    // narrow board is the one that decides the order.
    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Needs attention', 'Proxy hosts', 'Certificates'],
    );

    // Absent rather than stubbed: `NpmClient` calls neither `/api/audit-log`
    // nor `/api/nginx/access-lists`, and a region given a fake zero is worse
    // than a region that was never promised.
    expect(find.text('Audit log'), findsNothing);
    expect(find.text('Access lists'), findsNothing);
  });

  testWidgets('each section link is named after the tab it opens', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.semanticHint),
      [
        // Needs attention has nowhere single to go: a refused configuration
        // belongs to Proxy hosts and a lapsing certificate to Certificates, and
        // one destination would have to lie about half the rows.
        null,
        'opens the Nginx Proxy Manager Proxy hosts tab',
        'opens the Nginx Proxy Manager Certificates tab',
      ],
    );
  });

  testWidgets('the shared chrome travels with the Overview', (tester) async {
    await _pump(tester, account: _viewOnly);

    // Both halves of the NPM split draw these, and so does this page: the band
    // is the sentence that explains an attenuated control, and the warning is a
    // fact about the box that outranks everything else on it.
    expect(find.byType(NpmDefaultAdminWarning), findsOneWidget);
    expect(find.byType(NpmCapabilityBannerSlot), findsOneWidget);
    expect(find.byType(CapabilityBanner), findsOneWidget);
    expect(find.textContaining('view-only'), findsOneWidget);

    // And the Overview adds no write of its own, so the gate is neither
    // weakened nor duplicated here.
    expect(find.byType(CapabilityGatedAction), findsNothing);
  });

  testWidgets('the probe coverage is printed beside every figure it touches', (
    tester,
  ) async {
    await _pump(
      tester,
      upstreams: _report({1: NpmUpstream.down, 2: NpmUpstream.answering}),
    );

    // Two hosts of three were reached, from this device. A count that
    // dropped the coverage would turn the one unchecked host into a healthy
    // one. Needs attention carries none: nothing in it comes from the probe.
    final headers = tester
        .widgetList<SectionHeader>(find.byType(SectionHeader))
        .toList();
    // No fault, and a count of none is not drawn under the heading.
    expect(headers[0].subtitle, isNull);
    expect(
      headers[1].subtitle,
      '3\u00A0· 2 of 3 enabled checked from this device',
    );
  });

  testWidgets('a host this device could not reach says so, and is no fault', (
    tester,
  ) async {
    await _pump(tester, upstreams: _report({1: NpmUpstream.down}));

    // It used to head Needs attention as "Upstream down": from a phone away
    // from home, every LAN host fails the probe.
    expect(find.textContaining('Upstream down'), findsNothing);
    final attention = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Needs attention'),
    );
    // No fault, and a count of none is not drawn under the heading.
    expect(attention.subtitle, isNull);
    expect(find.textContaining('not reachable from this device'), findsWidgets);
  });

  testWidgets('a host the user switched off is backlog, never a fault', (
    tester,
  ) async {
    await _pump(
      tester,
      hosts: [
        _host(1, 'jellyfin.lan'),
        // Disabled *and* carrying no loaded configuration, which is what
        // disabled means on this server. Amber here is the commonest way the
        // five-arm tone rule breaks.
        _host(2, 'old.lan', enabled: false, configLoaded: false),
      ],
    );

    final attention = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Needs attention'),
    );
    // No fault, and a count of none is not drawn under the heading.
    expect(attention.subtitle, isNull);
    expect(find.textContaining('nginx refused'), findsNothing);
    // Still drawn on the host list, in the ordinary ink, with the word for it.
    expect(find.textContaining('disabled'), findsOneWidget);
  });

  testWidgets('a refused configuration quotes nginx and reads amber', (
    tester,
  ) async {
    await _pump(
      tester,
      hosts: [
        _host(
          1,
          'photos.lan',
          configLoaded: false,
          errorText: 'nginx: [emerg] invalid port in "listen" directive',
        ),
      ],
    );

    expect(
      find.text('nginx: [emerg] invalid port in "listen" directive'),
      findsOneWidget,
    );

    final row = tester.widget<ServiceOverviewRow>(
      find.widgetWithText(
        ServiceOverviewRow,
        'nginx refused\u00A0· photos.lan',
      ),
    );
    // Toned, and toned through `statusToneColor` rather than a raw palette
    // constant: the walk is what keeps amber legible on this surface.
    final colorScheme = Theme.of(
      tester.element(find.byType(NpmOverviewScreen)),
    ).colorScheme;
    expect(
      row.titleColor,
      statusToneColor(
        colorScheme,
        StatusTone.warning,
        surface: colorScheme.surfaceContainerLow,
      ),
    );
    // Never red: red belongs to an NPM that did not answer, and this one
    // answered; it answered with the error.
    expect(row.titleColor, isNot(colorScheme.error));
  });

  testWidgets('an expiring certificate is a fault; an expired one is not red', (
    tester,
  ) async {
    await _pump(
      tester,
      certificates: [
        _cert(1, 'seerr.lan', expiresIn: const Duration(days: 9)),
        _cert(2, 'photos.lan', expiresIn: const Duration(days: -4)),
      ],
    );

    expect(
      find.textContaining('Certificate expired\u00A0· photos.lan'),
      findsOneWidget,
    );
    expect(
      find.textContaining('1 certificate expiring\u00A0· seerr.lan'),
      findsOneWidget,
    );

    final colorScheme = Theme.of(
      tester.element(find.byType(NpmOverviewScreen)),
    ).colorScheme;
    final amber = statusToneColor(
      colorScheme,
      StatusTone.warning,
      surface: colorScheme.surfaceContainerLow,
    );
    for (final row in tester.widgetList<ServiceOverviewRow>(
      find.byType(ServiceOverviewRow),
    )) {
      expect(row.titleColor, anyOf(isNull, amber));
    }
  });

  testWidgets(
    'a certificate that lapsed hours ago reads expired in both places',
    (tester) async {
      await _pump(
        tester,
        certificates: [
          _cert(1, 'photos.lan', expiresIn: const Duration(hours: -6)),
        ],
      );

      // `daysUntilExpiry` truncates, so for a full day after a certificate
      // lapses it answers 0. Read as a day count this page would say
      // "1 expiring" on the header while Needs attention said
      // "Certificate expired" two regions above: one screen stating one fact
      // at two severities, with the header stating the softer one.
      final certificates = tester.widget<SectionHeader>(
        find.widgetWithText(SectionHeader, 'Certificates'),
      );
      expect(certificates.subtitle, '1\u00A0· 1 expired');
      expect(
        find.textContaining('Certificate expired\u00A0· photos.lan'),
        findsOneWidget,
      );
      expect(find.textContaining('expiring'), findsNothing);
    },
  );

  testWidgets('a source that did not answer prints `—` and never 0', (
    tester,
  ) async {
    await _pump(tester, failHosts: true, failCertificates: true);

    // "0 hosts" and "0 faults" over an unanswered question are claims nobody
    // made; the reading a user would act on is the opposite one.
    expect(find.text('0'), findsNothing);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('a section whose source failed does not take the page with it', (
    tester,
  ) async {
    await _pump(tester, failCertificates: true);

    // The failed regions say so in their own slots: Certificates, and Needs
    // attention, which is folded from both documents…
    expect(find.byType(InlineErrorRetry), findsNWidgets(2));
    expect(
      find.textContaining(", so the certificates are not shown."),
      findsOneWidget,
    );
    expect(
      find.textContaining(", so what needs attention is not shown."),
      findsOneWidget,
    );
    // …and all three still drew their headings.
    expect(find.byType(SectionHeader), findsNWidgets(3));
    expect(find.textContaining('jellyfin.lan'), findsOneWidget);
  });

  testWidgets('a resting NPM wears no alarm chrome', (tester) async {
    await _pump(tester);

    expect(
      find.text('Every host is serving and no certificate is due'),
      findsOneWidget,
    );
    expect(find.byType(InlineErrorRetry), findsNothing);
  });

  testWidgets('nothing overflows at an accessibility reading size', (
    tester,
  ) async {
    await _pump(
      tester,
      textScaleFactor: 3.0,
      hosts: [
        _host(
          1,
          'a-very-long-hostname-that-somebody-actually-uses.example.net',
          forwardHost: 'a-very-long-backend-name.internal.lan',
          configLoaded: false,
          errorText:
              'nginx: [emerg] invalid port in "listen" directive in '
              '/data/nginx/proxy_host/17.conf:4',
        ),
      ],
    );

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('an NPM that was never set up gets its own door', (tester) async {
    await _pump(tester, configured: false);

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    expect(placeholder.service, ServiceKey.nginxProxyManager);
    // Nothing behind the door was built, which is the point: every provider on
    // this page reaches `npmClientProvider`, which throws "not configured", and
    // a provider that throws is a *failed* provider retrying on a backoff for a
    // condition no waiting changes. A pending timer here would be the tell.
    expect(find.byType(SectionHeader), findsNothing);
    expect(find.byType(CapabilityBanner), findsNothing);
  });

  testWidgets('a scoped account gets no band on the Overview', (tester) async {
    // It can change something, and the Overview changes nothing: the tabs whose
    // writes it may not make say so themselves.
    await _pump(
      tester,
      account: const NpmAccount(
        id: 3,
        name: 'hosts',
        isAdmin: false,
        permissions: {'proxy_hosts': 'manage', 'certificates': 'view'},
      ),
    );
    expect(find.byType(CapabilityBanner), findsNothing);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

/// A view-only account: the band is the sentence that says why every control
/// elsewhere in this service is attenuated.
const _viewOnly = NpmAccount(
  id: 2,
  name: 'read-only',
  isAdmin: false,
  permissions: {},
);

Future<void> _pump(
  WidgetTester tester, {
  List<NpmProxyHost>? hosts,
  List<NpmCertificate>? certificates,
  NpmUpstreamReport? upstreams,
  NpmAccount? account,
  bool failHosts = false,
  bool failCertificates = false,
  bool configured = true,
  double textScaleFactor = 1.0,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 re-runs a failed provider on an exponential backoff, so one
      // `pumpAndSettle` would otherwise watch a deliberately failing region
      // retry a dozen times and never settle.
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => configured
              ? settingsWith(
                  npmUrl: 'http://npm.test:81',
                  npmUsername: 'admin@npm.test',
                  npmPassword: 'secret',
                )
              : const SettingsModel(),
        ),
        // The client is never built: every provider that would reach it is
        // answered here.
        npmProxyHostsProvider.overrideWith((ref) async {
          if (failHosts) throw Exception('proxy hosts failed');
          return hosts ??
              [
                _host(1, 'jellyfin.lan'),
                _host(2, 'immich.lan'),
                _host(3, 'seerr.lan'),
              ];
        }),
        npmCertificatesProvider.overrideWith((ref) async {
          if (failCertificates) throw Exception('certificates failed');
          return certificates ??
              [_cert(1, 'wildcard.lan', expiresIn: const Duration(days: 200))];
        }),
        // Nothing probed by default. A fabricated full report here would
        // quietly assert every upstream is up, which is the one claim this
        // page exists to avoid making.
        npmUpstreamReportProvider.overrideWith(
          (ref) async => upstreams ?? NpmUpstreamReport.empty,
        ),
        npmServerInfoProvider.overrideWith(
          (ref) async => const NpmServerInfo(
            // 2.11 still ships `admin@example.com` / `changeme`, so the warning
            // renders and the test can see it.
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
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: child!,
        ),
        home: const NpmOverviewScreen(topPadding: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

NpmProxyHost _host(
  int id,
  String domain, {
  String forwardHost = '',
  bool enabled = true,
  bool configLoaded = true,
  String errorText = '',
}) => NpmProxyHost(
  id: id,
  domainNames: [domain],
  forwardScheme: 'http',
  forwardHost: forwardHost.isEmpty ? '10.0.0.$id' : forwardHost,
  forwardPort: 8080,
  enabled: enabled,
  sslForced: false,
  certificateId: 0,
  accessListId: 0,
  cachingEnabled: false,
  blockExploits: false,
  allowWebsocketUpgrade: false,
  configLoaded: configLoaded,
  errorText: errorText,
  advancedConfig: '',
);

NpmCertificate _cert(int id, String name, {required Duration expiresIn}) =>
    NpmCertificate(
      id: id,
      provider: 'letsencrypt',
      niceName: name,
      domainNames: [name],
      expiresOn: DateTime.now().add(expiresIn),
    );

/// A probe pass over the default three hosts.
NpmUpstreamReport _report(Map<int, NpmUpstream> byHostId) => NpmUpstreamReport(
  byHostId: byHostId,
  checked: byHostId.length,
  total: 3,
  takenAt: DateTime.now(),
);
