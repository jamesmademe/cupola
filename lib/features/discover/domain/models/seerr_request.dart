import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/discover/domain/seerr_numbering.dart';

export 'package:cupola/features/discover/domain/seerr_numbering.dart';

enum RequestStatus {
  pendingApproval,
  approved,
  declined,
  failed,
  completed,
  unknown;

  static RequestStatus fromCode(dynamic value) {
    int? intValue;
    if (value is int) {
      intValue = value;
    } else if (value is String) {
      intValue = int.tryParse(value);
    }

    switch (intValue) {
      case 1:
        return RequestStatus.pendingApproval;
      case 2:
        return RequestStatus.approved;
      case 3:
        return RequestStatus.declined;
      case 4:
        return RequestStatus.failed;
      case 5:
        return RequestStatus.completed;
      default:
        return RequestStatus.unknown;
    }
  }
}

/// What Seerr holds of a title: its `MediaStatus`, decoded.
///
/// The one place a Seerr media code becomes a state. Every badge, every
/// request row and the Request gate read it through [fromCode], so a title
/// cannot read "Deleted" on one surface and "Blocklisted" on another.
enum SeerrMediaAvailability {
  unknown,
  pending,
  processing,
  partiallyAvailable,
  available,

  /// On Seerr's blocklist: the operator barred it, and Seerr takes no request
  /// for it. Seerr's and Jellyseerr's 6; Overseerr has no such code.
  blocklisted,

  /// Its files were removed: requestable again. Overseerr's 6, Seerr's 7.
  deleted;

  /// Decodes [value], a code from a server with [numbering]
  /// (`SeerrNumbering.fromVersion`).
  ///
  /// With [numbering] null, the server has not said which it follows yet: a 6
  /// is either barred or deleted, and reads [unknown] rather than either
  /// guess. A 7 is deleted whatever the numbering, since only Seerr sends it.
  static SeerrMediaAvailability fromCode(
    Object? value, {
    required SeerrNumbering? numbering,
  }) {
    final code = value is int
        ? value
        : value is num
        ? value.toInt()
        : value is String
        ? int.tryParse(value)
        : null;

    return switch (code) {
      1 => SeerrMediaAvailability.unknown,
      2 => SeerrMediaAvailability.pending,
      3 => SeerrMediaAvailability.processing,
      4 => SeerrMediaAvailability.partiallyAvailable,
      5 => SeerrMediaAvailability.available,
      6 => switch (numbering) {
        SeerrNumbering.overseerr => SeerrMediaAvailability.deleted,
        SeerrNumbering.seerr => SeerrMediaAvailability.blocklisted,
        null => SeerrMediaAvailability.unknown,
      },
      7 => SeerrMediaAvailability.deleted,
      _ => SeerrMediaAvailability.unknown,
    };
  }

  String get label {
    switch (this) {
      case SeerrMediaAvailability.unknown:
        return 'Unknown';
      case SeerrMediaAvailability.pending:
        return StateWord.waitingForApproval.label;
      case SeerrMediaAvailability.processing:
        return 'Processing';
      case SeerrMediaAvailability.partiallyAvailable:
        return 'Partially available';
      case SeerrMediaAvailability.available:
        return 'Available';
      case SeerrMediaAvailability.blocklisted:
        return StateWord.blocklisted.label;
      case SeerrMediaAvailability.deleted:
        return 'Deleted';
    }
  }
}

class SeerrRequest {
  final int id;
  final RequestStatus status;
  final RequestMedia? media;
  final String createdAt;
  final int? profileId;
  final String? profileName;
  final List<RequestSeason>? seasons;
  final String type; // 'movie' or 'tv'
  final bool is4k;
  final int? serverId;
  final bool canRemove;
  final RequestedBy? requestedBy;

  const SeerrRequest({
    required this.id,
    required this.status,
    this.media,
    required this.createdAt,
    this.profileId,
    this.profileName,
    this.seasons,
    required this.type,
    this.is4k = false,
    this.serverId,
    this.canRemove = false,
    this.requestedBy,
  });

