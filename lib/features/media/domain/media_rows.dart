import 'package:cupola/features/discover/domain/seerr_media_copy.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One row of a Media page's "On your server": one fact, from one source.
///
/// Each row declares its case before it is drawn (brand book,
/// *Configurations*): a connection Cupola has and what it said (cases c, d, e
/// travel in its reading), a claim Seerr makes about a server Cupola does not
/// have (case b), or a service nobody set up (case a). Case f draws no row.
sealed class MediaRow {
  const MediaRow();

  /// The service the row speaks for.
  ServiceKey get service;
}

/// A connection Cupola has, and its reading of the title.
///
/// [T] is the source's fact: `MediaRadarrCopy`, `MediaStreamCopy`,
/// `MediaBazarrCopy?` or `MediaSeerrRecord`.
final class MediaConnectionRow<T> extends MediaRow {
  const MediaConnectionRow(this.connection, this.reading);

  final ServiceInstance connection;
  final MediaReading<T> reading;

  @override
  ServiceKey get service => connection.service;
}

/// Case b: a copy Seerr says an arr holds, on a server Cupola has no
/// connection to. Seerr's word, attributed, with one quiet way to set the
/// server up (rule 9); never drawn as set up.
final class MediaThroughSeerrRow extends MediaRow {
  const MediaThroughSeerrRow({
    required this.seerr,
    required this.copy,
    required this.mediaInfo,
  });

  /// The Seerr connection that made the claim.
  final ServiceInstance seerr;

  /// The copy, bound to Seerr's server for it.
  final SeerrBoundCopy copy;

  /// Seerr's media row, for the copy's status (`status` or `status4k`).
  final Map<String, dynamic>? mediaInfo;

  @override
  ServiceKey get service => copy.arr;
}

/// Case a: [service] is not set up and nothing else knows it. One dimmed,
/// tappable row that opens its setup form (rule 3).
final class MediaNotSetUpRow extends MediaRow {
  const MediaNotSetUpRow(this.service);

  @override
  final ServiceKey service;
}
