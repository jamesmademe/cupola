@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

/// The Stoll series of 1921, fifteen two-reelers — public domain, and a real
/// season-shaped list of titles.
const _titles = [
  'The Dying Detective',
  "The Devil's Foot",
  'A Case of Identity',
  'The Yellow Face',
  'The Red-Headed League',
  'The Resident Patient',
  'A Scandal in Bohemia',
  'The Man with the Twisted Lip',
  'The Beryl Coronet',
  'The Noble Bachelor',
  'The Copper Beeches',
  'The Empty House',
  'The Tiger of San Pedro',
  'The Priory School',
  'The Solitary Cyclist',
];

const _available = MediaStatusInfo(availability: MediaAvailability.available);

MediaStatusInfo _episodeStatus(int index) => switch (index) {
  4 => const MediaStatusInfo(
    pipeline: MediaPipeline.downloading,
    progress: 0.42,
  ),
  6 => const MediaStatusInfo(availability: MediaAvailability.missing),
  _ => _available,
};

const _months = ['Jan', 'Feb', 'Mar', 'Apr'];

String _airDate(int index) =>
    '${_months[index ~/ 4]} ${1 + (index % 4) * 7}, 1921';

Widget _search(String tooltip) => MediaSearchPopupMenu(
  onAutoSearch: () {},
  onInteractiveSearch: () {},
  iconSize: 18,
  tooltip: tooltip,
);

Widget _episode(int index) {
  final status = _episodeStatus(index);
  final searchable = !status.isAvailable && !status.isInPipeline;
  return MediaChildTile.numbered(
    ordinal: formatEpisodeOrdinal(index + 1),
    ordinalLabel: 'Episode ${index + 1}',
    title: _titles[index],
    facts: [_airDate(index), ?mediaStatusWord(status)],
    status: status,
    onTap: () {},
    trailing: searchable ? _search('Search episode ${index + 1}') : null,
  );
}

const _seasons = [
  MediaChildGroup(
    id: 1,
    shortLabel: 'S1',
    label: 'Season 1',
    status: MediaStatusInfo(availability: MediaAvailability.partial),
    summary: '13 of 15 episodes',
    progress: 13 / 15,
  ),
  MediaChildGroup(
    id: 2,
    shortLabel: 'S2',
    label: 'Season 2',
    status: _available,
    summary: '15 of 15 episodes',
    progress: 1,
  ),
  MediaChildGroup(
    id: 3,
    shortLabel: 'S3',
    label: 'Season 3',
    status: MediaStatusInfo(availability: MediaAvailability.missing),
    summary: '0 of 15 episodes',
    progress: 0,
  ),
];

/// Seasons whose status hangs on a queue still being read: no badge, and no
/// word a moment later taken back.
const _awaitedSeasons = [
  MediaChildGroup(
    id: 1,
    shortLabel: 'S1',
    label: 'Season 1',
    status: null,
    summary: '13 of 15 episodes',
    progress: 13 / 15,
  ),
  MediaChildGroup(
    id: 2,
    shortLabel: 'S2',
    label: 'Season 2',
    status: _available,
    summary: '15 of 15 episodes',
    progress: 1,
  ),
];

/// Eight containers: past the six a rail serves, so the picker appears.
final _manySeasons = [
  const MediaChildGroup(
    id: 0,
    shortLabel: 'Sp',
    label: 'Specials',
    status: MediaStatusInfo(availability: MediaAvailability.missing),
    summary: '0 of 2 episodes',
  ),
  for (var season = 1; season <= 7; season++)
    MediaChildGroup(
      id: season,
      shortLabel: 'S$season',
      label: 'Season $season',
      status: _available,
      summary: '15 of 15 episodes',
      progress: 1,
    ),
];

Widget _groups(
  List<MediaChildGroup> groups, {
  Widget? Function(BuildContext, MediaChildGroup)? override,
  int Function(MediaChildGroup)? count,
}) => MediaChildGroupSliver(
  groups: groups,
  accent: ServiceKey.sonarr.accent,
  childCount: count ?? (group) => group.id == 1 ? _titles.length : 0,
  childBuilder: (context, group, index) => _episode(index),
  childOverride: override,
  groupAction: (context, group) => _search('Search ${group.label}'),
  emptyState: AppEmptyState.compact(
    icon: Icons.tv_off_rounded,
    title: 'No seasons yet',
    message:
        'Sonarr has not listed a season for this series. It picks new ones up '
        'on its next refresh.',
    accentColor: ServiceKey.sonarr.accent,
  ),
  pickerLabel: 'All ${groups.length} seasons',
  pickerTitle: 'Seasons',
  childNoun: 'episodes',
);

/// A detail column: the sliver on the page gutter, in a bounded box.
Widget _column(Widget sliver, {double width = 390, double height = 760}) =>
    SizedBox(
      width: width,
      height: height,
      child: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: sliver,
          ),
        ],
      ),
    );

/// Presses the first [TextButton] below it once it has laid out, the way a
/// user would — the collapse state is the sliver's own.
class _Pressed extends StatefulWidget {
  const _Pressed({required this.child});

  final Widget child;

  @override
  State<_Pressed> createState() => _PressedState();
}

class _PressedState extends State<_Pressed> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      VoidCallback? press;
      void visit(Element element) {
        if (press != null) return;
        final widget = element.widget;
        if (widget is TextButton) {
          press = widget.onPressed;
          return;
        }
        element.visitChildren(visit);
      }

      context.visitChildElements(visit);
      press?.call();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Widget _cover({bool art = true}) => ClipRRect(
  borderRadius: AppRadius.borderRadiusSm,
  child: art
      ? Image(
          image: CatalogArt.posterImage,
          width: 38,
          height: 54,
          fit: BoxFit.cover,
        )
      : Builder(
          builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            return Container(
              width: 38,
              height: 54,
              color: scheme.surfaceContainerHighest,
              child: Icon(Icons.album, color: scheme.outline),
            );
          },
        ),
);

