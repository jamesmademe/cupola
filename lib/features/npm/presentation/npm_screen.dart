import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:cupola/features/npm/data/npm_upstream_probe.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_access.dart';
import 'package:cupola/features/npm/presentation/npm_actions.dart';
import 'package:cupola/features/npm/presentation/npm_advanced_config_screen.dart';
import 'package:cupola/features/npm/presentation/npm_capability.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Which part of the old Nginx Proxy Manager dashboard a page lists.
///
/// Public since the tab model: Proxy hosts and Certificates are two entries on
/// NPM's own bar now, so the choice is made by the router rather than by
/// scrolling past one section to reach the other. [everything] is the page as
/// it was, for a caller that wants the whole service in one scroll.
enum NpmSection {
  everything('Nginx Proxy Manager'),
  proxyHosts('Proxy hosts'),
  certificates('Certificates'),
  accessLists('Access lists'),
  auditLog('Audit log');

  const NpmSection(this.label);

  /// The word the app bar prints when this page draws one of its own.
  final String label;
}

/// Nginx Proxy Manager: what the box is fronting, what is broken, and which
/// certificates are about to lapse.
///
/// **It used to be all of that on one page**, one section under the next at
/// `/dashboard/npm`. NPM's bar draws Proxy hosts and Certificates as separate
/// destinations, so the page split; each tab reads only the documents it draws.
///
/// Named constructors rather than a `section:` argument or a boolean, following
/// `lib/core/widgets/AGENTS.md`: a call site says which part it wants in the
/// constructor name.
///
/// **What went where, and why** — the split is a decision, not a cut:
///
///  * The **redirections, 404s and streams** ride the Proxy hosts tab rather
///    than getting one of their own. NPM's own menu files all four kinds under
///    Hosts, the bar has exactly one Hosts entry and this is it, and the list
///    is already fetched — under Certificates it would be nonsense, and dropped
///    it would delete a list the client answers for. On
///    [NpmSection.everything] that keeps the two host lists adjacent, which
///    moves them above Certificates: one grouping, drawn the same way whether
///    it is a tab or a stretch of one page.
///  * The **permission band and the default-admin warning are shared chrome**,
///    drawn on every variant. The band is not decoration: it is the sentence
///    that explains why a control is attenuated, and *both* tabs carry gated
///    controls — the host menu's Enable/Disable on one, a certificate's Renew
///    on the other. Leaving the controls on two tabs and the explanation on one
///    is exactly the failure `npm_write_gate.dart` exists to prevent. The
///    warning is a fact about the box rather than about a section, it renders
///    at all only on an install that still ships `admin@example.com`, and on
///    that install it outranks everything else on either tab.
///  * The **readouts are not here**. `ServiceKpiPeek` sat on the single page
///    because the single page was the service; under the tab model the Overview
///    is the tab that carries the identity block and the readouts, and
///    repeating them on a section tab would be the same figures twice in one
///    scroll. [NpmSection.everything] keeps them, because there it still *is*
///    the whole service.
///  * A section tab **lists everything it names**. The single page capped
///    certificates at eight and the other hosts at ten, which is right for a
///    peek and wrong for a tab called Certificates: eight of twenty, with
///    nothing saying so, is a count the reader has no way to doubt. The caps
///    stay on [NpmSection.everything] and nowhere else.
class NpmScreen extends ConsumerWidget {
  /// The whole service in one scroll, as it read before the bar.
  const NpmScreen({super.key, this.showAppBar = true, this.topPadding = 0})
    : section = NpmSection.everything;

  /// The hosts half — NPM's Proxy hosts tab.
  const NpmScreen.proxyHosts({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  }) : section = NpmSection.proxyHosts;

  /// The certificates half — NPM's Certificates tab.
  const NpmScreen.certificates({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  }) : section = NpmSection.certificates;

  const NpmScreen.accessLists({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  }) : section = NpmSection.accessLists;

  const NpmScreen.auditLog({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  }) : section = NpmSection.auditLog;

  final NpmSection section;

