/// The "On your server" rows of a film, against the households of the
/// configuration inventory: one row per fact, each from its own connection,
/// and a missing or silent service costing its own row, never the page.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';

import '../../test_helpers/profiles/profiles.dart';

/// The rows of [title] under [profile], once no source is still waiting.
Future<List<MediaRow>> _rows(
  ConfigProfile profile,
  WorldTitle title, {
  MediaKey? key,
}) async {
  final harness = await ProfileHarness.start(profile);
  final container = harness.container();
  key ??= title.isSeries
      ? MediaKey.tv(title.tmdbId)
      : MediaKey.movie(title.tmdbId);
  final rows = mediaRowsProvider(key);
  container.listen(rows, (_, _) {});
  for (var turn = 0; turn < 200; turn++) {
    final now = container.read(rows);
    final waiting = now.any(
      (row) => row is MediaConnectionRow && row.reading is MediaReadingWaiting,
    );
    if (!waiting) return now;
    await pumpEventQueue();
  }
  fail('a source of ${title.title} never answered under ${profile.id}');
}

/// Each row as `service:connection` (or `service` when it has none), with
/// the shape of what it holds, so an order and a set read at a glance.
String _describe(MediaRow row) => switch (row) {
  MediaConnectionRow(:final connection, :final reading) =>
    '${connection.id}:${switch (reading) {
      MediaReadingAnswered() => 'answered',
      MediaReadingFailed() => 'failed',
      MediaReadingWaiting() => 'waiting',
    }}',
  MediaThroughSeerrRow(:final copy) =>
    '${copy.arr.name}${copy.copy.is4k ? '-4k' : ''}:through-seerr',
  MediaNotSetUpRow(:final service) => '${service.name}:not-set-up',
};

T _answer<T>(MediaRow row) =>
    ((row as MediaConnectionRow).reading as MediaReadingAnswered).answer.value
        as T;

MediaRow _row(List<MediaRow> rows, String connectionId) => rows.firstWhere(
  (row) => row is MediaConnectionRow && row.connection.id == connectionId,
);

