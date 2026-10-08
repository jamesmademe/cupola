import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/domain/set_up_next.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/shell/domain/settings_return.dart';

/// Set up next: the services that would add the most to this Home, at its
/// foot, then the whole list. Absent when nothing it knows of is missing.
class SetUpNextModule extends ConsumerWidget {
  const SetUpNextModule({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final suggestions = setUpNextOf(settings.hasServiceConnection);
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return HomeModuleFrame(
      title: HomeModule.setUpNext.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, suggestion)
              in suggestions.take(setUpNextLimit).indexed)
            _SetUpRow(
              title: suggestion.title,
              line: suggestion.line,
              divided: index > 0,
              onTap: () => openSettings(
                context,
                ref,
                to: switch (suggestion.service) {
                  final service? => ServiceRoutes.setUp(service),
                  null => ServiceRoutes.settingsConnections,
                },
              ),
            ),
          _SetUpRow(
            title: 'All services',
            divided: true,
            onTap: () => openSettings(
              context,
              ref,
              to: ServiceRoutes.settingsConnections,
            ),
          ),
        ],
      ),
    );
  }
}

class _SetUpRow extends StatelessWidget {
  const _SetUpRow({
    required this.title,
    required this.onTap,
    this.line,
    this.divided = false,
  });

  final String title;
  final String? line;
  final bool divided;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: room.hair)) : null,
      ),
      child: PressableScale(
        onTap: onTap,
        semanticLabel: title,
        semanticValue: line,
        excludeChildSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title, style: AppType.row.copyWith(color: room.ink)),
                      if (line case final line?)
                        Text(
                          line,
                          style: AppType.meta.copyWith(
                            color: room.inkSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: room.inkSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The last thing on the operator's Home: the way to arrange it.
class EditHomeRow extends StatelessWidget {
  const EditHomeRow({super.key});

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.scaleXl,
        AppSpacing.gutter,
        0,
      ),
      child: PressableScale(
        onTap: () => context.push(ServiceRoutes.homeEdit),
        semanticLabel: 'Edit Home',
        semanticValue: 'Reorder and hide modules',
        excludeChildSemantics: true,
        child: CustomPaint(
          foregroundPainter: _DashedEdge(color: room.edge),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.gutter,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 19, color: room.inkSecondary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Edit Home',
                          style: AppType.row.copyWith(color: room.ink),
                        ),
                        Text(
                          'Reorder and hide modules',
                          style: AppType.meta.copyWith(
                            color: room.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: room.inkSecondary,
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

/// The dashed edge around Edit Home: a way out of the page's
/// content, not a module of it.
class _DashedEdge extends CustomPainter {
  const _DashedEdge({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          const Radius.circular(AppRadius.button),
        ),
      );
    const dash = 4.0;
    const gap = 3.0;
    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedEdge oldDelegate) => oldDelegate.color != color;
}
