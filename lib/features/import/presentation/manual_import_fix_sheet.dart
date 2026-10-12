import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/sheet_utils.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/import/domain/blocked_import.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/presentation/manual_import_provider.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Matches one file the arr could not place: which movie, which series and
/// episode, which artist, album and track.
Future<void> showManualImportFixSheet({
  required BuildContext context,
  required ServiceKey service,
  required ManualImportItem item,
}) => _show(context, _MatchSheet(service: service, items: [item]));

/// Matches several files at once: one title for all of them, and for a
/// series or an album, each file's own episode or track.
Future<void> showManualImportBulkFixSheet({
  required BuildContext context,
  required ServiceKey service,
  required List<ManualImportItem> items,
}) => _show(context, _MatchSheet(service: service, items: items));

/// The add sheet's chrome at a fixed height: the list under the header
/// scrolls, and the one button stays at the foot.
Future<void> _show(BuildContext context, Widget sheet) =>
    SheetUtils.showCupolaModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(heightFactor: 0.86, child: sheet),
    );

/// Where the sheet is: the title, then (a series, an album) the part of it.
enum _Step { title, album, part }

class _MatchSheet extends ConsumerStatefulWidget {
  const _MatchSheet({required this.service, required this.items})
    : assert(items.length > 0, 'nothing to match');

  final ServiceKey service;
  final List<ManualImportItem> items;

  @override
  ConsumerState<_MatchSheet> createState() => _MatchSheetState();
}

class _MatchSheetState extends ConsumerState<_MatchSheet> {
  final _scroll = ScrollController();

  /// The episode a single file starts on, brought into view when it is
  /// below the fold.
  final _picked = GlobalKey();

  /// The library, first; a lookup adds what a query finds beyond it.
  List<ManualImportLookupResult> _library = const [];
  List<ManualImportLookupResult> _shown = const [];
  String _query = '';
  bool _searching = true;

  _Step _step = _Step.title;
  ManualImportLookupResult? _match;

  List<ManualImportEpisode> _episodes = const [];
  int? _season;
  List<ManualImportAlbum> _albums = const [];
  ManualImportAlbum? _album;
  List<ManualImportTrack> _tracks = const [];
  bool _loadingPart = false;

  /// Each file's episode or track, by path.
  final _episodeOf = <String, ManualImportEpisode>{};
  final _trackOf = <String, ManualImportTrack>{};

  bool _applying = false;
  String? _refusal;

