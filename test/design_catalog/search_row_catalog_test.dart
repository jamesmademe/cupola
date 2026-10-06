@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';

import 'catalog.dart';

String get _poster => ImageUtils.buildTmdbPosterUrl(CatalogArt.tmdbPoster);

/// A search's answer as the page lays it out: a section name over its rows.
Widget _answer() => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    const _Heading('On your server'),
    SearchRow.title(
      title: 'Cosmos Laundromat',
      meta: 'Series · 2015 · TMDB\u00A08.0',
      status: (label: 'On Jellyfin', tone: StatusTone.success),
      poster: _poster,
      onTap: () {},
    ),
    const _Heading('Movies'),
    SearchRow.title(
      title: 'Cosmic Voyage',
      meta: 'Movie · 1996',
      onTap: () {},
      onAdd: () {},
      addLabel: 'Add Cosmic Voyage to Radarr',
    ),
    SearchRow.title(
      title: 'Metropolis',
      meta: 'Movie · 1927 · TMDB\u00A08.2',
      status: (label: 'Waiting for approval', tone: StatusTone.info),
      poster: _poster,
      onTap: () {},
    ),
    const _Heading('People'),
    SearchRow.person(
      name: 'Tom Hanks',
      line: 'Known for Forrest Gump, Toy Story',
      onTap: () {},
    ),
  ],
);

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 2),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}

void main() {
  catalogCard(
    'SearchRow',
    scenes: [
      CatalogScene(
        'A search by kind · a title on the server with its artwork and where '
        'it is, one with no artwork (its initials) and the plus, one waiting '
        'for approval, and a person with no picture',
        (_) => _answer(),
        width: 390,
      ),
      CatalogScene(
        'SearchRow.title · a long title and a long state, cut to one line '
        'each; the plus keeps its 44',
        (_) => SearchRow.title(
          title: 'The Cabinet of Dr. Caligari and Other Expressionist Films',
          meta: 'Movie · 1920 · TMDB\u00A08.0',
          status: (label: 'Partially available', tone: StatusTone.info),
          onTap: () {},
          onAdd: () {},
          addLabel: 'Add The Cabinet of Dr. Caligari to Radarr',
        ),
        width: 320,
      ),
      CatalogScene(
        'Text at 200% · the row grows past its floor, the words stay on one '
        'line each and the person\'s line takes two',
        (_) => _answer(),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
