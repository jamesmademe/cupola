import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/arr_history_entry_codec.dart';
import 'package:cupola/features/home/presentation/widgets/arrived_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_as_of_line.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

final _now = DateTime(2026, 10, 12, 20, 53);

ArrHistoryEntry _import(String title, {required int tmdbId, Duration? ago}) =>
    ArrHistoryEntry(
      service: ServiceKey.radarr,
      id: tmdbId,
      mediaId: tmdbId,
      title: title,
      unitId: null,
      detail: null,
      // No artwork: a picture would load forever in a test.
      posterUrl: '',
      outcome: ArrImportOutcome.imported,
      at: _now.subtract(ago ?? const Duration(days: 1)),
      reason: null,
      instanceId: 'radarr',
      tmdbId: tmdbId,
    );

ArrHistory _history(List<ArrHistoryEntry> entries) =>
    (entries: entries, coverage: SourceCoverage.answeredBy(ServiceKey.radarr));

/// The Home at a cold start: the last drawing, said for what it is, until the
/// live answer comes.
void main() {
  group('a cold start', () {
    late LastKnownStore store;
    setUp(() => store = LastKnownStore.memory());

    /// One run of the app: a fresh scope over the same [store], as a start
    /// over the same file would be.
    Future<void> run(
      WidgetTester tester,
      Future<ArrHistory> Function() arrivals, {
      SettingsModel Function(SettingsModel)? customize,
      DateTime? now,
    }) async {
      tester.view.physicalSize = const Size(1170, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final clock = now ?? _now;
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            ...await settingsScopeOverrides(
              configured: const [ServiceKey.radarr],
              customize: customize,
            ),
            lastKnownStoreProvider.overrideWithValue(store),
            calendarClockProvider.overrideWithValue(() => clock),
            arrivalsClockProvider.overrideWithValue(() => clock),
            servicesArrivalsProvider.overrideWith((ref) => arrivals()),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(
              body: Column(children: [HomeAsOfLine(), HomeArrivedModule()]),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<void> firstRun(WidgetTester tester) async {
      await run(
        tester,
        () async => _history([_import('Sintel', tmdbId: 2)]),
        now: _now,
      );
      await tester.pumpAndSettle();
      expect(find.text('Sintel'), findsOne);
      expect(find.textContaining('As of'), findsNothing);
    }

    testWidgets('draws the last drawing at once, says so, then the live one', (
      tester,
    ) async {
      await firstRun(tester);

      final answer = Completer<ArrHistory>();
      await run(
        tester,
        () => answer.future,
        now: _now.add(const Duration(hours: 1)),
      );
      // No skeleton: the card the person last saw, and the one line.
      expect(find.text('Sintel'), findsOne);
      expect(find.text('As of 20:53 · checking now'), findsOne);

      answer.complete(_history([_import('Spring', tmdbId: 1)]));
      await tester.pumpAndSettle();
      expect(find.text('Sintel'), findsNothing);
      expect(find.text('Spring'), findsOne);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('a live read that fails keeps the drawing at full ink, over '
        'the failure, and stops checking', (tester) async {
      await firstRun(tester);

      await run(
        tester,
        () async =>
            throw const ClassifiedFailure(ServiceFailureReason.unreachable),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sintel'), findsOne);
      expect(find.textContaining('did not answer'), findsOne);
      expect(find.text('As of 20:53'), findsOne);
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('another server or another person draws nothing of it', (
      tester,
    ) async {
      await firstRun(tester);

      await run(
        tester,
        () => Completer<ArrHistory>().future,
        customize: (settings) => settings.copyWithService(
          ServiceKey.radarr,
          url: 'https://other.test',
          apiKey: 'radarr-key',
        ),
      );
      expect(find.text('Sintel'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('a card the week left behind is not drawn again', (
      tester,
    ) async {
      await firstRun(tester);

      await run(
        tester,
        () => Completer<ArrHistory>().future,
        now: _now.add(const Duration(days: 7)),
      );
      expect(find.text('Sintel'), findsNothing);
    });

    testWidgets('a read with every library silent is not kept', (tester) async {
      await firstRun(tester);
      await run(
        tester,
        () async => (
          entries: const <ArrHistoryEntry>[],
          coverage: SourceCoverage.failure(
            ServiceKey.radarr,
            const ClassifiedFailure(ServiceFailureReason.unreachable),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await run(tester, () => Completer<ArrHistory>().future);
      expect(find.text('Sintel'), findsOne);
    });

    testWidgets('a read no library answered keeps the drawing over the '
        'failure, as a failed read does', (tester) async {
      // The Home's reads do not fail: they answer with every source silent.
      // That is the cold start with no network, the one a drawing is for.
      await firstRun(tester);
      await run(
        tester,
        () async => (
          entries: const <ArrHistoryEntry>[],
          coverage: SourceCoverage.failure(
            ServiceKey.radarr,
            const ClassifiedFailure(ServiceFailureReason.unreachable),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sintel'), findsOne);
      expect(find.textContaining('did not answer'), findsOne);
      expect(find.text('As of 20:53'), findsOne);
    });
  });

  group('the line', () {
    final today = DateTime(2026, 10, 12, 22, 10);

    test('says the oldest drawing, and checking while any is asked for', () {
      expect(homeAsOfWords(const [], now: today), isNull);
      expect(
        homeAsOfWords([
          (asOf: DateTime(2026, 10, 12, 20, 53), checking: false),
          (asOf: DateTime(2026, 10, 12, 21, 30), checking: true),
        ], now: today),
        'As of 20:53 · checking now',
      );
      expect(
        homeAsOfWords([
          (asOf: DateTime(2026, 10, 12, 20, 53), checking: false),
        ], now: today),
        'As of 20:53',
      );
    });

    test('names the day as a row about a person does', () {
      expect(
        formatAsOf(DateTime(2026, 10, 11, 20, 53), now: today),
        'yesterday 20:53',
      );
      expect(
        formatAsOf(DateTime(2026, 10, 7, 9, 5), now: today),
        'Wednesday 09:05',
      );
      expect(formatAsOf(DateTime(2026, 9, 29, 9, 5), now: today), 'Tue 29 Sep');
    });
  });

  test('a history record survives its codec whole', () {
    final entry = ArrHistoryEntry(
      service: ServiceKey.sonarr,
      id: 7,
      mediaId: 3,
      title: 'Andor',
      unitId: 2,
      detail: 'S2 E4',
      posterUrl: 'https://image.tmdb.org/t/p/w500/a.jpg',
      outcome: ArrImportOutcome.imported,
      at: DateTime.utc(2026, 10, 12, 18, 30),
      reason: null,
      instanceId: 'sonarr-4k',
      connectionName: '4K',
      tmdbId: 83867,
      backdropUrl: 'https://image.tmdb.org/t/p/w1280/b.jpg',
      mediaAddedAt: DateTime.utc(2026, 10, 1),
      fileName: 'Andor.S02E04.mkv',
      downloadId: 'ABC',
    );
    final back = arrHistoryEntryFromJson(arrHistoryEntryToJson(entry))!;
    expect(arrHistoryEntryToJson(back), arrHistoryEntryToJson(entry));
    expect(back.at!.isAtSameMomentAs(entry.at!), isTrue);
    expect(arrHistoryEntryFromJson({'service': 'nope'}), isNull);
  });
}
