@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/widgets/header_action_row.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
import 'package:cupola/features/discover/domain/seerr_request_gate.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_action_buttons.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

/// A label painted under the 1.6× clamp, as every band label is.
Widget _clamped(Widget label) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
    child: label,
  ),
);

/// The consequence sentence, as the action band sets it under the row.
Widget _consequence(BuildContext context, String text) => Text(
  text,
  maxLines: 3,
  overflow: TextOverflow.ellipsis,
  style: Theme.of(context).textTheme.bodySmall!.copyWith(
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  ),
);

ButtonStyle _discStyle(ColorScheme scheme) =>
    HeaderActionRow.tonalIconButtonStyle(
      foregroundColor: scheme.onSurfaceVariant,
      backgroundColor: scheme.onSurface.withValues(alpha: 0.06),
      borderColor: scheme.outlineVariant,
    );

Widget _disc(
  BuildContext context,
  IconData icon,
  String name, {
  bool enabled = true,
}) => SizedBox.square(
  dimension: HeaderActionRow.buttonHeight,
  child: OutlinedButton(
    onPressed: enabled ? () {} : null,
    style: _discStyle(Theme.of(context).colorScheme),
    child: Icon(icon, size: ActionStateGlyph.glyphSize, semanticLabel: name),
  ),
);

Widget _discs(List<Widget> discs) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    for (var i = 0; i < discs.length; i++) ...[
      if (i > 0) const SizedBox(width: AppSpacing.sm),
      discs[i],
    ],
  ],
);

/// A band with a promoted primary: the ink-filled expanded control (the brand book's
/// primary, the same on every service), the discs beside it, and the sentence
/// underneath.
Widget _primaryBand({
  required ServiceKey service,
  required String label,
  required IconData icon,
  required String consequence,
  bool isBusy = false,
  bool isConfirmed = false,
  bool withSecondary = true,
}) => Builder(
  builder: (context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = scheme.primary;
    final onFill = scheme.onPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeaderActionRow(
          expanded: FilledButton.icon(
            onPressed: isBusy ? null : () {},
            icon: ActionStateGlyph(
              icon: icon,
              label: label,
              isBusy: isBusy,
              isConfirmed: isConfirmed,
              color: onFill,
              fill: fill,
            ),
            label: _clamped(
              Text(label, maxLines: 2, textAlign: TextAlign.center),
            ),
            style: HeaderActionRow.expandedButtonStyle(
              foregroundColor: onFill,
              backgroundColor: fill,
            ),
          ),
          trailing: _discs([
            if (withSecondary)
              _disc(
                context,
                Icons.search_rounded,
                'Interactive search',
                enabled: !isBusy,
              ),
            _disc(
              context,
              Icons.more_horiz_rounded,
              'More actions',
              enabled: !isBusy,
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.sm),
        _consequence(context, consequence),
      ],
    );
  },
);

/// A band whose primary is withheld: two labelled tonal buttons take the
/// wide slot.
Widget _tonalBand(String consequence) => Builder(
  builder: (context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tonal(String label) => OutlinedButton(
      onPressed: () {},
      style:
          HeaderActionRow.tonalExpandedButtonStyle(
            foregroundColor: scheme.onSurfaceVariant,
            backgroundColor: scheme.onSurface.withValues(alpha: 0.06),
            borderColor: scheme.outlineVariant,
          ).copyWith(
            padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
              EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            ),
          ),
      child: _clamped(Text(label, maxLines: 2, textAlign: TextAlign.center)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeaderActionRow(
          expanded: Row(
            children: [
              Expanded(child: tonal('Interactive search')),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: tonal('Automatic search')),
            ],
          ),
          trailing: _disc(context, Icons.more_horiz_rounded, 'More actions'),
        ),
        const SizedBox(height: AppSpacing.sm),
        _consequence(context, consequence),
      ],
    );
  },
);

/// Nothing promoted and nothing to surface: the sentence takes the wide slot.
Widget _sentenceBand() => Builder(
  builder: (context) => HeaderActionRow(
    expanded: _consequence(
      context,
      "There's nothing to search for until it's released.",
    ),
    trailing: _disc(context, Icons.more_horiz_rounded, 'More actions'),
  ),
);