  /// Whether to draw this screen's own app bar.
  ///
  /// False inside the tab shell, where `ServiceHomeScreen` draws the service
  /// band and `ServiceTabScaffold` the tab bar above it: a third bar of its own
  /// would put two titles and two back chevrons in one corner.
  final bool showAppBar;

  /// Room those two glass bands take above this page, since they float over it
  /// rather than pushing it down.
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    // Checked **before** any provider is read, not after: `npmClientProvider`
    // throws when NPM is not configured, and a `FutureProvider` that throws is
    // a failed provider — it schedules a retry with backoff for a condition no
    // waiting changes, and surfaces in tests as a pending timer.
    final isConfigured = settings.isServiceConfigured(
      ServiceKey.nginxProxyManager,
    );

    return AmbientScaffold(
      accent: ServiceKey.nginxProxyManager.accent,
      appBar: showAppBar ? GlassAppBar(title: Text(section.label)) : null,
      body: SafeArea(
        top: showAppBar,
        child: isConfigured
            // Keyed by section so two variants cannot share one list state:
            // they are separate branches of the service shell and each keeps
            // its own scroll offset.
            ? _NpmSection(
                key: ValueKey(section),
                section: section,
                topPadding: topPadding,
              )
            : NotConfiguredPlaceholder.forService(ServiceKey.nginxProxyManager),
      ),
    );
  }
}

final _invalidateAfterAction = <ProviderOrFamily>[
  npmProxyHostsProvider,
  npmCertificatesProvider,
];

/// Re-reads what the section on screen draws, and nothing else.
///
/// A pull on Certificates no longer re-fetches the host list: the two are
/// separate branches now, and refreshing a page the user cannot see is a round
/// trip they did not ask for. Three things are re-read by every section — the
/// account probe behind the permission band, the server info behind the
/// default-admin warning, and the KPI and summary the Dashboard card reads —
/// because all three qualify whatever is on screen.
void _invalidate(WidgetRef ref, NpmSection section) {
  switch (section) {
    case NpmSection.everything:
      ref.invalidate(npmProxyHostsProvider);
      ref.invalidate(npmOtherHostsProvider);
      ref.invalidate(npmCertificatesProvider);
    case NpmSection.proxyHosts:
      ref.invalidate(npmProxyHostsProvider);
      ref.invalidate(npmOtherHostsProvider);
    case NpmSection.certificates:
      ref.invalidate(npmCertificatesProvider);
    case NpmSection.accessLists:
      ref.invalidate(npmAccessListsProvider);
    case NpmSection.auditLog:
      ref.invalidate(npmAuditLogProvider);
  }
  // The account probe does not ride anything, and a permission changed on the
  // server is exactly the kind of thing a person pulls to refresh for.
  ref.invalidate(npmAccountProvider);
  ref.invalidate(npmServerInfoProvider);
  ref.invalidate(serviceKpiProvider(ServiceKey.nginxProxyManager));
  ref.invalidate(serviceSummaryProvider(ServiceKey.nginxProxyManager));
}

/// `25 · reachability checked for 8 of 23 enabled`, and nothing before either
/// answers.
String? _proxyHostSubtitle(
  List<NpmProxyHost>? hosts,
  NpmUpstreamReport? report,
) {
  if (hosts == null) return null;
  return ['${hosts.length}', ?report?.coverage].join(' · ');
}

class _NpmSection extends ConsumerWidget {
  const _NpmSection({
    super.key,
    required this.section,
    required this.topPadding,
  });

  final NpmSection section;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(
      serviceSummaryProvider(ServiceKey.nginxProxyManager),
    );
    // A failed probe, in its own words: "did not answer" only when nothing did,
    // the refusal and its remedy when the sign-in was refused.
    final failed = summaryAsync.whenOrNull(
      data: (summary) => summary.isOnline ? null : summary,
    );

