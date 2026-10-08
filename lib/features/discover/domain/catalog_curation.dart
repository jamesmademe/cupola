/// The atrium's curated lists: the networks, studios, moods and languages it
/// offers, each with the TMDB id or code Seerr's discover filters take.
///
/// Curated because Seerr cannot list them: its `/network/:id` and
/// `/studio/:id` answer empty (lab, 06/10), it has no way to list networks at
/// all, and a keyword search finds "feel good" with two titles beside "time
/// travel" with thirteen hundred. Every id below was checked on the lab
/// against the titles it brings back (06/10); Seerr's own web app keeps the
/// same kind of list for its sliders.
library;

import 'package:cupola/features/discover/domain/models/seerr_genre.dart';

/// A network, a studio or a mood: a TMDB id with the name the app writes.
typedef CatalogEntity = ({int id, String name});

/// A language TMDB records as a title's original one.
typedef CatalogLanguage = ({String code, String name});

/// Where series first aired, the best known first.
const List<CatalogEntity> curatedNetworks = [
  (id: 213, name: 'Netflix'),
  (id: 49, name: 'HBO'),
  (id: 2552, name: 'Apple TV+'),
  (id: 1024, name: 'Prime Video'),
  (id: 2739, name: 'Disney+'),
  (id: 4, name: 'BBC One'),
  (id: 453, name: 'Hulu'),
  (id: 3186, name: 'Max'),
  (id: 4330, name: 'Paramount+'),
  (id: 3353, name: 'Peacock'),
  (id: 174, name: 'AMC'),
  (id: 88, name: 'FX'),
  (id: 67, name: 'Showtime'),
  (id: 318, name: 'Starz'),
  (id: 26, name: 'Channel 4'),
  (id: 332, name: 'BBC Two'),
  (id: 9, name: 'ITV1'),
  (id: 1063, name: 'Sky Atlantic'),
  (id: 6, name: 'NBC'),
  (id: 16, name: 'CBS'),
  (id: 2, name: 'ABC'),
  (id: 19, name: 'FOX'),
  (id: 71, name: 'The CW'),
  (id: 80, name: 'Adult Swim'),
  (id: 56, name: 'Cartoon Network'),
  (id: 13, name: 'Nickelodeon'),
  (id: 47, name: 'Comedy Central'),
  (id: 1, name: 'Fuji TV'),
  (id: 98, name: 'TV Tokyo'),
  (id: 533, name: 'Rai 1'),
  (id: 285, name: 'Canal+'),
  (id: 31, name: 'ZDF'),
];

/// Who made the films.
const List<CatalogEntity> curatedStudios = [
  (id: 41077, name: 'A24'),
  (id: 10342, name: 'Studio Ghibli'),
  (id: 3, name: 'Pixar'),
  (id: 420, name: 'Marvel Studios'),
  (id: 1, name: 'Lucasfilm'),
  (id: 2, name: 'Walt Disney Pictures'),
  (id: 521, name: 'DreamWorks Animation'),
  (id: 6704, name: 'Illumination'),
  (id: 2251, name: 'Sony Pictures Animation'),
  (id: 297, name: 'Aardman'),
  (id: 11537, name: 'Laika'),
  (id: 3172, name: 'Blumhouse'),
  (id: 923, name: 'Legendary'),
  (id: 90733, name: 'Neon'),
  (id: 127929, name: 'Searchlight Pictures'),
  (id: 10146, name: 'Focus Features'),
  (id: 13184, name: 'Annapurna Pictures'),
  (id: 81, name: 'Plan B'),
  (id: 10163, name: 'Working Title'),
  (id: 56, name: 'Amblin'),
  (id: 12, name: 'New Line Cinema'),
  (id: 14, name: 'Miramax'),
  (id: 174, name: 'Warner Bros. Pictures'),
  (id: 33, name: 'Universal Pictures'),
  (id: 4, name: 'Paramount Pictures'),
  (id: 5, name: 'Columbia Pictures'),
  (id: 127928, name: '20th Century Studios'),
  (id: 1632, name: 'Lionsgate'),
  (id: 694, name: 'StudioCanal'),
  (id: 9, name: 'Gaumont'),
  (id: 882, name: 'Toho'),
];

