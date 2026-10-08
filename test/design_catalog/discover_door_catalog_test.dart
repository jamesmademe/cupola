@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_door.dart';

import 'catalog.dart';

String get _poster => ImageUtils.buildTmdbPosterUrl(CatalogArt.tmdbPoster);
String get _backdrop =>
    ImageUtils.buildTmdbPosterUrl(CatalogArt.tmdbBackdrop, size: 'w300');

/// [doors] [columns] to a row, each row as tall as its tallest door, as the
/// atrium lays them out.
Widget _rows(List<Widget> doors, {int columns = 3}) => Column(
  children: [
    for (var start = 0; start < doors.length; start += columns)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = start; i < start + columns; i++) ...[
                if (i > start) const SizedBox(width: 8),
                Expanded(
                  child: i < doors.length ? doors[i] : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      ),
  ],
);

Widget _lobby({int columns = 3}) => _rows(columns: columns, [
  DiscoverDoor.lobby(
    title: 'Trending',
    subtitle: 'This week',
    lightUrl: _poster,
    posterUrls: [_poster, _poster],
    onTap: () {},
  ),
  DiscoverDoor.lobby(
    title: 'Genres',
    subtitle: '19',
    lightUrl: _backdrop,
    onTap: () {},
  ),
  DiscoverDoor.lobby(
    title: 'Networks',
    subtitle: 'Series',
    names: const ['Netflix', 'HBO', 'BBC One'],
    onTap: () {},
  ),
  DiscoverDoor.lobby(
    title: 'Studios',
    subtitle: 'Movies',
    names: const ['A24', 'Studio Ghibli', 'Pixar'],
    onTap: () {},
  ),
  DiscoverDoor.lobby(
    title: 'People',
    subtitle: 'Directors, cast',
    lightUrl: _poster,
    onTap: () {},
  ),
  DiscoverDoor.lobby(title: 'Decades', subtitle: '1920s to now', onTap: () {}),
]);

void main() {
  catalogCard(
    'DiscoverDoor',
    // Wide enough for the scene of a tablet on its side.
    width: 1160,
    scenes: [
      CatalogScene(
        'DiscoverDoor.lobby · the atrium\'s six: lit with leaning posters, '
        'lit alone, names stacked and fading, plain',
        (_) => _lobby(),
        width: 390,
      ),
      CatalogScene(
        'The lobby on a tablet on its side · all six on one row, each wider '
        'than the narrowest phone\'s',
        (_) => _lobby(columns: 6),
        width: 1068,
      ),
      CatalogScene(
        'DiscoverDoor.index · a genre lit by its backdrop with a poster '
        'leaning in, its name at the foot; plain tiles name a network and a '
        'decade at the head',
        (_) => _rows(columns: 2, [
          DiscoverDoor.index(
            title: 'Animation',
            lightUrl: _backdrop,
            posterUrls: [_poster],
            onTap: () {},
          ),
          DiscoverDoor.index(
            title: 'Science fiction',
            lightUrl: _backdrop,
            onTap: () {},
          ),
          DiscoverDoor.index(title: 'Netflix', onTap: () {}),
          DiscoverDoor.index(title: '1990s', onTap: () {}),
        ]),
        width: 390,
      ),
      CatalogScene(
        'Text at 200% · the words follow the reading size to the compact '
        'ceiling, the atrium lays the doors two to a row, and a door drops '
        'its corner so nothing sits on its name',
        (_) => _lobby(columns: 2),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
