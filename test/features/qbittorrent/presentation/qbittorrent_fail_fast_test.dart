import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/core/lifecycle/poll_probe.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/status/read_age.dart';
import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_overview_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_rss_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_screen.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../../test_helpers/settings_scope.dart';

const _interval = Duration(seconds: 3);
const _loginPath = '/api/v2/auth/login';
const _listPath = '/api/v2/sync/maindata';

/// A qBittorrent that can be switched off, held mid-request, or made to refuse
/// the password, and that counts every request by path, because the defects
/// under test are stated in units of network traffic.
class _Qb implements HttpClientAdapter {
  final Map<String, int> calls = {};

  /// Every request fails as a refused connection.
  bool down = false;

  /// The login answers 401, qBittorrent 5.1's wrong-password reply.
  bool rejectLogin = false;

  /// While non-null, the list's read waits on it: a host that drops packets.
  Completer<void>? hold;

  int count(String path) => calls[path] ?? 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.update(options.path, (n) => n + 1, ifAbsent: () => 1);
    final gate = hold;
    if (gate != null && options.path == _listPath) await gate.future;
    if (down) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connection refused',
      );
    }
    if (options.path == _loginPath) {
      return _reply(rejectLogin ? '' : 'Ok.', rejectLogin ? 401 : 200);
    }
    final body = options.path == _listPath
        ? jsonEncode({
            'rid': 1,
            'full_update': true,
            'torrents': {
              'aaa': {
                'name': 'Ubuntu.ISO',
                'state': 'downloading',
                'progress': 0.5,
                'size': 1024,
                'eta': 420,
              },
            },
            'server_state': <String, dynamic>{},
          })
        : jsonEncode(<String, dynamic>{});
    return _reply(body, 200, json: true);
  }

  static ResponseBody _reply(String body, int status, {bool json = false}) {
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(body)),
      status,
      headers: {
        Headers.contentTypeHeader: [
          json ? 'application/json' : 'text/plain; charset=utf-8',
        ],
      },
    );
  }
}

/// A service whose every read fails the way a dark host does.
class _DarkService implements QbittorrentService {
  static Never _refused() => throw DioException.connectionError(
    requestOptions: RequestOptions(path: _listPath),
    reason: 'Connection refused',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) return Future<Never>(_refused);
    return super.noSuchMethod(invocation);
  }
}

/// The list page gated exactly as `QbittorrentScreen` gates it, without the
/// screen's chrome.
class _ListPage extends ConsumerWidget {
  const _ListPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watchWhileLive(context, torrentPollingProvider);
    ref.watch(torrentsProvider);
    return const SizedBox.shrink();
  }
}