Widget _albums() => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    MediaChildTile.stacked(
      leading: _cover(),
      title: 'Nosferatu (Original 1922 Score)',
      facts: const ['1922', '9 of 13 tracks', 'Partial'],
      status: const MediaStatusInfo(availability: MediaAvailability.partial),
      progress: 9 / 13,
      onTap: () {},
      semanticHint: 'opens the track list',
      trailing: _search('Search Nosferatu (Original 1922 Score)'),
    ),
    const SizedBox(height: 4),
    MediaChildTile.stacked(
      leading: _cover(art: false),
      title: 'Metropolis (Original 1927 Score)',
      facts: const ['1927', '24 of 24 tracks'],
      status: _available,
      progress: 1,
      onTap: () {},
      semanticHint: 'opens the track list',
      trailing: _search('Search Metropolis (Original 1927 Score)'),
    ),
    const SizedBox(height: 4),
    MediaChildTile.stacked(
      leading: _cover(art: false),
      title: 'The Cabinet of Dr. Caligari (Original 1920 Score)',
      facts: const ['1920', '0 of 11 tracks', 'Downloading 12%'],
      status: const MediaStatusInfo(
        pipeline: MediaPipeline.downloading,
        progress: 0.12,
      ),
      progress: 0,
      onTap: () {},
      trailing: _search('Search The Cabinet of Dr. Caligari'),
    ),
  ],
);

Widget _loose() => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    // A Seerr episode: availability is per season, so the row has no status.
    MediaChildTile.numbered(
      ordinal: 'E8',
      ordinalLabel: 'Episode 8',
      title: 'The Man with the Twisted Lip',
      facts: const ['Feb 15, 1921'],
    ),
    const SizedBox(height: 4),
    MediaChildTile.numbered(
      ordinal: 'E13',
      ordinalLabel: 'Episode 13',
      title:
          'The Tiger of San Pedro, being a reminiscence of Mr. Sherlock '
          'Holmes in two parts',
      facts: const ['Apr 1, 1921', 'Not released'],
      status: const MediaStatusInfo(
        availability: MediaAvailability.unavailable,
      ),
      onTap: () {},
    ),
    const SizedBox(height: 4),
    MediaChildTile.numbered(
      ordinal: 'E14',
      ordinalLabel: 'Episode 14',
      title: 'The Priory School',
      facts: const ['Apr 8, 1921', 'Stuck 61%'],
      status: const MediaStatusInfo(
        pipeline: MediaPipeline.stalled,
        progress: 0.61,
      ),
      onTap: () {},
    ),
  ],
);

Widget _row(List<Widget> children) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    for (final (index, child) in children.indexed) ...[
      if (index > 0) const SizedBox(width: 24),
      child,
    ],
  ],
);

void main() {
  catalogCard(
    'MediaChildList',
    width: 1328,
    scenes: [
      CatalogScene(
        'MediaChildGroupSliver · three seasons, Season 1 partial, collapsed '
        'to eight; then expanded · the summary carries a full badge, the '
        'search menu and a 3pt progress bar; rows speak their status in words',
        (_) => _row([
          _column(_groups(_seasons), height: 680),
          _Pressed(child: _column(_groups(_seasons), height: 990)),
        ]),
      ),
      CatalogScene(
        'MediaChildGroupSliver · eight containers, then 1.5× reading size, '
        'then no containers · the rail ends in the picker past six or past '
        '1.4×, where the summary also stacks',
        (context) => _row([
          _column(_groups(_manySeasons), height: 200),
          MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: _column(
              _groups(_seasons, count: (group) => group.id == 1 ? 2 : 0),
              height: 400,
            ),
          ),
          _column(_groups(const []), height: 200),
        ]),
      ),
      CatalogScene(
        'MediaChildGroupSliver(childOverride:) · loading, a failed load, an '
        'empty season · the override replaces the rows, the selector stays',
        (_) => _row([
          _column(
            _groups(
              _seasons,
              override: (_, _) =>
                  const ShimmerList(itemCount: 3, itemHeight: 56),
            ),
            height: 340,
          ),
          _column(
            _groups(
              _seasons,
              override: (_, _) => AppErrorState.compact(
                error: 'Connection refused',
                serviceName: 'Sonarr',
                onRetry: () {},
              ),
            ),
            height: 340,
          ),
          _column(
            _groups(
              _seasons,
              override: (_, group) => AppEmptyState.compact(
                icon: Icons.event_busy_rounded,
                title: 'No episodes',
                message: 'Sonarr lists nothing under ${group.label} yet.',
                accentColor: ServiceKey.sonarr.accent,
              ),
            ),
            height: 340,
          ),
        ]),
      ),
      CatalogScene(
        'MediaChildGroupSliver · a season whose status hangs on a queue still '
        'being read (status: null) · the summary keeps its search menu and '
        'draws no badge, the bar takes the neutral tone',
        (_) => _column(_groups(_awaitedSeasons, count: (_) => 0), height: 200),
      ),
      CatalogScene(
        'MediaChildTile.stacked · Lidarr albums: 38 × 54 cover, own progress '
        'bar, compact badge; then MediaChildTile.numbered with no status, a '
        'two-line title, and a stalled row',
        (_) => _row([
          SizedBox(
            width: 390,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _albums(),
            ),
          ),
          SizedBox(
            width: 390,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _loose(),
            ),
          ),
        ]),
      ),
      CatalogScene(
        'MediaChildGroupSliver · desktop, the 720 reading column · compact '
        'density, the same rows',
        (_) => _column(_groups(_seasons), width: 720, height: 640),
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