    if (failed != null) {
      return ServiceOfflineState.fromSummary(
        summary: failed,
        onRetry: () => _invalidate(ref, section),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _invalidate(ref, section);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          if (section == NpmSection.everything)
            ServiceKpiPeek(
              kpis: ref.watch(serviceKpiProvider(ServiceKey.nginxProxyManager)),
              accent: ServiceKey.nginxProxyManager.accent,
            ),
          const NpmDefaultAdminWarning(),
          NpmCapabilityBannerSlot(
            resources: switch (section) {
              NpmSection.everything => const {
                NpmResource.proxyHosts,
                NpmResource.certificates,
              },
              NpmSection.proxyHosts => const {NpmResource.proxyHosts},
              NpmSection.certificates => const {NpmResource.certificates},
              // No writes on these two: the banner speaks only when the
              // account can change nothing at all.
              NpmSection.accessLists || NpmSection.auditLog => null,
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          ...switch (section) {
            NpmSection.everything => [
              ..._hostChildren(ref),
              ..._certificateChildren(ref),
            ],
            NpmSection.proxyHosts => _hostChildren(ref),
            NpmSection.certificates => _certificateChildren(ref),
            NpmSection.accessLists => _accessListChildren(ref),
            NpmSection.auditLog => _auditChildren(ref),
          },
        ],
      ),
    );
  }

  List<Widget> _hostChildren(WidgetRef ref) {
    final hostsAsync = ref.watch(npmProxyHostsProvider);
    return [
      SectionHeader(
        title: 'Proxy hosts',
        showChevron: false,
        // "25 · reachability checked for 8 of 23 enabled" — the coverage is
        // drawn because the Upstream column is partial by design. Without it a
        // column that answered for eight rows and stayed blank for fifteen
        // would read as fifteen healthy hosts.
        subtitle: _proxyHostSubtitle(
          hostsAsync.asData?.value,
          ref.watch(npmUpstreamReportProvider).asData?.value,
        ),
      ),
      const SizedBox(height: 2),
      _ProxyHostList(hostsAsync: hostsAsync),
      const SizedBox(height: AppSpacing.sm),
      const SectionHeader(
        title: 'Redirections, 404s and streams',
        showChevron: false,
      ),
      const SizedBox(height: 2),
      _SimpleHostList(
        hostsAsync: ref.watch(npmOtherHostsProvider),
        limit: section == NpmSection.everything ? 10 : null,
      ),
    ];
  }

  List<Widget> _certificateChildren(WidgetRef ref) => [
    const SectionHeader(title: 'Certificates', showChevron: false),
    const SizedBox(height: 2),
    _CertificateList(
      certsAsync: ref.watch(npmCertificatesProvider),
      limit: section == NpmSection.everything ? 8 : null,
    ),
  ];

  List<Widget> _accessListChildren(WidgetRef ref) => [
    const SectionHeader(title: 'Access lists', showChevron: false),
    const SizedBox(height: 2),
    _AccessListList(listsAsync: ref.watch(npmAccessListsProvider)),
  ];

  List<Widget> _auditChildren(WidgetRef ref) {
    final account = ref.watch(npmAccountProvider).asData?.value;
    return [
      const SectionHeader(title: 'Audit log', showChevron: false),
      const SizedBox(height: 2),
      if (account != null && !account.isAdmin)
        const _NpmCapabilityNote(
          message:
              'Nginx Proxy Manager exposes its audit log to administrators only.',
        )
      else
        _AuditLogList(entriesAsync: ref.watch(npmAuditLogProvider)),
    ];
  }
}

