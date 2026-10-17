/// A connection's settings change while a screen is reading it: the client
/// the read started on is closed by the rebuild, and that is not the server
/// failing.
///
/// A client provider closes its client the moment its connection's
/// transport changes (`ref.onDispose(client.close)`, which Riverpod runs on
/// invalidation) and rebuilds it when it is next read. A screen that holds
/// what it read (its own future, a walk over pages) and sends again before
/// reading the provider again sends on the closed client, and Dio refuses it
/// as a connection error: "Radarr did not answer", in red, about a server
/// that had just answered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_provider.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';

import '../../test_helpers/profiles/profiles.dart';

const _latency = Duration(milliseconds: 400);

/// What a screen says, in red, about a server that did not answer.
Finder _didNotAnswer() => find.textContaining('did not answer');

/// Radarr's queue answers its first page with a second one promised, and the
/// connection's settings change the moment that page is answered: a gateway
/// header added on the connection's form, say. The walk's next request then
/// finds its client closed by the change.
///
/// The change is set straight on the notifier because the window is that
/// narrow: between the two requests of one read.
void _changeSettingsMidWalk(ProfileHarness harness, ProviderContainer c) {
  var armed = true;
  harness.network.on(WorldIds.radarr, 'GET', '/api/v3/queue', (request) {
    if (!armed || request.query['page'] != '1') return null;
    armed = false;
    final settings = c.read(currentSettingsProvider);
    final radarr = settings.instanceById(WorldIds.radarr)!;
    // ignore: invalid_use_of_protected_member
    c.read(settingsProvider.notifier).state = settings.copyWithInstance(
      radarr.copyWith(
        access: const CustomHeaders([(name: 'X-Gate', value: 'one')]),
      ),
    );
    return NetworkReply.json({
      'page': 1,
      'pageSize': 200,
      'totalRecords': 2,
      'records': [
        {
          'id': 1,
          'movieId': 1,
          'title': 'Cupola.Test.Feature.1999.1080p',
          'status': 'downloading',
          'trackedDownloadStatus': 'ok',
          'trackedDownloadState': 'downloading',
          'size': 100,
          'sizeleft': 50,
        },
      ],
    });
  });
}

/// The queue reads Radarr answered with the gateway header: the rebuilt
/// client's.
Iterable<NetworkRequest> _freshQueueReads(ProfileHarness harness) => harness
    .network
    .requestsTo(WorldIds.radarr)
    .where((r) => r.path == '/api/v3/queue' && r.headers['x-gate'] == 'one');

void main() {
  testWidgets('a page holding its own read keeps its answer, and a pull reads '
      'again, never an outage', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1.withLatency(WorldIds.radarr, _latency),
      // The rest of the app reading Radarr (Home, the Radarr room) keeps its
      // client live, which is what closes it the moment the settings change.
      child: Consumer(
        builder: (context, ref, _) {
          ref.watch(radarrServiceProvider);
          return const ActivityPage(tab: ActivityTab.downloads);
        },
      ),
      surfaceSize: const Size(430, 2400),
      settle: false,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActivityPage)),
    );
    _changeSettingsMidWalk(harness, container);

    await tester.pump(_latency);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      _didNotAnswer(),
      findsNothing,
      reason: 'the closed client is not the server failing',
    );

    await harness.settle(tester);
    expect(_didNotAnswer(), findsNothing);
    // A settings write does not re-read Activity on purpose: the answer it
    // holds stands until a pull, a return or its poll.
    expect(_freshQueueReads(harness), isEmpty);

    // The pull reads again, on the client the change rebuilt.
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 400),
      1000,
    );
    await harness.settle(tester);
    expect(_didNotAnswer(), findsNothing);
    expect(_freshQueueReads(harness), isNotEmpty);

    await harness.unmount(tester);
  });

  testWidgets('a section read through its providers keeps its rows', (
    tester,
  ) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1.withLatency(WorldIds.radarr, _latency),
      child: const RadarrOverviewScreen(),
      surfaceSize: const Size(430, 3200),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RadarrOverviewScreen)),
    );
    _changeSettingsMidWalk(harness, container);

    // A pull to refresh: the page's own handler invalidates these.
    container
      ..invalidate(radarrNeedsAttentionProvider)
      ..invalidate(radarrQueueRecordsProvider)
      ..invalidate(radarrCutoffUnmetCountProvider);
    await tester.pump(_latency);
    await tester.pump(const Duration(milliseconds: 50));

    expect(_didNotAnswer(), findsNothing);

    // The read again goes out on the rebuilt client one latency later. Waited
    // for in time, not by `settle`: nothing on the page animates meanwhile
    // (the KPI rail keeps its figures through a reload), so there may be no
    // frame scheduled while the request is still on its way.
    await tester.pump(_latency * 2);
    await harness.settle(tester);
    expect(_didNotAnswer(), findsNothing);
    expect(_freshQueueReads(harness), isNotEmpty);

    await harness.unmount(tester);
  });
}
