/// The words of the Home's Featured: up to three slides, what somebody was
/// watching, the newest arrival and what comes out today, each with its
/// artwork and its two ways forward.
library;

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/home/domain/arrived.dart';
import 'package:cupola/features/home/domain/continue_watching.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart'
    show askedAgo;
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/settings_model.dart'
    show serviceWithConnection;
import 'package:cupola/features/stream/domain/models/stream_item.dart';

/// How many slides Featured holds.
const featuredSlideLimit = 3;

/// What a media server would open for a title: the item, on the connection
/// that holds it.
typedef FeaturedPlay = ({ServiceInstance server, StreamItem item});

/// One slide: a title, its wide artwork and what it is doing here.
sealed class FeaturedSlide {
  const FeaturedSlide({required this.art});

  /// The picture the slide draws, wide; the one that lights the room.
  final ImageSource art;

  /// The title, as the slide names it: an episode by its series.
  String get title;

  /// The line under the title: `Continue watching · S2 E3 · 5 min left`.
  String line(DateTime now);

  /// What makes two slides the same title, across their sources: the
  /// lowercased title, which an episode shares with its series.
  String get sameness => title.trim().toLowerCase();
}

/// What somebody started and did not finish: `Resume`, then its page.
final class FeaturedResume extends FeaturedSlide {
  const FeaturedResume(this.row, {required super.art});

  final ResumeRow row;

  @override
  String get title => resumeTitle(row.item);

  @override
  String line(DateTime now) {
    final item = row.item;
    return [
      'Continue watching',
      if (item.kind == StreamItemKind.episode)
        ?formatArrEpisodeCode(item.seasonNumber, item.episodeNumber),
      ?resumeLeft(item),
    ].join(' · ');
  }
}

/// The newest title the libraries gained: `Play` when a media server holds
/// it, then its page.
final class FeaturedArrival extends FeaturedSlide {
  const FeaturedArrival(this.entry, {required super.art, this.play});

  final ArrHistoryEntry entry;

  /// Where it plays, when a media server answered that it holds it.
  final FeaturedPlay? play;

  @override
  String get title => entry.title;

  /// `New on your server · 2 h ago`, and the connection while the service
  /// has two: `New on your server · 2 h ago · Radarr 4K`.
  @override
  String line(DateTime now) => [
    'New on your server',
    if (entry.at case final at?) askedAgo(at, now: now),
    if (entry.connectionName case final name? when name.isNotEmpty)
      serviceWithConnection(entry.service, name, joiner: ' '),
  ].join(' · ');
}

/// A movie out today or an episode that airs today: its page, and the queue
/// while it is downloading.
final class FeaturedToday extends FeaturedSlide {
  const FeaturedToday(this.event, {required super.art});

  final CalendarEvent event;

  @override
  String get title => event.title;

  /// Whether the queue is where it stands now.
  bool get downloading => event.state.stand == CalendarStand.inFlight;

  /// `Out on digital today · downloading 62%`, `In cinemas today`, `S3 E1 ·
  /// premiere · airs today at 21:00`.
  @override
  String line(DateTime now) {
    final state = event.state;
    final standing = switch (state.stand) {
      CalendarStand.notYet => null,
      CalendarStand.out => state.missingKnown ? StateWord.missing.inline : null,
      _ => state.words(notYet: '', outWord: ''),
    };
    if (event.kind == CalendarKind.episode) {
      final airs = switch (event.airsAt) {
        final at? when at.isAfter(now) =>
          'airs today at ${formatClockTime(at)}',
        _ => standing == null ? 'aired today' : null,
      };
      return [?event.code, ?event.mark?.words, ?airs, ?standing].join(' · ');
    }
    final out = switch (event.release) {
      Lexicon.inCinemas => 'In cinemas today',
      final release? => 'Out $release today',
      null => 'Out today',
    };
    return [out, ?standing].join(' · ');
  }
}

/// Featured's slides, in their order: the title most recently played and
/// not finished, the newest movie or series that arrived, and a movie or an
/// episode dated today; each only with wide artwork, and never a title twice.
///
/// [resume], [arrivals] and [today] are each source's candidates, in its
/// own order: the first of each that has artwork and is not already a slide
/// is the one featured.
List<FeaturedSlide> featuredSlidesOf({
  required List<FeaturedResume> resume,
  required List<FeaturedArrival> arrivals,
  required List<FeaturedToday> today,
}) {
  final slides = <FeaturedSlide>[];
  final seen = <String>{};
  for (final candidates in [resume, arrivals, today]) {
    for (final slide in candidates) {
      if (slide.art.url.isEmpty || !seen.add(slide.sameness)) continue;
      slides.add(slide);
      break;
    }
  }
  return slides;
}

/// The arrivals Featured may lead with: movies and series, newest first,
/// one per title (`arrivedOf`). An album has its card in Arrived; Featured
/// is what can be watched.
List<ArrHistoryEntry> featuredArrivalsOf(
  List<ArrHistoryEntry> entries, {
  required DateTime since,
}) => [
  for (final entry in arrivedOf(entries, since: since))
    if (entry.service == ServiceKey.radarr ||
        entry.service == ServiceKey.sonarr)
      entry,
];

/// The calendar's movies and episodes dated today, in its order.
List<CalendarEvent> featuredTodayOf(List<CalendarEvent> events, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return [
    for (final event in events)
      if (event.day == today &&
          (event.kind == CalendarKind.movie ||
              event.kind == CalendarKind.episode))
        event,
  ];
}