  /// [numbering] is the numbering of the server that sent [json], for its
  /// media's code: see [SeerrMediaAvailability.fromCode].
  factory SeerrRequest.fromJson(
    Map<String, dynamic> json, {
    SeerrNumbering? numbering,
  }) {
    return SeerrRequest(
      id: json['id'] ?? 0,
      status: RequestStatus.fromCode(json['status']),
      media: json['media'] != null
          ? RequestMedia.fromJson(json['media'], numbering: numbering)
          : null,
      createdAt: json['createdAt'] ?? '',
      profileId: json['profileId'],
      profileName: json['profileName'],
      seasons: (json['seasons'] as List<dynamic>?)
          ?.map((e) => RequestSeason.fromJson(e))
          .toList(),
      type: json['type'] ?? 'movie',
      is4k: _parseBool(json['is4k']),
      serverId: json['serverId'],
      canRemove: _parseBool(json['canRemove']),
      requestedBy: json['requestedBy'] != null
          ? RequestedBy.fromJson(json['requestedBy'])
          : null,
    );
  }

  // Allow enriching with new media (e.g. with title/poster metadata)
  SeerrRequest copyWith({RequestMedia? media}) {
    return SeerrRequest(
      id: id,
      status: status,
      media: media ?? this.media,
      createdAt: createdAt,
      profileId: profileId,
      profileName: profileName,
      seasons: seasons,
      type: type,
      is4k: is4k,
      serverId: serverId,
      canRemove: canRemove,
      requestedBy: requestedBy,
    );
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    return false;
  }
}

enum SeerrRequestDisplayKind {
  pending,
  approved,
  available,
  partiallyAvailable,
  processing,
  blocklisted,
  deleted,
  declined,
  failed,
  completed,
  unknown,
}

typedef SeerrRequestDisplayStatus = ({
  String label,
  SeerrRequestDisplayKind kind,
});

extension SeerrRequestDisplayStatusX on SeerrRequest {
  /// What Seerr holds of this request's title **at the request's own
  /// resolution**: the 4K state for a 4K request, the standard one otherwise.
  ///
  /// Seerr keeps the two apart on the media row (`status` and `status4k`), and
  /// a title can be on disk in HD while its 4K copy is still waiting for
  /// approval. Read through the standard field, that 4K request said
  /// "Available" for a file nobody had downloaded.
  SeerrMediaAvailability? get mediaAvailability {
    final media = this.media;
    if (media == null) return null;
    return is4k ? media.status4k : media.status;
  }

  SeerrRequestDisplayStatus get displayStatus {
    final mediaStatus = mediaAvailability;

    if (mediaStatus != null) {
      switch (mediaStatus) {
        case SeerrMediaAvailability.available:
          return (label: 'Available', kind: SeerrRequestDisplayKind.available);
        case SeerrMediaAvailability.partiallyAvailable:
          return (
            label: 'Partially available',
            kind: SeerrRequestDisplayKind.partiallyAvailable,
          );
        case SeerrMediaAvailability.processing:
          return (
            label: 'Processing',
            kind: SeerrRequestDisplayKind.processing,
          );
        case SeerrMediaAvailability.blocklisted:
          return (
            label: StateWord.blocklisted.label,
            kind: SeerrRequestDisplayKind.blocklisted,
          );
        case SeerrMediaAvailability.deleted:
          return (label: 'Deleted', kind: SeerrRequestDisplayKind.deleted);
        case SeerrMediaAvailability.pending:
          return (
            label: StateWord.waitingForApproval.label,
            kind: SeerrRequestDisplayKind.pending,
          );
        case SeerrMediaAvailability.unknown:
          break;
      }
    }

    switch (status) {
      case RequestStatus.pendingApproval:
        return (
          label: StateWord.waitingForApproval.label,
          kind: SeerrRequestDisplayKind.pending,
        );
      case RequestStatus.approved:
        return (label: 'Approved', kind: SeerrRequestDisplayKind.approved);
      case RequestStatus.declined:
        return (label: 'Declined', kind: SeerrRequestDisplayKind.declined);
      case RequestStatus.failed:
        return (label: 'Failed', kind: SeerrRequestDisplayKind.failed);
      case RequestStatus.completed:
        return (label: 'Completed', kind: SeerrRequestDisplayKind.completed);
      case RequestStatus.unknown:
        return (label: 'Unknown', kind: SeerrRequestDisplayKind.unknown);
    }
  }
}

