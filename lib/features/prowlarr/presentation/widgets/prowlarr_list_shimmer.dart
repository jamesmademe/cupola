import 'package:flutter/material.dart';

import 'package:cupola/core/widgets/list_rows_shimmer.dart';

/// Loading placeholder for Prowlarr list sections.
///
/// A thin wrapper over [ListRowsShimmer.pulsing] that keeps Prowlarr's own row
/// height and the outer [verticalPadding] its sheets and settings lists rely on.
///
/// [count] controls how many shimmer rows are rendered (the dashboard shows a
/// short preview, the library a fuller list).
class ProwlarrListShimmer extends StatelessWidget {
  const ProwlarrListShimmer({
    super.key,
    this.count = 3,
    this.verticalPadding = 0,
  });

  /// Row height Prowlarr's list tiles collapse to while loading.
  static const double _rowHeight = 56;

  final int count;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: ListRowsShimmer(count: count, rowHeight: _rowHeight),
    );
  }
}
