import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';

/// Service for interacting with the Readarr API (v1).
///
/// Reuses the shared *arr contract via [ArrActivityMixin] (queue, history,
/// wanted, releases). Readarr is archived upstream but its v1 API is unchanged,
/// so the same header-auth [ApiClient] and mixin apply as for Lidarr.
///
/// The tab surfaces are backed by the shared activity mixin and the dedicated
/// presentation screens; an author's page by the author, their books and the
/// writes below. Readarr is archived upstream and its metadata host no longer
/// answers, so nothing here looks a new book up: what is in the library, and
/// searching the indexers for a book it already knows, still work.
///
/// - the writes: `PUT /api/v1/author/{id}` for monitor and profile,
///   `POST /api/v1/command` for the searches, `DELETE /api/v1/author/{id}`.
class ReadarrService with ArrActivityMixin {
  ReadarrService(this.client);

  @override
  final ApiClient client;

  @override
  final ArrServiceConfig config = ArrServiceConfig.readarr;

  /// Asks for the book and the author with every queue record.
  ///
  /// A Readarr queue record on its own carries `bookId`/`authorId` and the raw
  /// release name, nothing else, so a row built from it could only print
  /// `Orbital.2023.RETAIL.EPUB-XYZ`. The embeds are what turn that back into
  /// `Import failed · Orbital`, and they only ride along when the request asks
  /// for them, exactly as Sonarr must ask for `includeSeries`/`includeEpisode`.
  /// On the page primitive, which `getQueue` delegates to, so a count and its
  /// rows both carry them.
  @override
  Future<ArrRecordPage> getQueuePage({Map<String, dynamic>? queryParameters}) {
    return super.getQueuePage(
      queryParameters: {
        'includeBook': true,
        'includeAuthor': true,
        ...?queryParameters,
      },
    );
  }

  /// On the **page** primitive, not on `getHistory`.
  ///
  /// `getHistory` delegates here, so both spellings pick the parameters up,
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
  /// The degrading read: answers `[]` when the library cannot be read. The
  /// author list and every *figure* use [getAuthorsOrThrow]; nothing in the
  /// app reads this one today.
  Future<List<ReadarrAuthor>> getAuthors() {
    return fetchAllItems('author', ReadarrAuthor.fromJson);
  }

  /// The same library, with a failed fetch allowed to reach the caller.
  ///
  /// See [fetchAllItemsOrThrow].
  Future<List<ReadarrAuthor>> getAuthorsOrThrow() {
    return fetchAllItemsOrThrow('author', ReadarrAuthor.fromJson);
  }

  /// One author, letting a failure reach the caller: their page says why it
  /// could not read the record rather than that there is none.
  Future<ReadarrAuthor> getAuthorOrThrow(int authorId) =>
      fetchItemOrThrow('author', authorId, ReadarrAuthor.fromJson);

  /// An author's books, every one Readarr knows of.
  Future<List<ReadarrBook>> getBooks(int authorId) =>
      fetchListItems('book', {'authorId': authorId}, ReadarrBook.fromJson);

  Future<List<Map<String, dynamic>>> getQualityProfiles() =>
      fetchQualityProfiles();

  Future<void> updateAuthorMonitored(int authorId, bool monitored) =>
      updateItemMonitored('author', authorId, monitored);

  Future<void> updateAuthorProfile(int authorId, int qualityProfileId) =>
      updateItemProfile('author', authorId, qualityProfileId);

  /// Asks the indexers for [bookIds], each as the book Readarr knows.
  Future<void> searchBooks(List<int> bookIds) async {
    await client.post(
      '/api/v1/command',
      data: {'name': 'BookSearch', 'bookIds': bookIds},
    );
  }

  /// Asks the indexers for every monitored book of an author's.
  Future<void> searchAuthor(int authorId) async {
    await client.post(
      '/api/v1/command',
      data: {'name': 'AuthorSearch', 'authorId': authorId},
    );
  }

  Future<void> deleteAuthor(
    int authorId, {
    bool deleteFiles = false,
    bool addImportListExclusion = false,
  }) async {
    await client.delete(
      '/api/v1/author/$authorId',
      queryParameters: {
        'deleteFiles': deleteFiles,
        'addImportListExclusion': addImportListExclusion,
      },
    );
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
