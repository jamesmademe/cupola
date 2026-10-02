@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/selection_pills.dart';

import 'catalog.dart';

void main() {
  catalogCard(
    'SelectionPills',
    scenes: [
      CatalogScene(
        'SelectionPills<int>() · the selected pill is the strong fill under '
        'the primary ink, the nav bar\'s pill',
        (_) => SelectionPills<int>(
          values: const [0, 1, 2],
          selected: 1,
          labelBuilder: (i) => const ['Grabbed', 'Imported', 'Failed'][i],
          onSelected: (_) {},
        ),
      ),
      CatalogScene(
        'SelectionPills<int>() · on a service page · the same pill: no '
        'service colours it',
        (_) => SelectionPills<int>(
          values: const [0, 1, 2, 3],
          selected: 0,
          labelBuilder: (i) =>
              const ['Queue', 'History', 'Wanted', 'Calendar'][i],
          onSelected: (_) {},
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
                padding: SelectionPills.flush,
              ),
            ],
          ),
        ),
        width: 390,
      ),
      CatalogScene(
        'SelectionPills.wrap() · a choice that must be seen whole, on a 320pt '
        'phone: the four Access choices take a second line rather than a '
        'hidden scroll',
        (_) => SelectionPills<int>.wrap(
          values: const [0, 1, 2, 3],
          selected: 1,
          labelBuilder: (i) => const [
            'None',
            'Cloudflare Access',
            'Password',
            'Custom headers',
          ][i],
          onSelected: (_) {},
        ),
        width: 320,
      ),
      CatalogScene(
        'Text at 200% · the scrolling row: the pills grow with the label and '
        'the fourth is reached by scrolling',
        (_) => SelectionPills<int>(
          values: const [0, 1, 2, 3],
          selected: 1,
          labelBuilder: (i) =>
              const ['Queue', 'History', 'Wanted', 'Calendar'][i],
          onSelected: (_) {},
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · SelectionPills.wrap: the four Access choices on '
        'a 390pt phone',
        (_) => SelectionPills<int>.wrap(
          values: const [0, 1, 2, 3],
          selected: 1,
          labelBuilder: (i) => const [
            'None',
            'Cloudflare Access',
            'Password',
            'Custom headers',
          ][i],
          onSelected: (_) {},
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
