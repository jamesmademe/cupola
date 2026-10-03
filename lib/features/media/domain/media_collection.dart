import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/discover/domain/seerr_numbering.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';

/// How much of a collection the household holds: what `5 of 8 on your server`
/// says.
typedef MediaCollectionHeld = ({int held, int total});

/// The members of a collection, as Seerr's `/collection/:id` answered them
/// ([json]), counted by the status Seerr attaches to each: a member is held
/// when it is available, whole or in part, in either quality. Null when Seerr
/// answered that it has no such collection, or one with no members: no figure
/// to state.
MediaCollectionHeld? mediaCollectionHeld(
  Map<String, dynamic> json, {
  SeerrNumbering? numbering,
}) {
  final parts = [
    for (final part in json['parts'] as List<dynamic>? ?? const [])
      if (part is Map) part.cast<String, dynamic>(),
  ];
  if (parts.isEmpty) return null;
  bool onServer(MediaStatusInfo status) =>
      status.availability == MediaAvailability.available ||
      status.availability == MediaAvailability.partial;
  var held = 0;
  for (final part in parts) {
    final info = part['mediaInfo'];
    final media = info is Map ? info.cast<String, dynamic>() : null;
    // A member held only in 4K is on the server too.
    if (onServer(seerrMediaStatus(media, numbering: numbering)) ||
        onServer(seerrMediaStatus(media, is4k: true, numbering: numbering))) {
      held++;
    }
  }
  return (held: held, total: parts.length);
}
