@Tags(['catalog'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/widgets/media_browse_scaffold.dart';
import 'package:cupola/core/widgets/service_kpi_peek.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import 'catalog.dart';

/// On the catalog's pinned origin with no file behind it: the load fails.
const _missing = 'https://art.catalog/missing.jpg';

typedef _Film = ({
  int id,
  String title,
  String sortTitle,
  int year,
  String? poster,
  MediaStatusInfo status,
  String added,
});

/// Public-domain silents. One sample poster exists and it is Nosferatu's; the
/// rest show the no-URL and failed-load states rather than borrowing it.
const List<_Film> _library = [
  (
    id: 1,
    title: 'Nosferatu',
    sortTitle: 'nosferatu',
    year: 1922,
    poster: CatalogArt.poster,
    status: MediaStatusInfo(availability: MediaAvailability.available),
    added: '2026-09-20T10:00:00Z',
  ),
  (
    id: 2,
    title: 'Metropolis',
    sortTitle: 'metropolis',
    year: 1927,
    poster: null,
    status: MediaStatusInfo(
      pipeline: MediaPipeline.downloading,
      progress: 0.42,
    ),
    added: '2026-09-26T10:00:00Z',
  ),
  (
    id: 3,
    title: 'The Cabinet of Dr. Caligari',
    sortTitle: 'cabinet of dr caligari',
    year: 1920,
    poster: _missing,
    status: MediaStatusInfo(availability: MediaAvailability.missing),
    added: '2026-09-12T10:00:00Z',
  ),
  (
    id: 4,
    title: 'Sherlock Jr.',
    sortTitle: 'sherlock jr',
    year: 1924,
    poster: null,
    status: MediaStatusInfo(pipeline: MediaPipeline.stalled, progress: 0.61),
    added: '2026-09-18T10:00:00Z',
  ),
  (
    id: 5,
    title: 'Nanook of the North',
    sortTitle: 'nanook of the north',
    year: 1922,
    poster: null,
    status: MediaStatusInfo(availability: MediaAvailability.upgradable),
    added: '2026-09-02T10:00:00Z',
  ),
  (
    id: 6,
    title: 'Safety Last!',
    sortTitle: 'safety last',
    year: 1923,
    poster: null,
    status: MediaStatusInfo(
      availability: MediaAvailability.missing,
      unmonitored: true,
    ),
    added: '2026-08-30T10:00:00Z',
  ),
  (
    id: 7,
    title: '20,000 Leagues Under the Sea',
    sortTitle: '20000 leagues under sea',
    year: 1916,
    poster: null,
    status: MediaStatusInfo(availability: MediaAvailability.available),
    added: '2026-08-12T10:00:00Z',
  ),
  (
    id: 8,
    title: 'The Mark of Zorro',
    sortTitle: 'mark of zorro',
    year: 1920,
    poster: null,
    status: MediaStatusInfo(availability: MediaAvailability.available),
    added: '2026-08-14T10:00:00Z',
  ),
  (
    id: 9,
    title: 'The Navigator',
    sortTitle: 'navigator',
    year: 1924,
    poster: null,
    status: MediaStatusInfo(pipeline: MediaPipeline.queued),
    added: '2026-09-27T10:00:00Z',
  ),
  (
    id: 10,
    title: 'The Sheik',
    sortTitle: 'sheik',
    year: 1921,
    poster: null,
    status: MediaStatusInfo(availability: MediaAvailability.available),
    added: '2026-08-20T10:00:00Z',
  ),
];

final _libraryProvider = FutureProvider<List<_Film>>((ref) async => _library);

/// The same library without its one-title sections, so a lettered wall shows
/// full rows: M, N and S only.
final _shelfProvider = FutureProvider<List<_Film>>(
  (ref) async => [
    for (final film in _library)
      if ('mns'.contains(film.sortTitle[0])) film,
  ],
);
final _emptyProvider = FutureProvider<List<_Film>>((ref) async => const []);
final _pendingProvider = FutureProvider<List<_Film>>(
  (ref) => Completer<List<_Film>>().future,
);
final _failingProvider = FutureProvider<List<_Film>>(
  (ref) async => throw Exception('Connection refused'),
  retry: noProviderRetry,
);
final _unconfiguredProvider = FutureProvider<List<_Film>>(
  (ref) async => throw Exception('Radarr not configured'),
  retry: noProviderRetry,
);

/// Each phone gets its own query, so typing into one does not search another.
final _queries = [
  for (var i = 0; i < 12; i++) StateProvider<String>((ref) => ''),
];

FutureProvider<List<_Film>?> _resultsFor(StateProvider<String> query) =>
    FutureProvider<List<_Film>?>((ref) async {
      final text = ref.watch(query).toLowerCase();
      if (text.isEmpty) return null;
      return [
        for (final film in _library)
          if (film.title.toLowerCase().contains(text)) film,
      ];
    });

const _kpis = AsyncValue<List<ServiceKpi>>.data([
  ServiceKpi(label: 'Movies', value: '1,284', icon: Icons.movie_rounded),
  ServiceKpi(
    label: 'Monitored',
    value: '1,190',
    icon: Icons.visibility_rounded,
  ),
  ServiceKpi(
    label: 'Missing',
    value: '37',
    icon: Icons.report_gmailerrorred_rounded,
    tone: StatusTone.neutral,
  ),
  ServiceKpi(label: 'Queue', value: '3', icon: Icons.download_rounded),
]);

final _results = [for (final query in _queries) _resultsFor(query)];

Widget _scaffold(
  int phone, {
  FutureProvider<List<_Film>>? library,
  bool peek = true,
  bool sorts = true,
  Set<int>? cutoff = const {5},
  MediaBrowseTileShape shape = MediaBrowseTileShape.poster,
  String title = 'Movies',
}) {
  return MediaBrowseScaffold<_Film>(
    title: title,
    searchHint: 'Search movies...',
    activityRoute: '/activity',
    navigationSection: NavigationSection.dashboard,
    serviceName: 'Radarr',
    accentColor: ServiceKey.radarr.accent,
    heroTagPrefix: 'movie',
    searchHeroTagPrefix: 'movie_search',
    libraryProvider: library ?? _libraryProvider,
    searchQueryProvider: _queries[phone],
    searchResultsProvider: _results[phone],
    titleExtractor: (film) => film.title,
    subtitleExtractor: (film) => '${film.year}',
    sortTitleExtractor: (film) => film.sortTitle,
    imagesExtractor: (film) => film.poster == null
        ? const []
        : [
            {'coverType': 'poster', 'remoteUrl': film.poster},
          ],
    idExtractor: (film) => film.id,
    statusExtractor: (film) => film.status,
    settingsSelector: (_) => ('', ''),
    onItemTap: (_, _, _) {},
    tileShape: shape,
    cutoffUnmetIds: cutoff,
    sorts: sorts
        ? [
            MediaBrowseSort<_Film>.dateAdded((film) => film.added),
            MediaBrowseSort<_Film>.year((film) => film.year),
          ]
        : const [],
    kpiPeek: peek
        ? ServiceKpiPeek(kpis: _kpis, accent: ServiceKey.radarr.accent)
        : null,
  );
}

/// A phone-sized screen: its own box and its own `MediaQuery`, so three can
/// stand side by side in one scene.
Widget _phone(Widget child) => Builder(
  builder: (context) => SizedBox(
    width: 390,
    height: 844,
    child: MediaQuery(
      data: MediaQuery.of(context).copyWith(size: const Size(390, 844)),
      child: ClipRect(child: child),
    ),
  ),
);

Widget _phones(List<Widget> screens) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    for (final (index, screen) in screens.indexed) ...[
      if (index > 0) const SizedBox(width: 24),
      _phone(screen),
    ],
  ],
);

