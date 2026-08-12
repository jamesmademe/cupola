import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';

/// Skeleton rows shown while a dashboard list section loads.
///
/// One shape, deliberately. Eleven sections used to render static tinted blocks
/// while four pulsed, which is a difference the user reads as meaning: a
/// motionless grey slab is what this app draws for an *empty* well, so a
/// stalled-looking dashboard was indistinguishable from one that had finished
/// loading and found nothing. The sweep is the only part that says "still
/// coming", and it is also the accessible choice — [ShimmerPlaceholder] drops to
/// a flat fill under `MediaQuery.disableAnimationsOf`, so Reduce Motion gets the
/// calm version by asking for it rather than by accident of which screen it
/// landed on.
class ListRowsShimmer extends StatelessWidget {
  const ListRowsShimmer({super.key, this.count = 4, this.rowHeight = 60});

  /// How many rows to render.
  final int count;

  /// Height of one row. Sections with denser rows pass their own.
  final double rowHeight;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    child: Column(
      children: List.generate(
        count,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ShimmerPlaceholder(height: rowHeight),
        ),
      ),
    ),
  );
}
