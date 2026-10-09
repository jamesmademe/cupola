/// Storage: how full the pools are, and whether a disk needs the person.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/home/data/storage.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/domain/storage.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/settings_return.dart';

/// Storage, off until the person switches it on: every TrueNAS pool and
/// Unraid array, the share used in ink, its state, and each disk in trouble
/// in amber, its pool one tap away.
///
/// Switched on without TrueNAS or Unraid, it asks for TrueNAS in their
/// place. A server that did not answer keeps the module in its place.
class HomeStorageModule extends ConsumerWidget {
  const HomeStorageModule({super.key});

  static const _title = 'Storage';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final setUp = HomeModule.storage.services.any(settings.isServiceConfigured);
    if (!setUp) {
      return HomeModuleFrame.needsService(
        title: _title,
        service: ServiceKey.truenas,
        headline: 'Set up TrueNAS to see your storage',
        setUpLine: 'Pools, space and disk health',
        onSetUp: () => openSettings(
          context,
          ref,
          to: ServiceRoutes.setUp(ServiceKey.truenas),
        ),
      );
    }

    // The last answer stands while the next one is read.
    final read = ref.watch(homeStorageProvider);
    final storage = read.value;
    if (storage == null) {
      return const HomeModuleFrame.loading(title: _title);
    }
    final coverage = storage.coverage;
    if (storage.pools.isEmpty) {
      if (!coverage.everySourceFailed) return const SizedBox.shrink();
      return HomeModuleFrame.silent(
        title: _title,
        coverage: coverage,
        onRetry: () => ref.invalidate(homeStorageProvider),
      );
    }

    final shown = storage.pools.take(storagePoolLimit).toList(growable: false);
    final sources = {
      for (final pool in storage.pools) pool.service.title,
    }.join(' · ');
    final note = coverage.isPartial ? coverageFailureSentence(coverage) : null;
    return HomeModuleFrame(
      title: _title,
      subtitle: sources,
      semanticLabel: joinSpokenParts([_title, sources, ?note]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null) HomeCoverageNote(note: note, coverage: coverage),
          for (final (index, pool) in shown.indexed)
            StoragePoolRow(
              key: ValueKey('${pool.instanceId}/${pool.name}'),
              pool: pool,
              divided: index > 0,
              onTap: () => context.go(switch (pool.service) {
                ServiceKey.unraid => ServiceRoutes.unraidArray,
                _ => ServiceRoutes.truenasPool(pool.name),
              }),
            ),
          if (storage.pools.length > shown.length)
            HomeModuleLink(
              label: 'See all ${storage.pools.length}',
              onTap: () => context.go(ServiceRoutes.truenasStorage),
            ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

/// One pool: its name and share used, the bar in ink, the figures and its
/// state, then each disk in trouble. One target, to the pool.
class StoragePoolRow extends StatelessWidget {
  const StoragePoolRow({
    super.key,
    required this.pool,
    required this.onTap,
    this.divided = false,
  });

  final StoragePool pool;
  final VoidCallback onTap;

  /// Whether space separates it from the pool above.
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final percent = pool.percent;
    final capacity = pool.capacity;
    final stateTone = pool.healthy ? StatusTone.success : StatusTone.warning;
    final fraction = pool.usedFraction;
    return Semantics(
      container: true,
      button: true,
      label: joinSpokenParts([
        pool.name,
        if (percent != null) '$percent used',
        ?capacity,
        pool.stateLine,
        ...pool.disks,
      ]),
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderRadiusSm,
        child: Padding(
          padding: EdgeInsets.only(
            top: divided ? AppSpacing.md : AppSpacing.xs,
            bottom: AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pool.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.row.copyWith(color: room.ink),
                    ),
                  ),
                  if (percent != null)
                    Text(
                      percent,
                      style: AppType.row
                          .weight(FontWeight.w600)
                          .copyWith(color: room.ink),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: SizedBox(
                  height: 6,
                  child: LinearProgressIndicator(
                    value: fraction ?? 0,
                    color: room.ink,
                    backgroundColor: room.fillStrong,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 2,
                spacing: AppSpacing.sm,
                children: [
                  if (capacity != null)
                    Text(
                      capacity,
                      style: AppType.meta.copyWith(color: room.inkSecondary),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusToneColor(
                            scheme,
                            stateTone,
                            surface: room.slab,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          pool.stateLine,
                          style: AppType.meta.copyWith(
                            color: room.inkSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              for (final disk in pool.disks) ...[
                const SizedBox(height: AppSpacing.sm),
                _DiskChip(text: disk),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A disk in trouble: amber, on its own wash, with the way to its pool.
class _DiskChip extends StatelessWidget {
  const _DiskChip({required this.text});

  final String text;

  static const _wash = 0.14;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ink = statusToneColor(
      scheme,
      StatusTone.warning,
      surface: room.slab,
      tintAlpha: _wash,
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: statusToneFill(
          scheme,
          StatusTone.warning,
        ).withValues(alpha: _wash),
        borderRadius: AppRadius.borderRadiusMd,
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: ink),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppType.meta.weight(FontWeight.w600).copyWith(color: ink),
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: ink),
        ],
      ),
    );
  }
}
