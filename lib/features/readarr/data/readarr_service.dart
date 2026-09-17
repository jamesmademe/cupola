import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';

/// Service for interacting with the Readarr API (v1).
///
/// Reuses the shared *arr contract via [ArrActivityMixin] (queue, history,
/// wanted, releases). Readarr is archived upstream but its v1 API is unchanged,
/// so the same header-auth [ApiClient] and mixin apply as for Lidarr.
///
/// **What full parity with the other three \*arr still needs, and none of it
/// is UI work.** The list moved here when the pre-tab-model home it used to
/// live on was retired: every item is a call this class does not make, which
/// is why the Calendar, Queue, Wanted and History tabs are still placeholders
/// and why the Overview draws neither `Coming up` nor `Recently added`.
/// Archived upstream makes it a *fixed* target rather than a moving one —
/// decision 13 in `context/decisions.md`.
///
/// - `getAuthor(id)` — this class has [getAuthors] and nothing per-author, so
///   an author detail page has no first fetch. `GET /api/v1/author/{id}`.
/// - a book list — `GET /api/v1/book` (optionally `?authorId=`), plus a
///   `ReadarrBook` model. Today `ReadarrAuthor` is the only library entity,
///   and it carries neither a release date nor a cover.
/// - the calendar — `GET /api/v1/calendar`, the same shape and the same
///   builder the other three \*arr need and none of them calls yet.
/// - wanted and cutoff — `getMissingPage`/`getCutoffPage` already exist on the
///   shared base, so these are provider and screen work, not client work.
/// - the writes — `PUT /api/v1/author` for monitor and profile,
///   `POST /api/v1/command` for the searches, `DELETE /api/v1/author/{id}`,
///   and the manual-import routes.
class ReadarrService with ArrActivityMixin {
  ReadarrService(this.client);

  @override
  final ApiClient client;

  @override
  final ArrServiceConfig config = ArrServiceConfig.readarr;

  /// Asks for the book and the author with every queue record.
  ///
  /// A Readarr queue record on its own carries `bookId`/`authorId` and the raw
  /// release name, nothing else — so a row built from it could only print
  /// `Orbital.2023.RETAIL.EPUB-XYZ`. The embeds are what turn that back into
  /// `Import failed · Orbital`, and they only ride along when the request asks
  /// for them, exactly as Sonarr must ask for `includeSeries`/`includeEpisode`.
  @override
  Future<List<dynamic>> getQueue({Map<String, dynamic>? queryParameters}) {
    return super.getQueue(
      queryParameters: {
        'includeBook': true,
        'includeAuthor': true,
        ...?queryParameters,
      },
    );
  }

  /// On the **page** primitive, not on `getHistory`.
  ///
  /// `getHistory` delegates here, so both spellings pick the parameters up —
  /// but only this way round. Hung off `getHistory` instead, a caller reaching
  /// for `getHistoryPage` (the one carrying the envelope's total, and therefore
  /// the only one a count may be derived from) would get records with no
  /// embedded `book` and no embedded `author`. `base_arr_service.dart` warns
  /// about precisely this.
  @override
  Future<ArrRecordPage> getHistoryPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) {
    return super.getHistoryPage(
      page: page,
      pageSize: pageSize,
      queryParameters: {
        'includeBook': true,
        'includeAuthor': true,
        ...?queryParameters,
      },
    );
  }

  @override
  Future<List<dynamic>> getAllHistory({Map<String, dynamic>? queryParameters}) {
    return super.getAllHistory(
      queryParameters: {
        'includeBook': true,
        'includeAuthor': true,
        ...?queryParameters,
      },
    );
  }

  /// Fetches all authors (the primary library entity).
  ///
  /// The degrading read: answers `[]` when the library cannot be read. Callers
  /// that derive a *figure* use [getAuthorsOrThrow].
  Future<List<ReadarrAuthor>> getAuthors() {
    return fetchAllItems('author', ReadarrAuthor.fromJson);
  }

  /// The same library, with a failed fetch allowed to reach the caller.
  ///
  /// See [fetchAllItemsOrThrow].
  Future<List<ReadarrAuthor>> getAuthorsOrThrow() {
    return fetchAllItemsOrThrow('author', ReadarrAuthor.fromJson);
  }

  /// Fetches recent history mapped to typed items for the dashboard.
  Future<List<ReadarrHistoryItem>> getRecentHistory({int pageSize = 20}) async {
    final records = await getHistory(page: 1, pageSize: pageSize);
    return records
        .whereType<Map>()
        .map((e) => ReadarrHistoryItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }
}