const _trailer = RelatedVideo(
  url: 'https://www.youtube.com/watch?v=catalog',
  key: 'catalog',
  name: 'Official Trailer',
  type: 'Trailer',
  site: 'YouTube',
);

TvSeason _season(int number) => TvSeason(
  id: number,
  seasonNumber: number,
  name: 'Season $number',
  episodeCount: 8,
);

/// Seerr's deck itself, `DiscoverActionButtons`, in one of its states: the
/// Request primary, then at most two captioned buttons whose tops align with
/// it. Trailers only when Seerr sent something to play; Manage when Seerr
/// holds a row for the title, otherwise the jump into Radarr or Sonarr.
///
/// The real widget rather than a composition of its parts: the composition
/// this replaced drew Manage and Open side by side, which the deck never does.
/// [mediaInfo] goes through the same `seerrRequestGate` the page uses.
Widget _seerrDeck({
  String mediaType = 'movie',
  Map<String, dynamic>? mediaInfo,
  bool? isInService,
  List<TvSeason> seasons = const [],
  List<RelatedVideo> videos = const [_trailer],
  SeerrNumbering numbering = SeerrNumbering.seerr,
  bool has4kServer = false,
}) => DiscoverActionButtons(
  mediaId: 603,
  mediaType: mediaType,
  hasManageableMedia: mediaInfo?['id'] != null,
  isInService: isInService,
  requestGate: seerrRequestGate(
    mediaInfo,
    isMovie: mediaType == 'movie',
    seasons: seasons,
    numbering: numbering,
    has4kServer: has4kServer,
  ),
  tvdbId: mediaType == 'tv' ? 81189 : null,
  mediaInfo: mediaInfo,
  title: mediaType == 'movie' ? 'Sprite Fright' : 'Night Shift',
  voteAverage: 7.4,
  videos: videos,
);

/// A series with its first two seasons on disk and two more to ask for.
Widget _partlyHeldSeries() => _seerrDeck(
  mediaType: 'tv',
  mediaInfo: const {
    'id': 2,
    'status': 4,
    'seasons': [
      {'seasonNumber': 1, 'status': 5},
      {'seasonNumber': 2, 'status': 5},
    ],
  },
  isInService: true,
  seasons: [for (var s = 1; s <= 4; s++) _season(s)],
);

/// The captioned button's own states, side by side.
Widget _buttonStates() => const Wrap(
  spacing: AppSpacing.sm,
  runSpacing: AppSpacing.md,
  children: [
    HeaderActionButton(
      icon: Icons.saved_search_rounded,
      label: 'Auto search',
      semanticLabel: 'Automatic search',
      onPressed: _noop,
    ),
    HeaderActionButton(
      icon: Icons.saved_search_rounded,
      label: 'Auto search',
      semanticLabel: 'Automatic search',
      onPressed: _noop,
      isBusy: true,
    ),
    HeaderActionButton(
      icon: Icons.saved_search_rounded,
      label: 'Auto search',
      semanticLabel: 'Automatic search',
      onPressed: _noop,
      isConfirmed: true,
    ),
    HeaderActionButton(
      icon: Icons.saved_search_rounded,
      label: 'Auto search',
      semanticLabel: 'Automatic search',
    ),
    HeaderActionButton(
      icon: Icons.manage_search_rounded,
      label: 'Interactive search',
      onPressed: _noop,
    ),
  ],
);

void _noop() {}

