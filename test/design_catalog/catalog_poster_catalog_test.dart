@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/presentation/catalog_title_actions.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_poster.dart';

import 'package:cupola/features/media/domain/operator_adds_via.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/settings/data/operator_adds_via_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/model_builders.dart';
import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

/// Four titles as Seerr's catalogue answers them: one on the server, one
/// waiting for approval, one downloading, one Seerr holds no record of.
const _row = [
  MediaPreview(
    id: 1,
    title: 'Sintel',
    mediaType: 'movie',
    posterPath: CatalogArt.tmdbPoster,
    voteAverage: 7.4,
    mediaInfo: {'status': 5},
  ),
  MediaPreview(
    id: 2,
    title: 'Charge',
    mediaType: 'movie',
    posterPath: CatalogArt.tmdbPoster,
    voteAverage: 7.6,
    mediaInfo: {'status': 2},
  ),
  MediaPreview(
    id: 3,
    title: 'Sprite Fright',
    mediaType: 'movie',
    posterPath: CatalogArt.tmdbPoster,
    voteAverage: 7.8,
    mediaInfo: {
      'status': 3,
      'downloadStatus': [
        {
          'status': 'downloading',
          'trackedDownloadState': 'downloading',
          'size': 1000,
          'sizeLeft': 380,
        },
      ],
    },
  ),
  MediaPreview(
    id: 4,
    title: 'The Cabinet of Dr. Caligari',
    mediaType: 'movie',
    posterPath: CatalogArt.tmdbPoster,
    voteAverage: 8.0,
  ),
];

/// The four in a row; with [pointed], the second under a mouse. (The
/// keyboard's focus is shown on the ContentCard card: the menus on this
/// sheet take the focus when they open.)
Widget _rail({bool pointed = false}) => Builder(
  builder: (context) => SizedBox(
    height: CatalogPoster.heightFor(context, 104),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, item) in _row.indexed) ...[
          switch ((pointed, index)) {
            (true, 1) => CatalogPointer.hover(child: _poster(item)),
            _ => _poster(item),
          },
          const SizedBox(width: 12),
        ],
      ],
    ),
  ),
);

Widget _poster(MediaPreview item) =>
    CatalogPoster(item: item, heroTag: 'poster_${item.id}', width: 104);

/// The tile under a mouse with its menu open at the ⋯, on a navigator of
/// the scene's own so the menu lands on the sheet.
Widget _menuOpen(MediaPreview item) => SizedBox(
  height: 330,
  child: Navigator(
    onGenerateRoute: (_) => PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => Align(
        alignment: Alignment.topLeft,
        child: CatalogPointer.hover(child: _MenuAtMore(item: item)),
      ),
    ),
  ),
);

class _MenuAtMore extends ConsumerStatefulWidget {
  const _MenuAtMore({required this.item});

  final MediaPreview item;

  @override
  ConsumerState<_MenuAtMore> createState() => _MenuAtMoreState();
}

class _MenuAtMoreState extends ConsumerState<_MenuAtMore> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject()! as RenderBox;
      showCatalogTitleMenu(
        context,
        ref,
        widget.item,
        mediaType: widget.item.mediaType,
        onOpen: () {},
        at: box.localToGlobal(Offset(box.size.width - 8, 148)),
      );
    });
  }

  @override
  Widget build(BuildContext context) => _poster(widget.item);
}

final _radarrSettings = settingsWithServices(const [
  ServiceKey.seerr,
  ServiceKey.radarr,
]);

class _AddsViaArr extends OperatorAddsViaNotifier {
  @override
  OperatorAddsVia build() => OperatorAddsVia.arr;
}

/// The operator whose Radarr holds Sintel and not The Cabinet.
final List<Override> _operator = [
  currentSettingsProvider.overrideWith((ref) => _radarrSettings),
  audienceProvider.overrideWithValue(Audience.operator),
  roleGateProvider('').overrideWithValue(
    const RoleGate(audience: Audience.operator, grant: SeerrGrant.apiKey()),
  ),
  operatorAddsViaProvider.overrideWith(_AddsViaArr.new),
  moviesForProvider(
    _radarrSettings.primaryOf(ServiceKey.radarr)!.id,
  ).overrideWith((ref) async => [buildMovie(id: 7, tmdbId: 1)]),
];

/// The requester, who may ask.
final List<Override> _requester = [
  currentSettingsProvider.overrideWith(
    (ref) => settingsWithServices(const [ServiceKey.seerr]),
  ),
  audienceProvider.overrideWithValue(Audience.requester),
  roleGateProvider('').overrideWithValue(
    const RoleGate(
      audience: Audience.requester,
      grant: SeerrGrant.account(permissions: 32),
    ),
  ),
];

void main() {
  catalogCard(
    'CatalogPoster',
    overrides: () async => [
      seerrNumberingProvider.overrideWith((ref) async => null),
    ],
    scenes: [
      CatalogScene(
        'CatalogPoster · the operator · on the server, waiting for approval, '
        'downloading at 62%, and a title Seerr holds nothing of (no badge) · '
        'the poster word top-right, two lines of title, TMDB score in dim '
        'ink',
        (_) => _rail(),
        width: 500,
        overrides: [audienceProvider.overrideWithValue(Audience.operator)],
      ),
      CatalogScene(
        'CatalogPoster · the requester · the same four in her words: On the '
        'server, Waiting for approval, Downloading, nothing',
        (_) => _rail(),
        width: 500,
        overrides: [audienceProvider.overrideWithValue(Audience.requester)],
      ),
      CatalogScene(
        'Text at 200% · the words follow the reading size to the compact '
        "tile's ceiling (1.6x) and the tile grows with them; past it they "
        'ellipsise, and a word wider than the tile (Caligari) steps the '
        'title down until it fits whole',
        (_) => _rail(),
        width: 500,
        textScale: catalogTextScale,
        overrides: [audienceProvider.overrideWithValue(Audience.operator)],
      ),
      CatalogScene(
        'CatalogPoster · with a pointer · Charge under a mouse: its poster '
        'rises 2 pt and glows stronger, the caption stays, and the ⋯ that '
        'opens its menu sits on the corner',
        (_) => _rail(pointed: true),
        width: 500,
        platform: CatalogPlatform.desktop,
        overrides: [audienceProvider.overrideWithValue(Audience.operator)],
      ),
      CatalogScene(
        'The menu · the operator, Sintel held by Radarr (a right click, a long '
        'press, the menu key, or the ⋯): Open, Open in Radarr, Copy TMDB link',
        (_) => _menuOpen(_row[0]),
        width: 500,
        platform: CatalogPlatform.desktop,
        overrides: _operator,
      ),
      CatalogScene(
        'The menu · the operator, The Cabinet held by no library: Open, Add to '
        'Radarr, Copy TMDB link',
        (_) => _menuOpen(_row[3]),
        width: 500,
        platform: CatalogPlatform.desktop,
        overrides: _operator,
      ),
      CatalogScene(
        'The menu · the requester, a title nobody asked for: Open, Request, '
        'Copy TMDB link',
        (_) => _menuOpen(_row[3]),
        width: 500,
        platform: CatalogPlatform.desktop,
        overrides: _requester,
      ),
    ],
  );
}
