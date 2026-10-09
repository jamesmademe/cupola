/// Stack health: every configured service's mark with its light, on one slab.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/home/data/stack_lights.dart';
import 'package:cupola/features/home/domain/stack_lights.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';

/// Stack health, off until the person switches it on: the header already
/// says how many services answer, and this is for the people who want the
/// lights on Home. Switched on, it never steps aside.
///
/// The marks are one target, to Stack. Under them, a service that did not
/// answer, in red with Retry; otherwise the services with a fault, in amber;
/// before anything has answered, that each one is being asked.
class HomeStackHealthModule extends ConsumerWidget {
  const HomeStackHealthModule({super.key});

  static const _title = 'Stack';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lights = ref.watch(stackLightsProvider);
    if (lights.rows.isEmpty) return const SizedBox.shrink();
    final silent = lights.silent;
    final faultLine = lights.faultLine;
    final Widget? under;
    if (silent.isNotEmpty) {
      // When the probe that found them silent settled: the header's.
      final checkedAt = ref.watch(
        stackHealthProvider.select((health) => health.checkedAt),
      );
      under = FaultBand.section(
        message: servicesDidNotAnswer([
          for (final service in silent) service.title,
        ], at: checkedAt),
        onRetry: () => retryDashboardServices(ref, silent),
      );
    } else if (faultLine != null) {
      under = _Line(
        icon: Icons.warning_amber_rounded,
        text: faultLine,
        tone: StatusTone.warning,
      );
    } else if (lights.checking) {
      under = const _Line(
        icon: Icons.hourglass_top_rounded,
        text: 'Asking each service',
      );
    } else {
      under = null;
    }

    return HomeModuleFrame(
      title: _title,
      subtitle: lights.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            button: true,
            label: lights.spoken,
            hint: 'opens Stack',
            excludeSemantics: true,
            onTap: () => context.go(ServiceRoutes.stack),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.go(ServiceRoutes.stack),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final row in lights.rows)
                    StackLightMark(
                      key: ValueKey(row.service),
                      icon: row.service.icon,
                      light: row.light,
                    ),
                ],
              ),
            ),
          ),
          if (under != null) ...[const SizedBox(height: AppSpacing.sm), under],
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// One service: its mark in a quiet tile, and its light at the corner.
class StackLightMark extends StatelessWidget {
  const StackLightMark({super.key, required this.icon, required this.light});

  /// The service's mark, from `ServiceKey.icon`.
  final IconData icon;

  final StackLight light;

  /// The tile's side.
  static const size = 44.0;

  static const _lightSize = 9.0;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tone = switch (light) {
      StackLight.checking => null,
      StackLight.answering => StatusTone.success,
      StackLight.fault => StatusTone.warning,
      StackLight.silent => StatusTone.error,
    };
    final lit = tone == null
        ? Colors.transparent
        : statusToneColor(scheme, tone, surface: room.slab);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: room.fillStrong,
                borderRadius: AppRadius.borderRadiusMd,
                border: Border.all(color: room.hair),
              ),
              child: Icon(icon, size: 20, color: room.ink),
            ),
          ),
          Positioned(
            top: -2,
            right: -2,
            // A light that switches on, never one that blinks: the colour
            // eases in once, when its service first answers.
            child: AnimatedContainer(
              duration: AppAnimation.standard,
              curve: AppAnimation.standardCurve,
              width: _lightSize,
              height: _lightSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: lit,
                border: Border.all(
                  color: tone == null ? room.inkTertiary : room.slab,
                  width: tone == null ? 1.5 : 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The line under the marks: its glyph and its words, in [tone] when it has
/// one.
class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.tone});

  final IconData icon;
  final String text;
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = switch (tone) {
      final tone? => statusToneColor(scheme, tone, surface: room.slab),
      null => room.inkSecondary,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(text, style: AppType.meta.copyWith(color: color)),
        ),
      ],
    );
  }
}
