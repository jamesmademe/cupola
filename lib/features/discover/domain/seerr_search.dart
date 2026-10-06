import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// Someone Seerr's search found: TMDB's person, with the titles TMDB says
/// they are known for.
class SeerrSearchPerson {
  const SeerrSearchPerson({
    required this.id,
    required this.name,
    this.profilePath,
    this.knownFor = const [],
  });

  /// One person result of `/search`, or null when it carries no id or name.
  static SeerrSearchPerson? fromJson(Map<String, dynamic> json) {
    final id = intOrNull(json['id']);
    final name = stringOrNull(json['name'])?.trim() ?? '';
    if (id == null || id <= 0 || name.isEmpty) return null;
    final knownFor = json['knownFor'];
    return SeerrSearchPerson(
      id: id,
      name: name,
      profilePath: stringOrNull(json['profilePath']),
      knownFor: [
        if (knownFor is List)
          for (final title in knownFor)
            if (title is Map)
              if (stringOrNull(title['title']) ?? stringOrNull(title['name'])
                  case final name? when name.trim().isNotEmpty)
                name.trim(),
      ],
    );
  }

  final int id;
  final String name;
  final String? profilePath;

  /// TMDB's order: the titles the person is best known for first.
  final List<String> knownFor;
}

/// What one Seerr search found: movies and series, and people.
class SeerrSearchAnswer {
  const SeerrSearchAnswer({
    this.titles = const [],
    this.people = const [],
    this.leadsWithPeople = false,
  });

  /// The titles, in Seerr's order (TMDB's relevance), movies and series mixed.
  final List<MediaPreview> titles;

  /// The people, in Seerr's order.
  final List<SeerrSearchPerson> people;

  /// Seerr ranked a person above every title: the word names someone
  /// (`tom hanks`), and the page leads with the people.
  final bool leadsWithPeople;

  bool get isEmpty => titles.isEmpty && people.isEmpty;
}
