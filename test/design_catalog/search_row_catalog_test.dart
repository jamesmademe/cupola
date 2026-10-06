@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/settings_scope.dart';
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
      action: SearchRowAdd(label: 'Add Cosmic Voyage to Radarr', onTap: () {}),
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

/// A person's page with no Radarr set up: a series keeps its plus to
/// Sonarr, a movie is asked of Seerr, and where Seerr has no Radarr either
/// the plus stays, dimmed.
Widget _withoutRadarr() => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    const _Heading('Directed'),
    SearchRow.title(
      title: 'Dynamo Dream',
      meta: '2019 · Series',
      onTap: () {},
      action: SearchRowAdd(label: 'Add Dynamo Dream to Sonarr', onTap: () {}),
    ),
    SearchRow.title(
      title: 'Tears of Steel',
      meta: '2012 · Movie · TMDB\u00A06.6',
      status: (label: 'Available', tone: StatusTone.success),
      poster: _poster,
      onTap: () {},
    ),
    SearchRow.title(
      title: 'Project London',
      meta: '2011 · Movie',
      onTap: () {},
      action: SearchRowRequest(
        label: 'Request Project London',
        verdict: const Live(),
        onTap: () {},
      ),
    ),
    SearchRow.title(
      title: 'Project London',
      meta: '2011 · Movie',
      onTap: () {},
      action: const SearchRowSetUp(
        label: 'Add Project London',
        service: ServiceKey.radarr,
        blockedMessage: 'Radarr is not set up.',
      ),
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
    // Seerr and Sonarr are set up, Radarr is not.
    overrides: () async => [
      currentSettingsProvider.overrideWith(
        (ref) =>
            settingsWithServices(const [ServiceKey.seerr, ServiceKey.sonarr]),
      ),
    ],
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
          action: SearchRowAdd(
            label: 'Add The Cabinet of Dr. Caligari to Radarr',
            onTap: () {},
          ),
        ),
        width: 320,
      ),
      CatalogScene(
        'The control at the end · the plus to Sonarr, a title on the server '
        'with none, Request where Seerr sends a movie to its Radarr, and the '
        'plus dimmed where nothing set up can add it',
        (_) => _withoutRadarr(),
        width: 390,
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
