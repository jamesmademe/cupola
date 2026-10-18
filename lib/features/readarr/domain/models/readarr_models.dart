/// Typed models for the Readarr API (v1).
///
/// Readarr shares the *arr contract with Radarr/Sonarr/Lidarr. The project is
/// archived upstream, but the v1 API remains functional; these models cover the
/// dashboard (authors, recent history) and an author's page (their books).
library;

import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// An author (the primary library entity in Readarr, analogous to a Lidarr
/// artist). Books live under authors.
class ReadarrAuthor {
  const ReadarrAuthor({
    required this.id,
    required this.authorName,
    required this.monitored,
    required this.bookCount,
    required this.bookFileCount,
    this.overview,
    this.status,
    this.path,
    this.images = const [],
    this.qualityProfileId,
    this.titleSlug,
    this.sizeOnDisk = 0,
    this.added,
  });

  final int id;
  final String authorName;
  final bool monitored;

  /// Total number of books tracked for this author.
  final int bookCount;

  /// Number of books that have a downloaded file on disk.
  final int bookFileCount;

  final String? overview;
  final String? status;

  /// Where the author's books are filed on the server.
  final String? path;

  /// Readarr's pictures of the author: `poster` is their photo.
  final List<dynamic> images;

  final int? qualityProfileId;

  /// The author's address in Readarr's own web app: `/author/<titleSlug>`.
  final String? titleSlug;

  /// What the author's files take on disk, in bytes.
  final int sizeOnDisk;

  /// When the author joined the library, as Readarr writes it (an ISO
  /// string), or null when it does not say.
  final String? added;

  /// Monitored books still missing a file.
  int get missingBookCount => (bookCount - bookFileCount).clamp(0, bookCount);

  factory ReadarrAuthor.fromJson(Map<String, dynamic> json) {
    final stats = json['statistics'];
    final statsMap = stats is Map<String, dynamic>
        ? stats
        : const <String, dynamic>{};
    return ReadarrAuthor(
      id: intOrNull(json['id']) ?? 0,
      authorName:
          (json['authorName'] ??
                  json['authorNameLastFirst'] ??
                  'Unknown author')
              .toString(),
      monitored: json['monitored'] == true,
      bookCount:
          intOrNull(statsMap['bookCount'] ?? statsMap['totalBookCount']) ?? 0,
      bookFileCount: intOrNull(statsMap['bookFileCount']) ?? 0,
      overview: json['overview']?.toString(),
      status: json['status']?.toString(),
      path: json['path']?.toString(),
      images: json['images'] is List ? json['images'] as List : const [],
      qualityProfileId: intOrNull(json['qualityProfileId']),
      titleSlug: json['titleSlug']?.toString(),
      sizeOnDisk: intOrNull(statsMap['sizeOnDisk']) ?? 0,
      added: json['added']?.toString(),
    );
  }
}

/// A book of an author's, as `GET /api/v1/book?authorId=` lists it.
class ReadarrBook {
  const ReadarrBook({
    required this.id,
    required this.title,
    required this.monitored,
    required this.bookFileCount,
    this.releaseDate,
    this.images = const [],
  });

  final int id;
  final String title;
  final bool monitored;

  /// How many files of the book are on disk: a book with one is on disk.
  final int bookFileCount;

  final String? releaseDate;

  /// Readarr's pictures of the book: `cover` is its cover.
  final List<dynamic> images;

  bool get onDisk => bookFileCount > 0;

  /// The year it came out, or null when Readarr does not say.
  int? get year => DateTime.tryParse(releaseDate ?? '')?.year;

  factory ReadarrBook.fromJson(Map<String, dynamic> json) {
    final stats = json['statistics'];
    final title = json['title']?.toString().trim() ?? '';
    return ReadarrBook(
      id: intOrNull(json['id']) ?? 0,
      title: title.isEmpty ? 'Unknown book' : title,
      monitored: json['monitored'] == true,
      bookFileCount: stats is Map ? intOrNull(stats['bookFileCount']) ?? 0 : 0,
      releaseDate: json['releaseDate']?.toString(),
      images: json['images'] is List ? json['images'] as List : const [],
    );
  }
}

/// A single Readarr history record, used for the "Recent Activity" section.
///
/// The `data` payload varies per `eventType`; only the stable fields are typed.
class ReadarrHistoryItem {
  const ReadarrHistoryItem({
    required this.id,
    required this.eventType,
    this.sourceTitle,
    this.date,
    this.authorName,
  });

  final int id;
  final String eventType;
  final String? sourceTitle;
  final DateTime? date;
  final String? authorName;

  factory ReadarrHistoryItem.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    return ReadarrHistoryItem(
      id: intOrNull(json['id']) ?? 0,
      eventType: (json['eventType'] ?? 'unknown').toString(),
      sourceTitle: json['sourceTitle']?.toString(),
      date: DateTime.tryParse(json['date']?.toString() ?? ''),
      authorName: author is Map
          ? author['authorName']?.toString()
          : json['authorTitle']?.toString(),
    );
  }
}
