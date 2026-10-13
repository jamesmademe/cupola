import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/core/last_known/stored_image.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart'
    show StatusTone, statusToneColor;
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/home/data/last_known/downloads_last_known.dart';
import 'package:cupola/features/home/data/last_known/service_queue_item_codec.dart';
import 'package:cupola/features/home/domain/downloads.dart';
import 'package:cupola/features/home/presentation/widgets/downloads_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_as_of_line.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/home/data/home_last_known.dart';

import '../../../test_helpers/settings_scope.dart';

final _now = DateTime(2026, 10, 12, 20, 53);

const _noPicture = <String, Object?>{};

ServiceQueueItem _item(
  String title, {
  String id = '7',
  ServiceKey service = ServiceKey.radarr,
  double? progress = 0.5,
  int? eta = 600,
  InFlightFault? fault,
  String? release,
  String? poster,
  int? rate,
}) => ServiceQueueItem(
  service: service,
  id: id,
  title: title,
  progress: progress,
  clientLabel: 'qBittorrent',
  etaSeconds: eta,
  fault: fault,
  clientService: ServiceKey.qbittorrent,
  instanceId: 'radarr',
  downloadId: 'HASH-$id',
  // Pictures load forever in a widget test: none unless the test is about one.
  posterUrl: poster,
  rateBytesPerSecond: rate,
  outputPath: '/data/torrents/private-folder/$title',
  warning: 'The arr says no',
  stalledSince: _now.subtract(const Duration(hours: 3)),
  names: release == null
      ? null
      : MediaNames(
          title: title,
          machineName: release,
          machineKind: MachineNameKind.release,
        ),
);

ServicesInFlight _inFlight({
  List<ServiceQueueItem> moving = const [],
  List<ServiceQueueItem> queued = const [],
  List<ServiceQueueItem> faults = const [],
  int? rate,
  SourceCoverage? coverage,
}) => (
  preview: moving,
  activeCount: moving.length,
  movingCount: moving.length,
  queued: queued,
  faults: faults,
  held: 0,
  rateBytesPerSecond: rate,
  clients: rate == null ? 0 : 1,
  coverage:
      coverage ??
      SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.radarr),
        SourceCoverage.answeredBy(ServiceKey.qbittorrent),
      ]),
);

/// The household's evening: two moving, one stuck, one waiting its turn, at
/// 40 MB/s.
ServicesInFlight _evening() => _inFlight(
  moving: [
    _item(
      'Sprite Fright',
      id: '1',
      progress: 0.88,
      eta: 60,
      release: 'Sprite.Fright.2021.1080p.WEB',
      rate: 30000000,
    ),
    _item('Elephants Dream', id: '2', progress: 0.31, eta: 360),
  ],
  faults: [
    _item(
      'Big Buck Bunny',
      id: '3',
      progress: 0.47,
      fault: InFlightFault.stalled,
    ),
    _item('Cosmos', id: '4', fault: InFlightFault.needsImport),
  ],
  queued: [_item('Sintel', id: '5', progress: null, eta: null)],
  rate: 40400000,
);

ArrHistory _noHistory() =>
    (entries: const <ArrHistoryEntry>[], coverage: SourceCoverage.none);

ArrHistory _importedAt(DateTime at) => (
  entries: [
    ArrHistoryEntry(
      service: ServiceKey.radarr,
      id: 1,
      mediaId: 1,
      title: 'Spring',
      unitId: null,
      detail: null,
      posterUrl: '',
      outcome: ArrImportOutcome.imported,
      at: at,
      reason: null,
      instanceId: 'radarr',
    ),
  ],
  coverage: SourceCoverage.answeredBy(ServiceKey.radarr),
);

