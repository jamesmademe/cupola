import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/domain_section.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/service_connection_row.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';
import 'package:cupola/features/settings/presentation/widgets/test_all_connections_button.dart';

/// Every service Cupola can talk to, and the state of each connection.
///
/// This is the one place a service's setup lives. The settings home used to
/// list configured services with their status while a second screen listed all
/// thirteen with a delete button and no status — two doors to the same room,
/// neither of them complete.
class SettingsConnectionsScreen extends ConsumerWidget {
  const SettingsConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // A Seerr account that signed out is among the connections, not among
    // the services to set up.
    final configured = ServiceKey.values
        .where(settings.hasServiceConnection)
        .toList(growable: false);
    final available = ServiceKey.values
        .where((service) => !settings.hasServiceConnection(service))
        .toList(growable: false);

    return AmbientScaffold(
      // No accent: a settings pane has no artwork, so its room is lit by the
      // neutral lamp, the fallback of `AmbientBackground`.
      appBar: const GlassAppBar(title: Text('Connections')),
      body: SettingsMasterDetail(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            // The nav bar floats over this content and grows with the reading
            // size, so the last row is only reachable if the list reserves for it.
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            if (configured.isNotEmpty) ...[
              SectionHeader.action(
                // Not "Answering": this section is what has an address saved,
                // and one of them being unreachable is exactly why you are here.
                title: 'Your services',
                // The count and the command share the trailing slot: the chip
                // says how much "all" is, and the button is the only way to
                // re-ask without opening seventeen forms. `.action` is what
                // keeps the button reachable — the plain header silences its
                // own subtree, which would have left a nested control unnamed.
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CountChip(count: configured.length),
                    const SizedBox(width: AppSpacing.sm),
                    const TestAllConnectionsButton(),
                  ],
                ),
                semanticLabel:
                    '${configured.length} of ${ServiceKey.values.length} '
                    'services set up',
              ),
              for (final domain in ServiceDomain.values)
                ..._domainGroup(context, domain, configured),
              const SizedBox(height: AppSpacing.xl),
            ],
            SectionHeader(
              title: available.isEmpty
                  ? 'Everything is set up'
                  : 'Add a service',
              showChevron: false,
              subtitle: available.isEmpty
                  ? 'All ${ServiceKey.values.length} services Cupola supports '
                        'have an address saved.'
                  : 'Cupola talks straight to your instance. Nothing is stored '
                        'anywhere but this device.',
            ),
            if (available.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              SettingsGroupCard(
                children: [
                  for (final service in available)
                    ServiceConnectionRow(
                      service: service,
                      onTap: () => _open(context, service),
                    ),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Icon(
                  Icons.check_circle_outline_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            // Omitted rather than shown empty: trust is per origin, so an
            // origin can outlive every service that once used it — but with
            // nothing ever trusted there is nothing this row could find.
            if (settings.trustedCertificates.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              SettingsGroupCard(
                children: [
                  SettingsCard.grouped(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: 'Trusted certificates',
                    subtitle: settings.trustedCertificates.length == 1
                        ? '1 self-signed certificate trusted'
                        : '${settings.trustedCertificates.length} self-signed '
                              'certificates trusted',
                    onTap: () => context.push('/settings/certificates'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _domainGroup(
    BuildContext context,
    ServiceDomain domain,
    List<ServiceKey> configured,
  ) {
    final services = configured
        .where((service) => service.domain == domain)
        .toList(growable: false);
    if (services.isEmpty) return const [];

    return [
      DomainSectionHeader(
        label: domain.label,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
      ),
      SettingsGroupCard(
        children: [
          for (final service in services)
            ServiceConnectionRow(
              service: service,
              onTap: () => _open(context, service),
            ),
        ],
      ),
    ];
  }

  void _open(BuildContext context, ServiceKey service) {
    context.push('/settings/service/${service.routeParam}');
  }
}

/// The number of connected services, sized as a label rather than a figure —
/// it qualifies the heading, it is not a readout in its own right.
class _CountChip extends StatelessWidget {
  const _CountChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Text(
        '$count of ${ServiceKey.values.length}',
        style: AppTheme.chrome(context, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
