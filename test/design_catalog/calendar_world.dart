import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';

import 'catalog.dart';

/// The calendar of the boards' household, read on Tuesday 29 September at
/// 20:53: Sprite Fright out on digital and downloading, the week's
/// episodes, an album on Friday, the disc in twelve days.
abstract final class CalendarWorld {
  static final now = DateTime(2026, 9, 29, 20, 53);
  static final window = CalendarWindow.from(now);

  static const _poster = (url: CatalogArt.poster, headers: null);

  static CalendarState downloading({double progress = 0.62}) =>
      CalendarState.inFlight(
        mediaStatusFromQueue(
          availability: MediaAvailability.missing,
          monitored: true,
          queueEntry: ArrQueueEntry(
            pipeline: MediaPipeline.downloading,
            progress: progress,
          ),
        ),
        finishesAt: DateTime(2026, 9, 29, 21, 10),
      );

  static CalendarEvent spriteFright({CalendarState? state}) => CalendarEvent(
    identity: 'sf-digital',
    kind: CalendarKind.movie,
    day: DateTime(2026, 9, 29),
    title: 'Sprite Fright',
    release: Lexicon.onDigital,
    poster: _poster,
    sources: const ['Radarr', 'Radarr 4K'],
    state: state ?? downloading(),
  );

  static CalendarEvent episode(
    String title,
    int day,
    int hour,
    int season,
    int episode, {
    CalendarMark? mark,
    bool poster = false,
    CalendarState state = const CalendarState.notYet(),
  }) => CalendarEvent(
    identity: '$title-$season-$episode',
    kind: CalendarKind.episode,
    day: DateTime(2026, 9, day),
    airsAt: DateTime(2026, 9, day, hour),
    title: title,
    season: season,
    episode: episode,
    mark: mark,
    poster: poster ? _poster : null,
    sources: const ['Sonarr'],
    state: state,
  );

  static final album = CalendarEvent(
    identity: 'sintel-album',
    kind: CalendarKind.album,
    day: DateTime(2026, 10, 2),
    title: 'Sintel (Anniversary Edition)',
    byline: 'Jan Morgenstern',
    poster: _poster,
    sources: const ['Lidarr'],
    state: const CalendarState.notYet(),
  );

  static final disc = CalendarEvent(
    identity: 'sf-disc',
    kind: CalendarKind.movie,
    day: DateTime(2026, 10, 12),
    title: 'Sprite Fright',
    release: Lexicon.onDisc,
    poster: _poster,
    sources: const ['Radarr', 'Radarr 4K'],
    state: const CalendarState.notYet(),
  );

  /// The operator's thirty days, sorted.
  static List<CalendarEvent> get events => [
    spriteFright(),
    episode('Night Shift', 30, 22, 2, 5),
    // 2 October is the 32nd of September to `DateTime`.
    episode('Harbour Lights', 31, 21, 1, 3),
    album,
    episode(
      'Cosmos Laundromat',
      32,
      21,
      3,
      1,
      mark: CalendarMark.premiere,
      poster: true,
    ),
    episode('The Long Field', 34, 20, 4, 9),
    disc,
  ]..sort(compareCalendarEvents);

  /// Anna's: her movie downloading, her series' premiere on Friday.
  static List<CalendarEvent> get requester => [
    CalendarEvent(
      identity: 'sf',
      kind: CalendarKind.movie,
      day: DateTime(2026, 9, 29),
      title: 'Sprite Fright',
      release: Lexicon.onDigital,
      region: 'Italy',
      note: 'On digital in Italy today',
      poster: _poster,
      state: downloading(),
    ),
    CalendarEvent(
      identity: 'cl',
      kind: CalendarKind.episode,
      day: DateTime(2026, 10, 2),
      title: 'Cosmos Laundromat',
      season: 3,
      episode: 1,
      mark: CalendarMark.premiere,
      note: 'You asked for season 3 on Sat 26 Sep',
      poster: _poster,
      state: const CalendarState.notYet(),
    ),
  ];
}
