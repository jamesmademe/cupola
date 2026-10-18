/// The tap on a season or an episode while it waits for its series' ids: what
/// the press does and does not do, against a server whose answer the test
/// holds. What it opens once it has them is `media_stream_season_test.dart`'s,
/// through the households.
library;

import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';

import '../../test_helpers/settings_scope.dart';

/// A media server that answers only the one question a tap asks, when the test
/// says.
class _Server implements StreamServerClient {
  final answer = Completer<MediaKey?>();
  final tokens = <CancelToken?>[];

  @override
  Future<MediaKey?> getSeriesKey(String seriesId, {CancelToken? cancelToken}) {
    tokens.add(cancelToken);
    return answer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _episode = StreamItem(
  id: 'jf-ep-1',
  title: 'The Second Cycle',
  subtitle: null,
  kind: StreamItemKind.episode,
  posterPath: null,
  year: null,
  runtimeMs: null,
  isPlayed: false,
  resumeOffsetMs: null,
  unplayedChildCount: null,
  seasonNumber: 2,
  episodeNumber: 3,
  seriesId: 'jf-series',
);

/// A page with one tile, which is what a row on any screen is to the tap.
class _Home extends StatefulWidget {
  const _Home({required this.items});

  final ValueNotifier<bool> items;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: widget.items,
    builder: (context, shown, _) => Scaffold(
      body: shown
          ? Builder(
              builder: (context) => TextButton(
                onPressed: () => context.openStreamItem(
                  ServiceKey.jellyfin,
                  _episode,
                  instanceId: 'jellyfin',
                ),
                child: const Text('Open'),
              ),
            )
          : const Text('Nothing here'),
    ),
  );
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  required StreamServerClient Function() client,
  ValueNotifier<bool>? shown,
}) async {
  final items = shown ?? ValueNotifier(true);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => _Home(items: items),
      ),
      GoRoute(
        path: '/media/tv/:id',
        builder: (context, state) => Text('series ${state.uri}'),
      ),
      GoRoute(
        path: '${ServiceRoutes.jellyfinItemBase}/:id',
        builder: (context, state) => Text('item ${state.uri}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...await settingsScopeOverrides(
          configured: const [ServiceKey.jellyfin],
        ),
        streamClientForProvider.overrideWith((ref, key) => client()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  return router;
}

void main() {
  testWidgets('while the read is out nothing opens, a second tap does not ask '
      'again, and the page opens once it answers', (tester) async {
    final server = _Server();
    await _pump(tester, client: () => server);

    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Open'), findsOneWidget, reason: 'still on its page');
    expect(server.tokens, hasLength(1));

    server.answer.complete(const MediaKey.tv(1399));
    await tester.pumpAndSettle();

    expect(find.text('series /media/tv/1399?i=jellyfin&season=2'), findsOne);
    expect(find.text('Open'), findsNothing);
  });

  testWidgets('a read that does not answer in time gives way to the '
      'server\'s own page, and is ended', (tester) async {
    final server = _Server();
    await _pump(tester, client: () => server);

    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Open'), findsOneWidget, reason: 'still waiting');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(
      find.text('item ${ServiceRoutes.jellyfinItemBase}/jf-ep-1?i=jellyfin'),
      findsOneWidget,
    );
    expect(server.tokens.single!.isCancelled, isTrue);
    // The answer that comes after changes nothing.
    server.answer.complete(const MediaKey.tv(1399));
    await tester.pumpAndSettle();
    expect(find.textContaining('series'), findsNothing);
  });

  testWidgets('a tap whose tile went away while the read was out opens '
      'nothing, and throws nothing', (tester) async {
    final server = _Server();
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    final router = await _pump(tester, client: () => server, shown: shown);

    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(seconds: 1));
    shown.value = false;
    await tester.pump();
    server.answer.complete(const MediaKey.tv(1399));
    await tester.pumpAndSettle();

    expect(find.text('Nothing here'), findsOneWidget);
    expect(router.state.uri.path, '/');
  });

  testWidgets('a connection that is gone opens the server\'s own page', (
    tester,
  ) async {
    await _pump(
      tester,
      client: () => throw const ServiceNotConfigured(ServiceKey.jellyfin),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.text('item ${ServiceRoutes.jellyfinItemBase}/jf-ep-1?i=jellyfin'),
      findsOneWidget,
    );
  });

  testWidgets('a series the server could not name opens the server\'s own '
      'page, as it always did', (tester) async {
    final server = _Server();
    await _pump(tester, client: () => server);

    await tester.tap(find.text('Open'));
    await tester.pump();
    server.answer.complete(null);
    await tester.pumpAndSettle();

    expect(
      find.text('item ${ServiceRoutes.jellyfinItemBase}/jf-ep-1?i=jellyfin'),
      findsOneWidget,
    );
  });
}
