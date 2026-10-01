import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';

/// Which side of the camera a [PersonCredit] is on.
enum PersonCreditRole { cast, crew }

/// One line of a person's filmography, as Seerr's
/// `GET /api/v1/person/{id}/combined_credits` reports it.
class PersonCredit {
  const PersonCredit({
    required this.media,
    required this.role,
    required this.status,
    this.character,
    this.job,
    this.department,
  });

  final MediaPreview media;
  final PersonCreditRole role;

  /// Who they played. Cast credits only.
  final String? character;

  /// TMDB's job — `Director`, `Screenplay`, `Producer`. Crew credits only.
  final String? job;

  /// TMDB's department — `Directing`, `Writing`, `Production`. Crew only.
  final String? department;

  /// What Seerr holds for this title, from the `mediaInfo` it attaches to every
  /// credit, read through the same resolver the detail page uses.
  /// `notTracked` when Seerr has no record of it.
  final MediaStatusInfo status;

  /// On the user's server, whole or in part. What "3 of 4 on your server"
  /// counts.
  bool get isOnServer =>
      status.availability == MediaAvailability.available ||
      status.availability == MediaAvailability.partial;

  /// Null for a row that is not a film or a series, or has no id.
  ///
  /// [numbering] is the numbering of the Seerr that sent [json], for the
  /// title's status: see `seerrMediaStatus`.
  static PersonCredit? fromJson(
    Map<String, dynamic> json,
    PersonCreditRole role, {
    SeerrNumbering? numbering,
  }) {
    final mediaType = json['mediaType'] ?? json['media_type'];
    if (mediaType != 'movie' && mediaType != 'tv') return null;
    final id = intOrNull(json['id']);
    if (id == null) return null;
    final mediaInfo = json['mediaInfo'];
    return PersonCredit(
      media: MediaPreview.fromJson({...json, 'id': id}),
      role: role,
      status: seerrMediaStatus(
        mediaInfo is Map ? mediaInfo.cast<String, dynamic>() : null,
        numbering: numbering,
      ),
      character: role == PersonCreditRole.cast
          ? stringOrNull(json['character'])
          : null,
      job: role == PersonCreditRole.crew ? stringOrNull(json['job']) : null,
      department: role == PersonCreditRole.crew
          ? stringOrNull(json['department'])
          : null,
    );
  }
}

/// A person's whole filmography: in front of the camera and behind it.
///
/// Seerr sends one row per role, so a film someone both directed and wrote is
/// two crew rows. [cast] and [crew] keep every row; the derived lists below
/// fold them to one entry per title.
class PersonCombinedCredits {
  const PersonCombinedCredits({this.cast = const [], this.crew = const []});

  static const empty = PersonCombinedCredits();

  factory PersonCombinedCredits.fromJson(
    Map<String, dynamic> json, {
    SeerrNumbering? numbering,
  }) {
    List<PersonCredit> parse(Object? raw, PersonCreditRole role) => [
      if (raw is List)
        for (final entry in raw)
          if (entry is Map)
            ?PersonCredit.fromJson(
              entry.cast<String, dynamic>(),
              role,
              numbering: numbering,
            ),
    ];
    return PersonCombinedCredits(
      cast: parse(json['cast'], PersonCreditRole.cast),
      crew: parse(json['crew'], PersonCreditRole.crew),
    );
  }

  final List<PersonCredit> cast;
  final List<PersonCredit> crew;

  bool get isEmpty => cast.isEmpty && crew.isEmpty;

  /// The acting filmography, once per title, strongest-rated first.
  ///
  /// What the Person page's rail shows. It folds on the TMDB id alone, as it
  /// always has: the rail builds its Hero tags from that id, and a film and a
  /// series sharing one would put two heroes under one tag.
  List<MediaPreview> get castFilmography {
    final seen = <int>{};
    final items = [
      for (final credit in cast)
        if (seen.add(credit.media.id)) credit.media,
    ];
    items.sort((a, b) => (b.voteAverage ?? 0).compareTo(a.voteAverage ?? 0));
    return items;
  }

  /// Every title credited to them as [job] (`Director`), once per title, in
  /// Seerr's order. Matches TMDB's job name exactly, ignoring case.
  List<PersonCredit> crewAs(String job) {
    final wanted = job.trim().toLowerCase();
    final seen = <String>{};
    return [
      for (final credit in crew)
        if (credit.job?.trim().toLowerCase() == wanted &&
            seen.add('${credit.media.mediaType}:${credit.media.id}'))
          credit,
    ];
  }
}
