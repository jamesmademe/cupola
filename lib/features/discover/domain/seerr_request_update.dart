import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The body of `PUT /api/v1/request/{id}` that sends [request] to [server],
/// with [profileId] and [rootFolder], before it is approved.
///
/// Checked against Seerr's API (`seerr-api.yml`, `PUT /request/{requestId}`:
/// `mediaType` required; `seasons`, `is4k`, `serverId`, `profileId`,
/// `rootFolder`, `languageProfileId`, `userId` optional) and its route
/// (`server/routes/request.ts`), which goes further than the spec in two
/// ways this body answers:
///
/// * it writes every field from the body, so a field left out is written
///   as missing. Every field the request already carries goes back as it
///   was, `tags` included, which the route reads though the spec does not
///   list it; `userId` is left out, so the requester stays;
/// * a series edit **requires** `seasons` and throws without them. The
///   request's own seasons go back unchanged; a series request that carries
///   none is refused here, before anything is sent.
///
/// `is4k` is sent as the request has it: the route does not change a
/// request's copy, which is why [server] must take the same copy.
///
/// Throws [ArgumentError] for a [server] of the wrong kind or the wrong copy,
/// and for a series request with no seasons.
Map<String, dynamic> seerrRequestUpdateBody(
  SeerrRequest request, {
  SeerrArrServer? server,
  int? profileId,
  String? rootFolder,
}) {
  final isSeries = request.type == 'tv';
  if (server != null) {
    final arr = isSeries ? ServiceKey.sonarr : ServiceKey.radarr;
    if (server.service != arr) {
      throw ArgumentError.value(
        server.name,
        'server',
        'A ${isSeries ? 'series' : 'movie'} request goes to ${arr.title}',
      );
    }
    if (server.is4k != request.is4k) {
      // Seerr would send the request there and go on tracking it on the
      // other copy of the title.
      throw ArgumentError.value(
        server.name,
        'server',
        request.is4k
            ? 'A 4K request goes to a 4K server'
            : 'A standard request goes to a standard server',
      );
    }
  }

  final seasons = [
    for (final season in request.seasons ?? const <RequestSeason>[])
      season.seasonNumber,
  ];
  if (isSeries && seasons.isEmpty) {
    throw ArgumentError.value(
      request.id,
      'request',
      'A series request is changed with its seasons, and this one has none',
    );
  }

  final serverId = server?.id ?? request.serverId;
  final profile = profileId ?? request.profileId;
  final folder = rootFolder ?? request.rootFolder;
  final languageProfileId = request.languageProfileId;
  final tags = request.tags;
  return {
    'mediaType': isSeries ? 'tv' : 'movie',
    'is4k': request.is4k,
    if (isSeries) 'seasons': seasons,
    'serverId': ?serverId,
    'profileId': ?profile,
    'rootFolder': ?folder,
    if (isSeries) 'languageProfileId': ?languageProfileId,
    'tags': ?tags,
  };
}
