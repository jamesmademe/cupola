import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/core/lifecycle/poll_probe.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../../test_helpers/settings_scope.dart';

/// Counts every request the polls actually make, by path.
///
/// The whole requirement is stated in units of network traffic, so the assertions
/// are too: a hidden page must add nothing to these counters, however long it is
/// left alone.
class _CountingAdapter implements HttpClientAdapter {
  final Map<String, int> calls = {};

  int get total => calls.values.fold(0, (a, b) => a + b);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.update(options.path, (n) => n + 1, ifAbsent: () => 1);
    final body = options.path.contains('properties')
        ? <String, dynamic>{}
        : <dynamic>[];
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(body))),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

const _interval = Duration(seconds: 3);
const _hash = 'aaa';

/// The list page, gated exactly as `QbittorrentScreen` gates it.
class _ListPage extends ConsumerWidget {
  const _ListPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watchWhileLive(context, torrentPollingProvider);
    // Watched for the same reason the real screen watches it: an invalidation
    // only costs a request if something is listening, so a page that polls
    // without displaying would prove nothing about traffic.
    ref.watch(torrentsProvider);
    return const SizedBox.shrink();
  }
}

/// The detail page, gated exactly as `TorrentDetailScreen` gates it.
class _DetailPage extends ConsumerWidget {
  const _DetailPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watchWhileLive(context, torrentDetailPollingProvider(_hash));
    ref.watch(qbittorrentTorrentsProvider(_hash));
    ref.watch(torrentPropertiesProvider(_hash));
    return const SizedBox.shrink();
  }
}

class _Host extends StatefulWidget {
  const _Host({required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool branchActive = true;

  void setBranchActive(bool value) => setState(() => branchActive = value);

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: widget.navigatorKey,
    home: BranchActivityScope(
      isActive: branchActive,
      branchIndex: 0,
      child: const _ListPage(),
    ),
  );
}

void main() {
  late _CountingAdapter adapter;
  late PollClock clock;
  late DateTime now;

  setUp(() {
    adapter = _CountingAdapter();
    now = DateTime(2026, 8, 25, 12);
    clock = PollClock()..now = () => now;
    PollProbe.instance.reset();
  });

  int listTicks() => PollProbe.instance.countFor('qbittorrent.list');
  int detailTicks() => PollProbe.instance.countFor('qbittorrent.detail.$_hash');

  Future<_HostState> pump(WidgetTester tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pollClockProvider.overrideWithValue(clock),
          currentSettingsProvider.overrideWith(
            (ref) => settingsWith(qbittorrentUrl: 'http://qb.test'),
          ),
          qbittorrentServiceProvider.overrideWith((ref) {
            final dio = Dio(BaseOptions(baseUrl: 'http://qb.test'))
              ..httpClientAdapter = adapter;
            return QbittorrentService(
              QbittorrentClient(url: 'http://qb.test', dio: dio),
            );
          }),
        ],
        child: _Host(navigatorKey: navigatorKey),
      ),
    );
    await tester.pump();
    return tester.state<_HostState>(find.byType(_Host));
  }

  Future<void> elapse(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
  }

  group('qBittorrent polling gate', () {
    testWidgets('the visible list polls, and its ticks cost requests', (
      tester,
    ) async {
      await pump(tester);
      final afterMount = adapter.total;
      expect(listTicks(), 0, reason: 'the page just loaded its own data');

      await elapse(tester, _interval);
      await tester.pump();

      expect(listTicks(), 1);
      // The chain the whole requirement rests on: a tick is an invalidation, and
      // an invalidation on a watched provider is traffic.
      expect(adapter.total, greaterThan(afterMount));
    });

    testWidgets('a hidden branch adds not one request, however long it waits', (
      tester,
    ) async {
      final host = await pump(tester);
      await elapse(tester, _interval);
      await tester.pump();

      host.setBranchActive(false);
      await tester.pump();
      final frozenTicks = listTicks();
      final frozenCalls = adapter.total;

      // Twenty intervals: a minute of a tab nobody is looking at.
      await elapse(tester, _interval * 20);
      await tester.pump();

      expect(listTicks(), frozenTicks);
      expect(adapter.total, frozenCalls);
    });

    testWidgets('returning after a long absence refreshes at once', (
      tester,
    ) async {
      final host = await pump(tester);
      await elapse(tester, _interval);
      expect(listTicks(), 1);

      host.setBranchActive(false);
      // One frame for the rebuild to drop the watch: dropping the last listener
      // is what disposes the poller, and disposal is what cancels its timer.
      // Fast-forwarding the clock first would run the old timer instead.
      await tester.pump();
      await elapse(tester, const Duration(minutes: 5));
      expect(listTicks(), 1, reason: 'nothing ran while it was away');

      host.setBranchActive(true);
      await tester.pump();
      await tester.pump();

      // Due by a wide margin, so the return is worth a fetch immediately rather
      // than three seconds of showing minute-old numbers.
      expect(listTicks(), 2);

      // The immediate refresh is a request still on its way (Dio queues it
      // on a timer). The test lets it land before it ends: since Riverpod
      // 3.4 the rebuild that starts it runs a step later than it did.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a detail page on top stops the list, not just its own tab', (
      tester,
    ) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pollClockProvider.overrideWithValue(clock),
            currentSettingsProvider.overrideWith(
              (ref) => settingsWith(qbittorrentUrl: 'http://qb.test'),
            ),
            qbittorrentServiceProvider.overrideWith((ref) {
              final dio = Dio(BaseOptions(baseUrl: 'http://qb.test'))
                ..httpClientAdapter = adapter;
              return QbittorrentService(
                QbittorrentClient(url: 'http://qb.test', dio: dio),
              );
            }),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: BranchActivityScope(
              isActive: true,
              branchIndex: 0,
              child: const _ListPage(),
            ),
          ),
        ),
      );
      await tester.pump();
      await elapse(tester, _interval);
      await tester.pump();

      expect(listTicks(), greaterThan(0), reason: 'the list was polling');
      final listTicksBefore = listTicks();

      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const _DetailPage()),
      );
      await tester.pumpAndSettle();

      await elapse(tester, _interval * 5);
      await tester.pump();

      // The decision the two independent gates exist to make: the list under the
      // detail stops entirely. Its tick was an unfiltered /torrents/info plus a
      // /transfer/info; neither is spent while nobody can see the list.
      expect(
        listTicks(),
        listTicksBefore,
        reason: 'a covered list must not poll',
      );
      // And the detail is the one running now.
      expect(detailTicks(), greaterThan(0));
    });
  });
}
