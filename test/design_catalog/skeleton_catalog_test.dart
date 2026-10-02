@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/list_rows_shimmer.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';

import 'catalog.dart';

void main() {
  catalogCard(
    'Skeleton',
    scenes: [
      CatalogScene(
        'ShimmerPlaceholder bare shapes · .card (radius-md), .text (radius-xs, '
        '3 widths), .circle',
        (_) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerPlaceholder.card(width: 80, height: 120),
            const SizedBox(width: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ShimmerPlaceholder.text(width: 200, height: 22),
                const SizedBox(height: 12),
                ShimmerPlaceholder.text(width: 120),
                const SizedBox(height: 8),
                ShimmerPlaceholder.text(width: 160),
              ],
            ),
            const SizedBox(width: 24),
            const ShimmerPlaceholder.circle(size: 48),
          ],
        ),
      ),
      CatalogScene(
        'AppSkeleton.listRows() · 5 rows, 104pt tall (an activity tile\'s '
        'settled height), 8 apart, radius-md',
        (_) => AppSkeleton.listRows(),
      ),
      CatalogScene(
        'ListRowsShimmer() · dashboard section rows, 4 at 60pt, square '
        'corners',
        (_) => const ListRowsShimmer(),
      ),
      CatalogScene(
        'AppSkeleton.posterRow() · 6 posters, 168 tall at 2:3',
        (_) => AppSkeleton.posterRow(),
      ),
      CatalogScene(
        'AppSkeleton.posterGrid() · 3 columns, 2:3 cells, 12pt gaps',
        (_) => AppSkeleton.posterGrid(),
        width: 360,
        height: 560,
      ),
      CatalogScene(
        'AppSkeleton.detailBody() · backdrop band, poster + title lines, '
        'then two full-width lines and a short one',
        (_) => AppSkeleton.detailBody(),
        height: 520,
      ),
      CatalogScene(
        'Reduce Motion · the controller stops and each block paints the flat '
        'base colour, no gradient',
        (_) => Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerPlaceholder.card(width: 80, height: 120),
                const SizedBox(width: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShimmerPlaceholder.text(width: 200, height: 22),
                    const SizedBox(height: 12),
                    ShimmerPlaceholder.text(width: 120),
                  ],
                ),
                const SizedBox(width: 24),
                const ShimmerPlaceholder.circle(size: 48),
              ],
            ),
          ),
        ),
      ),
      CatalogScene(
        'Text at 200% · the list rows and the poster row at twice the '
        'reading size',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSkeleton.listRows(),
            const SizedBox(height: 12),
            AppSkeleton.posterRow(),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
