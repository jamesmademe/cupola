import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/service_kpi_peek.dart';
import 'package:cupola/core/widgets/staggered_entrance.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/presentation/truenas_console_shell.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_version_banner.dart';

/// A TrueNAS management section reachable from the hub grid.
/// TrueNAS root: a grid of management sections, each drilling into its own
/// screen. Replaces the former single-dashboard layout.
class TrueNasHubScreen extends ConsumerWidget {
  final bool showAppBar;
  final double topPadding;

  const TrueNasHubScreen({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(
      currentSettingsProvider.select(
        (s) => s.isServiceConfigured(ServiceKey.truenas),
      ),
    );

    return AmbientScaffold(
      accent: ServiceKey.truenas.accent,
      appBar: showAppBar ? const GlassAppBar(title: Text('TrueNAS')) : null,
      body: TrueNasConsoleShell(
        child: configured
            ? _HubGrid(topPadding: topPadding)
            : _NotConfigured(topPadding: topPadding),
      ),
    );
  }
}

class _HubGrid extends ConsumerWidget {
  final double topPadding;
  const _HubGrid({required this.topPadding});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );
    final top =
        topPadding +
        (topPadding > 0 ? MediaQuery.paddingOf(context).top : 0) +
        AppSpacing.sm;

    return ListView(
      padding: EdgeInsets.only(top: top),
      children: [
        ServiceKpiPeek(
          kpis: ref.watch(serviceKpiProvider(ServiceKey.truenas)),
          accent: AppColors.truenas,
        ),
        const TrueNasVersionBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            // Grows the cells taller with the reading size; a fixed ratio
            // clipped the tile labels at accessibility text sizes.
            childAspectRatio: TextScaleMetrics.aspectRatio(context, base: 1.35),
            children: [
              for (var i = 0; i < trueNasSections.length; i++)
                StaggeredEntrance(
                  index: i,
                  child: _SectionTile(section: trueNasSections[i]),
                ),
            ],
          ),
        ),
        SizedBox(height: bottomPadding + AppSpacing.lg),
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  final TrueNasSection section;
  const _SectionTile({required this.section});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serviceTheme = serviceThemeFor(ServiceKey.truenas);

    return PressableScale(
      onTap: () => context.push(section.route),
      child: AppCard.surfaceOutlined(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: serviceTheme.softContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    section.icon,
                    size: 20,
                    color: serviceTheme.accent,
                  ),
                ),
                const Spacer(),
                if (section.experimental)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'BETA',
                      style: theme.textTheme.labelSmall!
                          .weight(FontWeight.w700)
                          .copyWith(color: AppColors.warning),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              section.title,
              style: theme.textTheme.titleSmall!.weight(FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              section.subtitle,
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

class _NotConfigured extends StatelessWidget {
  final double topPadding;
  const _NotConfigured({required this.topPadding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top:
            topPadding +
            (topPadding > 0 ? MediaQuery.paddingOf(context).top : 0),
      ),
      child: AppEmptyState(
        icon: Icons.storage_rounded,
        title: 'TrueNAS is not set up',
        message: 'Add your TrueNAS URL and API key to see system status.',
        accentColor: AppColors.truenas,
        action: FilledButton.icon(
          onPressed: () =>
              context.go('/settings/service/${ServiceKey.truenas.routeParam}'),
          icon: const Icon(Icons.settings_outlined, size: 18),
          label: const Text('Set up TrueNAS'),
        ),
      ),
    );
  }
}
