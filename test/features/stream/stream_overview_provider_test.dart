import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/presentation/stream_overview_provider.dart';

/// The window rules of the media-server Overview, as pure functions.
///
/// Every one of them takes an explicit `now`, which is the whole reason they are
/// top-level: a boundary asserted against a real clock is a test that passes at
/// 14:00 and fails at 23:59.
void main() {
  group('streamScanAgeLabel', () {
    final now = DateTime(2026, 9, 17, 14, 0);

    test('reads in the shared relative vocabulary', () {
      expect(
        streamScanAgeLabel(now.subtract(const Duration(minutes: 20)), now: now),
        '20 min ago',
      );
      expect(
        streamScanAgeLabel(now.subtract(const Duration(hours: 2)), now: now),
        '2 h ago',
      );
      expect(
        streamScanAgeLabel(now.subtract(const Duration(days: 2)), now: now),
        '2 days ago',
      );
    });

    test('a scan finishing seconds ago is "just now", not "0 min ago"', () {
      expect(
        streamScanAgeLabel(now.subtract(const Duration(seconds: 20)), now: now),
        'just now',
      );
    });

    test('a host whose clock runs ahead still reads "just now"', () {
      // The case this function exists for. A NAS four minutes ahead of the
      // phone hands back a `scannedAt` in the future, and the shared formatter
      // answers that honestly with "in 4 min" — which under a heading reading
      // *Last scan* is not a sentence. The scan happened; only the two clocks
      // disagree about when.
      expect(
        streamScanAgeLabel(now.add(const Duration(minutes: 4)), now: now),
        'just now',
      );
      // And exactly on the boundary, where `isBefore` is false.
      expect(streamScanAgeLabel(now, now: now), 'just now');
    });
  });

  group('streamShelfRows', () {
    final now = DateTime(2026, 9, 17, 14, 0);

    test('names the rooms, not just whether a broom is moving', () {
      // The region's substance, and the reason it is worth a third of the
      // page: `getLibraries` already answered names and kinds, so a Jellyfin
      // server at rest — the majority state of a home server — says what is on
      // the shelf instead of only "no scan running".
      final rows = streamShelfRows([
        _library(name: 'Films', kind: StreamLibraryKind.movies),
        _library(name: 'Kids TV', kind: StreamLibraryKind.shows),
      ], now: now);

      expect(rows.map((row) => row.title), ['Films', 'Kids TV']);
      expect(rows.map((row) => row.detail), ['Movies', 'Shows']);
      expect(rows.map((row) => row.tone), [
        StatusTone.neutral,
        StatusTone.neutral,
      ]);
    });

    test('a detail never repeats the title', () {
      // Both servers ship with libraries named exactly after their kind, and
      // `Movies` under `Movies` is a row reporting itself twice. The kind is
      // the leading glyph's job when the name has already said it.
      final rows = streamShelfRows([
        _library(name: 'Movies', kind: StreamLibraryKind.movies),
        // Case and padding do not make it a different word.
        _library(name: ' shows ', kind: StreamLibraryKind.shows),
        // A Jellyfin library of unclassified content, whose kind label is the
        // word "Library" — worse than a stutter under a library's name.
        _library(name: 'Home video', kind: StreamLibraryKind.other),
      ], now: now);

      expect(rows.map((row) => row.detail), ['', '', 'Library']);
    });

    test('a scan in progress is informational, never a fault', () {
      final rows = streamShelfRows([
        _library(name: 'Films', refreshing: true),
        _library(name: 'Shows'),
      ], now: now);

      expect(rows.first.title, 'Films');
      expect(rows.first.detail, 'Movies · Scanning');
      // Blue, not amber: the server is doing exactly what it was asked to do.
      // Amber is reserved for a fault, and a working library wearing it is how
      // the five-arm tone rule breaks.
      expect(rows.first.tone, StatusTone.info);
    });

    test('a scan is promoted above the rooms the peek would otherwise show', () {
      // Otherwise a rescan of the ninth library is pushed off a three-row peek
      // by the eight rooms listed before it.
      final rows = streamShelfRows([
        for (var i = 0; i < 8; i++) _library(name: 'Library $i'),
        _library(name: 'Concerts', refreshing: true),
      ], now: now);

      expect(rows.first.title, 'Concerts');
    });

    test('rows are capped and the remainder is left to the census', () {
      final rows = streamShelfRows([
        for (var i = 0; i < 9; i++)
          _library(name: 'Library $i', refreshing: true),
      ], now: now);

      // Three rows out of nine scans. Nothing here states a total — the
      // header's subtitle is built from the whole list — so the sample is
      // never presented as the count.
      expect(rows, hasLength(streamShelfPeekLimit));
    });

    test('while a library is scanning, its last scan is not also reported', () {
      final rows = streamShelfRows([
        _library(
          name: 'Films',
          refreshing: true,
          scannedAt: now.subtract(const Duration(hours: 5)),
        ),
      ], now: now);

      // "Scanned 5 h ago" beside "Scanning" is the stale half of the same fact.
      expect(rows.single.detail, 'Movies · Scanning');
    });

    test('a room at rest carries the age of its own scan', () {
      final rows = streamShelfRows([
        _library(
          name: 'Movies',
          scannedAt: now.subtract(const Duration(hours: 2)),
        ),
      ], now: now);

      expect(rows.single.detail, 'Scanned 2 h ago');
      expect(rows.single.kind, StreamShelfKind.atRest);
    });

    test(
      'a library the server gave no scan time for is never "never scanned"',
      () {
        // Every Jellyfin library lands here: that server exposes no per-library
        // timestamp, so null means "not reported" and "never scanned" at once.
        // The room is still named — the half of the row the server did answer.
        final rows = streamShelfRows([_library(name: 'Films')], now: now);

        expect(rows.single.title, 'Films');
        expect(rows.single.detail, 'Movies');
        expect(rows.single.detail, isNot(contains('never')));
      },
    );

    test('an empty server reports nothing rather than a zero', () {
      expect(streamShelfRows(const [], now: now), isEmpty);
    });

    test('a row speaks one sentence with the dots read as pauses', () {
      final rows = streamShelfRows([
        _library(name: 'Films', refreshing: true),
      ], now: now);

      expect(rows.single.spoken, 'Films, Movies, Scanning');
    });

    test('a room with nothing to add speaks its name alone', () {
      final rows = streamShelfRows([_library(name: 'Movies')], now: now);

      // Not "Movies, " with a trailing pause: an empty detail is dropped
      // rather than joined.
      expect(rows.single.spoken, 'Movies');
    });
  });

  group('streamLibrariesCensus', () {
    test('counts the rooms a server that answered actually has', () {
      expect(
        streamLibrariesCensus(
          libraries: [
            _library(name: 'Movies', refreshing: true),
            _library(name: 'Shows'),
          ],
          serverAnswering: true,
        ),
        '2 libraries · Movies scanning',
      );
    });

    test('a list still in flight is not a zero', () {
      expect(
        streamLibrariesCensus(libraries: null, serverAnswering: true),
        isNull,
      );
    });

    test('an empty shelf on a server that answered is genuinely empty', () {
      expect(
        streamLibrariesCensus(libraries: const [], serverAnswering: true),
        '0 libraries',
      );
    });

    test('an empty list from a dark server is a silence, not a zero', () {
      // The defect this function exists for. Both clients end `getLibraries`
      // with `catch (_) { return const []; }` and neither provider re-throws,
      // so a server that is off the LAN or 502-ing behind a proxy resolves to
      // `data([])` — and "0 libraries" over that reads as a shelf whose
      // libraries were deleted, which is the claim a user acts on.
      expect(
        streamLibrariesCensus(libraries: const [], serverAnswering: false),
        isNull,
      );
      expect(
        streamLibrariesUnanswered(libraries: const [], serverAnswering: false),
        isTrue,
      );
    });

    test('rooms in hand outrank whatever the probe is saying this second', () {
      // A list with libraries in it was answered by definition; a probe that
      // has not landed yet must not turn a real census into an em dash.
      expect(
        streamLibrariesCensus(
          libraries: [_library(name: 'Movies')],
          serverAnswering: false,
        ),
        '1 library',
      );
    });
  });

  group('streamOnDeckPreview', () {
    test('drops an item that could not be opened', () {
      // The tile's whole purpose is to open the thing. A poster that routes
      // nowhere is a control that fails, which is worse than one fewer poster.
      final items = streamOnDeckPreview([
        _item(id: '', title: 'Ghost'),
        _item(id: '12', title: 'Severance'),
      ]);

      expect(items.map((item) => item.title), ['Severance']);
    });

    test('drops an episode that arrived in two hubs at once', () {
      // `PlexClient._itemsFromHubs` concatenates `Metadata` across every hub
      // with no dedupe, and `/hubs/continueWatching` answers as a hub list on
      // some builds — so one episode sitting in Continue watching *and* On deck
      // arrives twice under one ratingKey. Two tiles for one episode is the
      // visible half; two Heroes sharing a tag is an assertion at flight time.
      final items = streamOnDeckPreview([
        _item(id: '12', title: 'Severance'),
        _item(id: '12', title: 'Severance'),
        _item(id: '13', title: 'Andor'),
      ]);

      expect(items.map((item) => item.title), ['Severance', 'Andor']);
    });

    test('caps at the rail length', () {
      final items = streamOnDeckPreview([
        for (var i = 0; i < 20; i++) _item(id: '$i', title: 'Item $i'),
      ]);

      expect(items, hasLength(streamOnDeckPreviewLimit));
    });
  });

  group('streamOnDeckCaption', () {
    test('names what it belongs to, then how far in', () {
      expect(
        streamOnDeckCaption(
          _item(subtitle: 'S02E05', runtimeMs: 3000, resumeMs: 900),
        ),
        'S02E05 · 30% in',
      );
    });

    test('falls back to the year when there is no parent', () {
      expect(streamOnDeckCaption(_item(year: 2024)), '2024');
    });

    test('a runtime the server withheld costs the figure, not the row', () {
      // No percentage rather than a made-up one: `resumeOffsetMs` alone is half
      // of a position, and a film with no runtime cannot be a fraction of
      // anything.
      expect(
        streamOnDeckCaption(_item(subtitle: 'S02E05', resumeMs: 900)),
        'S02E05',
      );
    });

    test('an item watched to the end says so', () {
      expect(streamOnDeckCaption(_item(played: true)), 'watched');
    });
  });
}

StreamLibrary _library({
  String name = 'Library',
  StreamLibraryKind kind = StreamLibraryKind.movies,
  bool refreshing = false,
  DateTime? scannedAt,
}) => StreamLibrary(
  id: name,
  name: name,
  kind: kind,
  itemCount: null,
  lastScannedAt: scannedAt,
  isRefreshing: refreshing,
);

StreamItem _item({
  String id = '1',
  String title = 'Title',
  String? subtitle,
  int? year,
  int? runtimeMs,
  int? resumeMs,
  bool played = false,
}) => StreamItem(
  id: id,
  title: title,
  subtitle: subtitle,
  kind: StreamItemKind.movie,
  posterPath: null,
  year: year,
  runtimeMs: runtimeMs,
  isPlayed: played,
  resumeOffsetMs: resumeMs,
  unplayedChildCount: null,
);