void main() {
  group('P1, the full household', () {
    test('Tears of Steel: Jellyfin, both Radarr, Bazarr, Seerr, in that '
        'order', () async {
      final rows = await _rows(Profiles.p1, WorldTitles.tearsOfSteel);

      expect(rows.map(_describe), [
        '${WorldIds.jellyfin}:answered',
        '${WorldIds.radarr}:answered',
        '${WorldIds.radarr4k}:answered',
        '${WorldIds.bazarr}:answered',
        '${WorldIds.seerr}:answered',
      ]);
    });

    test('each Radarr answers about its own copy, by its own id', () async {
      final rows = await _rows(Profiles.p1, WorldTitles.tearsOfSteel);

      final hd = _answer<MediaRadarrCopy>(_row(rows, WorldIds.radarr));
      final uhd = _answer<MediaRadarrCopy>(_row(rows, WorldIds.radarr4k));
      expect(hd.movie?.id, 5);
      expect(uhd.movie?.id, 4);
      expect(hd.status?.availability, MediaAvailability.available);
      expect(uhd.status?.availability, MediaAvailability.available);
    });

    test('Bazarr covers the copy it follows, checked, and names it', () async {
      final rows = await _rows(Profiles.p1, WorldTitles.tearsOfSteel);

      final bazarr = _answer<MediaBazarrCopy?>(_row(rows, WorldIds.bazarr));
      expect(bazarr?.arrConnectionId, WorldIds.radarr);
      expect(
        bazarr?.movie?.missingLanguages.map((language) => language.code2),
        contains('de'),
      );
    });

    test('Jellyfin holds the film, verified by its ids', () async {
      final rows = await _rows(Profiles.p1, WorldTitles.tearsOfSteel);

      final jellyfin = _answer<MediaStreamCopy>(_row(rows, WorldIds.jellyfin));
      expect(jellyfin.outcome, StreamLookupOutcome.found);
      expect(jellyfin.item?.title, WorldTitles.tearsOfSteel.title);
    });

    test('a match whose ids differ is no match: no Jellyfin row at all '
        '(case f)', () async {
      final rows = await _rows(Profiles.p1, WorldTitles.elephantsDream);

      expect(rows.where((row) => row.service == ServiceKey.jellyfin), isEmpty);
    });

    test(
      'a film no Radarr tracks: each Radarr answers, holding nothing',
      () async {
        final rows = await _rows(Profiles.p1, WorldTitles.charge);

        expect(
          _answer<MediaRadarrCopy>(_row(rows, WorldIds.radarr)).isTracked,
          isFalse,
        );
        expect(
          _answer<MediaRadarrCopy>(_row(rows, WorldIds.radarr4k)).isTracked,
          isFalse,
        );
        expect(_answer<MediaBazarrCopy?>(_row(rows, WorldIds.bazarr)), isNull);
      },
    );
  });

  group('a series', () {
    test('P1, Cosmos Laundromat: Sonarr asked by the TVDB id Seerr names, '
        'Bazarr on its copy', () async {
      final rows = await _rows(Profiles.p1, WorldTitles.cosmosLaundromat);

      expect(rows.map(_describe), [
        '${WorldIds.jellyfin}:answered',
        '${WorldIds.sonarr}:answered',
        '${WorldIds.bazarr}:answered',
        '${WorldIds.seerr}:answered',
      ]);
      final sonarr = _answer<MediaSonarrCopy>(_row(rows, WorldIds.sonarr));
      expect(sonarr.series?.tvdbId, WorldTitles.cosmosLaundromat.tvdbId);
      final bazarr = _answer<MediaBazarrCopy?>(_row(rows, WorldIds.bazarr));
      expect(bazarr?.arrConnectionId, WorldIds.sonarr);
      expect(bazarr?.series?.title, WorldTitles.cosmosLaundromat.title);
    });

    test('known by TVDB alone, without Seerr: Sonarr answers, Seerr is not '
        'asked', () async {
      final rows = await _rows(
        Profiles.p4,
        WorldTitles.cosmosLaundromat,
        key: MediaKey.tvdb(WorldTitles.cosmosLaundromat.tvdbId!),
      );

      expect(rows.map(_describe), [
        '${WorldIds.sonarr}:answered',
        'seerr:not-set-up',
      ]);
      expect(
        _answer<MediaSonarrCopy>(_row(rows, WorldIds.sonarr)).isTracked,
        isTrue,
      );
    });
  });

  group('P5, known through Seerr', () {
    test("Radarr reads as Seerr's claim, not as set up (case b)", () async {
      final rows = await _rows(Profiles.p5, WorldTitles.tearsOfSteel);

      expect(rows.map(_describe), [
        '${WorldIds.jellyfin}:answered',
        'radarr:through-seerr',
        '${WorldIds.seerr}:answered',
      ]);
      final claim = rows.whereType<MediaThroughSeerrRow>().single;
      expect(claim.seerr.id, WorldIds.seerr);
      expect(claim.copy.connection, isNull);
      expect(claim.copy.copy.externalId, 5);
    });
  });

  group('P4, an arr stack without Seerr', () {
    test('Seerr costs one row, set up from there; nothing else is '
        'asked of it (case a)', () async {
      final rows = await _rows(Profiles.p4, WorldTitles.tearsOfSteel);

      expect(rows.map(_describe), [
        '${WorldIds.radarr}:answered',
        'seerr:not-set-up',
      ]);
    });
  });

  group('P7, degraded and away', () {
    test('Jellyfin did not answer: its row says so; the others still '
        'answer (case c)', () async {
      final rows = await _rows(Profiles.p7, WorldTitles.tearsOfSteel);

      final jellyfin = _row(rows, WorldIds.jellyfin) as MediaConnectionRow;
      final reading = jellyfin.reading as MediaReadingFailed;
      expect(reading.failure, ServiceFailureReason.unreachable);
      expect(reading.lastKnown, isNull);
      expect(
        _answer<MediaRadarrCopy>(_row(rows, WorldIds.radarr)).isTracked,
        isTrue,
      );
    });
  });

  test('a failed refresh keeps the last answer under the failure', () async {
    var fails = false;
    final answer = MediaAnswer<int>(42, DateTime(2026, 10, 3, 20, 41));
    final source = FutureProvider<MediaAnswer<int>>((ref) async {
      if (fails) throw StateError('gone');
      return answer;
    });
    final container = ProviderContainer(retry: (_, _) => null);
    addTearDown(container.dispose);
    container.listen(source, (_, _) {});
    await container.read(source.future);

    fails = true;
    container.invalidate(source);
    await expectLater(container.read(source.future), throwsStateError);

    final reading = MediaReading.of(container.read(source));
    expect(reading, isA<MediaReadingFailed<int>>());
    expect((reading as MediaReadingFailed<int>).lastKnown, same(answer));
  });
}
