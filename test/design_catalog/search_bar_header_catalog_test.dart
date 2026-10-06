@Tags(['catalog'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/search_bar_header.dart';

import 'catalog.dart';

void _ignore(String _) {}

/// The Discover tab's field. Monochrome like every other: the magnifier is the
/// secondary ink whichever screen it searches. It offers Cancel while it
/// holds a query.
Widget _discoverTab({String? query}) => SearchBarHeader(
  hintText: 'Movies, series, people',
  initialQuery: query,
  onQueryChanged: _ignore,
  onCancel: () {},
);

List<CatalogScene> _scenes(CatalogPlatform platform, double width) => [
  CatalogScene(
    'Discover tab · empty, hint only · the magnifier in the secondary ink, '
    'the same on every service',
    (_) => _discoverTab(),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Discover tab · with a query · the clear button appears only with '
    'text, and Cancel after the field puts the search away',
    (_) => _discoverTab(query: 'Nosferatu'),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'qBittorrent · empty · no service colour reaches the field',
    (_) => const SearchBarHeader(
      hintText: 'Search torrents',
      onQueryChanged: _ignore,
    ),
    width: width,
    platform: platform,
  ),
];

void main() {
  catalogCard(
    'SearchBarHeader',
    width: 816,
    scenes: [
      ..._scenes(CatalogPlatform.phone, 390),
      CatalogScene(
        'Lidarr library · Search artists... · the hint in the field\'s own '
        'hint ink',
        (_) => const SearchBarHeader(
          hintText: 'Search artists',
          onQueryChanged: _ignore,
        ),
        width: 390,
      ),
      CatalogScene(
        'Long query · the text scrolls inside the field, the clear button '
        'keeps its place',
        (_) => _discoverTab(
          query: 'The Cabinet of Dr. Caligari 1920 restoration tinted',
        ),
        width: 390,
      ),
      CatalogScene(
        'autofocus: true · focused, caret in the field',
        (_) => const SearchBarHeader(
          hintText: 'Search movies',
          autofocus: true,
          onQueryChanged: _ignore,
        ),
        width: 390,
      ),
      CatalogScene(
        'Text at 200% · hint and query: the field grows with the text, the '
        'magnifier and the clear button keep their places',
        (_) => const Column(
          children: [
            SearchBarHeader(
              hintText: 'Movies, series, artists',
              onQueryChanged: _ignore,
            ),
            SearchBarHeader(
              hintText: 'Movies, series, artists',
              initialQuery: 'Nosferatu',
              onQueryChanged: _ignore,
            ),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Long hint · the longest hint any screen sets, on a 320pt phone: it '
        'ellipsises inside the field rather than pushing the glyph out',
        (_) => const SearchBarHeader(
          hintText: 'Search every movie, series, artist and album',
          onQueryChanged: _ignore,
        ),
        width: 320,
      ),
      ..._scenes(CatalogPlatform.desktop, 768),
      CatalogScene(
        'autofocus: true on the desktop · the field holding keyboard focus, '
        'where the focus ring is read',
        (_) => const SearchBarHeader(
          hintText: 'Search movies',
          autofocus: true,
          onQueryChanged: _ignore,
        ),
        width: 768,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
