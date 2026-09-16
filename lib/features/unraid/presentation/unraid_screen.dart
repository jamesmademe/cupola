import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

/// Unraid dashboard: array status, disks and Docker containers.
///
/// **Read-only, and that is a data-layer fact rather than a product choice.**
/// Decision 14 draws the guarded write set — Stop and Restart a container, Stop
/// and Force stop a VM, each through one dialog naming the host — but the
/// Unraid GraphQL contract this app is written against
/// (`test/fixtures/unraid/schema.graphql`) declares no `Mutation` type at all,
/// and the release whose schema does is not the one the three read documents
/// here match. Guessing a mutation name would ship a confirm dialog that names
/// the user's server and then fails, which is worse than not offering it.
/// See the notes on `UnraidDockerContainer.condition` for the half that *is*
/// readable from what the API already returns.
class UnraidScreen extends ConsumerWidget {
  const UnraidScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.unraid);

    return AmbientScaffold(
      accent: AppColors.unraid,
      appBar: showAppBar ? const GlassAppBar(title: Text('Unraid')) : null,
      body: SafeArea(
        // The shared placeholder, not a private copy: four dashboards had each
        // grown their own "this service isn't set up" card, which is the state
        // `NotConfiguredPlaceholder` exists to unify.
        child: isConfigured
            ? _UnraidDashboard(topPadding: topPadding)
            : NotConfiguredPlaceholder.forService(ServiceKey.unraid),
      ),
    );
  }
}

class _UnraidDashboard extends ConsumerWidget {
  const _UnraidDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arrayAsync = ref.watch(unraidArrayProvider);
    final dockerAsync = ref.watch(unraidDockerProvider);
    final summaryAsync = ref.watch(serviceSummaryProvider(ServiceKey.unraid));
    final isOffline = summaryAsync.maybeWhen(
      data: (summary) => !summary.isOnline,
      orElse: () => false,
    );

    if (isOffline) {
      return ServiceOfflineState(
        serviceName: ServiceKey.unraid.title,
        accent: AppColors.unraid,
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
            kpis: ref.watch(serviceKpiProvider(ServiceKey.unraid)),
            accent: AppColors.unraid,
          ),
          const SizedBox(height: AppSpacing.sm),
          const SectionHeader(title: 'Array disks', showChevron: false),
          const SizedBox(height: 2),
          _DiskList(arrayAsync: arrayAsync),
          const SizedBox(height: AppSpacing.sm),
          SectionHeader(
            title: 'Docker',
            showChevron: false,
            // The board heads this section with "14 containers · 12 running ·
            // 1 stopped · 1 unhealthy". Only the arms the payload can answer
            // are printed, and none of them before the load resolves: a header
            // reading "0 running" while the request is still in flight states
            // the one thing we do not yet know.
            subtitle: dockerAsync.asData == null
                ? null
                : _dockerTally(dockerAsync.requireValue),
          ),
          const SizedBox(height: 2),
          _DockerList(dockerAsync: dockerAsync),
        ],
      ),
    );
  }
}

/// `14 containers · 12 running · 1 unhealthy` — only the arms that are non-zero.
///
/// A tally that printed every arm would read "0 unhealthy" on a healthy server,
/// which is a sentence about a problem where there is none.
String _dockerTally(List<UnraidDockerContainer> containers) {
  int count(UnraidContainerCondition condition) =>
      containers.where((c) => c.condition == condition).length;

  final running = count(UnraidContainerCondition.running);
  final unhealthy = count(UnraidContainerCondition.unhealthy);
  final stopped = count(UnraidContainerCondition.stopped);
  final crashed =
      count(UnraidContainerCondition.exitedUnexpectedly) +
      count(UnraidContainerCondition.restarting) +
      count(UnraidContainerCondition.dead);

  return [
    '${containers.length} containers',
    if (running > 0) '$running running',
    if (stopped > 0) '$stopped stopped',
    if (unhealthy > 0) '$unhealthy unhealthy',
    if (crashed > 0) '$crashed failed',
  ].join(' · ');
}

void _invalidateAll(WidgetRef ref) {
  ref.invalidate(unraidArrayProvider);
  ref.invalidate(unraidDockerProvider);
  ref.invalidate(serviceKpiProvider(ServiceKey.unraid));
  ref.invalidate(serviceSummaryProvider(ServiceKey.unraid));
}

class _DiskList extends ConsumerWidget {
  const _DiskList({required this.arrayAsync});

  final AsyncValue<UnraidArray> arrayAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return arrayAsync.when(
      data: (array) {
        if (array.disks.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('No array disks reported.'),
          );
        }
        return Column(
          children: array.disks.map((disk) => _DiskTile(disk: disk)).toList(),
        );
      },
      loading: () => const ListRowsShimmer(),
      error: (error, _) => InlineErrorRetry(
        message: 'Failed to load the array',
        onRetry: () => ref.invalidate(unraidArrayProvider),
      ),
    );
  }
}

