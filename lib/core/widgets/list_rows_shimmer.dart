import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';

/// Skeleton rows shown while a dashboard list section loads.
///
/// Two shapes, because the dashboards genuinely ship both: the default renders
/// static tinted blocks, while [ListRowsShimmer.pulsing] renders animated
/// [ShimmerPlaceholder] rows. Unifying the two is a visible UI change, so it is
/// deliberately not done here.
class ListRowsShimmer extends StatelessWidget {
  /// Static tinted blocks, [count] of them.
  const ListRowsShimmer({super.key, this.count = 4}) : _pulseRowHeight = null;

  /// Animated [ShimmerPlaceholder] rows of [rowHeight], [count] of them.
  const ListRowsShimmer.pulsing({
    super.key,
    this.count = 4,
    double rowHeight = 60,
  }) : _pulseRowHeight = rowHeight;

  /// Height of one static block row.
  static const double _blockHeight = 56;

  /// How many rows to render.
  final int count;

  /// `null` for the static default; the row height for the pulsing variant.
  final double? _pulseRowHeight;

  @override
  Widget build(BuildContext context) {
    final pulseRowHeight = _pulseRowHeight;
    if (pulseRowHeight != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          children: List.generate(
            count,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ShimmerPlaceholder(height: pulseRowHeight),
            ),
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: List.generate(
        count,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          child: Container(
            height: _blockHeight,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: AppRadius.borderRadiusMd,
            ),
          ),
        ),
      ),
    );
  }
}
