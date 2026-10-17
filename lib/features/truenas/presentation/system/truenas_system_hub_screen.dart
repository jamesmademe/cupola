import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_diagnostics_screen.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_power_card.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_section_scaffold.dart';
import 'package:cupola/features/truenas/presentation/truenas_console_shell.dart';
import 'package:cupola/features/truenas/domain/truenas_capability.dart';

class _SystemEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final String section;
  const _SystemEntry(this.title, this.subtitle, this.icon, this.section);
}

const _entries = <_SystemEntry>[
  _SystemEntry('General', 'Timezone & language', Icons.tune_rounded, 'general'),
  _SystemEntry(
    'Advanced',
    'Console & syslog',
    Icons.developer_mode_rounded,
    'advanced',
  ),
  _SystemEntry('Services', 'Start & stop', Icons.bolt_rounded, 'services'),
  _SystemEntry('Network', 'Interfaces & DNS', Icons.lan_rounded, 'network'),
  _SystemEntry(
    'Credentials',
    'Users & groups',
    Icons.group_rounded,
    'credentials',
  ),
  _SystemEntry(
    'Certificates',
    'TLS certificates',
    Icons.verified_user_rounded,
    'certificates',
  ),
  _SystemEntry('Email', 'Alerts delivery', Icons.email_rounded, 'email'),
  _SystemEntry(
    'Update',
    'System updates',
    Icons.system_update_rounded,
    'update',
  ),
  _SystemEntry('NTP servers', 'Time sync', Icons.schedule_rounded, 'ntp'),
  _SystemEntry(
    'Alert settings',
    'Notification services',
    Icons.notifications_rounded,
    'alert-settings',
  ),
];

class TrueNasSystemHubScreen extends StatelessWidget {
  const TrueNasSystemHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TrueNasSectionScaffold(
      title: 'System',
      capabilityAreas: {TrueNasCapabilityArea.power.key},
      body: TrueNasConsoleShell(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              // Grows the cells taller with the reading size; a fixed ratio
              // clipped the tile labels at accessibility text sizes.
              childAspectRatio: TextScaleMetrics.aspectRatio(
                context,
                base: 1.4,
              ),
              children: [
                for (final entry in _entries) _SystemTile(entry: entry),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const TrueNasPowerCard(),
            // Entry point for inspecting raw JSON-RPC responses. Debug builds
            // only: the screen dumps server payloads verbatim with a copy button,
            // which must never ship to release even while today's probes are
            // limited to non-sensitive methods. It stays route-less on purpose
            // (decision 37): a `go_router` path would be reachable by deep link
            // in a release build, where `kDebugMode` no longer guards anything.
            if (kDebugMode) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TrueNasDiagnosticsScreen(),
                  ),
                ),
                icon: const Icon(Icons.bug_report_rounded, size: 18),
                label: const Text('Diagnostics\u00A0· debug builds only'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SystemTile extends StatelessWidget {
  final _SystemEntry entry;
  const _SystemTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serviceTheme = serviceThemeFor(ServiceKey.truenas);
    final compact = MediaQuery.sizeOf(context).width < 600;
    return PressableScale(
      onTap: () =>
          context.push(ServiceRoutes.truenasSystemSection(entry.section)),
      child: AppCard.surfaceOutlined(
        padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 32 : 38,
              height: compact ? 32 : 38,
              decoration: BoxDecoration(
                color: serviceTheme.softContainer,
                borderRadius: BorderRadius.circular(compact ? 10 : 11),
              ),
              child: Icon(
                entry.icon,
                size: compact ? 17 : 19,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              entry.title,
              style: theme.textTheme.titleSmall!.weight(FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              entry.subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
