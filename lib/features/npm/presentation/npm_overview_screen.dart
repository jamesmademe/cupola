import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_access.dart';
import 'package:cupola/features/npm/presentation/npm_capability.dart';
import 'package:cupola/features/npm/presentation/npm_overview_provider.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/npm/presentation/npm_screen.dart'
    show NpmDefaultAdminWarning;
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The first tab of Nginx Proxy Manager's service home.
///
/// Overview alone carries the identity block and the readouts: Proxy hosts and
/// Certificates are each a view of one kind of record, and then three regions
/// in the order the **mobile** board draws them: what is wrong, what is being
/// fronted, what is about to lapse. That order is the board's answer rather
/// than a preference: `HomeNpmMobile` promotes Needs attention above the host
/// table, because the narrow column cannot draw a table and a person who opens
/// a reverse proxy on a phone is almost always there because something stopped
/// answering.
///
/// **It draws neither the app bar nor the tab bar.** `ServiceHomeScreen` owns
/// the first and `ServiceTabScaffold` the second, both floated above this page
/// as glass bands so the ambient gradient reads continuously behind them; this
/// screen reserves the room with [topPadding] instead.
///
/// ## The chrome this page inherits rather than invents
///
/// [NpmDefaultAdminWarning] and [NpmCapabilityBannerSlot] are drawn here as they
/// are on every other NPM surface, and neither is decoration:
///
///  * the warning fires only on an install that still ships
///    `admin@example.com` / `changeme`, and on that install it outranks every
///    other thing on the page: that account rewrites every route on the box;
///  * the band is the sentence that explains why a control elsewhere in this
///    service is attenuated. `npm_capability.dart` owns the gate, this page
///    neither weakens nor duplicates it: **the Overview offers no writes at
///    all.** Renew lives on the Certificates tab beside its confirmation, and
///    `NpmClient.renewCertificate` talks to Let's Encrypt, so a Renew reachable
///    from a pull-to-refresh surface is one mis-tap away from burning the
///    user's ACME rate limits, a failure that outlasts the app session and
///    that they cannot fix from here. Better to delete a promise than to build
///    a control that has to be defended.
///
/// ## What this page intentionally does not duplicate
///
/// Access lists and Audit log now have dedicated endpoint-backed tabs. The
/// Overview keeps its focus on proxy health, fronted hosts and certificates;
/// it does not repeat those records or imply that a one-shot reachability
/// probe can provide a historical `since` timestamp. The probe reports its
/// actual coverage instead, and the detailed tabs own their own loading and
/// failure states.
///
/// ## The coverage figure, which is the one thing that must never disappear
///
/// The upstream probe is partial **by design**: eight hosts of however many
/// the box fronts. Every region here that reports anything derived from it
/// prints `8 of 23 enabled checked from this device` beside
/// the figure, and a host with no verdict contributes no clause to its row. That last word is not
/// padding: the probe never opens a socket for a disabled host, so its total is
/// a narrower population than the host count printed beside it, and unnamed the
/// pair reads as two hosts having gone missing in between. See `npm_overview_provider.dart`
/// for the three rules and the reason: a coverage line that quietly vanishes
/// turns fifteen unchecked hosts into fifteen healthy ones.
///
/// Sections load and fail independently. An NPM answering `/nginx/proxy-hosts`
/// but not `/nginx/certificates` still draws two regions, and the third says so
/// in its own slot instead of taking the page down.
class NpmOverviewScreen extends ConsumerWidget {
  const NpmOverviewScreen({super.key, this.topPadding = _hostedTopPadding});

  /// The room the two glass bands above this page occupy.
  ///
  /// Composed from the same two constants the router composes its own from, so
  /// a screen built outside the router (a test, a preview) reserves the right
  /// space instead of tucking its first region under the tab bar.
  static const double _hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Checked **before** any provider is reached. `npmClientProvider` throws
    // `Nginx Proxy Manager not configured`, and letting `AsyncValueWidget`
    // catch that throw would draw the same pixels while leaving five *failed*
    // providers behind it, each scheduling a retry with backoff for a condition
    // no amount of waiting changes: a battery cost on device and a pending
    // timer in tests.
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) =>
            settings.isServiceConfigured(ServiceKey.nginxProxyManager),
      ),
    );

    return AmbientScaffold(
      accent: ServiceKey.nginxProxyManager.accent,
      body: SafeArea(
        bottom: false,
        child: configured
            ? _OverviewBody(topPadding: topPadding)
            // `.forService`, never the generic form: this is a service
            // dashboard, so the door goes to NPM's own connection form rather
            // than the settings index. NPM is the one service whose form asks
            // for an email and a password instead of an API key, which makes
            // landing on the right form matter more here than anywhere else.
            : NotConfiguredPlaceholder.forService(ServiceKey.nginxProxyManager),
      ),
    );
  }
}