class _NpmCapabilityNote extends StatelessWidget {
  const _NpmCapabilityNote({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _AccessListList extends ConsumerWidget {
  const _AccessListList({required this.listsAsync});
  final AsyncValue<List<NpmAccessList>> listsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) => listsAsync.when(
    data: (lists) => lists.isEmpty
        ? const _NpmCapabilityNote(message: 'No access lists configured.')
        : Column(
            children: lists
                .map((list) {
                  final hosts = list.proxyHostCount;
                  final detail = [
                    if (hosts != null)
                      '$hosts ${hosts == 1 ? 'host' : 'hosts'}',
                    '${list.clients.length} IP ${list.clients.length == 1 ? 'rule' : 'rules'}',
                    if (list.passAuth) 'basic auth',
                  ].join(' · ');
                  return _NpmReadOnlyTile(
                    icon: Icons.shield_outlined,
                    title: list.name,
                    detail: detail,
                  );
                })
                .toList(growable: false),
          ),
    loading: () => const ListRowsShimmer(count: 3),
    error: (error, _) => InlineErrorRetry(
      message: sectionFailureMessage(
        ServiceKey.nginxProxyManager,
        error,
        consequence: 'the access lists are not shown',
      ),
      error: error,
      service: ServiceKey.nginxProxyManager,
      onRetry: () => ref.invalidate(npmAccessListsProvider),
    ),
  );
}

class _AuditLogList extends ConsumerWidget {
  const _AuditLogList({required this.entriesAsync});
  final AsyncValue<List<NpmAuditEntry>> entriesAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) => entriesAsync.when(
    data: (entries) => entries.isEmpty
        ? const _NpmCapabilityNote(message: 'No audit entries reported.')
        : Column(
            children: entries
                .map((entry) {
                  final target = entry.summary.isEmpty
                      ? '${entry.objectType}${entry.objectId == null ? '' : ' #${entry.objectId}'}'
                      : entry.summary;
                  final time = entry.createdOn == null
                      ? null
                      : formatRelativeDateTime(entry.createdOn!);
                  return _NpmReadOnlyTile(
                    icon: Icons.history_rounded,
                    title: '${entry.action} · $target',
                    detail: [entry.objectType, ?time].join(' · '),
                  );
                })
                .toList(growable: false),
          ),
    loading: () => const ListRowsShimmer(count: 4),
    error: (error, _) => InlineErrorRetry(
      message: sectionFailureMessage(
        ServiceKey.nginxProxyManager,
        error,
        consequence: 'the audit log is not shown',
      ),
      error: error,
      service: ServiceKey.nginxProxyManager,
      onRetry: () => ref.invalidate(npmAuditLogProvider),
    ),
  );
}

class _NpmReadOnlyTile extends StatelessWidget {
  const _NpmReadOnlyTile({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$title, $detail',
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadiusMd,
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          leading: Icon(
            icon,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          title: Text(title),
          subtitle: Text(detail),
        ),
      ),
    ),
  );
}

