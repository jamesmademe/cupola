@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
        'SelectionPills<int>(leading:) · a way back at the head of the row, '
        'never one of the values; then the lone SelectionPill of a '
        'catalogue page: a choice with its chevron, a toggle off and on',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectionPills<int>(
              values: const [0, 1, 2],
              selected: 0,
              labelBuilder: (i) => const ['Networks', 'Trending', 'Genres'][i],
              onSelected: (_) {},
              leading: SelectionPill(
                label: 'Discover',
                selected: false,
                onTap: () {},
              ),
            ),
            Padding(
              padding: SelectionPills.gutter,
              child: Wrap(
                spacing: 8,
                children: [
                  SelectionPill(
                    label: 'Popular',
                    selected: false,
                    trailing: Icons.expand_more_rounded,
                    onTap: () {},
                  ),
                  SelectionPill(
                    label: 'Rating 7+ · 100+ votes',
                    selected: false,
                    onTap: () {},
                  ),
                  SelectionPill(
                    label: 'Under 100\u00A0min',
                    selected: true,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
        width: 420,
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
