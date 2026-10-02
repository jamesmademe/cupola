@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/section_header.dart';

import 'catalog.dart';

void main() {
  catalogCard(
    'SectionHeader',
    scenes: [
      CatalogScene(
        'SectionHeader() · default, tappable · "See all" through a primary '
        'chevron, floored at 44pt',
        (_) => SectionHeader(title: 'Needs attention', onTap: () {}),
        width: 360,
      ),
      CatalogScene(
        'SectionHeader(subtitle:) · non-tappable, no chevron',
        (_) => const SectionHeader(
          title: 'Pool health',
          subtitle: '3 pools · 1 degraded',
        ),
        width: 360,
      ),
      CatalogScene(
        'SectionHeader.action · the trailing slot is its own control, the row '
        'itself is not tappable',
        (_) => SectionHeader.action(
          title: 'Custom formats',
          trailing: FilledButton.tonal(
            onPressed: () {},
            child: const Text('New'),
          ),
        ),
        width: 360,
      ),
      CatalogScene(
        'SectionHeader · long title at 1.6x text scale — clamped, wraps '
        'between words instead of breaking mid-word; the chevron stays on the '
        'title line, since only an explicit trailing stacks',
        (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: SectionHeader(
            title: 'Requested and awaiting release',
            onTap: () {},
          ),
        ),
        width: 360,
      ),
      CatalogScene(
        'SectionHeader.action · above 1.4x reading size the row stacks: title, '
        'then the full-width trailing control',
        (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: SectionHeader.action(
            title: 'Wanted',
            trailing: OutlinedButton(
              onPressed: () {},
              child: const Text('Search all'),
            ),
          ),
        ),
        width: 300,
      ),
      CatalogScene(
        'Text at 200% · the tappable header and the one with an action: the '
        'title wraps between words, and the trailing control takes its own '
        'full-width line',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Requested and awaiting release',
              onTap: () {},
            ),
            const SizedBox(height: 12),
            const SectionHeader(
              title: 'Pool health',
              subtitle: '3 pools · 1 degraded',
            ),
            const SizedBox(height: 12),
            SectionHeader.action(
              title: 'Custom formats',
              trailing: FilledButton.tonal(
                onPressed: () {},
                child: const Text('New'),
              ),
            ),
          ],
        ),
        width: 360,
        textScale: catalogTextScale,
      ),
    ],
  );
}