List<CatalogScene> _bands(CatalogPlatform platform, double width) => [
  CatalogScene(
    'Primary + two discs · Radarr, Automatic search · the ink fill with the '
    'on-ink label, 48pt tall, radius md — never the service\'s colour',
    (_) => _primaryBand(
      service: ServiceKey.radarr,
      label: 'Automatic search',
      icon: Icons.saved_search_rounded,
      consequence: 'Radarr is hunting a release for this title.',
    ),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Primary busy · Sonarr · a 16pt spinner for this control only; the discs '
    'stay in place, disabled',
    (_) => _primaryBand(
      service: ServiceKey.sonarr,
      label: 'Automatic search',
      icon: Icons.saved_search_rounded,
      consequence: 'Sonarr is hunting a release for this title.',
      isBusy: true,
    ),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Primary confirmed · Lidarr · the success check walked against the '
    'ink fill',
    (_) => _primaryBand(
      service: ServiceKey.lidarr,
      label: 'Automatic search',
      icon: Icons.saved_search_rounded,
      consequence: 'Lidarr is hunting a release for this title.',
      isConfirmed: true,
      withSecondary: false,
    ),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Primary withheld · two tonal buttons take the wide slot, no glyph',
    (_) =>
        _tonalBand("Radarr has everything it expects, so it isn't searching."),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Nothing to promote · the sentence takes the expanded slot',
    (_) => _sentenceBand(),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Seerr deck · nothing requested yet · Request, Trailers and Open; Open is '
    'gated on a Radarr not set up, dimmed and still tappable; tops align, '
    'captions hang',
    (_) => _seerrDeck(),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Seerr deck · a series partly on disk · Request stays open and names the '
    'seasons it would add; Manage takes the place of Open',
    (_) => _partlyHeldSeries(),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Seerr deck · Available · a state read, not a dead control, with why '
    'nothing is offered; no Trailers when Seerr sent nothing to play',
    (_) => _seerrDeck(
      mediaInfo: const {'id': 1, 'status': 5},
      isInService: true,
      videos: const [],
    ),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Seerr deck · on disk in HD, Seerr has a 4K server · Request stays open '
    'for the 4K copy, and says so',
    (_) => _seerrDeck(
      mediaInfo: const {'id': 1, 'status': 5, 'status4k': 1},
      isInService: true,
      videos: const [],
      has4kServer: true,
    ),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Seerr deck · Requested, waiting for approval in Seerr',
    (_) => _seerrDeck(
      mediaInfo: const {
        'id': 1,
        'status': 2,
        'requests': [
          {'id': 9, 'status': 1, 'is4k': false},
        ],
      },
      isInService: false,
    ),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Seerr deck · Request failed · Seerr takes no second request while the '
    'failed one stands; Manage is where it is removed',
    (_) => _seerrDeck(
      mediaInfo: const {
        'id': 1,
        'status': 1,
        'requests': [
          {'id': 9, 'status': 4, 'is4k': false},
        ],
      },
      isInService: false,
    ),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Seerr deck · Blocklisted · the operator barred the title in Seerr, which '
    'takes no request for it; neutral, a choice and not a fault',
    (_) => _seerrDeck(
      mediaInfo: const {'id': 1, 'status': 6},
      isInService: false,
      videos: const [],
    ),
    width: width,
    platform: platform,
  ),
];

void main() {
  catalogCard(
    'HeaderActionRow',
    width: 720,
    overrides: () async => [
      // Radarr is not set up, so the gated Open draws dimmed.
      currentSettingsProvider.overrideWith(
        (ref) => settingsWithServices(const [ServiceKey.sonarr]),
      ),
    ],
    scenes: [
      ..._bands(CatalogPlatform.phone, 390),
      CatalogScene(
        'HeaderActionButton · idle, busy, confirmed, onPressed: null, long '
        'caption · a 48pt square in a 72pt measure, caption wraps to two lines',
        (_) => _buttonStates(),
      ),
      CatalogScene(
        'At 2× reading size · the captions and the primary label clamp at 1.6× '
        'and wrap; the measure does not grow',
        (_) => _partlyHeldSeries(),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'At 2× reading size · the library band: the primary label and the '
        'consequence sentence take the lines they need, the discs keep 48pt',
        (_) => _primaryBand(
          service: ServiceKey.radarr,
          label: 'Automatic search',
          icon: Icons.saved_search_rounded,
          consequence: 'Radarr is hunting a release for this title.',
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'At 2× reading size · the Seerr deck with Open dimmed: four captions '
        'wrap under their squares, dimmed and still tappable',
        (_) => _seerrDeck(),
        width: 390,
        textScale: catalogTextScale,
      ),
      ..._bands(CatalogPlatform.desktop, 560),
    ],
  );
}
