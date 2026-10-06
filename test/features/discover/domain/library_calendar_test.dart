import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The calendar of everything the household's arrs date: one row per
/// release, airing, album and book in the next thirty days, each connection
/// that holds it named once, and the words each row says.
void main() {
  // Tuesday 29 September, 20:53, as on the boards.
  final now = DateTime(2026, 9, 29, 20, 53);
  final window = CalendarWindow.from(now);
  String day(int offset) {
    final d = DateTime(2026, 9, 29 + offset);
    return '${d.year}-${'${d.month}'.padLeft(2, '0')}-'
        '${'${d.day}'.padLeft(2, '0')}T00:00:00Z';
  }

  Map<String, dynamic> spriteFright({bool hasFile = false}) => {
    'id': 7,
    'tmdbId': 508947,
    'title': 'Sprite Fright',
    'hasFile': hasFile,
    'digitalRelease': day(0),
    'physicalRelease': day(13),
    // Long before the window: no row.
    'inCinemas': '2021-10-29T00:00:00Z',
  };

  ArrQueueSnapshot downloading(int id) => ArrQueueSnapshot.fromQueueItems([
    {
      'movieId': id,
      'status': 'downloading',
      'trackedDownloadState': 'downloading',
      'size': 100,
      'sizeleft': 38,
      'estimatedCompletionTime': DateTime(
        2026,
        9,
        29,
        21,
        10,
      ).toUtc().toIso8601String(),
    },
  ], idsFor: (item) => [item['movieId'] as int]);

  CalendarReading reading(
    ServiceKey service,
    String label,
    List<Map<String, dynamic>> records, {
    ArrQueueSnapshot? queue,
    String? id,
  }) => CalendarReading(
    service: service,
    connectionId: id ?? label,
    label: label,
    records: records,
    queue: queue,
  );

  test('a movie is a row per release inside the thirty days, one row for '
      'every Radarr that holds it, the furthest on of them', () {
    final events = libraryCalendarEvents(
      [
        reading(ServiceKey.radarr, 'Radarr', [
          spriteFright(),
        ], queue: downloading(7)),
        reading(ServiceKey.radarr, 'Radarr 4K', [
          spriteFright(),
        ], queue: ArrQueueSnapshot.empty),
      ],
      window,
      now,
    );

    expect(events, hasLength(2));
    final digital = events.first;
    expect(digital.release, 'on digital');
    expect(digital.sources, ['Radarr', 'Radarr 4K']);
    expect(digital.state.stand, CalendarStand.inFlight);
    expect(digital.statusLine(now), 'Out today · downloading 62%');
    expect(digital.state.finishesAt, DateTime(2026, 9, 29, 21, 10));
    expect(digital.lead(), (lead: 'Digital', under: 'all day'));
    expect(
      digital.target,
      const CalendarMediaTarget(MediaKey.movie(508947), connectionId: 'Radarr'),
    );
    expect(
      digital.spoken(now),
      'Today, Sprite Fright, movie out on digital, downloading 62 percent, '
      'ready around 21:10, in Radarr and Radarr 4K',
    );

    // A release still to come reads as one, whatever the file says.
    final disc = events.last;
    expect(disc.day, DateTime(2026, 10, 12));
    expect(disc.statusLine(now), 'Not out yet');
    expect(disc.state.hollow, isTrue);
  });

  test('on the server, a movie says only that; out with nothing on disk it '
      'is missing only over a queue read whole', () {
    List<CalendarEvent> read(ArrQueueSnapshot queue, {bool hasFile = false}) =>
        libraryCalendarEvents(
          [
            reading(ServiceKey.radarr, 'Radarr', [
              spriteFright(hasFile: hasFile),
            ], queue: queue),
          ],
          window,
          now,
        );

    expect(
      read(ArrQueueSnapshot.empty, hasFile: true).first.statusLine(now),
      'On your server',
    );
    expect(
      read(ArrQueueSnapshot.empty).first.statusLine(now),
      'Out today · missing',
    );
    expect(
      read(const ArrQueueSnapshot.failed('down')).first.statusLine(now),
      'Out today',
    );
  });

  test('an episode has its time, its mark, and leads nothing on its day', () {
    final events = libraryCalendarEvents(
      [
        reading(ServiceKey.sonarr, 'Sonarr', [
          {
            'id': 3001,
            'seasonNumber': 3,
            'episodeNumber': 1,
            'airDateUtc': DateTime(2026, 10, 2, 21).toUtc().toIso8601String(),
            'hasFile': false,
            'series': {'title': 'Cosmos Laundromat', 'tvdbId': 900},
          },
          {
            'id': 4010,
            'seasonNumber': 4,
            'episodeNumber': 10,
            'finaleType': 'season',
            'airDateUtc': DateTime(2026, 10, 11, 20).toUtc().toIso8601String(),
            'series': {'title': 'The Long Field', 'tvdbId': 901},
          },
        ]),
        reading(ServiceKey.lidarr, 'Lidarr', [
          {
            'id': 4,
            'title': 'Sintel (Anniversary Edition)',
            'foreignAlbumId': 'mb-4',
            'releaseDate': day(3),
            'artistId': 1,
            'artist': {'artistName': 'Jan Morgenstern'},
          },
        ]),
      ],
      window,
      now,
    );

    expect(
      [for (final e in events) e.title],
      [
        // Friday: the album, a date with no time, before the 21:00 episode.
        'Sintel (Anniversary Edition)',
        'Cosmos Laundromat',
        'The Long Field',
      ],
    );
    final album = events[0];
    expect(album.statusLine(now), 'Jan Morgenstern · not out yet');
    expect(album.lead(), (lead: 'Album', under: 'all day'));
    expect(
      album.target,
      const CalendarShelfTarget(ServiceKey.lidarr, 'Lidarr', 1),
    );

    final premiere = events[1];
    expect(premiere.lead(), (lead: '21:00', under: null));
    expect(premiere.statusLine(now), 'S3 E1 · premiere · not aired');
    expect(premiere.target, isA<CalendarMediaTarget>());
    expect(
      premiere.spoken(now),
      'Friday 2 October at 21:00, Cosmos Laundromat season 3 premiere, '
      'not aired yet, in Sonarr',
    );
    expect(events[2].statusLine(now), 'S4 E10 · season finale · not aired');
  });

  test('an episode that aired with nothing on disk is the backlog', () {
    final events = libraryCalendarEvents(
      [
        reading(ServiceKey.sonarr, 'Sonarr', [
          {
            'id': 2105,
            'seasonNumber': 2,
            'episodeNumber': 5,
            'airDateUtc': DateTime(2026, 9, 29, 1).toUtc().toIso8601String(),
            'hasFile': false,
            'series': {'title': 'Night Shift', 'tvdbId': 902},
          },
        ], queue: ArrQueueSnapshot.empty),
      ],
      window,
      now,
    );
    expect(events.single.statusLine(now), 'S2 E5 · aired · missing');
    expect(events.single.state.tone, StatusTone.neutral);
    expect(events.single.state.hollow, isFalse);
  });

  test('the queue is asked only when something is out and off the disk', () {
    expect(
      calendarNeedsQueue(ServiceKey.radarr, [spriteFright()], window, now),
      isTrue,
    );
    expect(
      calendarNeedsQueue(
        ServiceKey.radarr,
        [spriteFright(hasFile: true)],
        window,
        now,
      ),
      isFalse,
    );
  });

  test('the agenda: a quiet line for three empty days or more, none for '
      'fewer, and the end of the thirty days', () {
    CalendarEvent at(int offset) => CalendarEvent(
      identity: '$offset',
      kind: CalendarKind.movie,
      day: DateTime(2026, 9, 29 + offset),
      title: 'Title $offset',
      state: const CalendarState.notYet(),
    );
    final agenda = calendarAgenda([at(3), at(5), at(9)], window);

    expect(agenda[0], isA<AgendaGap>());
    expect((agenda[0] as AgendaGap).until, DateTime(2026, 10, 2));
    expect((agenda[1] as AgendaDay).day, DateTime(2026, 10, 2));
    // Two empty days between: skipped without a word.
    expect((agenda[2] as AgendaDay).day, DateTime(2026, 10, 4));
    expect(agenda[3], isA<AgendaGap>());
    expect((agenda[4] as AgendaDay).day, DateTime(2026, 10, 8));
    expect(agenda.last, isA<AgendaEnd>());

    // Something today: no line before it.
    expect(calendarAgenda([at(0)], window).first, isA<AgendaDay>());
  });

  test('days and weeks as the strip names them', () {
    expect(calendarDayName(DateTime(2026, 9, 29), now), 'Today');
    expect(calendarDayName(DateTime(2026, 9, 30), now), 'Tomorrow');
    expect(calendarDayName(DateTime(2026, 10, 1), now), 'Thu');
    expect(calendarDayDate(DateTime(2026, 9, 29), now), 'Tue 29 Sep');
    expect(calendarDayDate(DateTime(2026, 10, 1), now), '1 Oct');
    expect(calendarShortDate(DateTime(2026, 10, 21)), 'Wed 21 Oct');

    final weeks = calendarWeeks(window);
    expect(weeks.first, DateTime(2026, 9, 28));
    // Tue 29 Sep to Thu 29 Oct: five weeks.
    expect(weeks, hasLength(5));
    expect(calendarWeekRange(weeks.first), 'Mon 28 Sep – Sun 4 Oct');
    expect(calendarWeekName(0), 'This week');
    expect(calendarWeekName(1), 'Next week');
  });

  test(
    "a day's dot is its most pressing row, a ring when nothing has come",
    () {
      const later = CalendarState.notYet();
      final flight = CalendarState.inFlight(
        mediaStatusFromQueue(
          availability: MediaAvailability.missing,
          monitored: true,
          queueEntry: const ArrQueueEntry(pipeline: MediaPipeline.downloading),
        ),
      );
      CalendarEvent row(CalendarState state) => CalendarEvent(
        identity: '${state.stand}',
        kind: CalendarKind.movie,
        day: DateTime(2026, 9, 29),
        title: 'x',
        state: state,
      );

      expect(calendarDayDot(const []), isNull);
      expect(calendarDayDot([row(later)]), (
        tone: StatusTone.neutral,
        hollow: true,
      ));
      expect(calendarDayDot([row(later), row(flight)]), (
        tone: StatusTone.info,
        hollow: false,
      ));
    },
  );
}
