@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/machine_name.dart';

import 'catalog.dart';

const _release = 'Severance.S02E05.1080p.WEB-DL.DDP5.1-GROUP';
const _file = 'Avengers.Endgame.2019.2160p.UHD.BluRay.x265-GROUP.mkv';
const _shortFile = 'Spring.2019.1080p.mkv';
const _renamed = 'Coffee Run (2020) WEBDL-1080p.mkv';
const _scene = 'Coffee.Run.2020.1080p.WEB-DL.DDP5.1.H.264-WORLD';

/// A row about a copy, as a host draws one: the title, then its machine name
/// under it. The plate is the scene's, not the component's: MachineName has
/// no plate of its own.
Widget _row(String title, Widget name) => Builder(
  builder: (context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTheme.rowTitle(theme.brightness)),
          const SizedBox(height: 2),
          name,
        ],
      ),
    );
  },
);

void main() {
  catalogCard(
    'MachineName',
    scenes: [
      CatalogScene(
        '.release · a narrow phone row (320) · the front says what it is, the '
        'back which copy; the ellipsis goes in the middle',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row('Severance · S2 E5', const MachineName.release(_release)),
            const SizedBox(height: AppSpacing.sm),
            _row('Avengers: Endgame (2019)', const MachineName.file(_file)),
            const SizedBox(height: AppSpacing.sm),
            _row('Spring (2019)', const MachineName.file(_shortFile)),
          ],
        ),
        width: 320,
      ),
      CatalogScene(
        '.release · a desktop row (400) · more room keeps more of both ends, '
        'the whole name on hover',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row('Severance · S2 E5', const MachineName.release(_release)),
            const SizedBox(height: AppSpacing.sm),
            _row('Avengers: Endgame (2019)', const MachineName.file(_file)),
          ],
        ),
        width: 400,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        '.fileInFull, then .releaseInFull(caption: \'Released as\') · the '
        'detail File section on a phone (358) · whole, wrapping after its dots, '
        'selectable, each with its copy button',
        (_) => const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MachineName.fileInFull(_renamed),
            MachineName.releaseInFull(_scene, caption: 'Released as'),
          ],
        ),
        width: 358,
      ),
      CatalogScene(
        '.fileInFull, then .releaseInFull · on a desktop (560) · the copy button '
        'keeps the pointer floor',
        (_) => const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MachineName.fileInFull(_file),
            MachineName.releaseInFull(_scene, caption: 'Released as'),
          ],
        ),
        width: 560,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