class _OverviewBody extends ConsumerWidget {
  const _OverviewBody({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        invalidateServiceReadout(ref, ServiceKey.nginxProxyManager);
        // The two documents every region is folded from. The upstream probe is
        // deliberately absent: it awaits `npmProxyHostsProvider.future`, so one
        // gesture re-reads the table and re-probes it, and invalidating it
        // separately would run a second pass of up to eight sockets.
        ref.invalidate(npmProxyHostsProvider);
        ref.invalidate(npmCertificatesProvider);
        // The account probe rides nothing, and a permission changed on the
        // server is exactly what a person pulls to refresh for. The server info
        // is what the default-admin warning reads.
        ref.invalidate(npmAccountProvider);
        ref.invalidate(npmServerInfoProvider);
        ref.invalidate(npmOverviewAttentionProvider);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      // One scroll view for the whole page: the regions are one column of
      // reading, not three independently scrolling panes.
      child: ServiceOverviewScroll(
        topPadding: topPadding,
        children: [
          const ServiceOverviewIdentity(service: ServiceKey.nginxProxyManager),
          ...sectionsOrOneLine(ref, ServiceKey.nginxProxyManager, [
            ServiceKpiPeek.room(
              kpis: ref.watch(serviceKpiProvider(ServiceKey.nginxProxyManager)),
              service: ServiceKey.nginxProxyManager,
            ),
            // Above every section, in this order: a box that still answers to
            // `changeme` outranks anything a section could say, and the band
            // that explains an attenuated control has to be readable before the
            // control is reached.
            const NpmDefaultAdminWarning(),
            const NpmCapabilityBannerSlot(),
            const SizedBox(height: AppSpacing.sm),
            const _NeedsAttentionSection(),
            const _ProxyHostsSection(),
            const _CertificatesSection(),
          ]),
        ],
      ),
    );
  }
}

// ─── 1. Needs attention ─────────────────────────────────────────────────────

/// What is wrong, before what is working.
class _NeedsAttentionSection extends ConsumerWidget {
  const _NeedsAttentionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(npmOverviewAttentionProvider);

    return ServiceOverviewSection(
      service: ServiceKey.nginxProxyManager,
      title: 'Needs attention',
      // The **census**. `npmAttentionItems` returns the whole list and the cap
      // is applied below at draw time, so this number can never be the length
      // of the sample.
      subtitle: npmAttentionSubtitle(items.asData?.value),
      // No link: a refused configuration belongs to Proxy hosts and a lapsing
      // certificate to Certificates, and one destination would have to lie
      // about half the rows. Each row is its own door instead.
      child: AsyncValueWidget<List<NpmAttentionItem>>.section(
        value: items,
        service: ServiceKey.nginxProxyManager,
        consequence: 'what needs attention is not shown',
        loadingLabel: 'Loading what needs attention',
        onRetry: () {
          ref.invalidate(npmOverviewAttentionProvider);
          ref.invalidate(npmProxyHostsProvider);
          ref.invalidate(npmCertificatesProvider);
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (data) => data.isEmpty,
        // A resting state wears no alarm chrome: nothing is wrong, and saying
        // so is not an error state.
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.check_circle_outline_rounded,
          label: 'Every host is serving and no certificate is due',
        ),
        data: (data) => Column(
          children: [
            for (final item in data.take(npmAttentionPreviewLimit))
              _AttentionRow(item: item),
          ],
        ),
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item});