class _DiskTile extends StatelessWidget {
  const _DiskTile({required this.disk});

  final UnraidDisk disk;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // A slot with no temperature is spun down, not cold. It used to render as
    // no reading at all, which left the row silent about the one thing that
    // explains a missing figure.
    final tempLabel = disk.spunDown ? 'spun down' : '${disk.temp}°C';
    final tone = statusToneColor(
      colorScheme,
      disk.tone,
      // The reading sits on the row's own card, not on the page background;
      // walking against the wrong ground is how amber ends up under 3:1 on the
      // light theme.
      surface: colorScheme.surface,
    );
    // The plate is a 12% accent wash, so its glyph is ink on that composite
    // rather than on the surface — seven of the seventeen accents lose the
    // contrast check otherwise, and Unraid's orange is one of them.
    final plateInk = ServiceTheme.onTint(
      AppColors.unraid,
      surface: colorScheme.surface,
      tintAlpha: 0.12,
    );

    return Semantics(
      container: true,
      // Three fragments — a device name, a `DISK_OK` token and a bare numeral —
      // read as three unrelated stops. One sentence, in the order a person
      // would say it, with the unit spoken rather than glyphed.
      label: [
        disk.name,
        if (disk.status.isNotEmpty) disk.status,
        disk.spunDown ? 'spun down' : '${disk.temp} degrees',
      ].join(', '),
      child: ExcludeSemantics(
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
                      color: AppColors.unraid.withValues(alpha: 0.12),
                      borderRadius: AppRadius.borderRadiusSm,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.storage_rounded,
                      size: 16,
                      color: plateInk,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          disk.name,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium!.weight(FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (disk.status.isNotEmpty)
                          Text(
                            disk.status,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: disk.tone == StatusTone.warning
                                      ? tone
                                      : colorScheme.onSurfaceVariant,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    tempLabel,
                    style: Theme.of(context).textTheme.labelMedium!
                        .weight(FontWeight.w700)
                        .tabular
                        .copyWith(
                          color: disk.warm
                              ? tone
                              : colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockerList extends ConsumerWidget {
  const _DockerList({required this.dockerAsync});

  final AsyncValue<List<UnraidDockerContainer>> dockerAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return dockerAsync.when(
      data: (containers) {
        if (containers.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('No containers reported.'),
          );
        }
        final sorted = [
          ...containers,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return Column(
          children: sorted
              .map((container) => _ContainerTile(container: container))
              .toList(),
        );
      },
      loading: () => const ListRowsShimmer(),
      error: (error, _) => InlineErrorRetry(
        message: 'Failed to load containers',
        onRetry: () => ref.invalidate(unraidDockerProvider),
      ),
    );
  }
}

class _ContainerTile extends StatelessWidget {
  const _ContainerTile({required this.container});

  final UnraidDockerContainer container;

  /// One glyph per condition, read off the condition rather than off the tone.
  ///
  /// A tone-keyed icon can only answer one picture for the four amber states,
  /// and "unhealthy while up" and "OOM-killed an hour ago" are not the same
  /// picture — the first is a warning about something running, the second is a
  /// thing that is down.
  IconData get _glyph => switch (container.condition) {
    UnraidContainerCondition.running => Icons.play_circle_rounded,
    UnraidContainerCondition.unhealthy => Icons.monitor_heart_rounded,
    UnraidContainerCondition.paused => Icons.pause_circle_rounded,
    UnraidContainerCondition.stopped => Icons.stop_circle_rounded,
    UnraidContainerCondition.exitedUnexpectedly ||
    UnraidContainerCondition.dead => Icons.error_outline_rounded,
    UnraidContainerCondition.restarting => Icons.sync_problem_rounded,
    UnraidContainerCondition.created => Icons.schedule_rounded,
    UnraidContainerCondition.unknown => Icons.help_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Decision 15 in one line: green for up and healthy, amber for a fault the
    // server told us about, neutral for a stop somebody chose. The tone comes
    // from the parsed condition — the row used to paint everything that was not
    // `running` in the dim foreground, so an OOM kill and a deliberate stop
    // were the same colour and the same words.
    final tone = statusToneColor(
      colorScheme,
      container.tone,
      surface: colorScheme.surface,
    );
    final neutral = container.tone == StatusTone.neutral;

    return Semantics(
      container: true,
      label: '${container.name}, ${container.summary}',
      child: ExcludeSemantics(
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
                    child: Icon(_glyph, size: 16, color: tone),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          container.name,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium!.weight(FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          container.summary,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                // A deliberate stop says so in the ordinary
                                // metadata voice; only a fault borrows the
                                // tone, so amber on this screen always means
                                // something to look at.
                                color: neutral
                                    ? colorScheme.onSurfaceVariant
                                    : tone,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
