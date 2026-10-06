import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';

/// Where one movie of a collection stands, as Seerr's record of it says.
enum CollectionPartStand {
  /// On the server, whole or in part.
  onServer,

  /// Approved and being fetched.
  onTheWay,

  /// Asked for, and waiting for someone to approve it.
  waiting,

  /// Neither there nor asked for.
  missing,
}

/// One movie of a collection and where it stands.
typedef CollectionPart = ({
  MediaPreview media,
  int? year,
  CollectionPartStand stand,
});

/// A collection as its page shows it: the movies in release order, and how
/// many of them are on the server, on their way and waiting for approval.
///
/// Read from Seerr's record of each movie, which comes with the collection:
/// every count is exact.
class CollectionShelf {
  const CollectionShelf._(this.parts);

  /// [numbering] decodes the codes as the Seerr that sent them means them.
  factory CollectionShelf.of(
    CollectionDetail collection, {
    SeerrNumbering? numbering,
  }) {
    final parts = <CollectionPart>[
      for (final media in collection.parts)
        (
          media: media,
          year: int.tryParse(media.year),
          stand: _standOf(media.mediaInfo, numbering),
        ),
    ];
    parts.sort((a, b) {
      if (a.year == null || b.year == null) {
        return (a.year == null ? 1 : 0) - (b.year == null ? 1 : 0);
      }
      return (a.media.releaseDate ?? '').compareTo(b.media.releaseDate ?? '');
    });
    return CollectionShelf._(parts);
  }

  /// The movies, oldest first; one with no date yet goes last.
  final List<CollectionPart> parts;

  int count(CollectionPartStand stand) =>
      parts.where((part) => part.stand == stand).length;

  /// Whether the atrium may invite the operator to complete it: some of it
  /// is on the server, and its page has something left to do, a movie to add
  /// or a request to answer. Movies on their way leave nothing to do.
  bool get invitesCompletion =>
      count(CollectionPartStand.onServer) > 0 &&
      count(CollectionPartStand.missing) + count(CollectionPartStand.waiting) >
          0;

  /// The years the collection spans, `2006–2022`; one year when they all
  /// came out in it; empty with no dates.
  String get span {
    final years = [for (final part in parts) ?part.year];
    if (years.isEmpty) return '';
    final first = years.reduce((a, b) => a < b ? a : b);
    final last = years.reduce((a, b) => a > b ? a : b);
    return first == last ? '$first' : '$first–$last';
  }

  /// What sits under the collection's name: `Collection · 8 movies ·
  /// 2006–2022`.
  String get summary => [
    'Collection',
    '${parts.length} ${parts.length == 1 ? 'movie' : 'movies'}',
    if (span.isNotEmpty) span,
  ].join(' · ');

  static CollectionPartStand _standOf(
    Map<String, dynamic>? mediaInfo,
    SeerrNumbering? numbering,
  ) {
    if (seerrHolds(mediaInfo, numbering: numbering)) {
      return CollectionPartStand.onServer;
    }
    final code = intOrNull(mediaInfo?['status']);
    if (code == null) return CollectionPartStand.missing;
    return switch (SeerrMediaAvailability.fromCode(
      code,
      numbering: numbering,
    )) {
      SeerrMediaAvailability.available ||
      SeerrMediaAvailability.partiallyAvailable => CollectionPartStand.onServer,
      SeerrMediaAvailability.processing => CollectionPartStand.onTheWay,
      SeerrMediaAvailability.pending => CollectionPartStand.waiting,
      _ => CollectionPartStand.missing,
    };
  }
}
