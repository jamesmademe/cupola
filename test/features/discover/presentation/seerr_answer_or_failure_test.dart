/// Seerr's reads, driven through the app's real client on the profiles' fake
/// network: an empty answer and no answer never look alike.
///
/// Every one of these used to turn a failure into `{}` or `[]`, so a Seerr
/// that did not answer, or refused the key, read "Seerr answered, but it has no
/// record of them", "No results found", a Discover rail that quietly vanished,
/// and a global-search lane reading "0 results" and counted as answered.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'package:cupola/demo/world/fakes/media_fakes.dart';
import '../../../test_helpers/profiles/profiles.dart';

Future<ProviderContainer> _start(ConfigProfile profile) async {
  final harness = await ProfileHarness.start(profile);
  return harness.container(retry: (_, _) => null);
}

Future<ServiceFailureReason> _reasonOf(Future<Object?> future) async {
  try {
    await future;
  } catch (error) {
    return classifyConnectionFailure(error);
  }
  fail('expected the read to fail');
}

ConfigProfile _seerr(ConnectionBehaviour behaviour) =>
    Profiles.p1.withBehaviour(WorldIds.seerr, behaviour);

void main() {
  group('person', () {
    test('an answer is the person', () async {
      final c = await _start(Profiles.p1);
      final person = await c.read(
        personDetailProvider(SeerrFake.personId).future,
      );
      expect(person.name, SeerrFake.personName);
    });

    test('"no record" only when Seerr answered that it has none', () async {
      final c = await _start(Profiles.p1);
      final person = await c.read(personDetailProvider(424242).future);
      expect(person.isEmpty, isTrue);
    });

    test('a Seerr that did not answer is a failure, not "no record"', () async {
      final c = await _start(_seerr(ConnectionBehaviour.didNotAnswer));
      expect(
        await _reasonOf(
          c.read(personDetailProvider(SeerrFake.personId).future),
        ),
        ServiceFailureReason.unreachable,
      );
      expect(
        await _reasonOf(
          c.read(personCreditsProvider(SeerrFake.personId).future),
        ),
        ServiceFailureReason.unreachable,
      );
    });
  });

  group('collection', () {
    test('a refused key is a refusal, not "nothing filed here"', () async {
      final c = await _start(_seerr(ConnectionBehaviour.refusesKey));
      expect(
        await _reasonOf(
          c.read(collectionDetailProvider(SeerrFake.collectionId).future),
        ),
        ServiceFailureReason.unauthorized,
      );
    });

    test('an answer is the collection', () async {
      final c = await _start(Profiles.p1);
      final collection = await c.read(
        collectionDetailProvider(SeerrFake.collectionId).future,
      );
      expect(collection.name, SeerrFake.collectionName);
    });
  });

  group('Discover', () {
    test(
      'a rail whose source failed fails, instead of reading empty',
      () async {
        final c = await _start(_seerr(ConnectionBehaviour.refusesKey));
        expect(
          await _reasonOf(c.read(discoverTrendingProvider.future)),
          ServiceFailureReason.unauthorized,
        );
      },
    );
  });

  group('the global-search Seerr lane', () {
    Future<GlobalSearchServiceResults> seerrLane(ConfigProfile profile) async {
      final c = await _start(profile);
      final sub = c.listen(globalSearchLanesProvider, (_, _) {});
      addTearDown(sub.close);
      c.read(globalSearchQueryProvider.notifier).state = 'sprite';
      final legs = c.read(globalSearchLegsProvider);
      final leg = legs.singleWhere(
        (leg) => leg.instance.service == ServiceKey.seerr,
      );
      return c.read(globalSearchLegProvider(leg).future);
    }

    test('a refused key is a failed lane, never "0 results"', () async {
      final lane = await seerrLane(
        Profiles.p3.withBehaviour(
          WorldIds.seerr,
          ConnectionBehaviour.refusesKey,
        ),
      );
      expect(lane.state, SearchLaneState.failed);
      expect(lane.reason, ServiceFailureReason.unauthorized);
      expect(
        lane.faultSentence,
        'No Seerr results: Seerr answered but refused the key.',
      );
    });

    test('a Seerr that did not answer is not counted as answered', () async {
      final lane = await seerrLane(
        Profiles.p3.withBehaviour(
          WorldIds.seerr,
          ConnectionBehaviour.didNotAnswer,
        ),
      );
      expect(lane.state, SearchLaneState.unreachable);
      expect(lane.faultSentence, 'No Seerr results: Seerr did not answer.');
      expect(lane.hasFault, isTrue);
    });

    test('an answer is an answered lane with its rows', () async {
      final lane = await seerrLane(Profiles.p3);
      expect(lane.state, SearchLaneState.answered);
      expect(lane.results, isNotEmpty);
    });
  });
}
