@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

void _ignore(String _) {}

/// The Search tab's accent, walked for the field the way the screen does it.
Widget _searchTab({String? query}) => Builder(
  builder: (context) => SearchBarHeader(
    hintText: 'Movies, shows, artists...',
    initialQuery: query,
    accent: ServiceTheme.onTint(
      AppColors.navSearch,
      surface: Theme.of(context).colorScheme.surfaceContainer,
      tintAlpha: 0,
    ),
    onQueryChanged: _ignore,
  ),
);

List<CatalogScene> _scenes(CatalogPlatform platform, double width) => [
  CatalogScene(
    'Seerr Discover · empty, hint only · the magnifier in Seerr\'s accent, '
    'walked against surfaceContainer',
    (_) => SearchBarHeader(
      hintText: 'Search movies & TV shows...',
      accent: ServiceKey.seerr.accent,
      onQueryChanged: _ignore,
    ),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Search tab · with a query · the clear button appears only with text',
    (_) => _searchTab(query: 'Nosferatu'),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'qBittorrent · empty · the accent is ink here, so it is measured',
    (_) => SearchBarHeader(
      hintText: 'Search torrents...',
      accent: ServiceKey.qbittorrent.accent,
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
        'Lidarr library · Search artists... · the pink walked darker in light '
        'theme until it clears the field',
        (_) => SearchBarHeader(
          hintText: 'Search artists...',
          accent: ServiceKey.lidarr.accent,
          onQueryChanged: _ignore,
        ),
        width: 390,
      ),
      CatalogScene(
        'No accent · falls back to primary',
        (_) => const SearchBarHeader(onQueryChanged: _ignore),
        width: 390,
      ),
      CatalogScene(
        'Long query · the text scrolls inside the field, the clear button '
        'keeps its place',
        (_) => _searchTab(
          query: 'The Cabinet of Dr. Caligari 1920 restoration tinted',
        ),
        width: 390,
      ),
      CatalogScene(
        'autofocus: true · focused, caret in the field',
        (_) => SearchBarHeader(
          hintText: 'Search movies...',
          accent: ServiceKey.radarr.accent,
          autofocus: true,
          onQueryChanged: _ignore,
        ),
        width: 390,
      ),
      ..._scenes(CatalogPlatform.desktop, 768),
    ],
  );
}
