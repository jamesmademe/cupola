/// Featured's last drawing: its slides, each with what it opens and plays.
library;

import 'package:cupola/core/last_known/stored_image.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/arr_history_entry_codec.dart';
import 'package:cupola/features/home/data/last_known/calendar_event_codec.dart';
import 'package:cupola/features/home/data/last_known/resume_row_codec.dart';
import 'package:cupola/features/home/data/last_known/stream_item_codec.dart';
import 'package:cupola/features/home/domain/featured.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The slides as Featured drew them, through the codecs of the modules that
/// show the same things whole: a resume as Continue watching keeps it, an
/// arrival as Arrived does, a slide of today as Coming up does.
///
/// The pictures keep no credential: a resume's is its server's path (the
/// connection's client makes the same address again when it is drawn), an
/// arrival's is the public address its record holds, and today's goes with
/// its event. What is no longer true when it is drawn is cut then
/// ([featuredAsDrawn]). An empty Featured is kept too: the next start waits
/// for the live answer rather than drawing slides from before it.
final featuredLastKnown = HomeLastKnownSlot<List<FeaturedSlide>>(
  id: 'featured',
  // 2: today's slide keeps its event's arr pictures by connection and path
  // (`StoredArrImage`); an entry of 1 kept addresses and is dropped.
  schema: 2,
  services: HomeModule.featured.services.toSet(),
  encode: (slides, keep) => {
    'slides': [for (final slide in slides) ?_slideToJson(slide, keep)],
  },
  decode: (data, image) {
    if (data is! Map || data['slides'] is! List) return null;
    return [
      for (final json in data['slides'] as List) ?_slideFromJson(json, image),
    ];
  },
);

Map<String, Object?>? _slideToJson(
  FeaturedSlide slide,
  StoredImageKeeper keep,
) => switch (slide) {
  FeaturedResume(:final row) => switch (row.item.backdropPath) {
    final path? when path.isNotEmpty => {
      'kind': 'resume',
      'row': resumeRowToJson(row),
      'art': StoredStreamImage(
        service: row.service,
        connectionId: row.instanceId,
        path: path,
        width: featuredArtWidth,
      ).toJson(),
    },
    _ => null,
  },
  FeaturedArrival(:final entry, :final play) =>
    StoredImage.carriesCredential(entry.backdropUrl)
        ? null
        : {
            'kind': 'arrival',
            'entry': arrHistoryEntryToJson(entry),
            if (play != null)
              'play': {
                'service': play.service.name,
                'instanceId': play.instanceId,
                'item': streamItemToJson(play.item),
              },
          },
  FeaturedToday(:final event) => {
    'kind': 'today',
    'event': calendarEventToJson(event, keep),
  },
};

FeaturedSlide? _slideFromJson(Object? json, StoredImageResolver image) {
  if (json is! Map) return null;
  switch (json['kind']) {
    case 'resume':
      final row = resumeRowFromJson(json['row']);
      final art = StoredImage.fromJson(json['art']);
      if (row == null || art == null) return null;
      final source = image(art);
      if (source.url.isEmpty) return null;
      return FeaturedResume(row, art: source);
    case 'arrival':
      final entry = arrHistoryEntryFromJson(json['entry']);
      if (entry == null || entry.backdropUrl.isEmpty) return null;
      return FeaturedArrival(
        entry,
        art: (url: entry.backdropUrl, headers: null),
        play: _playFromJson(json['play']),
      );
    case 'today':
      final event = calendarEventFromJson(json['event'], image);
      final art = event?.backdrop;
      if (event == null || art == null || art.url.isEmpty) return null;
      return FeaturedToday(event, art: art);
    default:
      return null;
  }
}

FeaturedPlay? _playFromJson(Object? json) {
  if (json is! Map) return null;
  final service = ServiceKey.values.asNameMap()[json['service']];
  final instanceId = json['instanceId'];
  final item = streamItemFromJson(json['item']);
  if (service == null || instanceId is! String || item == null) return null;
  return (service: service, instanceId: instanceId, item: item);
}

/// The slides of a drawing as they are drawn at [now]: an arrival the week
/// ([since]) has left behind is gone, and a slide of today is gone once today
/// is another day. The words of each are made at [now] by the slide itself.
List<FeaturedSlide> featuredAsDrawn(
  List<FeaturedSlide> slides, {
  required DateTime now,
  required DateTime since,
}) {
  final today = DateTime(now.year, now.month, now.day);
  return [
    for (final slide in slides)
      if (switch (slide) {
        FeaturedResume() => true,
        FeaturedArrival(:final entry) =>
          entry.at != null && !entry.at!.isBefore(since),
        FeaturedToday(:final event) =>
          event.day == today &&
              (event.kind == CalendarKind.movie ||
                  event.kind == CalendarKind.episode),
      })
        slide,
  ];
}
