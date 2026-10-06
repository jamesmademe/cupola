@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/file_info_section.dart';
import 'package:cupola/core/widgets/media_info_card.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

/// The cells Radarr's Details card builds for a movie in the library, in its
/// order.
const _details = [
  MediaInfoGroup(title: 'Monitored', child: Text('Yes')),
  MediaInfoGroup(title: 'In cinemas', child: Text('Mar 4, 1922')),
  MediaInfoGroup(title: 'Digital', child: Text('Dec 3, 2022')),
  MediaInfoGroup(title: 'Physical', child: Text('Jan 10, 2023')),
  MediaInfoGroup(title: 'Studio', child: Text('Prana-Film')),
  MediaInfoGroup(title: 'Certification', child: Text('Not Rated')),
  MediaInfoGroup(title: 'Language', child: Text('German')),
];

/// The Details slot on a phone: the 390 screen less the 16 gutters, in the
/// host card Radarr uses.
Widget _hosted(Widget child, {double width = 358}) => SizedBox(
  width: width,
  child: AppCard.surfaceOutlined(child: child),
);

void main() {
  catalogCard(
    'MediaInfoCard',
    scenes: [
      CatalogScene(
        'MediaInfoCard · Radarr Details: the two-column fact grid',
        (_) => _hosted(const MediaInfoCard(groups: _details)),
      ),
      CatalogScene(
        'MediaInfoCard · a 360pt phone, 296 of grid width · under two 144pt '
        'columns it folds to one, cells space-md apart',
        (_) => _hosted(
          const MediaInfoCard(
            groups: [
              MediaInfoGroup(title: 'Monitored', child: Text('Yes')),
              MediaInfoGroup(title: 'Studio', child: Text('Prana-Film')),
              MediaInfoGroup(title: 'Language', child: Text('German')),
            ],
          ),
          width: 360 - 32,
        ),
      ),
      CatalogScene(
        'MediaInfoCard · a long label and a long value · the label ellipsises '
        'on one line, the value on two',
        (_) => _hosted(
          const MediaInfoCard(
            groups: [
              MediaInfoGroup(
                title: 'Original title in the language of production',
                child: Text('Nosferatu, eine Symphonie des Grauens'),
              ),
              MediaInfoGroup(
                title: 'Studio',
                child: Text(
                  'Prana-Film GmbH, Berlin, in association with Jofa-Atelier '
                  'Berlin-Johannisthal',
                ),
              ),
            ],
          ),
        ),
      ),
      CatalogScene(
        'MediaFactsList · file facts · the same grid, with tabular figures',
        (_) => _hosted(
          const MediaFactsList(
            facts: [
              MediaFact('Runtime', '94 min'),
              MediaFact('Size', '41.2 GB'),
              MediaFact('Video', 'HEVC · 2160p'),
              MediaFact('Audio', 'FLAC 2.0'),
              MediaFact('Bitrate', '58.3 Mb/s'),
              MediaFact('Added', 'Sep 20, 2026'),
            ],
          ),
        ),
      ),
      CatalogScene(
        'FileInfoSection.file · the file leads in the ink; Released as and '
        'the folder (a path, so mono) are secondary · a file that kept its '
        'release name · .missing, the same footprint · .folder, a series '
        'under its Library path slot: the path alone, leading in the ink · '
        'the titled folder, the movie fallback under its File slot, no '
        'accent',
        (_) => SizedBox(
          width: 358,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FileInfoSection.file(
                fileName: 'Nosferatu (1922) Bluray-2160p.mkv',
                releasedAs: 'Nosferatu.1922.2160p.BluRay.x265-GROUP',
                path: '/data/media/movies/Nosferatu (1922)',
                accent: ServiceKey.radarr.accent,
              ),
              const SizedBox(height: 12),
              FileInfoSection.file(
                fileName: 'Metropolis.1927.1080p.BluRay.x264-GROUP.mkv',
                path: '/data/media/movies/Metropolis (1927)',
                accent: ServiceKey.radarr.accent,
              ),
              const SizedBox(height: 12),
              FileInfoSection.missing(accent: ServiceKey.radarr.accent),
              const SizedBox(height: 12),
              FileInfoSection.folder(
                path: '/data/media/series/Sherlock',
                accent: ServiceKey.sonarr.accent,
              ),
              const SizedBox(height: 12),
              const FileInfoSection(
                path: '/data/media/movies/Nosferatu (1922)',
              ),
            ],
          ),
        ),
      ),
      CatalogScene(
        'MediaInfoCard · desktop, the 380 side track (348 inside its '
        'gutters, 316 of grid) · two 150pt columns, as the boards draw',
        (_) => _hosted(const MediaInfoCard(groups: _details), width: 380 - 32),
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · Radarr Details on a phone, the long label and value, '
        'and the file section, at twice the reading size',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _hosted(const MediaInfoCard(groups: _details)),
            const SizedBox(height: 16),
            _hosted(
              const MediaInfoCard(
                groups: [
                  MediaInfoGroup(
                    title: 'Original title in the language of production',
                    child: Text('Nosferatu, eine Symphonie des Grauens'),
                  ),
                  MediaInfoGroup(title: 'Studio', child: Text('Prana-Film')),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 358,
              child: FileInfoSection.file(
                fileName: 'Nosferatu (1922) Bluray-2160p.mkv',
                releasedAs: 'Nosferatu.1922.2160p.BluRay.x265-GROUP',
                path: '/data/media/movies/Nosferatu (1922)',
                accent: ServiceKey.radarr.accent,
              ),
            ),
          ],
        ),
        textScale: catalogTextScale,
      ),
    ],
  );
}
