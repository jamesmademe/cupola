/// The three widgets' frames, made from what the Home's modules read and in
/// the words the modules say: Coming up from the calendar, Downloads from the
/// queues, Your requests from her requests.
///
/// Each builder takes the instant of the read and answers frames for the
/// moments its words change (`outsideFramesAt`): the first is the module as
/// it is drawn live; the later ones are the module as its last drawing is
/// drawn, by the same rules (`comingUpAsDrawn`, `downloadsKnownSubtitle`,
/// `myRequestsDrawn`), so a widget an hour old says what the Home would say
/// of a drawing an hour old, and nothing it would not.
library;

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/activity/domain/download_page.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/home/data/home_last_known.dart' show formatAsOf;
import 'package:cupola/features/home/data/last_known/my_requests_last_known.dart'
    show myRequestsDrawn;
import 'package:cupola/features/home/domain/coming_up.dart';
import 'package:cupola/features/home/domain/downloads.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/outside/domain/outside_snapshot.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';
import 'package:cupola/features/services/presentation/services_provider.dart'
    show ServiceQueueItem, ServicesInFlight;
import 'package:cupola/features/settings/domain/service_key.dart';

/// Gives a picture its file name beside the snapshot, and asks the run to
/// fetch it; null for no picture, or one the run will not keep.
typedef OutsidePictures = String? Function(ImageSource? source);

/// How long after a read the widget says the age of what it draws in every
/// size, the small one included.
const outsideAgedAfter = Duration(hours: 1);

/// How long the figures that run (a time left, a speed, a stall) are drawn
/// after the read that gave them. Past it, Downloads is drawn as its last
/// drawing is on the Home: a bar where it stopped, no time, no speed.
const outsideRunningFor = Duration(minutes: 15);

/// [tone] as a widget paints it. Red is not a widget's tone
/// (`OutsideSnapshot`), and the primary is the ink.
OutsideTone? outsideToneOf(StatusTone tone) => switch (tone) {
  StatusTone.success => OutsideTone.green,
  StatusTone.warning => OutsideTone.amber,
  StatusTone.info => OutsideTone.blue,
  StatusTone.neutral => OutsideTone.neutral,
  // Red and the ink: the word is drawn in the ink.
  _ => null,
};

String _age(DateTime takenAt, DateTime at) =>
    'As of ${formatAsOf(takenAt, now: at)}';

bool _aged(DateTime takenAt, DateTime at) =>
    !at.isBefore(takenAt.add(outsideAgedAfter));

// Coming up -----------------------------------------------------------------

/// Coming up's frames for a calendar read at [takenAt]: the Home's module at
/// the read, then as its drawing is drawn at each midnight and at each time
/// a thing airs, and once it is old enough to say so.
List<OutsideFrame> comingUpFrames(
  List<CalendarEvent> events, {
  required DateTime takenAt,
  required OutsidePictures pictures,
}) {
  final window = comingUpOf(events, takenAt);
  OutsideFace face(DateTime at) {
    // Past the read, the widget looks ahead: a thing whose time has come
    // leaves, and the next one leads (a drawing cannot know what became of
    // it, and the Home's drawing says no more than `aired`).
    final rows = at == takenAt
        ? window
        : comingUpAsDrawn([
            for (final event in events)
              if (!_hasCome(event, at)) event,
          ], at);
    // The widget leads with what comes next: a thing that aired this
    // morning stays among the rows, as the Home lists it, and gives the lead
    // to the first one still to come.
    final next = rows.indexWhere((event) => !_hasComeAt(event, at));
    final lead = rows.isEmpty ? null : rows[next < 0 ? 0 : next];
    final shown = [
      for (final event in rows)
        if (!identical(event, lead)) event,
    ].take(comingUpRowLimit - 1).toList(growable: false);
    return OutsideFace(
      title: 'Coming up',
      age: _age(takenAt, at),
      aged: _aged(takenAt, at),
      lead: lead == null ? null : _comingUpItem(lead, at, pictures),
      items: [
        for (final event in shown)
          _comingUpItem(event, at, pictures, lead: false),
      ],
      // Only the read says nothing comes out: a drawing with nothing left to
      // draw says nothing, as the Home's does.
      calm: rows.isEmpty && at == takenAt ? comingUpCalmLine(at) : null,
      route: ServiceRoutes.discoverCalendar,
    );
  }

  return outsideFramesAt(takenAt, [
    ...outsideMidnights(takenAt),
    for (final event in window) ?event.airsAt,
    takenAt.add(outsideAgedAfter),
  ], face);
}

