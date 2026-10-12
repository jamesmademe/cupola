import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// Which side of the camera a [PersonCredit] is on.
enum PersonCreditRole { cast, crew }

/// One line of a person's filmography, as Seerr's
/// `GET /api/v1/person/{id}/combined_credits` reports it.
class PersonCredit {
  const PersonCredit({
    required this.media,
    required this.role,
    this.character,
    this.job,
    this.department,
    this.genreIds = const [],
  });

  final MediaPreview media;
  final PersonCreditRole role;

  /// Who they played. Cast credits only.
  final String? character;

  /// TMDB's job: `Director`, `Screenplay`, `Producer`. Crew credits only.
  final String? job;

  /// TMDB's department: `Directing`, `Writing`, `Production`. Crew only.
  final String? department;

  /// TMDB's genres for the title: a talk show (10767) is how a person page
  /// tells an appearance as themselves from a role.
  final List<int> genreIds;

  /// Null for a row that is not a film or a series, or has no id.
  static PersonCredit? fromJson(
    Map<String, dynamic> json,
    PersonCreditRole role,
  ) {
    final mediaType = json['mediaType'] ?? json['media_type'];
    if (mediaType != 'movie' && mediaType != 'tv') return null;
    final id = intOrNull(json['id']);
    if (id == null) return null;
    return PersonCredit(
      media: MediaPreview.fromJson({...json, 'id': id}),
      role: role,
      character: role == PersonCreditRole.cast
          ? stringOrNull(json['character'])
          : null,
      job: role == PersonCreditRole.crew ? stringOrNull(json['job']) : null,
      department: role == PersonCreditRole.crew
          ? stringOrNull(json['department'])
          : null,
      genreIds: [
        if (json['genreIds'] case final List<dynamic> ids)
          for (final id in ids) ?intOrNull(id),
      ],
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

  factory PersonCombinedCredits.fromJson(Map<String, dynamic> json) {
    List<PersonCredit> parse(Object? raw, PersonCreditRole role) => [
      if (raw is List)
        for (final entry in raw)
          if (entry is Map)
            ?PersonCredit.fromJson(entry.cast<String, dynamic>(), role),
    ];
    return PersonCombinedCredits(
      cast: parse(json['cast'], PersonCreditRole.cast),
      crew: parse(json['crew'], PersonCreditRole.crew),
    );
  }

  final List<PersonCredit> cast;
  final List<PersonCredit> crew;

  bool get isEmpty => cast.isEmpty && crew.isEmpty;
}