/// Warns when the install is old enough to still ship NPM's hard-coded default
/// administrator.
///
/// Not scaremongering: `admin@example.com` / `changeme` existed as a real
/// working login up to 2.12, and on this service that account can rewrite every
/// route on the box. If the user has one of those versions, saying so is worth
/// more than anything else on this screen.
///
/// **Public because it is shared chrome, not a section.** It is a fact about
/// the box rather than about a list, so every NPM surface draws it — this page
/// in all three of its shapes and `NpmOverviewScreen` — and a second copy of
/// the card written next door is a second copy that drifts.
/// `NpmCapabilityBannerSlot` travels with it for the same reason.
class NpmDefaultAdminWarning extends ConsumerWidget {
  const NpmDefaultAdminWarning({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(npmServerInfoProvider).asData?.value;
    if (info == null || !info.hasDefaultAdminRisk) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    // Through `statusToneColor`, not the raw palette constant it used to paint:
    // `AppColors.warning` is yellow-400, which on the light theme's near-white
    // card measures well under 3:1 and drew this card's icon and border as a
    // pale smear. The tone walk is what keeps amber legible in both themes.
    final tone = statusToneColor(
      colorScheme,
      StatusTone.warning,
      surface: colorScheme.surface,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(color: tone.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(Icons.gpp_maybe_rounded, color: tone, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Version ${info.version} still ships the default '
                'admin@example.com / changeme login. If it has not been '
                'changed, anyone who can reach this box has full control of '
                'every route on it.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProxyHostList extends ConsumerWidget {
  const _ProxyHostList({required this.hostsAsync});

  final AsyncValue<List<NpmProxyHost>> hostsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return hostsAsync.when(
      data: (hosts) {
        if (hosts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('No proxy hosts configured.'),
          );
        }
        // Broken first, then disabled, then the rest. A control-room screen
        // should not make you scroll to find the thing that is down.
        final ordered = [...hosts]
          ..sort((a, b) {
            int rank(NpmProxyHost h) =>
                h.hasConfigError ? 0 : (h.enabled ? 2 : 1);
            final byRank = rank(a).compareTo(rank(b));
            return byRank != 0
                ? byRank
                : a.primaryDomain.compareTo(b.primaryDomain);
          });
        return Column(
          children: ordered
              .map((host) => _ProxyHostTile(host: host))
              .toList(growable: false),
        );
      },
      loading: () => const ListRowsShimmer(count: 3),
      error: (error, _) => InlineErrorRetry(
        message: sectionFailureMessage(
          ServiceKey.nginxProxyManager,
          error,
          consequence: 'the proxy hosts are not shown',
        ),
        error: error,
        service: ServiceKey.nginxProxyManager,
        onRetry: () => ref.invalidate(npmProxyHostsProvider),
      ),
    );
  }
}

class _ProxyHostTile extends ConsumerWidget {
  const _ProxyHostTile({required this.host});

  final NpmProxyHost host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // NPM answered and told us this host's config is refused: a fault, not
    // silence. Red on this screen belongs to an NPM that did not answer.
    final (Color tone, IconData glyph, String state) = host.hasConfigError
        ? (
            statusToneColor(colorScheme, StatusTone.warning),
            Icons.error_outline_rounded,
            'nginx error',
          )
        : host.enabled
        ? (
            statusToneColor(colorScheme, StatusTone.success),
            Icons.check_circle_rounded,
            'Config loaded',
          )
        : (
            colorScheme.onSurfaceVariant,
            Icons.pause_circle_rounded,
            'Disabled',
          );

    final upstream =
        ref.watch(npmUpstreamReportProvider).asData?.value.forHost(host.id) ??
        NpmUpstream.unchecked;
    final down = upstream == NpmUpstream.down;

    // A backend that is not answering leads the line, for the same reason a
    // broken host leads the table: the reader is here for the thing that is
    // wrong. A host nobody probed says nothing at all — the section header
    // carries the coverage, so silence here means "not measured", not "fine".
    final detail = [
      if (down) 'upstream down',
      state,
      host.target,
      if (upstream == NpmUpstream.answering) 'upstream answering',
      if (host.hasCertificate) 'TLS',
      if (host.hasAccessList) 'Access list',
    ].join(' · ');

    final hasFault = host.errorText.isNotEmpty || down;
    final detailText = host.errorText.isNotEmpty ? host.errorText : detail;

    return Semantics(
      container: true,
      label: [
        host.primaryDomain,
        detailText,
        // The probe runs from the phone, not from the server, and the most
        // common reason it fails is a forward host that only resolves on the
        // server's own network. Said out loud rather than left as a colour.
        if (down) 'not reachable from this device',
      ].join(', '),
      // The actions menu is the only control on the row and has to stay on the
      // screen reader's path, so the subtree is explicit rather than excluded.
      explicitChildNodes: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        child: Material(
          color: colorScheme.surface,
          borderRadius: AppRadius.borderRadiusMd,
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: AppRadius.borderRadiusSm,
                  ),
                  alignment: Alignment.center,
                  child: ExcludeSemantics(
                    child: Icon(glyph, size: 16, color: tone),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          host.primaryDomain,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium!.weight(FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          detailText,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: hasFault
                                    ? statusToneColor(
                                        colorScheme,
                                        StatusTone.warning,
                                        surface: colorScheme.surface,
                                      )
                                    : colorScheme.onSurfaceVariant,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                _ProxyHostMenu(host: host),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProxyHostMenu extends ConsumerWidget {
  const _ProxyHostMenu({required this.host});

  final NpmProxyHost host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionId = capabilityConnectionId(
      ref,
      ServiceKey.nginxProxyManager,
    );
    bool allowed() => capabilityWriteAllowed(
      context,
      ref,
      service: ServiceKey.nginxProxyManager,
      connectionId: connectionId,
      resource: NpmResource.proxyHosts.key,
      blockedMessage: npmBlockedMessage(NpmResource.proxyHosts),
    );
    // Dimmed, never removed. Taking the item out would take the *fact* out with
    // it: the user would be left wondering where Disable went rather than
    // learning that this account cannot use it. And never `enabled: false`: a
    // disabled item drops off the screen reader's path, taking the explanation
    // with it.
    Widget label(String text) => CapabilityGatedMenuLabel(
      service: ServiceKey.nginxProxyManager,
      connectionId: connectionId,
      resource: NpmResource.proxyHosts.key,
      text: text,
      hint: npmCapabilityHint,
    );

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 18),
      tooltip: 'Host actions',
      onSelected: (value) {
        switch (value) {
          case 'enable':
            // Switching a host back **on** is the recoverable direction: it can
            // only restore service, and nginx refusing the config is reported
            // rather than hidden. No typed confirmation for that.
            if (!allowed()) return;
            runNpmAction(
              context,
              ref,
              resource: NpmResource.proxyHosts,
              action: (c) => c.setProxyHostEnabled(host.id, true),
              successMessage: '${host.primaryDomain} enabled',
              failureMessage: 'Could not enable ${host.primaryDomain}',
              invalidate: _invalidateAfterAction,
            );
          case 'disable':
            if (!allowed()) return;
            _confirmDisable(context, ref, host);
          case 'advanced':
            // Opening the editor is a read; the save inside it is what the role
            // gate and the typed confirm guard. A view-only account can and
            // should be able to look at the block.
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NpmAdvancedConfigScreen(host: host),
              ),
            );
        }
      },
      itemBuilder: (context) => [
        if (host.enabled)
          PopupMenuItem(value: 'disable', child: label('Disable…'))
        else
          PopupMenuItem(value: 'enable', child: label('Enable')),
        PopupMenuItem(
          value: 'advanced',
          child: Text(
            host.advancedConfigLines > 0
                ? 'Advanced · ${host.advancedConfigLines} lines'
                : 'Advanced Nginx config…',
          ),
        ),
      ],
    );
  }
}

Future<void> _confirmDisable(
  BuildContext context,
  WidgetRef ref,
  NpmProxyHost host,
) async {
  final confirmed = await confirmByTyping(
    context,
    title: 'Stop serving ${host.primaryDomain}?',
    message:
        'Disabling this proxy host stops Nginx Proxy Manager serving that '
        'hostname. Anyone using it, not just this device, gets a connection '
        'error immediately, and nothing on the server warns them.',
    phrase: host.primaryDomain,
    confirmLabel: 'Stop serving',
  );
  if (!confirmed || !context.mounted) return;

  await runNpmAction(
    context,
    ref,
    resource: NpmResource.proxyHosts,
    action: (c) => c.setProxyHostEnabled(host.id, false),
    successMessage: '${host.primaryDomain} is no longer served',
    failureMessage: 'Could not disable ${host.primaryDomain}',
    invalidate: _invalidateAfterAction,
  );
}

class _CertificateList extends ConsumerWidget {
  const _CertificateList({required this.certsAsync, required this.limit});

  final AsyncValue<List<NpmCertificate>> certsAsync;

  /// How many rows to draw, or null for all of them.
  ///
  /// A peek on the whole-service page, everything on the tab that is named
  /// after them: a list capped at eight with nothing saying so reads as a
  /// complete answer.
  final int? limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return certsAsync.when(
      data: (certs) {
        if (certs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('No certificates.'),
          );
        }
        final now = DateTime.now();
        final ordered = [...certs]
          ..sort((a, b) {
            final aDays = a.daysUntilExpiry(now) ?? 1 << 30;
            final bDays = b.daysUntilExpiry(now) ?? 1 << 30;
            return aDays.compareTo(bDays);
          });
        final shown = limit == null ? ordered : ordered.take(limit!);
        return Column(
          children: shown
              .map((cert) => _CertificateTile(cert: cert, now: now))
              .toList(growable: false),
        );
      },
      loading: () => const ListRowsShimmer(count: 3),
      error: (error, _) => InlineErrorRetry(
        message: sectionFailureMessage(
          ServiceKey.nginxProxyManager,
          error,
          consequence: 'the certificates are not shown',
        ),
        error: error,
        service: ServiceKey.nginxProxyManager,
        onRetry: () => ref.invalidate(npmCertificatesProvider),
      ),
    );
  }
}

