import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/core/status/read_age.dart';
import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/presentation/transmission_actions.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';
import 'package:cupola/features/transmission/presentation/transmission_screen.dart';

import '../../../test_helpers/scripted_http_adapter.dart';
import '../../../test_helpers/settings_scope.dart';

final _configured = settingsWith(
  transmissionUrl: 'https://transmission.test',
  transmissionUsername: 'user',
  transmissionPassword: 'secret',
);

/// Status 4 is downloading, 6 is seeding.
TransmissionTorrent _torrent(int id, {required int status}) {
  return TransmissionTorrent.fromJson({
    'id': id,
    'hashString': 'hash$id',
    'name': '${status == 4 ? 'Download' : 'Seed'} $id',
    'status': status,
    'percentDone': status == 4 ? 0.4 : 1.0,
    'totalSize': 1024 * 1024 * 1024,
    'sizeWhenDone': 1024 * 1024 * 1024,
    'leftUntilDone': status == 4 ? 512 * 1024 * 1024 : 0,
    'rateDownload': 0,
    'rateUpload': 0,
    'eta': -1,
    'uploadRatio': 1.0,
  });
}

List<Override> _ambient({Override? summary}) => [
  currentSettingsProvider.overrideWith((ref) => _configured),
  summary ??
      serviceSummaryProvider.overrideWith(
        (ref, service) async => ServiceSummary(
          service: service,
          status: ServiceSummaryStatus.online,
          host: 'transmission.test',
          version: '4.0.6',
        ),
      ),
  serviceKpiProvider.overrideWith((ref, service) async => const <ServiceKpi>[]),
  transmissionSessionProvider.overrideWith(
    (ref) async => TransmissionSession.fromJson(const {
      'version': '4.0.6',
      'rpc-version': 17,
    }),
  ),
];

