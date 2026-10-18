import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/readarr/presentation/readarr_search_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// `3/12 books · 4 missing`: the caption under an author's portrait.
///
/// Top-level and pure so the wording is assertable without a pumped wall, as
/// `lidarrArtistCaption` is. The counts are the ones the row has always shown;
/// the missing part is left out when nothing is.
///
/// An author with no book counted reads an em dash. Readarr's `statistics`
/// can be absent (an author it has not scanned yet) and the model reads an
/// absent count as zero, so `0/0 books` would assert a fact nobody reported.
String readarrAuthorCaption(ReadarrAuthor author) {
  if (author.bookCount <= 0) return Lexicon.noFigure;
  return [
    '${author.bookFileCount}/${author.bookCount} books',
    if (author.missingBookCount > 0)
      '${author.missingBookCount} ${StateWord.missing.inline}',
  ].join(dotSeparator);
}

/// Readarr's Library tab: the full author list, on the wall every other
/// library stands on.
///
/// It was a page pushed from the dashboard's "Authors" section and is now the
/// root of a branch, at the same path it always had. Two things follow from
/// that and both are why this class grew parameters.
///
/// **What it leaves out, and why.** No badge: Readarr's queue is indexed by
/// *book* (`readarrQueueSnapshotForProvider`), so an author's badge would
/// ignore the queue, and a badge that ignores the queue says Missing for an
/// author whose books are downloading. With no status the wall draws none of
/// the chips that ask one either (see `MediaBrowseScaffold.statusExtractor`).
/// No lookup: Readarr's metadata host no longer answers, so the search is the
/// library's own (`readarrSearchResultsProvider`).
class ReadarrLibraryScreen extends ConsumerWidget {
  /// Whether to draw this screen's own app bar.
  ///
  /// False inside the tab shell, where `ServiceHomeScreen` draws the service
  /// band and `ServiceTabScaffold` the tab bar above it: a third bar of its own
  /// would put two titles and two back chevrons in one corner.
  final bool showAppBar;

  /// Room those two glass bands take above this page, since they float over it
  /// rather than pushing it down.
  final double topPadding;

  const ReadarrLibraryScreen({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The configured check comes first, as it does on every other service's
    // landing surface: `readarrServiceProvider` throws for a Readarr that was
    // never set up, so without this the tab would answer a question about an
    // unreachable server with "Failed to load authors": an error about a
    // request that was never worth making.
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.readarr),
      ),
    );
    if (!configured) {
      return AmbientScaffold(
        accent: ServiceKey.readarr.accent,
        appBar: showAppBar ? const GlassAppBar(title: Text('Authors')) : null,
        // `.forService`, never the generic form: the door goes to Readarr's own
        // connection form rather than to the settings index.
        body: SafeArea(
          child: NotConfiguredPlaceholder.forService(ServiceKey.readarr),
        ),
      );
    }

    final lens =
        ref.watch(activeInstanceProvider(ServiceKey.readarr))?.id ?? '';
    // Which of its addresses the lens's connection is reached at: the
    // photos go where the library is read from.
    final route = ref.watch(connectionRouteProvider(lens));

    return MediaBrowseScaffold<ReadarrAuthor>(
      title: 'Authors',
      searchHint: 'Search authors',
      activityRoute: '${ServiceRoutes.readarr}/queue',
      navigationSection: NavigationSection.stack,
      serviceName: 'Readarr',
      service: ServiceKey.readarr,
      accentColor: ServiceKey.readarr.accent,
      heroTagPrefix: 'author',
      searchHeroTagPrefix: 'author_search',
      libraryProvider: readarrAuthorsProvider,
      searchQueryProvider: readarrSearchQueryProvider,
      searchResultsProvider: readarrSearchResultsProvider,
      titleExtractor: (author) => author.authorName,
      subtitleExtractor: readarrAuthorCaption,
      sortTitleExtractor: (author) => author.authorName,
      imagesExtractor: (author) => author.images,
      idExtractor: (author) => author.id,
      onRefresh: (ref) {
        // The rail above this wall reads its own non-swallowing copy of the
        // library. See `movies_screen.dart`. Today it is the same provider
        // the scaffold already invalidated, and stays named so the rail keeps
        // refreshing if the two are ever split.
        ref.invalidate(readarrKpiLibraryProvider);
      },
      // The connection the wall shows, which is the lens's, never the first
      // one's: see `movies_screen.dart`.
      settingsSelector: (settings) => settings.artworkKeyOf(lens, route),
      onItemTap: (context, author, heroTag) {
        // The author's own page, under this tab, opened on this Readarr's
        // copy.
        context.push(
          ServiceRoutes.readarrAuthor(
            author.id,
            heroTag: heroTag,
            instanceId: lens.isEmpty ? null : lens,
          ),
          extra: author,
        );
      },
      // The author's photo, as the author's page draws it: the same picture
      // on the wall and under the name, never a banner cropped to a circle.
      coverTypes: const ['poster'],
      // An author is not a poster: see `MusicScreen`, whose artists are drawn
      // the same way for the same reason.
      tileShape: MediaBrowseTileShape.circle,
      emptyIcon: Icons.menu_book_outlined,
      // Cupola manages Readarr's library but adds no one to it (its metadata
      // source is gone), so an empty shelf points to Readarr itself.
      emptyMessage: 'Authors are added in Readarr itself.',
      showAppBar: showAppBar,
      topPadding: topPadding,
      sorts: [
        MediaBrowseSort<ReadarrAuthor>.dateAdded((author) => author.added),
        MediaBrowseSort<ReadarrAuthor>.size((author) => author.sizeOnDisk),
      ],
      kpiPeek: ServiceKpiPeek(
        kpis: ref.watch(serviceKpiProvider(ServiceKey.readarr)),
        service: ServiceKey.readarr,
      ),
    );
  }
}