void main() {
  late _Qb qb;
  late PollClock clock;
  late ReadClock readClock;
  late DateTime now;

  setUp(() {
    qb = _Qb();
    now = DateTime(2026, 9, 29, 12);
    clock = PollClock()..now = () => now;
    readClock = ReadClock(now: () => now);
    PollProbe.instance.reset();
  });

  /// Lets Dio's interceptor chain, which hops through zero-delay timers, reach
  /// the adapter and come back.
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    String? username,
    String? password,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pollClockProvider.overrideWithValue(clock),
          readClockProvider.overrideWithValue(readClock),
          currentSettingsProvider.overrideWith(
            (ref) => settingsWith(qbittorrentUrl: 'http://qb.test'),
          ),
          qbittorrentServiceProvider.overrideWith((ref) {
            final dio = Dio(BaseOptions(baseUrl: 'http://qb.test'))
              ..httpClientAdapter = qb;
            final client = QbittorrentClient(
              url: 'http://qb.test',
              username: username,
              password: password,
              dio: dio,
            );
            ref.onDispose(client.close);
            return QbittorrentService(client);
          }),
          serviceKpiProvider.overrideWith(
            (ref, service) async => const <ServiceKpi>[],
          ),
        ],
        child: MaterialApp(
          home: BranchActivityScope(
            isActive: true,
            branchIndex: 0,
            child: page,
          ),
        ),
      ),
    );
    await flush(tester);
  }

  Future<void> tick(WidgetTester tester) async {
    now = now.add(_interval);
    await tester.pump(_interval);
    await flush(tester);
  }

  // OPS-05. With Riverpod's default retry a failed build is an `AsyncLoading`
  // that still carries the previous value and the error, which `when` draws as
  // loading; the 3 s poll invalidated before the tenth retry, so the list never
  // left that state while qBittorrent was down.
  group('every qBittorrent read fails on its first attempt', () {
    test('sources and derived providers alike', () async {
      final container = ProviderContainer(
        overrides: [
          // The list providers resolve which connection they read for the
          // read clock, so a container that runs them needs settings.
          currentSettingsProvider.overrideWith(
            (ref) => settingsWith(qbittorrentUrl: 'http://qb.test'),
          ),
          qbittorrentServiceProvider.overrideWithValue(_DarkService()),
        ],
      );
      addTearDown(container.dispose);

      final futures = <String, Future<Object?>>{
        'allTorrents': container.read(allTorrentsProvider.future),
        'torrents': container.read(torrentsProvider.future),
        'transferInfo': container.read(transferInfoProvider.future),
        'torrent(hash)': container.read(
          qbittorrentTorrentsProvider('a').future,
        ),
        'files(hash)': container.read(torrentFilesProvider('a').future),
        'trackers(hash)': container.read(torrentTrackersProvider('a').future),
        'properties(hash)': container.read(
          torrentPropertiesProvider('a').future,
        ),
        'overview.attention': container.read(
          qbittorrentOverviewAttentionProvider.future,
        ),
        'overview.transfers': container.read(
          qbittorrentOverviewTransfersProvider.future,
        ),
        'overview.counts': container.read(
          qbittorrentOverviewCountsProvider.future,
        ),
        'overview.categories': container.read(
          qbittorrentOverviewCategoriesProvider.future,
        ),
        'overview.categoryCount': container.read(
          qbittorrentOverviewCategoryCountProvider.future,
        ),
        'overview.session': container.read(
          qbittorrentOverviewSessionProvider.future,
        ),
        'rss.feeds': container.read(qbittorrentRssFeedsProvider.future),
        'rss.rules': container.read(qbittorrentRssRulesProvider.future),
      };

      for (final entry in futures.entries) {
        await expectLater(
          entry.value.timeout(const Duration(milliseconds: 300)),
          throwsA(isA<DioException>()),
          reason: '${entry.key} must fail at once, not after a backoff',
        );
      }
    });
  });

  group('qBittorrent going down', () {
    testWidgets('keeps the last list under a fault band, tick after tick', (
      tester,
    ) async {
      await pump(tester, const QbittorrentScreen());
      expect(find.text('Ubuntu.ISO'), findsOneWidget);

      qb.down = true;
      for (var i = 0; i < 5; i++) {
        await tick(tester);
        expect(
          find.byType(FaultBand),
          findsOneWidget,
          reason: 'tick ${i + 1}: the failure must land, not retry',
        );
        expect(find.text('Ubuntu.ISO'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }

      // And it heals on its own tick once qBittorrent is back.
      qb.down = false;
      await tick(tester);
      expect(find.byType(FaultBand), findsNothing);
      expect(find.text('Ubuntu.ISO'), findsOneWidget);
    });

    testWidgets('a list read before the failure says how old it is', (
      tester,
    ) async {
      await pump(tester, const QbittorrentScreen());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(QbittorrentScreen)),
      );

      // Healthy: the row counts down, says nothing of its age, and the page
      // has no clock running.
      expect(find.textContaining('7\u00A0min'), findsOneWidget);
      expect(find.textContaining('as of'), findsNothing);
      expect(container.exists(minuteNowProvider), isFalse);

      // Down: the same row keeps its list, and trades the ETA, which no longer
      // counts down, for the age of what it last read.
      qb.down = true;
      await tick(tester);
      expect(find.byType(FaultBand), findsOneWidget);
      expect(find.text('Ubuntu.ISO'), findsOneWidget);
      expect(find.textContaining('7\u00A0min'), findsNothing);
      expect(find.text('as of just now'), findsOneWidget);

      // And the age moves with the minutes, not with the three-second poll.
      now = now.add(const Duration(minutes: 6));
      await tester.pump(const Duration(minutes: 1));
      await flush(tester);
      expect(find.text('as of 6\u00A0min ago'), findsOneWidget);

      // Back: the ETA returns, the age goes, and so does the clock.
      qb.down = false;
      await tick(tester);
      expect(find.byType(FaultBand), findsNothing);
      expect(find.textContaining('7\u00A0min'), findsOneWidget);
      expect(find.textContaining('as of'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(container.exists(minuteNowProvider), isFalse);
    });

    testWidgets('a request still in flight is not thrown away by the poll', (
      tester,
    ) async {
      // A host that drops packets answers nothing for the connect timeout (ten
      // seconds) while the poll ticks every three. Restarting the request on
      // each tick meant it never failed, so the page never left loading.
      qb.hold = Completer<void>();
      await pump(tester, const _ListPage());
      expect(qb.count(_listPath), 1);

      for (var i = 0; i < 5; i++) {
        await tick(tester);
      }
      expect(qb.count(_listPath), 1, reason: 'no tick restarts a pending load');

      // The request finally fails; the next tick asks again, as usual.
      qb.down = true;
      qb.hold!.complete();
      qb.hold = null;
      await flush(tester);
      await tick(tester);
      expect(qb.count(_listPath), 2);
    });
  });

  // OPS-03. qBittorrent bans an address after five failed logins (for an hour,
  // by default), and behind a proxy the address is the proxy's. The client
  // used to reset its rejection flag at the start of every login, so each poll
  // tick, and each default retry, spent another attempt.
  group('a rejected password', () {
    testWidgets('is sent once, however long the page polls', (tester) async {
      qb.rejectLogin = true;
      await pump(
        tester,
        const _ListPage(),
        username: 'admin',
        password: 'wrong',
      );

      for (var i = 0; i < 20; i++) {
        await tick(tester);
      }

      expect(qb.count(_loginPath), 1, reason: 'one attempt, then hold it');
      expect(
        qb.count(_listPath),
        0,
        reason: 'nothing is asked unauthenticated',
      );
    });

    testWidgets('is tried again once when the user taps Retry', (tester) async {
      qb.rejectLogin = true;
      await pump(
        tester,
        const QbittorrentScreen(),
        username: 'admin',
        password: 'wrong',
      );
      expect(qb.count(_loginPath), 1);
      expect(
        find.textContaining('refused the saved credentials'),
        findsOneWidget,
      );

      await tick(tester);
      expect(qb.count(_loginPath), 1, reason: 'the poll does not retry it');

      // The user fixed the password on the server and asks again.
      qb.rejectLogin = false;
      await tester.tap(find.text('Retry'));
      await flush(tester);

      expect(qb.count(_loginPath), 2);
      expect(find.text('Ubuntu.ISO'), findsOneWidget);
    });
  });
}