  ServiceKey get _service => widget.service;
  bool get _bulk => widget.items.length > 1;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLibrary());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // === Reading ==============================================================

  Future<void> _loadLibrary() async {
    final results = await ref
        .read(manualImportFlowProvider.notifier)
        .getLibraryMatches();
    if (!mounted) return;
    setState(() {
      _library = results;
      _shown = _filtered(results, _query);
      _searching = false;
    });
  }

  List<ManualImportLookupResult> _filtered(
    List<ManualImportLookupResult> results,
    String query,
  ) {
    final term = query.trim().toLowerCase();
    return [
      for (final result in results)
        if (term.isEmpty ||
            result.title.toLowerCase().contains(term) ||
            (result.subtitle ?? '').toLowerCase().contains(term))
          result,
    ].take(12).toList(growable: false);
  }

  /// The library first; a query it does not answer goes to the arr's lookup.
  Future<void> _search(String query) async {
    setState(() {
      _query = query;
      _shown = _filtered(_library, query);
    });
    if (query.trim().isEmpty || _shown.isNotEmpty) return;
    setState(() => _searching = true);
    final found = await ref
        .read(manualImportFlowProvider.notifier)
        .lookup(query.trim());
    if (!mounted || _query != query) return;
    final merged = {
      for (final result in [..._library, ...found]) result.id: result,
    }.values.toList()..sort((a, b) => a.title.compareTo(b.title));
    setState(() {
      _library = merged;
      _shown = _filtered(merged, query);
      _searching = false;
    });
  }

  Future<void> _pickTitle(ManualImportLookupResult match) async {
    setState(() {
      _match = match;
      _refusal = null;
    });
    switch (_service) {
      case ServiceKey.sonarr:
        await _loadEpisodes(match);
      case ServiceKey.lidarr:
        await _loadAlbums(match);
      default:
        break;
    }
  }

  Future<void> _loadEpisodes(ManualImportLookupResult series) async {
    setState(() {
      _step = _Step.part;
      _loadingPart = true;
      _episodeOf.clear();
    });
    final episodes = await ref
        .read(manualImportFlowProvider.notifier)
        .getEpisodes(seriesId: series.id);
    if (!mounted) return;
    final seasons = _seasonsOf(episodes);
    final guessed = widget.items.first.seasonNumber;
    setState(() {
      _episodes = episodes;
      _season = seasons.contains(guessed)
          ? guessed
          : seasons.where((season) => season != 0).firstOrNull ??
                seasons.firstOrNull;
      _loadingPart = false;
      _guessEpisodes();
    });
    _revealPicked();
  }

  void _revealPicked() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final row = _picked.currentContext;
    if (row != null && row.mounted) {
      // As little as it takes: the series and the seasons stay in view
      // when the episode fits under them.
      Scrollable.ensureVisible(
        row,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    }
  });

  Future<void> _loadAlbums(ManualImportLookupResult artist) async {
    setState(() {
      _step = _Step.album;
      _loadingPart = true;
    });
    final albums = await ref
        .read(manualImportFlowProvider.notifier)
        .getAlbums(artist.id);
    if (!mounted) return;
    setState(() {
      _albums = albums;
      _loadingPart = false;
    });
  }

  Future<void> _pickAlbum(ManualImportAlbum album) async {
    setState(() {
      _album = album;
      _step = _Step.part;
      _loadingPart = true;
      _trackOf.clear();
    });
    final tracks = await ref
        .read(manualImportFlowProvider.notifier)
        .getTracks(album.id);
    if (!mounted) return;
    setState(() {
      _tracks = tracks;
      _loadingPart = false;
    });
  }

  void _back() => setState(() {
    _refusal = null;
    _step = switch (_step) {
      _Step.part when _service == ServiceKey.lidarr => _Step.album,
      _ => _Step.title,
    };
  });

  // === Episodes =============================================================

  static List<int> _seasonsOf(List<ManualImportEpisode> episodes) {
    final seasons = {
      for (final episode in episodes) episode.seasonNumber,
    }.toList()..sort();
    // The specials last, as the series' own pills order them.
    if (seasons.remove(0)) seasons.add(0);
    return seasons;
  }

  List<ManualImportEpisode> get _seasonEpisodes => [
    for (final episode in _episodes)
      if (episode.seasonNumber == _season) episode,
  ]..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));

  /// Each file starts on the episode its name carries, when the season has
  /// it and no other file took it.
  void _guessEpisodes() {
    final season = _seasonEpisodes;
    for (final item in widget.items) {
      final number = episodeNumberInName(item.fileName);
      final episode = season
          .where((each) => each.episodeNumber == number)
          .firstOrNull;
      if (episode != null && _chosenFor(episode, item) == null) {
        _episodeOf[item.path] = episode;
      }
    }
  }

  void _pickSeason(int season) {
    setState(() {
      _season = season;
      _episodeOf.clear();
      _guessEpisodes();
    });
    _revealPicked();
  }

  /// [item] goes on [episode]; the files after it with no episode yet follow
  /// it in order, one episode each, so a run of files is one choice.
  void _pickEpisode(ManualImportItem item, ManualImportEpisode episode) {
    setState(() {
      _refusal = null;
      _episodeOf[item.path] = episode;
      if (!_bulk) return;
      final season = _seasonEpisodes;
      var next = season.indexOf(episode);
      final after = widget.items.skip(widget.items.indexOf(item) + 1);
      for (final later in after) {
        if (_episodeOf.containsKey(later.path)) break;
        next++;
        if (next >= season.length) break;
        _episodeOf[later.path] = season[next];
      }
    });
  }

  /// The file [episode] is already on, other than [item]: one the Review
  /// placed, or one this sheet just did. Null when it is free.
  String? _chosenFor(ManualImportEpisode episode, ManualImportItem item) {
    for (final entry in _episodeOf.entries) {
      if (entry.key != item.path && entry.value.id == episode.id) {
        return _stemOf(entry.key);
      }
    }
    final ours = {for (final each in widget.items) each.path};
    for (final other in ref.read(manualImportFlowProvider).items) {
      if (ours.contains(other.path)) continue;
      if (other.episodes.any((each) => intOrNull(each['id']) == episode.id)) {
        return fileStem(other);
      }
    }
    return null;
  }

  String _stemOf(String path) => fileStem(
    widget.items.firstWhere(
      (item) => item.path == path,
      orElse: () => widget.items.first,
    ),
  );

  // === Applying =============================================================

  bool get _complete {
    final match = _match;
    if (match == null) return false;
    return switch (_service) {
      ServiceKey.sonarr => widget.items.every(
        (item) => _episodeOf.containsKey(item.path),
      ),
      ServiceKey.lidarr =>
        _album != null &&
            widget.items.every((item) => _trackOf.containsKey(item.path)),
      _ => true,
    };
  }

  ManualImportFixAssignment _assignmentFor(ManualImportItem item) {
    final episode = _episodeOf[item.path];
    final track = _trackOf[item.path];
    return ManualImportFixAssignment(
      match: _match!,
      episode: episode,
      episodes: [?episode],
      album: _album,
      track: track,
      tracks: [?track],
    );
  }

  Future<void> _apply() async {
    if (!_complete || _applying) return;
    setState(() {
      _applying = true;
      _refusal = null;
    });
    final notifier = ref.read(manualImportFlowProvider.notifier);
    final before = ref.read(manualImportFlowProvider).error;
    if (_bulk) {
      await notifier.applyBulkFixAssignments({
        for (final item in widget.items) item: _assignmentFor(item),
      });
    } else {
      await notifier.applyFixAssignment(
        widget.items.single,
        _assignmentFor(widget.items.single),
      );
    }
    if (!mounted) return;
    final after = ref.read(manualImportFlowProvider).error;
    if (after != null && after != before) {
      setState(() {
        _applying = false;
        _refusal = after;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  // === Drawing ==============================================================

  String get _title => switch ((_service, _step)) {
    (ServiceKey.radarr, _) => 'Which movie?',
    (ServiceKey.sonarr, _Step.title) => 'Which series?',
    (ServiceKey.sonarr, _) => _bulk ? 'Which episodes?' : 'Which episode?',
    (ServiceKey.lidarr, _Step.title) => 'Which artist?',
    (ServiceKey.lidarr, _Step.album) => 'Which album?',
    (ServiceKey.lidarr, _) => _bulk ? 'Which tracks?' : 'Which track?',
    _ => 'Which title?',
  };

  String? get _lead => switch ((_service, _step)) {
    (ServiceKey.radarr, _) =>
      _match == null ? 'Pick a movie' : 'Match to ${_match!.title}',
    (_, _Step.part) when _bulk => 'Match ${widget.items.length} files',
    (ServiceKey.sonarr, _Step.part) => switch (_episodeOf.values.firstOrNull) {
      final episode? => 'Match to ${episode.label}',
      null => 'Pick an episode',
    },
    (ServiceKey.lidarr, _Step.part) => switch (_trackOf.values.firstOrNull) {
      final ManualImportTrack track =>
        'Match to track ${track.trackNumber ?? ''}'.trim(),
      null => 'Pick a track',
    },
    // Picking the series or the album is the step: no button under it.
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final lead = _lead;
    return AppBottomSheet(
      title: _title,
      showClose: true,
      scrollController: _scroll,
      bodyPadding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Picking the title, the file and the field stay put over the
          // results; past it, each row a file names its own.
          if (_step == _Step.title) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _Files(items: widget.items, bulk: _bulk),
            ),
            SearchBarHeader(
              hintText: switch (_service) {
                ServiceKey.radarr => 'Search your movies',
                ServiceKey.lidarr => 'Search your artists',
                _ => 'Search your series',
              },
              debounceDuration: const Duration(milliseconds: 300),
              onQueryChanged: _search,
            ),
          ],
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              children: [
                if (_step != _Step.title && !_bulk) ...[
                  _Files(items: widget.items, bulk: false),
                  const SizedBox(height: AppSpacing.xs),
                ],
                ...switch (_step) {
                  _Step.title => _titleStep(context),
                  _Step.album => _albumStep(context),
                  _Step.part => _partStep(context),
                },
              ],
            ),
          ),
          if (lead != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_refusal case final refusal?) ...[
                    Text(
                      refusal,
                      style: AppType.meta.copyWith(
                        color: statusToneColor(
                          Theme.of(context).colorScheme,
                          StatusTone.warning,
                          surface: room.raised,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  FilledButton(
                    onPressed: _complete && !_applying ? _apply : null,
                    style: mediaLeadStyle(context, null),
                    child: _applying
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(lead),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _titleStep(BuildContext context) => [
    if (_searching && _shown.isEmpty)
      for (var i = 0; i < 4; i++)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: ShimmerPlaceholder(height: SearchRow.minHeight - 8),
        )
    else if (_shown.isEmpty)
      AppEmptyState.compact(
        icon: Icons.manage_search_rounded,
        title: _query.trim().isEmpty
            ? 'Nothing in your library yet'
            : 'Nothing called "${_query.trim()}"',
      )
    else
      for (final result in _shown)
        SearchRow.title(
          title: result.title,
          meta: _metaOf(result),
          poster: _posterOf(result.raw) ?? '',
          selected: _service == ServiceKey.radarr && _match?.id == result.id,
          onTap: () => _pickTitle(result),
        ),
  ];

  String _metaOf(ManualImportLookupResult result) {
    final raw = result.raw;
    return switch (_service) {
      ServiceKey.radarr => ['Movie', ?result.subtitle].join(' · '),
      ServiceKey.sonarr => () {
        final seasons = [
          for (final season in jsonObjects(raw['seasons'], (each) => each))
            if ((intOrNull(season['seasonNumber']) ?? 0) > 0) season,
        ].length;
        return [
          'Series',
          ?result.subtitle,
          if (seasons > 0) seasons == 1 ? '1 season' : '$seasons seasons',
        ].join(' · ');
      }(),
      _ => ['Artist', ?result.subtitle].join(' · '),
    };
  }

  /// The title picked, with the way back to the list.
  Widget _chosen(BuildContext context, String label) {
    final match = _match!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label(
          label,
          trailing: TextButton(onPressed: _back, child: const Text('Change')),
        ),
        SearchRow.title(
          title: match.title,
          meta: _metaOf(match),
          poster: _posterOf(match.raw) ?? '',
          onTap: _back,
        ),
      ],
    );
  }

  List<Widget> _albumStep(BuildContext context) => [
    _chosen(context, 'Artist'),
    const _Label('Album'),
    if (_loadingPart)
      const ShimmerPlaceholder(height: 3 * SearchRow.minHeight)
    else if (_albums.isEmpty)
      const AppEmptyState.compact(
        icon: Icons.album_outlined,
        title: 'No albums for this artist',
      )
    else
      for (final album in _albums)
        SearchRow.title(
          title: album.title,
          meta: ['Album', ?album.year?.toString()].join(' · '),
          poster: _posterOf(album.raw) ?? '',
          onTap: () => _pickAlbum(album),
        ),
  ];

  List<Widget> _partStep(BuildContext context) {
    if (_service == ServiceKey.lidarr) {
      return [
        _chosen(context, 'Album'),
        if (_loadingPart)
          const ShimmerPlaceholder(height: 4 * 56)
        else if (_tracks.isEmpty)
          const AppEmptyState.compact(
            icon: Icons.music_note_outlined,
            title: 'No tracks on this album',
          )
        else if (_bulk)
          ..._eachFile(
            label: 'Track',
            valueOf: (item) => _trackOf[item.path]?.label,
            onTap: (item) => _pickTrackFor(context, item),
          )
        else ...[
          const _Label('Track'),
          MediaGroup(
            children: [
              for (final track in _tracks)
                _PickRow(
                  title: track.label,
                  detail: _trackDetail(track),
                  selected: _trackOf[widget.items.single.path]?.id == track.id,
                  onTap: () => setState(
                    () => _trackOf[widget.items.single.path] = track,
                  ),
                ),
            ],
          ),
        ],
      ];
    }

    final seasons = _seasonsOf(_episodes);
    final season = _season;
    return [
      _chosen(context, 'Series'),
      if (_loadingPart)
        const ShimmerPlaceholder(height: 5 * 56)
      else if (seasons.isEmpty || season == null)
        const AppEmptyState.compact(
          icon: Icons.live_tv_outlined,
          title: 'No episodes for this series',
        )
      else ...[
        if (seasons.length > 1) ...[
          const _Label('Season'),
          SelectionPills<int>.wrap(
            values: seasons,
            selected: season,
            labelBuilder: seasonChipLabel,
            onSelected: _pickSeason,
          ),
        ],
        if (_bulk)
          ..._eachFile(
            label: 'Episodes',
            valueOf: (item) => switch (_episodeOf[item.path]) {
              final episode? => _episodeTitle(episode),
              null => null,
            },
            onTap: (item) => _pickEpisodeFor(context, item),
          )
        else ...[
          const _Label('Episode'),
          MediaGroup(
            children: [
              for (final episode in _seasonEpisodes)
                _PickRow(
                  key: _episodeOf[widget.items.single.path]?.id == episode.id
                      ? _picked
                      : null,
                  title: _episodeTitle(episode),
                  detail: _episodeDetail(episode),
                  chosenFor: _chosenFor(episode, widget.items.single),
                  selected:
                      _episodeOf[widget.items.single.path]?.id == episode.id,
                  onTap: () => _pickEpisode(widget.items.single, episode),
                ),
            ],
          ),
        ],
      ],
    ];
  }

  /// One row a file, each opening the value sheet on its own episode or
  /// track.
  List<Widget> _eachFile({
    required String label,
    required String? Function(ManualImportItem item) valueOf,
    required void Function(ManualImportItem item) onTap,
  }) => [
    _Label(label),
    MediaGroup(
      children: [
        for (final item in widget.items)
          _FileRow(
            file: fileStem(item),
            value: valueOf(item),
            onTap: () => onTap(item),
          ),
      ],
    ),
  ];

  Future<void> _pickEpisodeFor(
    BuildContext context,
    ManualImportItem item,
  ) async {
    final current = _episodeOf[item.path];
    final picked = await showMediaValueSheet<ManualImportEpisode>(
      context,
      title: fileStem(item),
      value: current,
      currentLabel: current == null ? 'none' : _episodeTitle(current),
      options: [
        for (final episode in _seasonEpisodes)
          MediaDetailValueOption(
            value: episode,
            label: switch (_chosenFor(episode, item)) {
              final other? => '${_episodeTitle(episode)} (on $other)',
              null => _episodeTitle(episode),
            },
          ),
      ],
    );
    if (picked != null) _pickEpisode(item, picked.value);
  }

  Future<void> _pickTrackFor(
    BuildContext context,
    ManualImportItem item,
  ) async {
    final current = _trackOf[item.path];
    final picked = await showMediaValueSheet<ManualImportTrack>(
      context,
      title: fileStem(item),
      value: current,
      currentLabel: current?.label ?? 'none',
      options: [
        for (final track in _tracks)
          MediaDetailValueOption(value: track, label: track.label),
      ],
    );
    if (picked != null) {
      setState(() => _trackOf[item.path] = picked.value);
    }
  }

  /// `E4 · The title`: the season is the pill above.
  static String _episodeTitle(ManualImportEpisode episode) => [
    formatEpisodeOrdinal(episode.episodeNumber),
    if (episode.title.isNotEmpty && episode.title != 'Episode') episode.title,
  ].join(' · ');

  /// When it aired and whether the library has it: `Aired 3 Oct 2024 · On
  /// disk`, `Aired 3 Oct 2024 · Missing`, `Airs 21 Oct`.
  static String? _episodeDetail(ManualImportEpisode episode) {
    final raw = episode.raw;
    final aired = DateTime.tryParse(
      stringOrNull(raw['airDateUtc']) ?? stringOrNull(raw['airDate']) ?? '',
    );
    final onDisk = raw['hasFile'] == true;
    if (aired == null) return onDisk ? 'On disk' : null;
    if (aired.isAfter(DateTime.now())) {
      return 'Airs ${formatDayMonth(aired.toLocal())}';
    }
    return [
      'Aired ${formatDayMonth(aired.toLocal())}',
      onDisk ? 'On disk' : 'Missing',
    ].join(' · ');
  }

  static String? _trackDetail(ManualImportTrack track) {
    final raw = track.raw;
    final seconds = (intOrNull(raw['duration']) ?? 0) ~/ 1000;
    final words = [
      if (seconds > 0)
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
      if (raw['hasFile'] == true) 'On disk',
    ];
    return words.isEmpty ? null : words.join(' · ');
  }
}

/// A poster, or an album's cover, off the arr's own host.
String? _posterOf(Map<String, dynamic> raw) {
  final images = raw['images'];
  if (images is! List) return null;
  for (final type in const ['poster', 'cover']) {
    for (final image in images) {
      if (image is Map && image['coverType'] == type) {
        final url = stringOrNull(image['remoteUrl']);
        if (url != null && url.startsWith('http')) return url;
      }
    }
  }
  return remotePosterOf(images);
}

/// The file being matched, as the arr found it: the evidence the choice is
/// made from, so never elided. Several files: the first three, then a count.
class _Files extends StatelessWidget {
  const _Files({required this.items, required this.bulk});

  final List<ManualImportItem> items;
  final bool bulk;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    const shown = 3;
    final names = [for (final item in items.take(shown)) fileStem(item)];
    return Semantics(
      container: true,
      label: bulk
          ? '${items.length} files: ${names.join(', ')}'
          : 'File: ${names.single}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bulk)
            Text(
              '${items.length} files',
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
          for (final name in names)
            Text(name, style: AppType.mono.copyWith(color: room.inkSecondary)),
          if (items.length > shown)
            Text(
              'and ${items.length - shown} more',
              style: AppType.meta.copyWith(color: room.inkTertiary),
            ),
        ],
      ),
    );
  }
}

/// A part's name over its list, with an action at its end when there is one.
class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: EdgeInsets.only(
        top: AppSpacing.md,
        bottom: trailing == null ? AppSpacing.sm : 0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// One episode or track to choose: what it is, when it aired and whether it
/// is on disk, and the other file already on it.
class _PickRow extends StatelessWidget {
  const _PickRow({
    super.key,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.chosenFor,
  });

  final String title;
  final String? detail;
  final String? chosenFor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final spoken = [
      title,
      ?detail,
      if (chosenFor case final other?) 'chosen for $other',
    ].join(', ');
    return PressableScale(
      onTap: onTap,
      semanticLabel: spoken,
      semanticValue: selected ? 'Selected' : null,
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: ActionStateGlyph.glyphSize,
                color: selected ? room.ink : room.inkTertiary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: selected
                          ? AppType.row
                                .weight(FontWeight.w600)
                                .copyWith(color: room.ink)
                          : AppType.row.copyWith(color: room.ink),
                    ),
                    if (detail case final detail?)
                      Text(
                        detail,
                        style: AppType.meta.copyWith(color: room.inkTertiary),
                      ),
                    if (chosenFor case final other?)
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Chosen for '),
                            TextSpan(
                              text: other,
                              style: AppType.mono.copyWith(
                                color: room.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                        style: AppType.meta.copyWith(color: room.inkSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of several files: its name, and the episode or track it goes on, or
/// that it has none yet.
class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.value,
    required this.onTap,
  });

  final String file;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return PressableScale(
      onTap: onTap,
      semanticLabel: '$file, ${value ?? 'not picked yet'}',
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(file, style: AppType.mono.copyWith(color: room.ink)),
                    Text(
                      value ?? 'Pick one',
                      style: AppType.meta.copyWith(
                        color: value == null
                            ? room.inkTertiary
                            : room.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: room.inkTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
