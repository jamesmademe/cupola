/// Home reads every connection of a service, the way its header does.
///
/// Needs you, Downloads and Arrived used to read the lens alone. With two
/// Radarr, the 4K's downloads, its failed imports and its imports never
/// reached Home, and nothing on Home said so. Each connection is now its own
/// source: one that fails is named under the figure and takes only its own
/// rows with it, and every row carries the connection it came off, so what it
/// opens is that server's.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/domain/arrived.dart';
import 'package:cupola/features/home/presentation/widgets/arrived_module.dart';
import 'package:cupola/features/home/presentation/widgets/downloads_module.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/decision_rows.dart';
import '../../../test_helpers/profiles/fakes/arr_fakes.dart';
import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/profiles/service_fakes.dart';

const _tall = Size(430, 6000);

/// One failed import of Elephants Dream, film 1 on the 4K Radarr.
Map<String, Object?> _failedImport(DateTime now) => {
  'id': 41,
  'movieId': 1,
  'eventType': 'importFailed',
  'sourceTitle': 'Elephants.Dream.2006.2160p.UHD.BluRay',
  'date': now.subtract(const Duration(minutes: 20)).toUtc().toIso8601String(),
  'movie': {'id': 1, 'title': 'Elephants Dream', 'year': 2006},
  'data': {'message': 'Not a valid video file'},
};

void _scriptFailedImportOn4k(ProfileNetwork network) {
  network.on(
    WorldIds.radarr4k,
    'GET',
    '/api/v3/history',
    (r) => NetworkReply.json(pagedEnvelope(r, [_failedImport(network.now)])),
  );
  // The week's read asks for imports by name; a server that ignores that
  // still answers with the failure among its imports, and Arrived leaves it
  // out.
  network.on(
    WorldIds.radarr4k,
    'GET',
    '/api/v3/history/since',
    (r) => NetworkReply.json([
      _failedImport(network.now),
      ...const RadarrFake().history(
        ServerContext(
          network: network,
          server: network.server(WorldIds.radarr4k),
        ),
      ),
    ]),
  );
}

Future<ProfileHarness> _pumpHome(
  WidgetTester tester,
  ConfigProfile profile, {
  void Function(ProfileNetwork network)? before,
}) async {
  final harness = await ProfileHarness.start(profile);
  before?.call(harness.network);
  await tester.binding.setSurfaceSize(_tall);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: const HomeScreen()),
    ),
  );
  await harness.settle(tester);
  return harness;
}

/// The week's answer, held open: the provider lets go of it when nothing
/// listens.
Future<ArrHistory> _arrivals(ProviderContainer container) {
  container.listen(servicesArrivalsProvider, (_, _) {});
  return container.read(servicesArrivalsProvider.future);
}

/// What Arrived draws as cards, newest first, over the week the profile's
/// network is in.
Future<List<ArrHistoryEntry>> _arrivedCards(
  ProviderContainer container,
  ProfileHarness harness,
) async => arrivedOf(
  (await _arrivals(container)).entries,
  since: harness.network.now.subtract(arrivalsWindow),
);

Finder _within(Type region, Finder matching) =>
    find.descendant(of: find.byType(region), matching: matching);

