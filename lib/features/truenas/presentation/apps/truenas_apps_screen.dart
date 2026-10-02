import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/domain/models/app.dart';
import 'package:cupola/features/truenas/presentation/apps/truenas_app_actions.dart';
import 'package:cupola/features/truenas/presentation/apps/truenas_apps_providers.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_async_body.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_section_scaffold.dart';
import 'package:cupola/features/truenas/presentation/truenas_console_shell.dart';
import 'package:cupola/features/truenas/presentation/truenas_capability.dart';
import 'package:cupola/features/truenas/domain/truenas_capability.dart';

class TrueNasAppsScreen extends ConsumerWidget {
  const TrueNasAppsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(truenasAppsProvider);
    final appList = apps.value ?? const <TrueNasApp>[];
    final upgradableCount = appList.where((a) => a.upgradeAvailable).length;

    return TrueNasSectionScaffold(
      title: 'Apps',
      capabilityAreas: {TrueNasCapabilityArea.apps.key},
      actions: [
        if (upgradableCount > 0)
          trueNasGatedIcon(
            ref: ref,
            area: TrueNasCapabilityArea.apps.key,
            verbPhrase: 'update apps',
            tooltip: 'Update all ($upgradableCount)',
            icon: Badge(
              label: Text('$upgradableCount'),
              child: const Icon(Icons.system_update_alt_rounded),
            ),
            onTap: () => updateAllApps(context, ref, apps: appList),
          ),
      ],
      body: TrueNasConsoleShell(
        child: TrueNasAsyncBody<List<TrueNasApp>>(
          value: apps,
          onRetry: () => ref.invalidate(truenasAppsProvider),
          data: (list) => list.isEmpty
              ? const AppEmptyState(
                  icon: Icons.apps_rounded,
                  title: 'No apps installed',
                  message: 'Install apps from the TrueNAS catalog.',
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    FloatingNavBarMetrics.getScrollViewBottomPadding(context),
                  ),
                  children: [
                    for (final app in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _AppCard(app: app),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _AppCard extends ConsumerWidget {
  final TrueNasApp app;
  const _AppCard({required this.app});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PressableScale(
      onTap: () => context.push(ServiceRoutes.truenasApp(app.name)),
      child: AppCard.surfaceOutlined(
        child: Row(
          children: [
            AppIcon(iconUrl: app.iconUrl),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          app.title,
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall!.weight(FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (app.upgradeAvailable) ...[
                        const SizedBox(width: 6),
                        const _UpgradeBadge(),
                      ],
                    ],
                  ),
                  AppStateLabel(state: app.state, version: app.humanVersion),
                ],
              ),
            ),
            AppLifecycleControl(app: app),
          ],
        ),
      ),
    );
  }
}

class AppIcon extends StatelessWidget {
  final String? iconUrl;
  const AppIcon({super.key, this.iconUrl, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ServiceKey.truenas.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.apps_rounded,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
    final url = iconUrl;
    if (url == null || url.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedNetworkImage(
        imageUrl: url,
        cacheManager: pinnedImageCacheFor(url),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => placeholder,
        placeholder: (_, _) => placeholder,
      ),
    );
  }
}

class AppStateLabel extends StatelessWidget {
  final String state;
  final String? version;
  const AppStateLabel({super.key, required this.state, this.version});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upper = state.toUpperCase();
    // CRASHED is amber, not red: the app fell over and TrueNAS told us so,
    // which is a fault. Red is the host that told us nothing. Everything else —
    // STOPPED, DEPLOYING — is neutral, because an app nobody started is not a
    // problem to be fixed.
    final color = statusToneColor(theme.colorScheme, switch (upper) {
      'RUNNING' => StatusTone.success,
      'CRASHED' => StatusTone.warning,
      _ => StatusTone.neutral,
    });
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          version != null ? '$upper · $version' : upper,
          style: theme.textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _UpgradeBadge extends StatelessWidget {
  const _UpgradeBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: statusToneColor(
          colorScheme,
          StatusTone.info,
        ).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(DesignTokens.radiusXs2),
      ),
      child: Text(
        'Update',
        style: Theme.of(context).textTheme.labelSmall!
            .weight(FontWeight.w600)
            // The ink walks against the tint it sits on, not against the page.
            .copyWith(
              color: statusToneColor(
                colorScheme,
                StatusTone.info,
                surface: colorScheme.surface,
              ),
            ),
      ),
    );
  }
}

/// Start/stop + overflow (upgrade/delete) control shared with the detail view.
class AppLifecycleControl extends ConsumerWidget {
  final TrueNasApp app;
  const AppLifecycleControl({super.key, required this.app});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        trueNasGatedIcon(
          ref: ref,
          area: TrueNasCapabilityArea.apps.key,
          verbPhrase: 'start or stop apps',
          icon: Icon(
            app.isRunning
                ? Icons.stop_circle_outlined
                : Icons.play_circle_outline_rounded,
            color: app.isRunning
                ? null
                : statusToneColor(
                    Theme.of(context).colorScheme,
                    StatusTone.success,
                  ),
          ),
          tooltip: app.isRunning ? 'Stop' : 'Start',
          onTap: () => appLifecycleAction(
            context,
            ref,
            app: app,
            action: app.isRunning ? AppAction.stop : AppAction.start,
          ),
        ),
        PopupMenuButton<AppAction>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (action) {
            if (!trueNasWriteAllowed(
              context,
              ref,
              area: TrueNasCapabilityArea.apps.key,
              verbPhrase: action == AppAction.delete
                  ? 'delete apps'
                  : 'upgrade apps',
            )) {
              return;
            }
            appLifecycleAction(context, ref, app: app, action: action);
          },
          // Never `enabled: false`: a disabled item drops off the screen
          // reader's path, taking the explanation with it.
          itemBuilder: (context) => [
            if (app.upgradeAvailable)
              PopupMenuItem(
                value: AppAction.upgrade,
                child: trueNasGatedMenuLabel(
                  ref: ref,
                  area: TrueNasCapabilityArea.apps.key,
                  text: 'Upgrade',
                ),
              ),
            PopupMenuItem(
              value: AppAction.delete,
              child: trueNasGatedMenuLabel(
                ref: ref,
                area: TrueNasCapabilityArea.apps.key,
                text: 'Delete app',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
