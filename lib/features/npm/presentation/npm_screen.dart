import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/npm/data/npm_upstream_probe.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_access.dart';
import 'package:cupola/features/npm/presentation/npm_actions.dart';
import 'package:cupola/features/npm/presentation/npm_advanced_config_screen.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/npm/presentation/npm_write_gate.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Nginx Proxy Manager dashboard: what the box is fronting, what is broken, and
/// which certificates are about to lapse.
class NpmScreen extends ConsumerWidget {
  const NpmScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(
      ServiceKey.nginxProxyManager,
    );

    return AmbientScaffold(
      accent: AppColors.nginxProxyManager,
      appBar: showAppBar
          ? const GlassAppBar(title: Text('Nginx Proxy Manager'))
          : null,
      body: SafeArea(
        child: isConfigured
            ? _NpmDashboard(topPadding: topPadding)
            : NotConfiguredPlaceholder.forService(ServiceKey.nginxProxyManager),
      ),
    );
  }
}

final _invalidateAfterAction = <ProviderOrFamily>[
  npmProxyHostsProvider,
  npmCertificatesProvider,
];

void _invalidateAll(WidgetRef ref) {
  ref.invalidate(npmProxyHostsProvider);
  // The upstream probe rides the host list rather than being invalidated here:
  // it awaits `npmProxyHostsProvider.future`, so one refresh re-reads and
  // re-probes. The account probe does not, and a permission changed on the
  // server is exactly the kind of thing a person pulls to refresh for.
  ref.invalidate(npmAccountProvider);
  ref.invalidate(npmCertificatesProvider);
  ref.invalidate(npmOtherHostsProvider);
  ref.invalidate(npmServerInfoProvider);
  ref.invalidate(serviceKpiProvider(ServiceKey.nginxProxyManager));
  ref.invalidate(serviceSummaryProvider(ServiceKey.nginxProxyManager));
}

/// `23 · reachability checked for 8 of 23`, and nothing before either answers.
String? _proxyHostSubtitle(
  List<NpmProxyHost>? hosts,
  NpmUpstreamReport? report,
) {
  if (hosts == null) return null;
  return ['${hosts.length}', ?report?.coverage].join(' · ');
}

class _NpmDashboard extends ConsumerWidget {
  const _NpmDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostsAsync = ref.watch(npmProxyHostsProvider);
    final certsAsync = ref.watch(npmCertificatesProvider);
    final otherAsync = ref.watch(npmOtherHostsProvider);
    final summaryAsync = ref.watch(
      serviceSummaryProvider(ServiceKey.nginxProxyManager),
    );
    final isOffline = summaryAsync.maybeWhen(
      data: (summary) => !summary.isOnline,
      orElse: () => false,
    );

    if (isOffline) {
      return ServiceOfflineState(
        serviceName: ServiceKey.nginxProxyManager.title,
        accent: AppColors.nginxProxyManager,
        onRetry: () => _invalidateAll(ref),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _invalidateAll(ref);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(ServiceKey.nginxProxyManager)),
            accent: AppColors.nginxProxyManager,
          ),
          const _DefaultAdminWarning(),
          const NpmAccessBand(),
          const SizedBox(height: AppSpacing.sm),
          SectionHeader(
            title: 'Proxy hosts',
            showChevron: false,
            // "23 · reachability checked for 8 of 23" — the coverage is drawn
            // because the Upstream column is partial by design. Without it a
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
          const SectionHeader(title: 'Certificates', showChevron: false),
          const SizedBox(height: 2),
          _CertificateList(certsAsync: certsAsync),
          const SizedBox(height: AppSpacing.sm),
          const SectionHeader(
            title: 'Redirections, 404s and streams',
            showChevron: false,
          ),
          const SizedBox(height: 2),
          _SimpleHostList(hostsAsync: otherAsync),
        ],
      ),
    );
  }
}