/// Downloads at a cold start: the last drawing, with the figures that run
/// stopped and no fault judged, until the live answer comes.
void main() {
  group('a cold start', () {
    late LastKnownStore store;
    setUp(() => store = LastKnownStore.memory());

    Future<void> run(
      WidgetTester tester,
      Future<ServicesInFlight> Function() queue, {
      Future<ArrHistory> Function()? history,
      SettingsModel Function(SettingsModel)? customize,
      DateTime? now,
    }) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final clock = now ?? _now;
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            ...await settingsScopeOverrides(
              configured: const [ServiceKey.radarr, ServiceKey.qbittorrent],
              customize: customize,
            ),
            lastKnownStoreProvider.overrideWithValue(store),
            calendarClockProvider.overrideWithValue(() => clock),
            stallClockProvider.overrideWithValue(() => clock),
            arrivalsClockProvider.overrideWithValue(() => clock),
            servicesInFlightProvider.overrideWith((ref) => queue()),
            servicesArrHistoryProvider.overrideWith(
              (ref) => (history ?? () async => _noHistory())(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [HomeAsOfLine(), HomeDownloadsModule()],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    /// The first run: what the household's evening looks like live, with its
    /// speed, its time left and its stuck row and remedy.
    Future<void> firstRun(
      WidgetTester tester, {
      ServicesInFlight? answer,
    }) async {
      await run(tester, () async => answer ?? _evening());
      await tester.pumpAndSettle();
      expect(find.textContaining('As of'), findsNothing);
    }

    testWidgets('the live module of the first run states its speed, its time '
        'left and its stuck row with a remedy', (tester) async {
      await firstRun(tester);
      expect(
        find.textContaining(
          RegExp(r'^2 moving · 1 stuck · 1 queued · [\d.]+.MB/s'),
        ),
        findsOne,
      );
      expect(find.text('88% · 1\u00A0min'), findsOne);
      expect(find.text('Stuck at 47%'), findsOne);
      expect(find.text('Try another download'), findsOne);
    });

    testWidgets('draws the last drawing at once with no speed, no time left, '
        'no stuck row and no remedy, says so, then the live answer', (
      tester,
    ) async {
      await firstRun(tester);

      final answer = Completer<ServicesInFlight>();
      await run(
        tester,
        () => answer.future,
        now: _now.add(const Duration(hours: 1)),
      );
      // The rows the person last saw, the one line, no skeleton.
      expect(find.text('Sprite Fright'), findsOne);
      expect(find.text('Sprite.Fright.2021.1080p.WEB'), findsOne);
      expect(find.text('Elephants Dream'), findsOne);
      expect(find.text('Big Buck Bunny'), findsOne);
      expect(find.text('As of 20:53 · checking now'), findsOne);
      // How far each got stays; how long is left is not said, and the
      // speed is not drawn.
      expect(find.text('88%'), findsOne);
      expect(find.text('31%'), findsOne);
      expect(find.text('47%'), findsOne);
      expect(find.textContaining('MB/s'), findsNothing);
      expect(find.textContaining('min'), findsNothing);
      expect(find.textContaining('left'), findsNothing);
      // What was moving, what waited; nothing about what was stuck.
      expect(find.text('2 moving · 1 queued'), findsOne);
      expect(find.textContaining('stuck'), findsNothing);
      expect(find.textContaining('Stuck'), findsNothing);
      expect(find.text('Try another download'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byTooltip('More for Big Buck Bunny'), findsNothing);
      // A blocked import is Needs you's, and is no row of a drawing.
      expect(find.textContaining('manual import'), findsNothing);
      expect(find.text('Cosmos'), findsNothing);

      answer.complete(
        _inFlight(moving: [_item('Spring', id: '9', progress: 0.1, eta: 120)]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sprite Fright'), findsNothing);
      expect(find.text('Spring'), findsOne);
      expect(find.text('10% · 2\u00A0min'), findsOne);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('a row that was stuck is not amber in the drawing, and every '
        'bar has stopped', (tester) async {
      await firstRun(tester);
      await run(tester, () => Completer<ServicesInFlight>().future);

      final room = CupolaRoom.of(
        tester.element(find.byType(DownloadRow).first),
      );
      final scheme = Theme.of(
        tester.element(find.byType(DownloadRow).first),
      ).colorScheme;
      final amber = statusToneColor(
        scheme,
        StatusTone.warning,
        surface: room.slab,
      );
      final blue = statusToneColor(scheme, StatusTone.info, surface: room.slab);

      // Three rows: two moving, one that was stuck; the same neutral on the
      // figure and on the bar, never the amber and never the blue of motion.
      final bars = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .toList();
      expect(bars, hasLength(3));
      for (final bar in bars) {
        expect(bar.color, room.inkSecondary);
        expect(bar.color, isNot(amber));
        expect(bar.color, isNot(blue));
      }
      final stuckValue = tester.widget<Text>(find.text('47%'));
      expect(stuckValue.style!.color, room.inkSecondary);
      expect(stuckValue.style!.color, isNot(amber));
      // The bar keeps its position.
      expect(bars.map((bar) => bar.value), [0.88, 0.31, 0.47]);
    });

    testWidgets('a row of a drawing still opens its download page', (
      tester,
    ) async {
      await firstRun(tester);
      await run(tester, () => Completer<ServicesInFlight>().future);
      final inks = tester.widgetList<InkWell>(
        find.descendant(
          of: find.byType(DownloadRow),
          matching: find.byType(InkWell),
        ),
      );
      expect(inks, hasLength(3));
      expect(inks.every((ink) => ink.onTap != null), isTrue);
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
      expect(find.text('Sprite Fright'), findsOne);
      expect(find.text('Big Buck Bunny'), findsOne);
      expect(find.textContaining('did not answer'), findsOne);
      expect(find.text('As of 20:53'), findsOne);
      expect(find.text('Try another download'), findsNothing);
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('another server draws nothing of it', (tester) async {
      await firstRun(tester);

      await run(
        tester,
        () => Completer<ServicesInFlight>().future,
        customize: (settings) => settings.copyWithService(
          ServiceKey.qbittorrent,
          url: 'https://other.test',
          apiKey: 'other-key',
        ),
      );
      expect(find.text('Sprite Fright'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('a read a client did not answer is drawn as the rows it saw, '
        'with no count', (tester) async {
      await firstRun(
        tester,
        answer: _inFlight(
          moving: [_item('Sprite Fright', id: '1', progress: 0.88)],
          coverage: SourceCoverage.merge([
            SourceCoverage.answeredBy(ServiceKey.radarr),
            SourceCoverage.failure(
              ServiceKey.qbittorrent,
              const ClassifiedFailure(ServiceFailureReason.unreachable),
            ),
          ]),
        ),
      );

      await run(tester, () => Completer<ServicesInFlight>().future);
      expect(find.text('Sprite Fright'), findsOne);
      expect(find.text('As of 20:53 · checking now'), findsOne);
      expect(find.textContaining('moving'), findsNothing);
      expect(find.text('Nothing is downloading'), findsNothing);
    });
  });

  group('nothing is downloading', () {
    late LastKnownStore store;
    setUp(() => store = LastKnownStore.memory());

    Future<void> run(
      WidgetTester tester,
      Future<ServicesInFlight> Function() queue, {
      Future<ArrHistory> Function()? history,
    }) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            ...await settingsScopeOverrides(
              configured: const [ServiceKey.radarr, ServiceKey.qbittorrent],
            ),
            lastKnownStoreProvider.overrideWithValue(store),
            calendarClockProvider.overrideWithValue(() => _now),
            stallClockProvider.overrideWithValue(() => _now),
            arrivalsClockProvider.overrideWithValue(() => _now),
            servicesInFlightProvider.overrideWith((ref) => queue()),
            servicesArrHistoryProvider.overrideWith(
              (ref) => (history ?? () async => _noHistory())(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [HomeAsOfLine(), HomeDownloadsModule()],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<void> quietFirstRun(WidgetTester tester) async {
      await run(tester, () async => _inFlight());
      await tester.pumpAndSettle();
      expect(find.text('Nothing is downloading'), findsOne);
      expect(find.textContaining('As of'), findsNothing);
    }

    testWidgets('a whole read with nothing in it is drawn as it was, and said '
        'to be as of then', (tester) async {
      await quietFirstRun(tester);
      await run(tester, () => Completer<ServicesInFlight>().future);
      expect(find.text('Nothing is downloading'), findsOne);
      expect(find.text('Nothing moving'), findsOne);
      expect(find.text('As of 20:53 · checking now'), findsOne);
    });

    testWidgets('and an import after that read means it is no longer drawn', (
      tester,
    ) async {
      await quietFirstRun(tester);
      await run(
        tester,
        () => Completer<ServicesInFlight>().future,
        history: () async => _importedAt(_now.add(const Duration(minutes: 20))),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // Something finished since: nothing is known to be quiet.
      expect(find.text('Nothing is downloading'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('an import before that read leaves the drawing as it was, '
        'with the line the live history gives', (tester) async {
      await quietFirstRun(tester);
      await run(
        tester,
        () => Completer<ServicesInFlight>().future,
        history: () async =>
            _importedAt(_now.subtract(const Duration(hours: 2))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nothing is downloading'), findsOne);
      expect(find.text('The last download finished at 18:53.'), findsOne);
      expect(find.text('As of 20:53 · checking now'), findsOne);
    });

    testWidgets('a read that was not whole and had no row is not kept: the '
        'drawing before it stays', (tester) async {
      await run(
        tester,
        () async => _inFlight(
          moving: [_item('Sprite Fright', id: '1', progress: 0.88)],
        ),
      );
      await tester.pumpAndSettle();
      await run(
        tester,
        () async => _inFlight(
          coverage: SourceCoverage.merge([
            SourceCoverage.answeredBy(ServiceKey.radarr),
            SourceCoverage.failure(
              ServiceKey.qbittorrent,
              const ClassifiedFailure(ServiceFailureReason.unreachable),
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await run(tester, () => Completer<ServicesInFlight>().future);
      expect(find.text('Sprite Fright'), findsOne);
      expect(find.text('Nothing is downloading'), findsNothing);
    });

    testWidgets('a read no queue answered is not kept', (tester) async {
      await quietFirstRun(tester);
      await run(
        tester,
        () async => _inFlight(
          coverage: SourceCoverage.merge([
            SourceCoverage.failure(
              ServiceKey.radarr,
              const ClassifiedFailure(ServiceFailureReason.unreachable),
            ),
            SourceCoverage.failure(
              ServiceKey.qbittorrent,
              const ClassifiedFailure(ServiceFailureReason.unreachable),
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await run(tester, () => Completer<ServicesInFlight>().future);
      // The drawing before: nothing was downloading then.
      expect(find.text('Nothing is downloading'), findsOne);
      expect(find.text('As of 20:53 · checking now'), findsOne);
    });
  });

  group('the codec', () {
    StoredImageResolver resolver() =>
        (image) => switch (image) {
          StoredUrl(:final url) => (url: url, headers: null),
          _ => noImage,
        };

    test('keeps every field a row draws, and none that runs', () {
      final row = _item(
        'Sprite Fright',
        id: 'abc',
        progress: 0.62,
        eta: 98765,
        release: 'Sprite.Fright.2021.1080p.WEB',
        poster: 'https://image.tmdb.org/t/p/w500/sprite.jpg',
        rate: 43210987,
        fault: InFlightFault.stalled,
      );
      final json = serviceQueueItemToJson(row);
      final text = jsonEncode(json);

      // Nothing that runs, no fault, nothing the row does not draw.
      expect(text, isNot(contains('98765')));
      expect(text, isNot(contains('43210987')));
      expect(text, isNot(contains('stalled')));
      expect(text, isNot(contains('private-folder')));
      expect(text, isNot(contains('The arr says no')));

      final back = serviceQueueItemFromJson(jsonDecode(text), resolver())!;
      expect(back.service, ServiceKey.radarr);
      expect(back.id, 'abc');
      expect(back.downloadId, 'HASH-abc');
      expect(back.title, 'Sprite Fright');
      expect(back.instanceId, 'radarr');
      expect(back.clientService, ServiceKey.qbittorrent);
      expect(back.progress, 0.62);
      expect(back.names.machineName, 'Sprite.Fright.2021.1080p.WEB');
      expect(back.posterUrl, 'https://image.tmdb.org/t/p/w500/sprite.jpg');
      // It comes back as the download it was, going: no fault, no clock.
      expect(back.fault, isNull);
      expect(back.etaSeconds, isNull);
      expect(back.rateBytesPerSecond, isNull);
      expect(back.stalledSince, isNull);
      expect(back.outputPath, isNull);
      expect(back.warning, isNull);
      expect(back.isMoving, isTrue);
    });

    test('keeps no credential and no path', () {
      final withKey = _item(
        'Sprite Fright',
        poster: 'https://nas.example.com/poster.jpg?apikey=SECRETKEY',
        release: '/data/downloads/Sprite.Fright',
      );
      final text = jsonEncode(serviceQueueItemToJson(withKey));
      expect(text, isNot(contains('SECRETKEY')));
      expect(text, isNot(contains('apikey')));
      expect(text, isNot(contains('/data/downloads')));
      final back = serviceQueueItemFromJson(jsonDecode(text), resolver())!;
      expect(back.posterUrl, isNull);
      expect(back.names.machineName, isNull);

      expect(
        jsonEncode(
          serviceQueueItemToJson(
            _item('Sprite Fright', release: r'C:\Downloads\Sprite.Fright'),
          ),
        ),
        isNot(contains('Downloads')),
      );
    });

    test('refuses a broken row', () {
      expect(serviceQueueItemFromJson(null, resolver()), isNull);
      expect(serviceQueueItemFromJson(_noPicture, resolver()), isNull);
      expect(
        serviceQueueItemFromJson({
          'service': 'nope',
          'id': '1',
          'title': 'x',
        }, resolver()),
        isNull,
      );
      expect(
        serviceQueueItemFromJson({
          'service': 'radarr',
          'id': 1,
          'title': 'x',
        }, resolver()),
        isNull,
      );
    });

    test('a drawing keeps its rows and counts, and refuses a broken one', () {
      final drawing = downloadsDrawingOf(_evening());
      expect(drawing.rows.map((row) => row.title), [
        'Sprite Fright',
        'Elephants Dream',
        'Big Buck Bunny',
      ]);
      expect(drawing.moving, 2);
      expect(drawing.queued, 1);
      expect(drawing.whole, isTrue);

      final data = downloadsLastKnown.encode(drawing, _keep);
      final back = downloadsLastKnown.decode(
        jsonDecode(jsonEncode(data)),
        resolver(),
      )!;
      expect(back.rows.map((row) => row.title), [
        'Sprite Fright',
        'Elephants Dream',
        'Big Buck Bunny',
      ]);
      expect(back.rows.every((row) => row.fault == null), isTrue);
      expect(back.moving, 2);
      expect(back.queued, 1);
      expect(back.whole, isTrue);

      // One row it cannot read: the whole drawing is nothing, never a drawing
      // that counts and says nothing is downloading over a missing row.
      expect(
        downloadsLastKnown.decode({
          'whole': true,
          'moving': 1,
          'queued': 0,
          'rows': [
            {'service': 'radarr'},
          ],
        }, resolver()),
        isNull,
      );
      expect(downloadsLastKnown.decode({'rows': []}, resolver()), isNull);
      expect(downloadsLastKnown.decode('nope', resolver()), isNull);
      // A drawing with no row that counts something moving is inconsistent.
      expect(
        downloadsLastKnown.decode({
          'whole': true,
          'moving': 2,
          'queued': 0,
          'rows': <Object?>[],
        }, resolver()),
        isNull,
      );
    });

    test('keeps no more rows than the module draws', () {
      final many = _inFlight(
        moving: [for (var i = 0; i < 5; i++) _item('Title $i', id: '$i')],
      );
      final data =
          downloadsLastKnown.encode(downloadsDrawingOf(many), _keep)
              as Map<String, Object?>;
      expect(data['rows'] as List, hasLength(downloadsRowLimit));
    });

    test('a read no queue answered, or one cut short with no row, is not '
        'kept', () {
      final silent = _inFlight(
        coverage: SourceCoverage.merge([
          SourceCoverage.failure(
            ServiceKey.radarr,
            const ClassifiedFailure(ServiceFailureReason.unreachable),
          ),
        ]),
      );
      expect(
        downloadsLastKnown.encode(downloadsDrawingOf(silent), _keep),
        isNull,
      );

      final cut = _inFlight(
        coverage: SourceCoverage.answeredBy(ServiceKey.radarr, cutShort: true),
      );
      expect(downloadsLastKnown.encode(downloadsDrawingOf(cut), _keep), isNull);

      // With a row to show, a cut read is kept without its counts.
      final cutWithRow = _inFlight(
        moving: [_item('Sprite Fright')],
        coverage: SourceCoverage.answeredBy(ServiceKey.radarr, cutShort: true),
      );
      final data =
          downloadsLastKnown.encode(downloadsDrawingOf(cutWithRow), _keep)
              as Map<String, Object?>;
      expect(data['whole'], isFalse);
      expect(data.containsKey('moving'), isFalse);
    });
  });

  group('the line under the name', () {
    test('counts what moved and what waited, with no speed and no stuck', () {
      expect(
        downloadsKnownSubtitle(
          moving: 3,
          queued: 1,
          whole: true,
          hasRows: true,
        ),
        '3 moving · 1 queued',
      );
      expect(
        downloadsKnownSubtitle(
          moving: 0,
          queued: 2,
          whole: true,
          hasRows: true,
        ),
        '2 queued',
      );
    });

    test('says nothing moved only of a whole read with no row', () {
      expect(
        downloadsKnownSubtitle(
          moving: 0,
          queued: 0,
          whole: true,
          hasRows: false,
        ),
        'Nothing moving',
      );
      // Rows to draw and nothing counted: no line over them.
      expect(
        downloadsKnownSubtitle(
          moving: 0,
          queued: 0,
          whole: true,
          hasRows: true,
        ),
        isNull,
      );
    });

    test('states no count over a read that was not whole', () {
      expect(
        downloadsKnownSubtitle(
          moving: 3,
          queued: 1,
          whole: false,
          hasRows: true,
        ),
        isNull,
      );
    });
  });
}

/// Keeps the pictures as the Home does, against no connection: a picture
/// with headers has nothing to be kept by, and only public ones are.
final _keep = storedImageKeeper(const SettingsModel());
