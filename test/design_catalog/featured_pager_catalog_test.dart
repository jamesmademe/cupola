@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/features/home/presentation/widgets/featured_pager.dart';

import 'catalog.dart';

/// Three lights drawn from three artworks: the laundromat's blue, the spring
/// sky's, the fright's pink.
const _lights = [
  TitleLight(
    light: Color(0xFF50B1D2),
    actionFill: Color(0xFF8ED6F2),
    actionInk: Color(0xFF0C222A),
    dayPrimary: Color(0xFF00677F),
  ),
  TitleLight(
    light: Color(0xFF6CAED4),
    actionFill: Color(0xFF96D4FA),
    actionInk: Color(0xFF0E222C),
    dayPrimary: Color(0xFF006590),
  ),
  TitleLight(
    light: Color(0xFFF48687),
    actionFill: Color(0xFFFFBBBA),
    actionInk: Color(0xFF311919),
    dayPrimary: Color(0xFF9C3F42),
  ),
];

void _none() {}

const _art = (url: CatalogArt.backdrop, headers: null);

final _resume = FeaturedPage(
  title: 'Cosmos Laundromat',
  line: 'Continue watching · S2 E3 · 5\u00A0min left',
  art: _art,
  label: 'Cosmos Laundromat, continue watching, S2 E3, 5 min left',
  onOpen: _none,
  lead: const FeaturedAction('Resume', _none, icon: Icons.play_arrow_rounded),
  second: const FeaturedAction('Details', _none),
  light: _lights[0],
);

final _arrival = FeaturedPage(
  title: 'Spring',
  line: 'New on your server · 2\u00A0h ago · Radarr 4K',
  art: _art,
  label: 'Spring, new on your server, 2 h ago, Radarr 4K',
  onOpen: _none,
  lead: const FeaturedAction('Play', _none, icon: Icons.play_arrow_rounded),
  second: const FeaturedAction('Details', _none),
  light: _lights[1],
);

final _today = FeaturedPage(
  title: 'Sprite Fright',
  line: 'Out on digital today · downloading 62%',
  art: _art,
  label: 'Sprite Fright, out on digital today, downloading 62%',
  onOpen: _none,
  lead: const FeaturedAction('Details', _none),
  second: const FeaturedAction('Queue', _none),
  light: _lights[2],
);

/// The pager in its room, lit by the slide in front as the Home is.
Widget _pager(int index, {List<FeaturedPage>? pages}) {
  final shown = pages ?? [_resume, _arrival, _today];
  return AmbientBackground(
    accent: shown[index].light?.light,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: FeaturedPager(pages: shown, initialIndex: index, advances: false),
    ),
  );
}

void main() {
  catalogCard(
    'FeaturedPager',
    width: 840,
    scenes: [
      CatalogScene(
        'Continue watching in front · the art lit by its title, Resume in the '
        'slide\'s light, Details quiet, the pause control and the pager',
        (_) => _pager(0),
        width: 390,
        height: 420,
      ),
      CatalogScene(
        'The newest arrival · Play where a media server holds it',
        (_) => _pager(1),
        width: 390,
        height: 420,
      ),
      CatalogScene(
        'Out today · Details leads, Queue while it downloads',
        (_) => _pager(2),
        width: 390,
        height: 420,
      ),
      CatalogScene(
        'One slide, no media server holds it · Details alone, no pager, '
        'nothing moves',
        (_) => _pager(
          0,
          pages: [
            FeaturedPage(
              title: 'Spring',
              line: 'New on your server · 2\u00A0h ago',
              art: _art,
              label: 'Spring, new on your server, 2 h ago',
              onOpen: _none,
              lead: const FeaturedAction('Details', _none),
              light: _lights[1],
            ),
          ],
        ),
        width: 390,
        height: 400,
      ),
      CatalogScene(
        'Screen reader or Reduce Motion · paused from the start: a button '
        'per slide, the control reads Play',
        (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(accessibleNavigation: true, disableAnimations: true),
          child: _pager(1),
        ),
        width: 390,
        height: 460,
      ),
      CatalogScene(
        'Loading · the art box and two lines hold the place',
        (_) => const Padding(
          padding: EdgeInsets.all(16),
          child: FeaturedSkeleton(),
        ),
        width: 390,
        height: 330,
      ),
      CatalogScene(
        'Text at 200% · the control under the artwork, the title across the '
        'width, the buttons one under the other',
        (_) => _pager(0),
        width: 390,
        height: 760,
        textScale: 2,
      ),
    ],
  );
}
