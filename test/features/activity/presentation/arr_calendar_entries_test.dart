import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/activity/presentation/arr_calendar_screen.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

/// `YYYY-MM-DDT00:00:00Z`, the way the *arrs store a release date.
String _arrDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}T00:00:00Z';

final _start = DateTime(2026, 10, 1);
final _end = DateTime(2026, 10, 31);

List<ArrCalendarEntry> _entries(
  List<Map<String, dynamic>> records, [
  ServiceKey service = ServiceKey.radarr,
]) =>
    arrCalendarEntries(records, service, windowStart: _start, windowEnd: _end);

class _CalendarRadarr extends FakeRadarrService {
  _CalendarRadarr(this.records);

  final List<Map<String, dynamic>> records;

  @override
  Future<List<dynamic>> getCalendar({
    DateTime? start,
    DateTime? end,
    Map<String, dynamic>? queryParameters,
  }) async => records;
}

void main() {
  group('arrCalendarEntries', () {
    test('a film is one row per dated event in the window, named', () {
      // One Radarr record carries all three dates. The page used to pick the
      // first in the window, so the disc release twelve days on never showed.
      final entries = _entries([
        {
          'title': 'Sprite Fright',
          'inCinemas': '2021-11-10T00:00:00Z',
          'digitalRelease': '2026-10-01T00:00:00Z',
          'physicalRelease': '2026-10-12T00:00:00Z',
        },
      ]);

      expect(entries.map((e) => e.event), ['on digital', 'on disc']);
      expect(entries.map((e) => e.day), [
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 12),
      ]);
      expect(entries.map((e) => arrCalendarTitle(e, ServiceKey.radarr)), [
        'Sprite Fright · on digital',
        'Sprite Fright · on disc',
      ]);
    });

    test('a release date is the calendar date it spells, in any timezone', () {
      // Midnight UTC is the previous evening west of Greenwich, and a late UTC
      // hour is the next morning east of it: `.toLocal()` moved the film a day
      // in one hemisphere or the other. Both read as the 12th here, wherever
      // the suite runs.
      final entries = _entries([
        {'title': 'A', 'digitalRelease': '2026-10-12T00:00:00Z'},
        {'title': 'B', 'digitalRelease': '2026-10-12T23:30:00Z'},
      ]);

      expect(entries.map((e) => e.day), [
        DateTime(2026, 10, 12),
        DateTime(2026, 10, 12),
      ]);
    });

    test("an episode's air time is an instant, on the device's clock", () {
      const airs = '2026-10-05T01:00:00Z';
      final entries = _entries([
        {'title': 'Ozymandias', 'airDateUtc': airs, 'airDate': '2026-10-04'},
      ], ServiceKey.sonarr);

      expect(entries.single.day, DateTime.parse(airs).toLocal());
      expect(entries.single.event, isNull);
    });

    test('rows across records come in date order', () {
      final entries = _entries([
        {
          'title': 'Sprite Fright',
          'digitalRelease': '2026-10-01T00:00:00Z',
          'physicalRelease': '2026-10-12T00:00:00Z',
        },
        {'title': 'Charge', 'digitalRelease': '2026-10-05T00:00:00Z'},
      ]);

      expect(entries.map((e) => arrCalendarTitle(e, ServiceKey.radarr)), [
        'Sprite Fright · on digital',
        'Charge · on digital',
        'Sprite Fright · on disc',
      ]);
    });

    test('a film with no date inside the window keeps one row', () {
      // The server reads the window in its own timezone, so a film can come
      // back with its date a day outside ours. It is not dropped.
      final entries = _entries([
        {'title': 'Edge', 'physicalRelease': '2026-11-01T00:00:00Z'},
      ]);

      expect(entries.single.day, DateTime(2026, 11, 1));
      expect(entries.single.event, 'on disc');
    });

    test('a record with no readable date is a row with no day', () {
      final entries = _entries([
        {'title': 'Undated'},
      ]);

      expect(entries.single.day, isNull);
    });
  });

  testWidgets('the calendar draws both of a film\'s dates, each named', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final disc = DateTime(now.year, now.month, now.day + 11);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWith(
              radarrUrl: 'https://radarr.example.com',
              radarrApiKey: 'key',
            ),
          ),
          radarrServiceProvider.overrideWithValue(
            _CalendarRadarr([
              {
                'title': 'Sprite Fright',
                'monitored': true,
                'inCinemas': '2021-11-10T00:00:00Z',
                'digitalRelease': _arrDate(today),
                'physicalRelease': _arrDate(disc),
              },
            ]),
          ),
        ],
        child: const MaterialApp(
          home: ArrCalendarScreen(service: ServiceKey.radarr),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Sprite Fright · on digital'), findsOneWidget);
    expect(find.text('Sprite Fright · on disc'), findsOneWidget);
    expect(find.text(formatIsoDate(today.toIso8601String())), findsOneWidget);
    expect(find.text(formatIsoDate(disc.toIso8601String())), findsOneWidget);
  });
}