Future<void> _pump(
  WidgetTester tester,
  List<Override> overrides, {
  Override? summary,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        ..._ambient(summary: summary),
        ...overrides,
      ],
      child: const MaterialApp(home: TransmissionScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// A daemon that answers `torrent-get` with a fixed list.
class _ListingTransmission implements TransmissionClient {
  _ListingTransmission(this.list);

  final List<TransmissionTorrent> list;

  @override
  Future<List<TransmissionTorrent>> torrents({List<String>? ids}) async => list;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String? _subtitleOf(WidgetTester tester, String title) {
  return tester
      .widget<SectionHeader>(
        find.byWidgetPredicate((w) => w is SectionHeader && w.title == title),
      )
      .subtitle;
}

void main() {
  group('transmissionTorrentCountLabel', () {
    test('states the count, and nothing while there is nothing to count', () {
      expect(transmissionTorrentCountLabel(null), isNull);
      expect(transmissionTorrentCountLabel(0), '0 torrents');
      expect(transmissionTorrentCountLabel(1), '1 torrent');
      expect(transmissionTorrentCountLabel(8), '8 torrents');
    });
  });

  // OPS-02. The Queue tab drew `take(5)` transfers and `take(10)` seeds with no
  // count and no way to reach the rest: eight downloads read as five.
  testWidgets('every transfer and every seed is reachable, with its count', (
    tester,
  ) async {
    final torrents = [
      for (var i = 1; i <= 8; i++) _torrent(i, status: 4),
      for (var i = 101; i <= 112; i++) _torrent(i, status: 6),
    ];
    await _pump(tester, [
      transmissionTorrentsProvider.overrideWith((ref) async => torrents),
    ]);

    expect(_subtitleOf(tester, 'Transferring'), '8 torrents');

    final list = find.byType(Scrollable).first;
    // The sixth to eighth transfers and the eleventh and twelfth seeds were
    // exactly the rows the old caps cut off.
    for (final name in ['Download 6', 'Download 8']) {
      await tester.scrollUntilVisible(find.text(name), 200, scrollable: list);
      expect(find.text(name), findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.text('Seeding and idle'),
      200,
      scrollable: list,
    );
    expect(_subtitleOf(tester, 'Seeding and idle'), '12 torrents');
    for (final name in ['Seed 111', 'Seed 112']) {
      await tester.scrollUntilVisible(find.text(name), 200, scrollable: list);
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('the rows are built lazily, not all at once', (tester) async {
    // A seedbox is two thousand seeds. Inside a `Column` every one was built
    // and laid out per rebuild; the sliver builds what is on screen.
    final torrents = [for (var i = 1; i <= 400; i++) _torrent(i, status: 6)];
    await _pump(tester, [
      transmissionTorrentsProvider.overrideWith((ref) async => torrents),
    ]);

    expect(_subtitleOf(tester, 'Seeding and idle'), '400 torrents');
    expect(find.text('Seed 400', skipOffstage: false), findsNothing);
  });

  testWidgets('a list still loading states no count, never zero', (
    tester,
  ) async {
    final gate = Completer<List<TransmissionTorrent>>();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ..._ambient(),
          transmissionTorrentsProvider.overrideWith((ref) => gate.future),
        ],
        child: const MaterialApp(home: TransmissionScreen()),
      ),
    );
    await tester.pump();

    expect(_subtitleOf(tester, 'Transferring'), isNull);
    expect(_subtitleOf(tester, 'Seeding and idle'), isNull);
    expect(find.textContaining('0 torrents'), findsNothing);

    gate.complete([_torrent(1, status: 4)]);
    await tester.pumpAndSettle();
    expect(_subtitleOf(tester, 'Transferring'), '1 torrent');
    expect(_subtitleOf(tester, 'Seeding and idle'), '0 torrents');
  });

  // A daemon that stops answering leaves its last list under a band. The rows
  // used to go on printing what is left to download as if it were counting
  // down; they say how old the read is instead.
  group('a list read before the daemon stopped answering', () {
    final readAt = DateTime(2026, 10, 12, 9);
    final key = queueReadKey(
      ServiceKey.transmission,
      _configured.primaryOf(ServiceKey.transmission)!.id,
    );
    // The same text as `remainingLabel`: 512 MB of the first torrent left.
    const remaining = '512\u00A0MB';
    final probeDown = StateProvider<bool>((ref) => false);
    late DateTime now;

    Future<ProviderContainer> pumpDownloading(WidgetTester tester) async {
      now = readAt;
      final clock = ReadClock(now: () => now);
      final client = _ListingTransmission([_torrent(1, status: 4)]);
      await _pump(
        tester,
        [
          readClockProvider.overrideWithValue(clock),
          transmissionClientProvider.overrideWithValue(client),
        ],
        summary: serviceSummaryProvider.overrideWith((ref, service) async {
          final down = ref.watch(probeDown);
          return ServiceSummary(
            service: service,
            status: down
                ? ServiceSummaryStatus.offline
                : ServiceSummaryStatus.online,
            host: 'transmission.test',
            version: down ? null : '4.0.6',
          );
        }),
      );
      return ProviderScope.containerOf(
        tester.element(find.byType(TransmissionScreen)),
      );
    }

    testWidgets('says how old it is where the figures stopped counting', (
      tester,
    ) async {
      final container = await pumpDownloading(tester);

      // Healthy: the row prints what is left, says nothing of its age, and the
      // page has no clock running.
      expect(find.text(remaining), findsOneWidget);
      expect(find.textContaining('as of'), findsNothing);
      expect(container.exists(minuteNowProvider), isFalse);
      expect(
        container.read(readClockProvider).at(key),
        readAt,
        reason: 'the list was noted when it came back',
      );

      // The probe fails with the list retained: the band goes up and the row
      // trades its remainder for the age of what it last read.
      now = readAt.add(const Duration(minutes: 6));
      container.read(probeDown.notifier).state = true;
      await tester.pumpAndSettle();
      expect(find.byType(FaultBand), findsOneWidget);
      expect(find.text('Download 1'), findsOneWidget);
      expect(find.text(remaining), findsNothing);
      expect(find.text('as of 6\u00A0min ago'), findsOneWidget);

      // And the age moves with the minutes.
      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('as of 7\u00A0min ago'), findsOneWidget);

      // Back: the remainder returns, the age goes, and so does the clock.
      container.read(probeDown.notifier).state = false;
      await tester.pumpAndSettle();
      expect(find.byType(FaultBand), findsNothing);
      expect(find.text(remaining), findsOneWidget);
      expect(find.textContaining('as of'), findsNothing);
      // The disposal the dropped watch scheduled runs a frame later.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(container.exists(minuteNowProvider), isFalse);
    });

    testWidgets('says nothing of the age of a read nobody recorded', (
      tester,
    ) async {
      // A list that did not come through the provider that notes it (a
      // test override, say) has no age to claim: the row stays as it was.
      now = readAt;
      await _pump(
        tester,
        [
          readClockProvider.overrideWithValue(ReadClock(now: () => now)),
          transmissionTorrentsProvider.overrideWith(
            (ref) async => [_torrent(1, status: 4)],
          ),
        ],
        summary: serviceSummaryProvider.overrideWith(
          (ref, service) async => ServiceSummary(
            service: service,
            status: ServiceSummaryStatus.offline,
            host: 'transmission.test',
            version: null,
          ),
        ),
      );

      expect(find.byType(FaultBand), findsOneWidget);
      expect(find.text(remaining), findsOneWidget);
      expect(find.textContaining('as of'), findsNothing);
    });
  });

  // The add flow ignored whether the add had worked and printed "Torrent
  // added" after the failure toast, for a refused link and a dead daemon alike.
  group('Add torrent', () {
    Future<void> add(WidgetTester tester, List<ScriptedReply> replies) async {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://transmission.test',
          followRedirects: false,
          validateStatus: allowRedirectStatus,
        ),
      )..httpClientAdapter = ScriptedHttpAdapter(replies);
      await _pump(tester, [
        transmissionTorrentsProvider.overrideWith((ref) async => const []),
        transmissionClientProvider.overrideWith(
          (ref) =>
              TransmissionClient(url: 'https://transmission.test', dio: dio),
        ),
      ]);
      await tester.tap(find.text('Add torrent'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'magnet:?xt=urn:btih:aa');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
    }

    testWidgets('a refused link says so, in the daemon words', (tester) async {
      await add(tester, const [
        ScriptedReply(body: {'result': 'invalid or corrupt torrent file'}),
      ]);

      expect(
        find.text(
          'Transmission refused the torrent\ninvalid or corrupt torrent file',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Torrent added'), findsNothing);
    });

    testWidgets('a duplicate is not reported as added', (tester) async {
      await add(tester, const [
        ScriptedReply(
          body: {
            'result': 'success',
            'arguments': {
              'torrent-duplicate': {
                'id': 4,
                'hashString': 'aa',
                'name': 'Sintel',
              },
            },
          },
        ),
      ]);

      expect(find.text('Already in Transmission\nSintel'), findsOneWidget);
      expect(find.textContaining('Torrent added'), findsNothing);
    });

    testWidgets('a request turned away says nothing was added', (tester) async {
      await add(tester, const [ScriptedReply(statusCode: 401)]);

      expect(
        find.text(
          'The torrent was not added\n'
          'Transmission rejected the username or password.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Torrent added'), findsNothing);
    });

    testWidgets('an added torrent is the only one called added', (
      tester,
    ) async {
      await add(tester, const [
        ScriptedReply(
          body: {
            'result': 'success',
            'arguments': {
              'torrent-added': {'id': 5, 'hashString': 'aa', 'name': 'Sintel'},
            },
          },
        ),
      ]);

      expect(find.text('Torrent added'), findsOneWidget);
    });
  });

  group('TransmissionAddReport.from', () {
    test('a timeout does not claim the torrent was added or not', () {
      final report = TransmissionAddReport.from(
        error: const TransmissionException(
          'The connection timed out',
          reason: ServiceFailureReason.timeout,
        ),
      );

      expect(report.verdict, TransmissionAddVerdict.unconfirmed);
      expect(report.message, contains('Check the queue'));
    });

    test('a host that never answered is a torrent not added', () {
      final report = TransmissionAddReport.from(
        error: const TransmissionException(
          'Connection refused',
          reason: ServiceFailureReason.unreachable,
        ),
      );

      expect(report.verdict, TransmissionAddVerdict.notSent);
      expect(report.message, 'The torrent was not added');
      expect(report.detail, 'Connection refused');
    });
  });
}