/// Warns when the install is old enough to still ship NPM's hard-coded default
/// administrator.
///
/// Not scaremongering: `admin@example.com` / `changeme` existed as a real
/// working login up to 2.12, and on this service that account can rewrite every
/// route on the box. If the user has one of those versions, saying so is worth
/// more than anything else on this screen.
class _DefaultAdminWarning extends ConsumerWidget {
  const _DefaultAdminWarning();

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
        message: 'Failed to load proxy hosts',
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
            'Online',
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
    final access = ref.watch(npmWriteAccessProvider);
    final mayWrite = access.canManage(NpmResource.proxyHosts);
    final colorScheme = Theme.of(context).colorScheme;
    // Dimmed, never removed. Taking the item out would take the *fact* out with
    // it: the user would be left wondering where Disable went rather than
    // learning that this account cannot use it.
    final itemStyle = mayWrite
        ? null
        : TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6));

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 18),
      tooltip: 'Host actions',
      onSelected: (value) {
        switch (value) {
          case 'enable':
            // Switching a host back **on** is the recoverable direction: it can
            // only restore service, and nginx refusing the config is reported
            // rather than hidden. No typed confirmation for that.
            if (!npmWriteAllowed(context, ref, NpmResource.proxyHosts)) return;
            runNpmAction(
              context,
              ref,
              action: (c) => c.setProxyHostEnabled(host.id, true),
              successMessage: '${host.primaryDomain} enabled',
              failureMessage: 'Failed to enable ${host.primaryDomain}',
              invalidate: _invalidateAfterAction,
            );
          case 'disable':
            if (!npmWriteAllowed(context, ref, NpmResource.proxyHosts)) return;
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
          PopupMenuItem(
            value: 'disable',
            // Semantics, not `enabled: false`: a disabled item drops off the
            // screen reader's path, taking the explanation with it.
            child: Semantics(
              hint: mayWrite ? null : access.hint,
              child: Text('Disable…', style: itemStyle),
            ),
          )
        else
          PopupMenuItem(
            value: 'enable',
            child: Semantics(
              hint: mayWrite ? null : access.hint,
              child: Text('Enable', style: itemStyle),
            ),
          ),
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
    title: 'Take ${host.primaryDomain} offline?',
    message:
        'Disabling this proxy host stops Nginx Proxy Manager serving that '
        'hostname. Anyone using it — not just this device — gets a connection '
        'error immediately, and nothing on the server warns them.',
    phrase: host.primaryDomain,
    confirmLabel: 'Disable',
  );
  if (!confirmed || !context.mounted) return;

  await runNpmAction(
    context,
    ref,
    action: (c) => c.setProxyHostEnabled(host.id, false),
    successMessage: '${host.primaryDomain} is now offline',
    failureMessage: 'Failed to disable ${host.primaryDomain}',
    invalidate: _invalidateAfterAction,
  );
}

class _CertificateList extends ConsumerWidget {
  const _CertificateList({required this.certsAsync});

  final AsyncValue<List<NpmCertificate>> certsAsync;

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
        return Column(
          children: ordered
              .take(8)
              .map((cert) => _CertificateTile(cert: cert, now: now))
              .toList(growable: false),
        );
      },
      loading: () => const ListRowsShimmer(count: 3),
      error: (error, _) => InlineErrorRetry(
        message: 'Failed to load certificates',
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
    final expired = days != null && days < 0;
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
        'Expired ${-days} days ago'
      else
        'Expires in $days days',
      if (cert.renewalNotCompleting(now))
        'renewal has not run — Let\'s Encrypt renews from 30 days out',
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
                NpmWriteButton(
                  resource: NpmResource.certificates,
                  label: 'Renew',
                  onPressed: () => runNpmAction(
                    context,
                    ref,
                    action: (c) => c.renewCertificate(cert.id),
                    successMessage: 'Renewal requested',
                    failureMessage: 'Failed to request renewal',
                    invalidate: _invalidateAfterAction,
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
  const _SimpleHostList({required this.hostsAsync});

  final AsyncValue<List<NpmSimpleHost>> hostsAsync;

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
        return Column(
          children: hosts
              .take(10)
              .map((host) => _SimpleHostTile(host: host))
              .toList(growable: false),
        );
      },
      loading: () => const ListRowsShimmer(count: 3),
      error: (error, _) => InlineErrorRetry(
        message: 'Failed to load the other hosts',
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
