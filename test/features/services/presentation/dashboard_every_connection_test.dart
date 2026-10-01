/// Home reads every connection of a service, the way its header does.
///
/// Needs a decision, In flight and Recently added used to read the lens
/// alone. With two Radarr, the 4K's downloads, its failed imports and its
/// imports never reached Home, and nothing on Home said so. Each connection is
/// now its own source: one that fails is named under the figure and takes
/// only its own rows with it, and every row carries the connection it came
/// off, so what it opens is that server's.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_screen.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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

void _scriptFailedImportOn4k(ProfileNetwork network) => network.on(
  WorldIds.radarr4k,
  'GET',
  '/api/v3/history',
  (r) => NetworkReply.json(pagedEnvelope(r, [_failedImport(network.now)])),
);

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
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: const DashboardScreen(),
      ),
    ),
  );
  await harness.settle(tester);
  return harness;
}

Finder _within(Type region, Finder matching) =>
    find.descendant(of: find.byType(region), matching: matching);

void main() {
  testWidgets('P1, lens on the HD: the 4K Radarr reaches every region, '
      'named', (tester) async {
    final handle = tester.ensureSemantics();
    final harness = await _pumpHome(
      tester,
      Profiles.p1,
      before: _scriptFailedImportOn4k,
    );

    // Needs a decision: the 4K's failed import, saying which Radarr.
    expect(
      _within(
        DashboardDecisionsSection,
        find.text('Import failed · Radarr 4K · Not a valid video file'),
      ),
      findsOne,
    );
    // In flight: the 4K's two films, joined to the SABnzbd moving them.
    expect(
      _within(
        ServicesInFlightSection,
        find.text(
          'Radarr 4K · Bluray-2160p · 2.9 of 9.4 GB · 6 min left · SABnzbd',
        ),
      ),
      findsOne,
    );
    // The HD's own rows say which Radarr too, now that there are two.
    expect(
      _within(
        ServicesInFlightSection,
        find.textContaining('Radarr 1 · WEBDL-1080p'),
      ),
      findsOne,
    );
    // Recently added: the 4K's failed import is on the rail, and the tile
    // says which Radarr it failed on.
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Elephants Dream, Radarr 4K, failed import, '),
      ),
      findsOne,
    );

    handle.dispose();
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

  test('P1: two films numbered 3, one on each Radarr, are two tiles that '
      'open two different films', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container(retry: (_, _) => null);

    final recent = await container.read(servicesRecentlyAddedProvider.future);
    final threes = recent.items
        .where((item) => item.service == ServiceKey.radarr && item.id == 3)
        .toList();
    expect(threes.map((item) => item.title), ['Spring', 'Coffee Run']);
    expect(threes.map((item) => item.instanceId), [
      WorldIds.radarr4k,
      WorldIds.radarr,
    ]);
    // One hero per tile: two tiles sharing a tag assert on the flight.
    expect(threes.map((item) => item.heroTag).toSet(), hasLength(2));
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
      _within(ServicesInFlightSection, find.text('Not in the total: Radarr 1')),
      findsOne,
    );
    expect(
      _within(ServicesInFlightSection, find.textContaining('Radarr 4K · ')),
      findsNWidgets(2),
    );
    expect(
      _within(
        ServicesRecentlyAddedSection,
        find.text('Not in the total: Radarr 1'),
      ),
      findsOne,
    );
    // A figure over the connections that answered, never a dash over a
    // Radarr that did.
    expect(find.text('— downloading'), findsNothing);
    expect(find.text('— imported'), findsNothing);

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
    expect(cabin.detail, startsWith('Request · Seerr Cabin · '));
    expect(cabin.route, '/activity/discover?i=${WorldIds.seerrCabin}');
    // Ids carry the connection: both Seerrs number their requests from one.
    expect(
      requests.decisions.map((decision) => decision.id).toSet(),
      hasLength(requests.decisions.length),
    );
    expect(requests.coverage.isWhole, isTrue);
  });
}
