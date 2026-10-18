/// Leaving home with the app open: a read on its way to the address at home
/// fails there, and its reader never says so. The failure waits for the
/// route probe, which moves the connection to the address away first, and
/// the reader, rebuilt on that address, reads again from there.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/network_change.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/route_knock.dart';
import 'package:cupola/features/settings/data/route_probe.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _away = 'https://radarr.example.net';

void main() {
  testWidgets('a read on its way out of the house never fails: it reads '
      'away', (tester) async {
    await tester.runAsync(() async {
      final profile = Profiles.p3.withConnection(
        ProfileConnection(
          WorldConnections.radarr.instance.copyWith(
            away: const ConnectionAddress(url: _away),
          ),
          // The address away crosses the internet: its answer, and its
          // knock, take a moment.
          latency: const Duration(milliseconds: 80),
        ),
      );
      // The knocks, as the two addresses answer them: home until the phone
      // leaves, away a moment later, across the internet.
      var atHome = true;
      final harness = await ProfileHarness.start(
        profile,
        overrides: [
          routeKnockProvider.overrideWithValue((
            service,
            reach, {
            required timeout,
          }) async {
            if (reach.url == _away) {
              await Future<void>.delayed(const Duration(milliseconds: 80));
              return true;
            }
            return atHome;
          }),
        ],
      );
      harness.network.serveAlsoAt(WorldIds.radarr, _away);
      final container = harness.container();
      container.read(routeProbeProvider);

      final states = <AsyncValue<List<RadarrMovie>>>[];
      container.listen(moviesProvider, (_, next) => states.add(next));
      await container.read(moviesProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        container.read(connectionRoutesProvider)[WorldIds.radarr],
        isNot(ConnectionRoute.away),
      );

      // Out of the house: home stops answering, the phone says its network
      // changed, and the list is read again at that moment.
      atHome = false;
      harness.network.behave(WorldIds.radarr, PlainBehaviour.didNotAnswer);
      states.clear();
      container.read(networkChangesProvider.notifier).changed();
      container.invalidate(moviesProvider);

      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (states.isNotEmpty &&
            states.last.hasValue &&
            !states.last.isLoading) {
          break;
        }
      }
      expect(
        states.where((state) => state.hasError),
        isEmpty,
        reason: 'the reader never drew the failure at home',
      );
      expect(states.last.value, isNotEmpty);
      expect(
        container.read(connectionRoutesProvider)[WorldIds.radarr],
        ConnectionRoute.away,
      );
    });
  });
}
