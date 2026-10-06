@Tags(['catalog'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/media_metadata_line.dart';

import 'catalog.dart';

void main() {
  catalogCard(
    'MediaMetadataLine',
    width: 640,
    scenes: [
      CatalogScene(
        'MediaMetadataLine · the hero fact line, non-empty items joined with '
        'the house middot',
        (_) => const MediaMetadataLine(
          items: ['1922', '1\u00A0h 34\u00A0min', 'Horror'],
        ),
      ),
      CatalogScene(
        'MediaMetadataLine(maxLines: 1) · the hero clamp: one line, then an '
        'ellipsis',
        (_) => const MediaMetadataLine(
          items: [
            '1922',
            '1\u00A0h 34\u00A0min',
            'Horror',
            'Fantasy',
            'Silent',
            'Black and white',
          ],
          maxLines: 1,
        ),
        width: 320,
      ),
      CatalogScene(
        'Text at 200% · the fact line on a 390pt phone: the items wrap onto '
        'more runs, or clip at the clamp',
        (_) => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MediaMetadataLine(
              items: ['1922', '1\u00A0h 34\u00A0min', 'Horror'],
            ),
            SizedBox(height: 12),
            MediaMetadataLine(
              items: ['1922', '1\u00A0h 34\u00A0min', 'Horror', 'Fantasy'],
              maxLines: 2,
            ),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
