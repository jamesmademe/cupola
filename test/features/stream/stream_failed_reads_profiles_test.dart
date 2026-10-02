/// A media server read that failed says it failed, where a page used to state
/// a fact from an empty answer.
///
/// The clients degraded these reads to an empty list or null: an item's
/// Contents read "Nothing inside" for a server that did not answer, Plex's
/// Server section read "The server did not describe itself", and a search lane
/// could only call a switched-off server a request that did not complete.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_item_screen.dart';
import 'package:cupola/features/stream/presentation/stream_overview_screen.dart';

import '../../test_helpers/profiles/profiles.dart';

const _seasons = '/Shows/jf-cosmosLaundromat/Seasons';

void main() {
  group('a Jellyfin series\' contents', () {
    testWidgets('a read that failed says so with a Retry, never "Nothing '
        'inside"', (tester) async {
      var failing = true;
      final harness = await ProfileHarness.start(Profiles.p1);
      harness.network.on(
        WorldIds.jellyfin,
        'GET',
        _seasons,
        (_) => failing
            ? NetworkReply.json({'message': 'boom'}, status: 500)
            : NetworkReply.json({
                'Items': const <Object?>[],
                'TotalRecordCount': 0,
              }),
      );
      await _pump(
        tester,
        harness,
        const StreamItemScreen(
          service: ServiceKey.jellyfin,
          itemId: 'jf-cosmosLaundromat',
        ),
      );

      expect(find.text('Nothing inside'), findsNothing);
      final failure = find.byType(AppErrorState);
      expect(failure, findsOneWidget);

      // Retry asks again, and an answer with nothing in it is "Nothing inside".
      failing = false;
      await tester.tap(
        find.descendant(of: failure, matching: find.text('Retry')),
      );
      await harness.settle(tester);
      expect(find.text('Nothing inside'), findsOneWidget);

      await harness.unmount(tester);
    });
  });

  testWidgets('Plex\'s Server section over a sheet that failed says so, '
      'never that the server did not describe itself', (tester) async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withConnection(WorldConnections.plex),
    );
    harness.network.on(
      WorldIds.plex,
      'GET',
      '/',
      (_) => NetworkReply.json({'message': 'boom'}, status: 500),
    );
    await _pump(
      tester,
      harness,
      const StreamOverviewScreen(service: ServiceKey.plex, topPadding: 0),
      size: const Size(430, 4000),
    );

    expect(find.text('The server did not describe itself'), findsNothing);
    // The one read that failed is the one section that says so.
    expect(find.byType(AppErrorState), findsOneWidget);

    await harness.unmount(tester);
  });

  test(
    'P7, Jellyfin does not answer: its search lane is red and says so',
    () async {
      final harness = await ProfileHarness.start(Profiles.p7);
      final container = harness.container(retry: (_, _) => null);
      final sub = container.listen(globalSearchLanesProvider, (_, _) {});
      addTearDown(sub.close);
      container.read(globalSearchQueryProvider.notifier).state = 'sintel';

      final leg = container
          .read(globalSearchLegsProvider)
          .singleWhere((leg) => leg.instance.service == ServiceKey.jellyfin);
      final lane = await container.read(globalSearchLegProvider(leg).future);

      // It used to read amber, a request that did not complete.
      expect(lane.state, SearchLaneState.unreachable);
      expect(lane.state.tone, StatusTone.error);
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  ProfileHarness harness,
  Widget child, {
  Size size = const Size(430, 2400),
}) async {
  harness.network.followFakeTime(tester.binding);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: child),
    ),
  );
  await harness.settle(tester);
}