/// Moods: TMDB keywords with enough titles behind them, on both sides
/// where the theme exists on both.
const List<CatalogEntity> curatedMoods = [
  (id: 4379, name: 'Time travel'),
  (id: 10051, name: 'Heists'),
  (id: 4565, name: 'Dystopia'),
  (id: 10683, name: 'Coming of age'),
  (id: 7312, name: 'Road trips'),
  (id: 10121, name: 'Stop-motion'),
  (id: 12190, name: 'Cyberpunk'),
  (id: 9672, name: 'True stories'),
  (id: 10349, name: 'Survival'),
  (id: 3358, name: 'Haunted houses'),
  (id: 161176, name: 'Space opera'),
  (id: 207268, name: 'Neo-noir'),
  (id: 12570, name: 'Whodunits'),
  (id: 4458, name: 'After the apocalypse'),
  (id: 779, name: 'Martial arts'),
  (id: 210024, name: 'Anime'),
  (id: 12377, name: 'Zombies'),
  (id: 8201, name: 'Satire'),
  (id: 33519, name: 'Courtroom'),
  (id: 207317, name: 'Christmas'),
];

/// Original languages, the most watched in translation first.
const List<CatalogLanguage> curatedLanguages = [
  (code: 'ja', name: 'Japanese'),
  (code: 'ko', name: 'Korean'),
  (code: 'fr', name: 'French'),
  (code: 'es', name: 'Spanish'),
  (code: 'it', name: 'Italian'),
  (code: 'de', name: 'German'),
  (code: 'hi', name: 'Hindi'),
  (code: 'zh', name: 'Mandarin'),
  (code: 'cn', name: 'Cantonese'),
  (code: 'da', name: 'Danish'),
  (code: 'sv', name: 'Swedish'),
  (code: 'no', name: 'Norwegian'),
  (code: 'pt', name: 'Portuguese'),
  (code: 'tr', name: 'Turkish'),
  (code: 'th', name: 'Thai'),
];

/// The decades the catalogue offers, newest first: the 1920s to now.
List<int> catalogDecades({required DateTime today}) => [
  for (var start = today.year - today.year % 10; start >= 1920; start -= 10)
    start,
];

/// The curated entry with [id] in [list], for a page reached by its id
/// alone (a deep link).
CatalogEntity? curatedById(List<CatalogEntity> list, int id) {
  for (final entry in list) {
    if (entry.id == id) return entry;
  }
  return null;
}

/// The language with [code], or null for one this list does not hold.
CatalogLanguage? curatedLanguage(String code) {
  for (final entry in curatedLanguages) {
    if (entry.code == code) return entry;
  }
  return null;
}

/// The genres the Genres door names, by TMDB id: a comedy, a horror and a
/// documentary say how wide the index runs, where the first three of Seerr's
/// list (A to Z: Action, Adventure, Animation) say only where it starts. Ids,
/// so the names on the door are Seerr's own, as the index writes them.
const List<int> doorGenreIds = [35, 27, 99];

/// [genres] with those of [doorGenreIds] first, in that order, then the rest
/// in Seerr's: a Seerr that lacks one still fills the door.
List<SeerrGenre> doorGenresFirst(List<SeerrGenre> genres) => [
  for (final id in doorGenreIds) ...genres.where((genre) => genre.id == id),
  ...genres.where((genre) => !doorGenreIds.contains(genre.id)),
];

/// [list] with the entries whose name is in [owned] first, in [list]'s own
/// order otherwise: the networks your series come from lead the index.
///
/// [owned] holds names as the arrs write them (Sonarr's `network`, Radarr's
/// `studio`), matched ignoring case and a trailing plus (`Apple TV+` and
/// `Apple TV`).
List<CatalogEntity> libraryFirst(
  List<CatalogEntity> list,
  Iterable<String> owned,
) {
  String key(String name) =>
      name.toLowerCase().replaceAll('+', '').replaceAll(' ', '');
  final mine = {for (final name in owned) key(name)};
  if (mine.isEmpty) return list;
  return [
    ...list.where((entry) => mine.contains(key(entry.name))),
    ...list.where((entry) => !mine.contains(key(entry.name))),
  ];
}