void main() {
  testWidgets('P1, lens on the HD: the 4K Radarr reaches every module, '
      'named', (tester) async {
    final handle = tester.ensureSemantics();
    final harness = await _pumpHome(
      tester,
      Profiles.p1,
      before: _scriptFailedImportOn4k,
    );

    // Downloads: the 4K's movie, named for its Radarr, with how far it is
    // and how long is left.
    expect(
      _within(HomeDownloadsModule, find.text('Elephants Dream · Radarr 4K')),
      findsOne,
    );
    expect(
      _within(HomeDownloadsModule, find.text('31% · 6\u00A0min')),
      findsOne,
    );
    // The value is figures, so it is tabular in the text face: figures are
    // never mono, which is for machine strings only.
    final value = tester.widget<Text>(find.text('31% · 6\u00A0min'));
    expect(value.style?.fontFamily, isNot(DesignTokens.typeFamilyMono));
    expect(
      value.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
    // Both of the 4K's movies were joined to the SABnzbd holding them: the
    // module draws four rows, so they are read off the data. Elephants Dream
    // moves, and Sintel waits its turn in SABnzbd: it is in `queued`, where
    // it was in `preview` (counted as moving) before.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    final inFlight = container.read(servicesInFlightProvider).requireValue;
    final fourK = [
      ...inFlight.preview,
      ...inFlight.queued,
    ].where((item) => item.instanceId == WorldIds.radarr4k);
    expect(fourK, hasLength(2));
    expect(
      fourK.map((item) => item.clientService),
      everyElement(ServiceKey.sabnzbd),
    );
    expect(inFlight.queued.map((item) => item.instanceId), [WorldIds.radarr4k]);
    // The HD's own rows say which Radarr too, now that there are two.
    expect(
      _within(HomeDownloadsModule, find.text('Sprite Fright · Radarr 1')),
      findsOne,
    );
    // Arrived: the 4K's import is on the rail, and the card says which
    // Radarr it came to. Its failed import is Needs you's, not a card.
    expect(
      _within(HomeArrivedModule, find.text('2\u00A0h ago · Radarr 4K')),
      findsOne,
    );
    expect(find.bySemanticsLabel('Spring, 2\u00A0h ago, Radarr 4K'), findsOne);
    expect(
      _within(HomeArrivedModule, find.text('Elephants Dream')),
      findsNothing,
    );

    handle.dispose();
    await harness.unmount(tester);
  });

  testWidgets('P1, lens on the HD: the 4K Radarr\'s failed import reaches '
      'Needs you, and its row says which Radarr', (tester) async {
    final harness = await ProfileHarness.start(Profiles.p1);
    _scriptFailedImportOn4k(harness.network);
    await tester.binding.setSurfaceSize(_tall);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The row itself: the Home leads with one line and opens the place a
    // fault is fixed, so the decision's row is mounted on its own.
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: ProvidedDecisionRows(
              where: (decision) => decision.kind == DecisionKind.failedImport,
            ),
          ),
        ),
      ),
    );
    await harness.settle(tester);

    expect(
      find.descendant(
        of: find.byType(DecisionRow),
        matching: find.text(
          'Import failed · Radarr 4K · Not a valid video file',
        ),
      ),
      findsOne,
    );

    await harness.unmount(tester);
  });

  test('P1: every row the 4K contributes is bound to the 4K', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    _scriptFailedImportOn4k(harness.network);
    final container = harness.container(retry: (_, _) => null);

    // The queue rows: their route opens the 4K's film, under the 4K's id.
    final queue = await container.read(servicesQueueProvider.future);
    final elephants = queue.items.singleWhere(
      (item) => item.title == 'Elephants Dream',
    );
    expect(elephants.instanceId, WorldIds.radarr4k);
    expect(Uri.parse(elephants.route!).queryParameters['i'], WorldIds.radarr4k);

    // The failed import's Fix opens the wizard on the 4K, and its row the
    // 4K's film.
    final history = await container.read(
      dashboardDecisionSourceProvider(DecisionSource.history).future,
    );
    final fix = history.decisions.single;
    expect(fix.instanceId, WorldIds.radarr4k);
    expect(fix.actionInstanceId, WorldIds.radarr4k);
    expect(Uri.parse(fix.route!).queryParameters['i'], WorldIds.radarr4k);
  });

  test('P1: two movies numbered 3, one on each Radarr, are two cards that '
      'open two different movies', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container(retry: (_, _) => null);

    final cards = await _arrivedCards(container, harness);
    final threes = cards
        .where((card) => card.service == ServiceKey.radarr && card.mediaId == 3)
        .toList();
    expect(threes.map((card) => card.title), ['Spring', 'Coffee Run']);
    expect(threes.map((card) => card.instanceId), [
      WorldIds.radarr4k,
      WorldIds.radarr,
    ]);
    // A card is a title, and a title is TMDB's: the number a Radarr gave it
    // is its own, so it is neither what keeps two cards apart nor what a card
    // opens.
    expect(threes.map((card) => card.tmdbId), [
      WorldTitles.spring.tmdbId,
      WorldTitles.coffeeRun.tmdbId,
    ]);
    expect(threes.map(arrivedIdentity).toSet(), hasLength(2));
  });

  test('P1: a movie on the HD and the 4K Radarr is one card, the newer '
      'import\'s, and says which Radarr', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    // The HD Radarr imported Tears of Steel three days ago, and the 4K a day
    // and two hours ago.
    harness.network.on(
      WorldIds.radarr,
      'GET',
      '/api/v3/history/since',
      (r) => NetworkReply.json([
        ...const RadarrFake().history(
          ServerContext(
            network: harness.network,
            server: harness.network.server(WorldIds.radarr),
          ),
        ),
        {
          'id': 77,
          'movieId': 5,
          'eventType': 'downloadFolderImported',
          'date': harness.network.now
              .subtract(const Duration(days: 3))
              .toUtc()
              .toIso8601String(),
          'movie': {
            'id': 5,
            'title': 'Tears of Steel',
            'tmdbId': WorldTitles.tearsOfSteel.tmdbId,
            'added': harness.network.now
                .subtract(const Duration(days: 17))
                .toUtc()
                .toIso8601String(),
          },
        },
      ]),
    );
    final container = harness.container(retry: (_, _) => null);

    final history = await _arrivals(container);
    expect(
      history.entries.where((entry) => entry.title == 'Tears of Steel'),
      hasLength(3),
      reason: 'the HD answered with its old import and its new one',
    );
    final tears = (await _arrivedCards(
      container,
      harness,
    )).where((card) => card.title == 'Tears of Steel').toList();
    expect(tears, hasLength(1));
    expect(tears.single.instanceId, WorldIds.radarr4k);
    expect(tears.single.connectionName, '4K');
  });

  test('P1: every connection of Radarr, Sonarr and Lidarr is asked for the '
      'week, and each entry carries its own', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container(retry: (_, _) => null);

    final history = await _arrivals(container);

    for (final id in [
      WorldIds.radarr,
      WorldIds.radarr4k,
      WorldIds.sonarr,
      WorldIds.lidarr,
    ]) {
      expect(
        harness.network
            .requestsTo(id)
            .where((r) => r.path.endsWith('/history/since')),
        hasLength(1),
        reason: '$id is asked once',
      );
    }
    expect(
      history.entries
          .where((entry) => entry.service == ServiceKey.radarr)
          .map((entry) => (entry.title, entry.instanceId, entry.connectionName))
          .toSet(),
      {
        ('Coffee Run', WorldIds.radarr, 'Radarr 1'),
        ('Sintel', WorldIds.radarr, 'Radarr 1'),
        ('Tears of Steel', WorldIds.radarr, 'Radarr 1'),
        ('Elephants Dream', WorldIds.radarr, 'Radarr 1'),
        ('Spring', WorldIds.radarr4k, '4K'),
        ('Tears of Steel', WorldIds.radarr4k, '4K'),
      },
    );
    expect(history.coverage.isWhole, isTrue);
  });

  test('P1, the HD Radarr dark: the week is the 4K\'s, and the coverage '
      'names the one missing', () async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withBehaviour(
        WorldIds.radarr,
        ConnectionBehaviour.didNotAnswer,
      ),
    );
    final container = harness.container(retry: (_, _) => null);

    final history = await _arrivals(container);
    final cards = await _arrivedCards(container, harness);

    expect(history.coverage.failed.keys.map((source) => source.title), [
      'Radarr 1',
    ]);
    expect(cards.map((card) => card.title), ['Spring', 'Tears of Steel']);
    expect(cards.map((card) => card.instanceId).toSet(), {WorldIds.radarr4k});
    expect(
      arrivedSubtitle(cards.length, history.coverage),
      'Last 7 days · 2 from Lidarr, Radarr 4K and Sonarr',
    );
  });

  testWidgets('P1, the HD Radarr dark: the 4K keeps its rows, and the note '
      'names the one missing', (tester) async {
    final harness = await _pumpHome(
      tester,
      Profiles.p1.withBehaviour(
        WorldIds.radarr,
        ConnectionBehaviour.didNotAnswer,
      ),
    );

    expect(
      _within(HomeDownloadsModule, find.text('Not in the total: Radarr 1')),
      findsOne,
    );
    // The 4K keeps its movies: the one the module has room for is drawn, and
    // both are still in what it counts.
    expect(
      _within(HomeDownloadsModule, find.text('Elephants Dream · Radarr 4K')),
      findsOne,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    final inFlight = container.read(servicesInFlightProvider).requireValue;
    // The one that moves and the one that waits its turn.
    expect(
      [
        ...inFlight.preview,
        ...inFlight.queued,
      ].where((item) => item.instanceId == WorldIds.radarr4k),
      hasLength(2),
    );
    // Arrived draws the 4K's cards, says whose they are, and names the Radarr
    // that did not answer over the rail.
    expect(
      _within(
        HomeArrivedModule,
        find.text('Last 7 days · 2 from Lidarr, Radarr 4K and Sonarr'),
      ),
      findsOne,
    );
    expect(
      _within(HomeArrivedModule, find.text('Radarr 1 did not answer.')),
      findsOne,
    );
    expect(
      _within(HomeArrivedModule, find.text('2\u00A0h ago · Radarr 4K')),
      findsOne,
    );
    // A figure over the connections that answered, never a dash over a
    // Radarr that did. Sintel on the 4K waits its turn, and is said apart.
    expect(
      _within(
        HomeDownloadsModule,
        find.text('4 moving · 1 stuck · 1 queued · 40.4\u00A0MB/s'),
      ),
      findsOne,
    );
    expect(find.text('— moving'), findsNothing);

    await harness.unmount(tester);
  });

  test('P1 + the cabin Seerr: both Seerrs\' requests wait on Home, each '
      'bound to its own', () async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withConnection(WorldConnections.seerrCabin),
    );
    final container = harness.container(retry: (_, _) => null);

    final requests = await container.read(
      dashboardDecisionSourceProvider(DecisionSource.requests).future,
    );
    final byConnection = <String, List<DashboardDecision>>{};
    for (final decision in requests.decisions) {
      (byConnection[decision.instanceId] ??= []).add(decision);
    }
    expect(
      byConnection.keys,
      unorderedEquals([WorldIds.seerr, WorldIds.seerrCabin]),
    );
    expect(
      byConnection[WorldIds.seerr]!.length,
      byConnection[WorldIds.seerrCabin]!.length,
    );

    final cabin = byConnection[WorldIds.seerrCabin]!.first;
    // Named, and opening the cabin's own requests list: Discover reads the
    // lens, so a media page would have asked the other Seerr.
    expect(cabin.detail, startsWith('Seerr Cabin · '));
    expect(cabin.route, '/activity/requests?i=${WorldIds.seerrCabin}');
    // Ids carry the connection: both Seerrs number their requests from one.
    expect(
      requests.decisions.map((decision) => decision.id).toSet(),
      hasLength(requests.decisions.length),
    );
    expect(requests.coverage.isWhole, isTrue);
  });
}
