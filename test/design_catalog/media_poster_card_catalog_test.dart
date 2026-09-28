@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/widgets/media_grid.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/status_badge.dart';

import 'catalog.dart';

/// A URL on the catalog's pinned origin that has no file behind it, so the
/// load fails the way a 404 poster does.
const _missing = 'https://art.catalog/missing.jpg';

typedef _Film = ({
  int id,
  String title,
  String? poster,
  MediaStatusInfo? status,
});

/// One sample poster exists, and it is Nosferatu's: the other titles show the
/// no-URL and failed-load states rather than borrowing it.
const List<_Film> _films = [
  (
    id: 1,
    title: 'Nosferatu',
    poster: CatalogArt.poster,
    status: MediaStatusInfo(availability: MediaAvailability.available),
  ),
  (
    id: 2,
    title: 'Metropolis',
    poster: null,
    status: MediaStatusInfo(
      pipeline: MediaPipeline.downloading,
      progress: 0.42,
    ),
  ),
  (
    id: 3,
    title: 'The Cabinet of Dr. Caligari',
    poster: null,
    status: MediaStatusInfo(availability: MediaAvailability.missing),
  ),
  (
    id: 4,
    title: 'Sherlock Jr.',
    poster: _missing,
    status: MediaStatusInfo(pipeline: MediaPipeline.stalled, progress: 0.61),
  ),
];

Widget _slot(double width, double height, Widget child) =>
    SizedBox(width: width, height: height, child: child);

Widget _row(List<Widget> children) => Wrap(
  spacing: 24,
  runSpacing: 16,
  crossAxisAlignment: WrapCrossAlignment.end,
  children: children,
);

Widget _grid() => MediaGrid<_Film>(
  items: _films,
  imagesExtractor: (film) => film.poster == null
      ? const []
      : [
          {'coverType': 'poster', 'remoteUrl': film.poster},
        ],
  idExtractor: (film) => film.id,
  titleExtractor: (film) => film.title,
  statusExtractor: (film) => film.status,
  baseUrl: '',
  apiKey: '',
  heroTagPrefix: 'movie',
  onItemTap: (_, _) {},
);

void main() {
  catalogCard(
    'MediaPosterCard',
    scenes: [
      CatalogScene(
        'MediaPosterCard() · the hero slot, 82 × 123, and a 120 × 180 cell · '
        'radius-md clip at level-2, image BoxFit.cover',
        (_) => _row([
          _slot(
            82,
            123,
            const MediaPosterCard(heroTag: 'a', imageUrl: CatalogArt.poster),
          ),
          _slot(
            120,
            180,
            const MediaPosterCard(heroTag: 'b', imageUrl: CatalogArt.poster),
          ),
        ]),
      ),
      CatalogScene(
        'MediaPosterCard() · no URL, a failed load, a music fallbackIcon · the '
        'plate, not the theme: the same dark well in both themes, glyph 48',
        (_) => _row([
          _slot(82, 123, const MediaPosterCard(heroTag: 'c')),
          _slot(
            120,
            180,
            const MediaPosterCard(heroTag: 'd', imageUrl: _missing),
          ),
          _slot(
            120,
            180,
            const MediaPosterCard(
              heroTag: 'e',
              fallbackIcon: Icons.music_note_outlined,
            ),
          ),
        ]),
      ),
      CatalogScene(
        'MediaPosterCard(borderRadius:) · radius-sm, then radius-lg · the only '
        'shape parameter the rectangle takes',
        (_) => _row([
          _slot(
            82,
            123,
            MediaPosterCard(
              heroTag: 'f',
              imageUrl: CatalogArt.poster,
              borderRadius: AppRadius.borderRadiusSm,
            ),
          ),
          _slot(
            82,
            123,
            MediaPosterCard(
              heroTag: 'g',
              imageUrl: CatalogArt.poster,
              borderRadius: AppRadius.borderRadiusLg,
            ),
          ),
        ]),
      ),
      CatalogScene(
        'MediaPosterCard.circular · 92 × 92, loaded and without artwork · the '
        'artist and person treatment, no radius',
        (_) => _row([
          _slot(
            92,
            92,
            const MediaPosterCard.circular(
              heroTag: 'h',
              imageUrl: CatalogArt.poster,
            ),
          ),
          _slot(
            92,
            92,
            const MediaPosterCard.circular(
              heroTag: 'i',
              fallbackIcon: Icons.person_outline,
            ),
          ),
        ]),
      ),
      CatalogScene(
        'MediaGrid · 390 phone · the 3-column floor wins over the 130 tile '
        'floor, 12 gaps, 2 : 3 tiles; loaded, no URL, failed load',
        (_) => _grid(),
        width: 390,
        height: 520,
      ),
      CatalogScene(
        'MediaGrid · 720 desktop well · columns grow at the 130 floor instead '
        'of stretching three posters',
        (_) => _grid(),
        width: 720,
        height: 300,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
