/// A Seerr request as the requester's Home keeps it: the fields her two
/// modules draw, and nothing else.
///
/// Seerr's request carries more than the Home needs and more than should be
/// written to a file: who asked (`requestedBy`), the server and the folder it
/// is sent to, the arr's copies and, for a title on its way, the downloads
/// Seerr follows, whose release names are never read. None of it is kept. The
/// downloads in particular are what runs (a percentage, a time left), and a
/// drawing is not a thing that runs: a request that was downloading is drawn
/// as what it is to her without a figure, on its way.
///
/// Times are kept as instants (the words, `Asked 2 h ago`, are made again
/// against the time of the drawing). The link to the title in her player is
/// kept so Watch stays where it was, unless it carries a credential.
library;

import 'package:cupola/core/last_known/stored_image.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';

Map<String, Object?> seerrRequestToJson(SeerrRequest request) {
  final media = request.media;
  return {
    'id': request.id,
    'status': request.status.name,
    'type': request.type,
    'is4k': request.is4k,
    'createdAt': ?_instantOf(request.createdAt),
    'updatedAt': ?_instantOf(request.updatedAt),
    if (media != null)
      'media': {
        'title': ?media.title,
        'tmdbId': ?media.tmdbId,
        'status': media.status.name,
        'status4k': media.status4k.name,
        'mediaType': ?media.mediaType,
        'posterPath': ?media.posterPath,
        'backdropPath': ?media.backdropPath,
        'voteAverage': ?media.voteAverage,
        'voteCount': ?media.voteCount,
        'addedAt': ?media.addedAt?.toUtc().toIso8601String(),
        'mediaUrl': ?_linkWorthKeeping(media.mediaUrl),
        'mediaUrl4k': ?_linkWorthKeeping(media.mediaUrl4k),
      },
  };
}

/// [json] read back; null for a record this version cannot read whole.
SeerrRequest? seerrRequestFromJson(Object? json) {
  if (json is! Map) return null;
  final status = RequestStatus.values.asNameMap()[json['status']];
  final id = json['id'];
  final type = json['type'];
  if (status == null || id is! int || type is! String || type.isEmpty) {
    return null;
  }
  final media = json['media'];
  RequestMedia? readMedia() {
    if (media is! Map) return null;
    final availability = SeerrMediaAvailability.values.asNameMap();
    final readStatus = availability[media['status']];
    final readStatus4k = availability[media['status4k']];
    if (readStatus == null || readStatus4k == null) return null;
    return RequestMedia(
      title: _text(media['title']),
      tmdbId: _number(media['tmdbId']),
      status: readStatus,
      status4k: readStatus4k,
      mediaType: _text(media['mediaType']),
      posterPath: _text(media['posterPath']),
      backdropPath: _text(media['backdropPath']),
      voteAverage: switch (media['voteAverage']) {
        final num value => value.toDouble(),
        _ => null,
      },
      voteCount: _number(media['voteCount']),
      addedAt: _instant(media['addedAt']),
      mediaUrl: _text(media['mediaUrl']),
      mediaUrl4k: _text(media['mediaUrl4k']),
    );
  }

  // A record that says it has a media and cannot give it whole is not read.
  final readMediaOrNull = readMedia();
  if (media != null && readMediaOrNull == null) return null;
  return SeerrRequest(
    id: id,
    status: status,
    media: readMediaOrNull,
    createdAt: _text(json['createdAt']) ?? '',
    type: type,
    is4k: json['is4k'] == true,
    updatedAt: _text(json['updatedAt']),
  );
}

String? _instantOf(String? raw) =>
    DateTime.tryParse(raw ?? '')?.toUtc().toIso8601String();

DateTime? _instant(Object? raw) => switch (raw) {
  final String text => DateTime.tryParse(text)?.toLocal(),
  _ => null,
};

String? _text(Object? raw) => switch (raw) {
  final String text when text.isNotEmpty => text,
  _ => null,
};

int? _number(Object? raw) => switch (raw) {
  final int number => number,
  _ => null,
};

/// [url] when it can be kept: an address with no user, and no key or token in
/// its query or in the query that Jellyfin's and Plex's own links carry after
/// the `#`. A link that cannot be kept is no Watch in the drawing, and Details
/// stays.
String? _linkWorthKeeping(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.userInfo.isNotEmpty) return null;
  if (StoredImage.carriesCredential(url)) return null;
  final fragment = uri.fragment;
  final at = fragment.indexOf('?');
  if (at >= 0) {
    final query = fragment.substring(at + 1);
    if (StoredImage.carriesCredential('https://example.invalid/?$query')) {
      return null;
    }
  }
  return url;
}