/// A thing that had not come at the read, and whose day or time has come
/// since.
bool _hasCome(CalendarEvent event, DateTime at) =>
    event.state.stand == CalendarStand.notYet && _hasComeAt(event, at);

/// Whether [event]'s day or time has come by [at], whatever came of it.
bool _hasComeAt(CalendarEvent event, DateTime at) =>
    CalendarEvent.hasCome(event.day, event.airsAt, at);

OutsideItem _comingUpItem(
  CalendarEvent event,
  DateTime at,
  OutsidePictures pictures, {
  bool lead = true,
}) {
  final day = calendarDayName(event.day, at);
  final airs = event.airsAt;
  final state = event.state;
  return OutsideItem(
    // The lead says the day and the time; a row says the day, and its time
    // is in its words, as the Home's row has it.
    eyebrow: lead && airs != null ? '$day · ${formatClockTime(airs)}' : day,
    title: event.title,
    words: !lead && airs != null
        ? '${formatClockTime(airs)} · ${event.statusLine(at)}'
        : event.statusLine(at),
    tone: state.stand == CalendarStand.inFlight
        ? outsideToneOf(state.tone)
        : null,
    poster: lead ? pictures(event.poster) : null,
    backdrop: lead ? pictures(event.backdrop) : null,
    route: _eventRoute(event),
  );
}

String? _eventRoute(CalendarEvent event) => switch (event.target) {
  CalendarMediaTarget(:final key, :final connectionId) => ServiceRoutes.media(
    key,
    from: ServiceRoutes.home,
    focus: connectionId,
  ),
  CalendarShelfTarget(:final service, :final connectionId, :final id) =>
    service == ServiceKey.readarr
        ? ServiceRoutes.readarrAuthor(id, instanceId: connectionId)
        : ServiceRoutes.lidarrArtist(id, instanceId: connectionId),
  null => null,
};

// Downloads -----------------------------------------------------------------

/// Downloads' frames for a queue read at [takenAt]: the Home's module while
/// its running figures are true ([outsideRunningFor]), then its last
/// drawing. Nothing at all of a read no queue answered: the frames before
/// it are the better ones, and the run keeps them.
///
/// [clientSetUp] and [clientSilent] are the module's: whether a download
/// client is set up, whether one did not answer (its speed is then unknown).
List<OutsideFrame>? downloadsFrames(
  ServicesInFlight data, {
  required DateTime takenAt,
  required bool clientSetUp,
  required bool clientSilent,
}) {
  final coverage = data.coverage;
  if (coverage.everySourceFailed) return null;
  final stuck = [
    for (final item in data.faults)
      if (isDownloadFault(item.fault)) item,
  ];
  final rows = downloadRowsOf(data.preview, stuck);
  final whole = coverage.isWhole;
  final calm = rows.isEmpty && whole ? 'Nothing is downloading' : null;

  OutsideFace live(DateTime at) => OutsideFace(
    title: 'Downloads',
    subtitle: downloadsSubtitle(
      moving: data.movingCount,
      stuck: stuck.length,
      queued: data.queued.length,
      clientSetUp: clientSetUp,
      clientSilent: clientSilent,
      rateBytesPerSecond: data.rateBytesPerSecond,
      coverage: coverage,
    ),
    figure: _figure(data, whole),
    figureWords: _figure(data, whole) == null ? null : 'moving',
    lead: stuck.isEmpty ? null : _downloadItem(stuck.first, live: true),
    items: [for (final item in rows) _downloadItem(item, live: true)],
    calm: calm,
    age: _age(takenAt, at),
    aged: _aged(takenAt, at),
    route: ServiceRoutes.activity,
  );

  // What the Home draws of the same read once it is a drawing
  // (`downloads_last_known.dart`): no fault, nothing that runs, counts only
  // of a whole read, and `Nothing is downloading` never, since only the read
  // it was true of could say it.
  OutsideFace known(DateTime at) => OutsideFace(
    title: 'Downloads',
    subtitle: downloadsKnownSubtitle(
      moving: data.movingCount,
      queued: data.queued.length,
      whole: whole,
      hasRows: rows.isNotEmpty,
    ),
    figure: _figure(data, whole),
    figureWords: _figure(data, whole) == null ? null : 'moving',
    items: [for (final item in rows) _downloadItem(item, live: false)],
    age: _age(takenAt, at),
    aged: _aged(takenAt, at),
    route: ServiceRoutes.activity,
  );

  final knownFrom = takenAt.add(outsideRunningFor);
  return outsideFramesAt(takenAt, [
    knownFrom,
    ...outsideMidnights(takenAt),
    takenAt.add(outsideAgedAfter),
  ], (at) => at.isBefore(knownFrom) ? live(at) : known(at));
}

