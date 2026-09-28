@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/selection_pills.dart';

import 'catalog.dart';

void main() {
  catalogCard(
    'SelectionPills',
    scenes: [
      CatalogScene(
        'SelectionPills<int>() · default accent (primary) — an aggregate '
        'surface is lit by primary, not by one service',
        (_) => SelectionPills<int>(
          values: const [0, 1, 2],
          selected: 1,
          labelBuilder: (i) => const ['Grabbed', 'Imported', 'Failed'][i],
          onSelected: (_) {},
        ),
      ),
      CatalogScene(
        'SelectionPills<int>(accent: AppColors.radarr) · a service page\'s '
        'own accent',
        (_) => SelectionPills<int>(
          values: const [0, 1, 2, 3],
          selected: 0,
          labelBuilder: (i) =>
              const ['Queue', 'History', 'Wanted', 'Calendar'][i],
          onSelected: (_) {},
          accent: AppColors.radarr,
        ),
      ),
      CatalogScene(
        'SelectionPills<int>() · a long label, the pill grows with it and '
        'the row scrolls rather than clipping',
        (_) => SelectionPills<int>(
          values: const [0, 1],
          selected: 0,
          labelBuilder: (i) => const ['Awaiting manual import', 'History'][i],
          onSelected: (_) {},
        ),
        width: 280,
      ),
      CatalogScene(
        'SelectionPills(padding: SelectionPills.flush) · inside a host already '
        'on the gutter, the first pill shares the column edge with the text '
        'above it',
        (context) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Season 1', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              SelectionPills<int>(
                values: const [1, 2, 3],
                selected: 1,
                labelBuilder: (i) => 'S$i',
                onSelected: (_) {},
                accent: AppColors.sonarr,
                padding: SelectionPills.flush,
              ),
            ],
          ),
        ),
        width: 390,
      ),
    ],
  );
}