/// Types [text] into the first text field below it once it has laid out, the
/// way a user would — the scaffold's field owns its own controller, so a
/// preset query would leave the field blank.
class _Typed extends StatefulWidget {
  const _Typed({required this.text, required this.child});

  final String text;
  final Widget child;

  @override
  State<_Typed> createState() => _TypedState();
}

class _TypedState extends State<_Typed> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      EditableTextState? field;
      void visit(Element element) {
        if (field != null) return;
        if (element is StatefulElement && element.state is EditableTextState) {
          field = element.state as EditableTextState;
          return;
        }
        element.visitChildren(visit);
      }

      context.visitChildElements(visit);
      field?.userUpdateTextEditingValue(
        TextEditingValue(
          text: widget.text,
          selection: TextSelection.collapsed(offset: widget.text.length),
        ),
        SelectionChangedCause.keyboard,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  catalogCard(
    'MediaBrowseScaffold',
    width: 1328,
    overrides: () async => [
      currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
    ],
    scenes: [
      CatalogScene(
        'MediaBrowseScaffold · library under Title A–Z, Lidarr\'s circular '
        'wall, then no sort choices and no cutoff source · letter headings '
        '(# for a digit) only over the alphabetical order; the sort control '
        'only with two orders',
        (_) => _phones([
          _scaffold(1, library: _shelfProvider),
          _scaffold(
            2,
            library: _shelfProvider,
            title: 'Artists',
            shape: MediaBrowseTileShape.circle,
            peek: false,
          ),
          _scaffold(3, sorts: false, cutoff: null, peek: false),
        ]),
      ),
      CatalogScene(
        'MediaBrowseScaffold · searching "Nosferatu", a search with no '
        'match, an empty library · results are a MediaGrid with compact '
        'badges; back arrow exits search',
        (_) => _phones([
          _Typed(text: 'Nosferatu', child: _scaffold(4)),
          _Typed(text: 'Wisborg', child: _scaffold(5)),
          _scaffold(6, library: _emptyProvider),
        ]),
      ),
      CatalogScene(
        'MediaBrowseScaffold · loading, a failed load, not configured · the '
        'wall defers to AsyncValueWidget; search and chips stay put',
        (_) => _phones([
          _scaffold(7, library: _pendingProvider),
          _scaffold(8, library: _failingProvider),
          _scaffold(9, library: _unconfiguredProvider),
        ]),
      ),
      CatalogScene(
        'MediaBrowseScaffold · 1280 desktop window · the wall sits in the '
        '1140 content well and adds columns at the 130 floor',
        (_) => _scaffold(10, library: _shelfProvider),
        width: 1280,
        height: 1000,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