  final NpmAttentionItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a raw `AppColors.warning`: the walk resolves
    // amber against the surface this row actually lands on, which on the light
    // theme is a different hue from the one the dark artboards draw.
    final tone = statusToneColor(
      colorScheme,
      item.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    final door = item.door;

    return ServiceOverviewRow(
      spoken: item.spoken,
      leading: Icon(item.icon, size: 18, color: tone),
      title: item.headline,
      titleColor: tone,
      detail: item.detail,
      onTap: door == null
          ? null
          : () =>
                openAttentionDoor(context, ServiceKey.nginxProxyManager, door),
      doorHint: door == null
          ? null
          : attentionDoorHint(ServiceKey.nginxProxyManager, door),
    );
  }
}

// ─── 2. Proxy hosts ─────────────────────────────────────────────────────────

/// What the box is fronting, worst first.
class _ProxyHostsSection extends ConsumerWidget {
  const _ProxyHostsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(npmProxyHostsProvider);
    final report = ref.watch(npmUpstreamReportProvider).asData?.value;

    return ServiceOverviewSection(
      service: ServiceKey.nginxProxyManager,
      title: 'Proxy hosts',
      // `25 · 8 of 23 enabled checked from this device`. The
      // second half is the difference between a partial probe and silent green
      // ticks, and its last word is what keeps the two counts from
      // contradicting each other.
      subtitle: npmProxyHostsSubtitle(hosts.asData?.value, report),
      destination: ServiceTab.proxyHosts,
      child: AsyncValueWidget<List<NpmProxyHost>>.section(
        value: hosts,
        service: ServiceKey.nginxProxyManager,
        consequence: 'the proxy hosts are not shown',
        loadingLabel: 'Loading proxy hosts',
        onRetry: () => ref.invalidate(npmProxyHostsProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 3),
        isEmpty: (data) => data.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.alt_route_rounded,
          label: 'No proxy hosts configured',
        ),
        data: (data) => Column(
          children: [
            for (final row in npmProxyHostRows(
              data,
              report,
            ).take(npmProxyHostPreviewLimit))
              _ProxyHostRow(row: row),
          ],
        ),
      ),
    );
  }
}

class _ProxyHostRow extends StatelessWidget {
  const _ProxyHostRow({required this.row});

  final NpmProxyHostRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(
      colorScheme,
      row.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: row.spoken,
      leading: Icon(row.icon, size: 18, color: tone),
      title: row.host.primaryDomain,
      // The hostname itself is not the fault, so it keeps the ordinary ink and
      // the mark beside it carries the tone. Colouring twenty-three domain
      // names green would spend the page's whole colour budget on the fact that
      // a reverse proxy is proxying.
      titleColor: row.tone == StatusTone.warning ? tone : null,
      detail: row.detail,
    );
  }
}

// ─── 3. Certificates ────────────────────────────────────────────────────────

/// What is about to lapse, soonest first.
class _CertificatesSection extends ConsumerWidget {
  const _CertificatesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final certificates = ref.watch(npmCertificatesProvider);
    // One `now` for the header and every row under it. Read twice, a
    // certificate expiring at this second could be counted in the subtitle and
    // drawn as valid in the row below it.
    final now = DateTime.now();

    return ServiceOverviewSection(
      service: ServiceKey.nginxProxyManager,
      title: 'Certificates',
      subtitle: npmCertificatesSubtitle(certificates.asData?.value, now),
      destination: ServiceTab.certificates,
      child: AsyncValueWidget<List<NpmCertificate>>.section(
        value: certificates,
        service: ServiceKey.nginxProxyManager,
        consequence: 'the certificates are not shown',
        loadingLabel: 'Loading certificates',
        onRetry: () => ref.invalidate(npmCertificatesProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (data) => data.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.lock_outline_rounded,
          label: 'No certificates yet',
        ),
        data: (data) => Column(
          children: [
            for (final row in npmCertificateRows(
              data,
              now,
            ).take(npmCertificatePreviewLimit))
              _CertificateRow(row: row),
          ],
        ),
      ),
    );
  }
}

class _CertificateRow extends StatelessWidget {
  const _CertificateRow({required this.row});

  final NpmCertificateRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(
      colorScheme,
      row.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: row.spoken,
      leading: Icon(row.icon, size: 18, color: tone),
      title: row.certificate.displayName,
      titleColor: row.tone == StatusTone.warning ? tone : null,
      detail: row.detail,
    );
  }
}