class _CertificateTile extends ConsumerWidget {
  const _CertificateTile({required this.cert, required this.now});

  final NpmCertificate cert;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final days = cert.daysUntilExpiry(now);
    final expiring = cert.isExpiringSoon(now);
    // `hasExpired`, not `days < 0`: the day count truncates toward zero, so for
    // the twenty-four hours after a certificate lapses it answers 0 and this
    // tile would print "Expires in 0 days" about something already refused.
    final expired = cert.hasExpired(now);
    // An expired certificate and one about to expire are the same kind of
    // fact — the canvas names "expiring" in the amber set — and neither is a
    // connection that did not answer.
    final tone = statusToneColor(
      colorScheme,
      expired || expiring ? StatusTone.warning : StatusTone.success,
    );
    // Let's Encrypt renews from 30 days out, so a short-dated certificate
    // inside that window is one whose renewal has not run. That is the only
    // failed-renewal reason this app can honestly give: NPM keeps no error on
    // the certificate record, and the renew call's own output is never
    // rendered because certbot failures carry the DNS-provider credentials
    // used for the challenge.
    final detail = [
      if (days == null)
        cert.provider
      else if (expired)
        (-days <= 0 ? 'Expired today' : 'Expired ${-days} days ago')
      else
        'Expires in $days days',
      if (cert.renewalNotCompleting(now))
        'renewal has not run, Let\'s Encrypt renews from 30 days out',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: tone),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cert.displayName,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.weight(FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: expiring || expired
                            ? tone
                            : colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Renewal is offered only for Let's Encrypt certificates, and
              // only as a deliberate tap. The call reaches Let's Encrypt, so
              // binding it to anything automatic — a retry, a pull-to-refresh —
              // would burn the account's ACME rate limits and get the user's
              // domain refused for hours in a way they cannot fix from here.
              //
              // Dimmed rather than hidden on a view-only account (decision 34):
              // the control keeps its target and its name, gains the hint, and
              // answers on tap.
              if (cert.isLetsEncrypt)
                CapabilityGatedAction.builder(
                  service: ServiceKey.nginxProxyManager,
                  connectionId: capabilityConnectionId(
                    ref,
                    ServiceKey.nginxProxyManager,
                  ),
                  resource: NpmResource.certificates.key,
                  hint: npmCapabilityHint,
                  blockedMessage: npmBlockedMessage(NpmResource.certificates),
                  onTap: () => runNpmAction(
                    context,
                    ref,
                    resource: NpmResource.certificates,
                    action: (c) => c.renewCertificate(cert.id),
                    successMessage: 'Renewal requested',
                    failureMessage: 'Could not request renewal',
                    invalidate: _invalidateAfterAction,
                  ),
                  builder: (context, onPressed, annotate) => TextButton(
                    onPressed: onPressed,
                    child: annotate(const Text('Renew')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimpleHostList extends ConsumerWidget {
  const _SimpleHostList({required this.hostsAsync, required this.limit});

  final AsyncValue<List<NpmSimpleHost>> hostsAsync;

  /// How many rows to draw, or null for all of them — [_CertificateList.limit]
  /// carries the reasoning.
  final int? limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return hostsAsync.when(
      data: (hosts) {
        if (hosts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('Nothing else configured.'),
          );
        }
        final shown = limit == null ? hosts : hosts.take(limit!);
        return Column(
          children: shown
              .map((host) => _SimpleHostTile(host: host))
              .toList(growable: false),
        );
      },
      loading: () => const ListRowsShimmer(count: 3),
      error: (error, _) => InlineErrorRetry(
        message: sectionFailureMessage(
          ServiceKey.nginxProxyManager,
          error,
          consequence: 'the other hosts are not shown',
        ),
        error: error,
        service: ServiceKey.nginxProxyManager,
        onRetry: () => ref.invalidate(npmOtherHostsProvider),
      ),
    );
  }
}

class _SimpleHostTile extends StatelessWidget {
  const _SimpleHostTile({required this.host});

  final NpmSimpleHost host;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Row(
            children: [
              Icon(
                host.hasConfigError
                    ? Icons.error_outline_rounded
                    : Icons.subdirectory_arrow_right_rounded,
                size: 18,
                color: host.hasConfigError
                    ? statusToneColor(colorScheme, StatusTone.warning)
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  host.label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.weight(FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  host.detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
