import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/home/domain/featured.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

import '../../../test_helpers/settings_scope.dart';

final _now = DateTime(2026, 9, 29, 20, 41);

StreamItem _item(
  String id,
  String title, {
  StreamItemKind kind = StreamItemKind.movie,
  String? backdropPath,
  int? resumeOffsetMs,
}) => StreamItem(
  id: id,
  title: title,
  subtitle: null,
  kind: kind,
  posterPath: null,
  backdropPath: backdropPath,
  year: 2021,
  runtimeMs: 1500000,
  isPlayed: false,
  resumeOffsetMs: resumeOffsetMs,
  unplayedChildCount: null,
);

ArrHistoryEntry _arrival(String title, {int tmdbId = 7}) => ArrHistoryEntry(
  service: ServiceKey.radarr,
  id: 1,
  mediaId: 1,
  title: title,
  unitId: null,
  detail: null,
  posterUrl: '',
  outcome: ArrImportOutcome.imported,
  at: _now.subtract(const Duration(hours: 2)),
  reason: null,
  instanceId: 'radarr',
  tmdbId: tmdbId,
  backdropUrl: 'https://art.test/$title.jpg',
);

final _spriteFright = CalendarEvent(
  identity: 'sprite-fright',
  kind: CalendarKind.movie,
  day: DateTime(2026, 9, 29),
  title: 'Sprite Fright',
  release: Lexicon.onDigital,
  backdrop: (url: 'https://art.test/sprite-fright.jpg', headers: null),
  state: CalendarState.inFlight(
    mediaStatusFromQueue(
      availability: MediaAvailability.missing,
      monitored: true,
      queueEntry: const ArrQueueEntry(
        pipeline: MediaPipeline.downloading,
        progress: 0.62,
      ),
    ),
  ),
);

/// What Featured reads: the sources the Home's modules already hold, and for
/// its arrival, whether a media server holds it.
void main() {
  Future<ProviderContainer> containerWith({
    List<ServiceKey> configured = const [
      ServiceKey.jellyfin,
      ServiceKey.radarr,
    ],
    Future<ArrHistory> Function()? arrivals,
    MediaStreamCopy copy = const MediaStreamCopy.notInLibrary(),
    void Function()? onResumeRead,
    List<Override> extra = const [],
  }) async {
    final scope = await settingsScopeOverrides(configured: configured);
    late final ProviderContainer container;
    container = ProviderContainer(
      overrides: [
        ...scope,
        arrivalsClockProvider.overrideWithValue(() => _now),
        calendarClockProvider.overrideWithValue(() => _now),
        homeResumeProvider.overrideWith((ref) async {
          onResumeRead?.call();
          final jellyfin = ref
              .read(currentSettingsProvider)
              .configuredInstancesOf(ServiceKey.jellyfin)
              .first;
          return (
            rows: [
              (
                service: ServiceKey.jellyfin,
                instanceId: jellyfin.id,
                connectionName: null,
                item: _item(
                  'e1',
                  'Cosmos Laundromat',
                  backdropPath: '/Items/e1/Images/Backdrop/0?tag=t',
                  resumeOffsetMs: 1200000,
                ),
              ),
            ],
            coverage: SourceCoverage.answeredBy(ServiceKey.jellyfin),
            viewerMissing: const <String>[],
          );
        }),
        servicesArrivalsProvider.overrideWith(
          (ref) =>
              arrivals?.call() ??
              Future.value((
                entries: [_arrival('Spring')],
                coverage: SourceCoverage.answeredBy(ServiceKey.radarr),
              )),
        ),
        libraryCalendarProvider.overrideWith(
          (ref) async => LibraryCalendar(
            window: CalendarWindow.from(_now),
            events: [_spriteFright],
            answered: const ['Radarr'],
            silent: const [],
            kinds: const {},
            readAt: _now,
          ),
        ),
        mediaStreamCopyProvider.overrideWith(
          (ref, source) async => MediaAnswer(copy, _now),
        ),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<List<FeaturedSlide>> slidesOf(ProviderContainer container) async {
    final subscription = container.listen(featuredProvider, (_, _) {});
    addTearDown(subscription.close);
    return container.read(featuredProvider.future);
  }

  test('a slide from each source, and the arrival plays where Jellyfin holds '
      'it', () async {
    final container = await containerWith(
      copy: MediaStreamCopy.found(_item('jf-spring', 'Spring')),
    );
    final slides = await slidesOf(container);
    expect(slides.map((slide) => slide.title), [
      'Cosmos Laundromat',
      'Spring',
      'Sprite Fright',
    ]);
    final resume = slides[0] as FeaturedResume;
    expect(resume.art.url, contains('/Items/e1/Images/Backdrop/0'));
    final arrival = slides[1] as FeaturedArrival;
    expect(arrival.play?.server.service, ServiceKey.jellyfin);
    expect(arrival.play?.item.id, 'jf-spring');
    expect((slides[2] as FeaturedToday).downloading, isTrue);
  });

  test('an arrival no media server holds has no Play', () async {
    final container = await containerWith();
    final slides = await slidesOf(container);
    expect((slides[1] as FeaturedArrival).play, isNull);
  });

  test('a source that did not answer gives no slide, and no failure', () async {
    final container = await containerWith(
      arrivals: () async => (
        entries: const <ArrHistoryEntry>[],
        coverage: SourceCoverage.failure(
          ServiceKey.radarr,
          Exception('Radarr did not answer'),
        ),
      ),
    );
    final slides = await slidesOf(container);
    expect(slides.map((slide) => slide.title), [
      'Cosmos Laundromat',
      'Sprite Fright',
    ]);
  });

  test('without a media server: no resume read, and nothing plays', () async {
    var resumeRead = false;
    final container = await containerWith(
      configured: const [ServiceKey.radarr],
      copy: MediaStreamCopy.found(_item('jf-spring', 'Spring')),
      onResumeRead: () => resumeRead = true,
    );
    final slides = await slidesOf(container);
    expect(resumeRead, isFalse);
    expect(slides.map((slide) => slide.title), ['Spring', 'Sprite Fright']);
    expect((slides[0] as FeaturedArrival).play, isNull);
  });

  test('nothing that feeds it is set up: no slide', () async {
    final container = await containerWith(configured: const []);
    expect(await slidesOf(container), isEmpty);
  });

  test(
    'the room is lit by the slide in front once its artwork is drawn',
    () async {
      const light = TitleLight(
        light: Color(0xFF50B1D2),
        actionFill: Color(0xFF8ED6F2),
        actionInk: Color(0xFF0C222A),
        dayPrimary: Color(0xFF00677F),
      );
      final container = await containerWith(
        extra: [titleLightProvider.overrideWith((ref, url) async => light)],
      );
      final slides = await slidesOf(container);
      final room = container.listen(featuredRoomLightProvider, (_, _) {});
      addTearDown(room.close);
      expect(room.read(), isNull);

      container.read(featuredViewProvider.notifier).drawn(slides[0].art.url);
      await container.read(titleLightProvider(slides[0].art.url).future);
      expect(room.read(), light.light);

      // The next slide's picture is not drawn yet: the lamp, until it is.
      container.read(featuredViewProvider.notifier).show(1);
      expect(room.read(), isNull);
    },
  );
}