class RequestMedia {
  final int? id; // Seerr internal media ID
  final String? title;
  final String? year;
  final int? tmdbId;
  final int? tvdbId;
  final SeerrMediaAvailability status;

  /// The 4K copy's state, Seerr's `status4k`: decoded with the same
  /// numbering as [status], and [SeerrMediaAvailability.unknown] when Seerr
  /// holds no 4K record of the title.
  final SeerrMediaAvailability status4k;
  final String? externalServiceSlug;
  final int? externalServiceId; // Radarr/Sonarr ID
  final String? mediaType;
  final String? posterPath;

  const RequestMedia({
    this.id,
    this.title,
    this.year,
    this.tmdbId,
    this.tvdbId,
    this.status = SeerrMediaAvailability.unknown,
    this.status4k = SeerrMediaAvailability.unknown,
    this.externalServiceSlug,
    this.externalServiceId,
    this.mediaType,
    this.posterPath,
  });

  factory RequestMedia.fromJson(
    Map<String, dynamic> json, {
    SeerrNumbering? numbering,
  }) {
    // Basic fields
    final id = json['id'] as int?;
    final tmdbId = json['tmdbId'];
    final tvdbId = json['tvdbId'];
    final status = SeerrMediaAvailability.fromCode(
      json['status'],
      numbering: numbering,
    );
    final status4k = SeerrMediaAvailability.fromCode(
      json['status4k'],
      numbering: numbering,
    );
    final slug = json['externalServiceSlug']?.toString();
    final externalServiceId = json['externalServiceId'] as int?;
    final mediaType = json['mediaType']?.toString();

    // Initial title attempt (unlikely to be here based on JSON)
    String? title = json['title'] ?? json['name'];
    String? year = json['year']?.toString() ?? json['releaseDate']?.toString();
    final posterPath =
        json['posterPath']?.toString() ?? json['poster_path']?.toString();

    return RequestMedia(
      id: id,
      title: title, // Can be null, service will fetch
      year: year,
      tmdbId: tmdbId,
      tvdbId: tvdbId,
      status: status,
      status4k: status4k,
      externalServiceSlug: slug,
      externalServiceId: externalServiceId,
      mediaType: mediaType,
      posterPath: posterPath,
    );
  }

  RequestMedia copyWith({String? title, String? year, String? posterPath}) {
    return RequestMedia(
      id: id,
      title: title ?? this.title,
      year: year ?? this.year,
      tmdbId: tmdbId,
      tvdbId: tvdbId,
      status: status,
      status4k: status4k,
      externalServiceSlug: externalServiceSlug,
      externalServiceId: externalServiceId,
      mediaType: mediaType,
      posterPath: posterPath ?? this.posterPath,
    );
  }
}

class RequestSeason {
  final int seasonNumber;
  final String status;

  const RequestSeason({required this.seasonNumber, required this.status});

  factory RequestSeason.fromJson(Map<String, dynamic> json) {
    return RequestSeason(
      seasonNumber: json['seasonNumber'] ?? 0,
      status: json['status']?.toString() ?? 'Unknown',
    );
  }
}

/// Represents the user who made a request.
class RequestedBy {
  final int id;
  final String displayName;
  final String? avatar;

  const RequestedBy({required this.id, required this.displayName, this.avatar});

  factory RequestedBy.fromJson(Map<String, dynamic> json) {
    return RequestedBy(
      id: json['id'] ?? 0,
      displayName: json['displayName'] ?? json['username'] ?? 'Unknown',
      avatar: json['avatar']?.toString(),
    );
  }
}
