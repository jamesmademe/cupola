import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One connection's calendar, asked for the thirty days from [from]'s day.
typedef CalendarSourceKey = ({
  ServiceKey service,
  String connectionId,
  DateTime from,
});

/// A connection whose calendar did not arrive, and why.
typedef CalendarSilence = ({
  ServiceKey service,
  String connectionId,
  String name,
  Object error,
});

/// Everything the household's arrs date in the next thirty days, as the
/// calendar shows it.
@immutable
class LibraryCalendar {
  const LibraryCalendar({
    required this.window,
    required this.events,
    required this.answered,
    required this.silent,
    required this.kinds,
    required this.readAt,
  });

  final CalendarWindow window;

  /// One row per dated thing, in date order.
  final List<CalendarEvent> events;

  /// The connections that answered, by name, in the settings' order.
  final List<String> answered;

  /// The connections that did not.
  final List<CalendarSilence> silent;

  /// The kinds the household has a service for: their chips.
  final Set<CalendarKind> kinds;

  /// When the calendars were read.
  final DateTime readAt;

  /// The kinds a silent connection may be missing rows of.
  Set<CalendarKind> get silentKinds => {
    for (final silence in silent) ?CalendarKind.of(silence.service),
  };

  /// The rows of [kind], or every row when [kind] is null.
  List<CalendarEvent> of(CalendarKind? kind) => kind == null
      ? events
      : [
          for (final event in events)
            if (event.kind == kind) event,
        ];
}

/// The services whose calendars the calendar reads, in its chips' order.
const calendarServices = [
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
  ServiceKey.readarr,
];

/// The connections the operator's calendar asks: every set-up connection of
/// the four arrs. The requester's calendar never reads an arr.
final calendarConnectionsProvider = Provider<List<ServiceInstance>>((ref) {
  if (ref.watch(audienceProvider) != Audience.operator) return const [];
  final settings = ref.watch(currentSettingsProvider);
  return [
    for (final service in calendarServices)
      for (final instance in settings.instancesOf(service))
        if (instance.isConfigured) instance,
  ];
});

/// The calendar of one connection for the thirty days from the key's day,
/// and its queue when something of it is out with nothing on disk: only
/// then does a row's word hang on the queue. A calendar that did not arrive
/// fails; a queue that did not answer is a snapshot that says so.
final calendarSourceProvider = FutureProvider.autoDispose
    .family<CalendarReading, CalendarSourceKey>((ref, key) async {
      final id = key.connectionId;
      final settings = ref.watch(currentSettingsProvider);
      final instance = settings.instanceById(id);
      if (instance == null || !instance.isConfigured) {
        throw Exception('${key.service.title} not configured');
      }
      final ArrActivityMixin service = switch (key.service) {
        ServiceKey.radarr => ref.watch(radarrServiceForProvider(id)),
        ServiceKey.sonarr => ref.watch(sonarrServiceForProvider(id)),
        ServiceKey.lidarr => ref.watch(lidarrServiceForProvider(id)),
        ServiceKey.readarr => ref.watch(readarrServiceForProvider(id)),
        _ => throw ArgumentError.value(key.service, 'service', 'no calendar'),
      };
      final window = CalendarWindow.from(key.from);
      final raw = await service.getCalendar(
        start: window.start,
        end: window.end,
      );
      final records = [
        for (final record in raw)
          if (record is Map) Map<String, dynamic>.from(record),
      ];
      ArrQueueSnapshot? queue;
      final now = ref.read(calendarClockProvider)();
      if (calendarNeedsQueue(key.service, records, window, now)) {
        queue = switch (key.service) {
          ServiceKey.radarr => await ref.watch(
            radarrQueueSnapshotForProvider(id).future,
          ),
          ServiceKey.sonarr => (await ref.watch(
            sonarrQueueSnapshotsForProvider(id).future,
          )).byEpisode,
          ServiceKey.lidarr => (await ref.watch(
            lidarrQueueSnapshotsForProvider(id).future,
          )).byAlbum,
          _ => await ref.watch(readarrQueueSnapshotForProvider(id).future),
        };
      }
      return CalendarReading(
        service: key.service,
        connectionId: id,
        label: settings.connectionTitle(id, key.service, joiner: ' '),
        records: records,
        queue: queue,
        poster: (images, coverTypes) => ImageUtils.extractPosterUrl(
          images,
          baseUrl: instance.url,
          apiKey: instance.credential,
          coverTypes: coverTypes,
        ),
      );
    }, retry: noProviderRetry);

/// The clock the calendar reads `today`, `out today` and `not aired` by.
/// A test that pins its world's time pins this to the same moment.
final calendarClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The day the calendar's thirty days start from: today, read once, so
/// every connection is asked the same window and the rows agree.
final calendarDayProvider = Provider.autoDispose<DateTime>((ref) {
  final now = ref.watch(calendarClockProvider)();
  return DateTime(now.year, now.month, now.day);
});

/// The operator's calendar: every connection of the four arrs, asked
/// together, the rows of each merged into one (a movie on two Radarrs is one
/// row naming both). A connection that did not answer loses its rows and is
/// named; the others' stand.
final libraryCalendarProvider = FutureProvider.autoDispose<LibraryCalendar>((
  ref,
) async {
  final from = ref.watch(calendarDayProvider);
  final connections = ref.watch(calendarConnectionsProvider);
  final settings = ref.read(currentSettingsProvider);
  final window = CalendarWindow.from(from);
  final answers = await Future.wait([
    for (final instance in connections)
      ref
          .watch(
            calendarSourceProvider((
              service: instance.service,
              connectionId: instance.id,
              from: from,
            )).future,
          )
          .then<Object>((reading) => reading, onError: (Object error) => error),
  ]);
  final readings = <CalendarReading>[];
  final silent = <CalendarSilence>[];
  for (final (index, answer) in answers.indexed) {
    final instance = connections[index];
    if (answer case final CalendarReading reading) {
      readings.add(reading);
    } else {
      silent.add((
        service: instance.service,
        connectionId: instance.id,
        name: settings.connectionTitle(
          instance.id,
          instance.service,
          joiner: ' ',
        ),
        error: answer,
      ));
    }
  }
  final now = ref.read(calendarClockProvider)();
  return LibraryCalendar(
    window: window,
    events: libraryCalendarEvents(readings, window, now),
    answered: [for (final reading in readings) reading.label],
    silent: silent,
    kinds: {
      for (final instance in connections) ?CalendarKind.of(instance.service),
    },
    readAt: now,
  );
}, retry: noProviderRetry);

/// Whether the household has anything the calendar can read: the band and
/// the page exist only then.
final hasLibraryCalendarProvider = Provider<bool>(
  (ref) => ref.watch(calendarConnectionsProvider).isNotEmpty,
);