/// The figure a small Downloads leads with: how many move, over a read that
/// was whole, and only when something does. `0 moving` in large type is
/// nothing to lead with: the line and the stuck one say it.
String? _figure(ServicesInFlight data, bool whole) =>
    whole && data.movingCount > 0 ? '${data.movingCount}' : null;

OutsideItem _downloadItem(ServiceQueueItem item, {required bool live}) {
  final fault = live ? item.fault : null;
  final stuck = isDownloadFault(fault);
  final percent = item.progress == null
      ? null
      : wholePercent(item.progress! * 100);
  return OutsideItem(
    title: item.title,
    words: stuck
        ? stuckValue(fault!, percent: percent)
        : movingValue(
            percent: percent,
            etaSeconds: live ? item.etaSeconds : null,
          ),
    // The blue is what makes a bar read as moving; a bar that stopped, as a
    // drawing's has, is the ink of a figure that does not move.
    tone: !live
        ? OutsideTone.neutral
        : stuck
        ? OutsideTone.amber
        : OutsideTone.blue,
    progress: item.progress,
    route: ServiceRoutes.activityDownload(
      instanceId: item.instanceId,
      key: downloadPageKey(item),
    ),
  );
}

// Your requests -------------------------------------------------------------

/// Your requests' frames for her requests read at [takenAt]: the newest
/// arrival leads (`Ready to watch`), and the rows are the Home's.
List<OutsideFrame> requestsFrames(
  List<SeerrRequest> requests, {
  required DateTime takenAt,
  required OutsidePictures pictures,
}) {
  OutsideFace face(DateTime at) {
    final mine = at == takenAt
        ? myRequestsOf(requests, now: at)
        : myRequestsDrawn(requests, now: at);
    final ready = mine.ready;
    final coming = mine.onTheWay.length;
    final rows = mine.homeRows(at);
    final onTheWay = switch (coming) {
      0 => null,
      1 => '1 on its way',
      _ => '$coming on the way',
    };
    final lead = ready.firstOrNull;
    return OutsideFace(
      title: 'Your requests',
      subtitle: onTheWay,
      lead: lead == null
          ? null
          : OutsideItem(
              eyebrow: 'Ready to watch',
              tone: OutsideTone.green,
              title: lead.title,
              words: onTheWay,
              poster: pictures(_tmdb(lead.request.media?.posterPath, 'w342')),
              backdrop: pictures(
                _tmdb(lead.request.media?.backdropPath, 'w780'),
              ),
              route: _requestRoute(lead),
            ),
      items: [
        for (final row in rows.take(comingUpRowLimit))
          OutsideItem(
            title: row.title,
            words: row.stateShort,
            tone: outsideToneOf(row.stage.tone),
            progress: row.progress,
            poster: pictures(_tmdb(row.request.media?.posterPath, 'w342')),
            route: _requestRoute(row),
          ),
      ],
      calm: rows.isEmpty && lead == null ? 'Nothing on its way' : null,
      age: _age(takenAt, at),
      aged: _aged(takenAt, at),
      route: ServiceRoutes.requests,
    );
  }

  return outsideFramesAt(takenAt, [
    ...outsideMidnights(takenAt),
    takenAt.add(outsideAgedAfter),
  ], face);
}

ImageSource? _tmdb(String? path, String size) {
  final url = ImageUtils.buildTmdbPosterUrl(path, size: size);
  return url.isEmpty ? null : (url: url, headers: null);
}

String? _requestRoute(MyRequest mine) {
  final id = mine.request.media?.tmdbId;
  if (id == null) return null;
  return ServiceRoutes.media(
    mine.request.type == 'tv' ? MediaKey.tv(id) : MediaKey.movie(id),
    from: ServiceRoutes.home,
  );
}
