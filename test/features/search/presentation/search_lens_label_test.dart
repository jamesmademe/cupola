import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

const _fourK = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  label: '4K',
  url: 'https://four-k.lan:7878',
  credential: 'k',
);
const _hd = ServiceInstance(
  id: 'radarr-hd11111',
  service: ServiceKey.radarr,
  label: 'HD',
  url: 'https://hd.lan:7879',
  credential: 'k',
);
const _sonarr = ServiceInstance(
  id: 'sonarr',
  service: ServiceKey.sonarr,
  url: 'https://sonarr.lan:8989',
  credential: 'k',
);

GlobalSearchServiceResults _lane(
  ServiceInstance instance, {
  bool named = false,
  SearchLaneState state = SearchLaneState.answered,
  List<GlobalSearchResult> results = const [],
}) => GlobalSearchServiceResults(
  leg: (instance: instance, name: named ? instance.label : ''),
  state: state,
  results: results,
);

void main() {
  group('the section says which connection answered', () {
    test('nothing to say while a service has one connection', () {
      // The default, and the one that matters: a stack with one Sonarr must
      // not grow a chip naming the only Sonarr there is.
      expect(_lane(_sonarr).instanceLabel, isEmpty);
      expect(_lane(_sonarr).laneTitle, 'Sonarr');
    });

    test('carries the label when there is one to carry', () {
      final lane = _lane(_fourK, named: true);
      expect(lane.instanceLabel, '4K');
      expect(lane.laneTitle, 'Radarr · 4K');
    });

    test('a connection with no label is called by its place, never its id', () {
      // A second connection is required to have a label, but nothing in the
      // model enforces it. The name comes from the app's one rule, so the
      // heading reads what every other surface reads.
      const nameless = ServiceInstance(
        id: 'radarr-hd11111',
        service: ServiceKey.radarr,
        url: 'https://hd.lan:7879',
        credential: 'k',
      );
      const settings = SettingsModel(instances: [_fourK, nameless]);
      final lane = GlobalSearchServiceResults(
        leg: (
          instance: nameless,
          name: settings.connectionName(nameless.id) ?? '',
        ),
      );
      expect(lane.instanceLabel, 'Radarr 2');
      expect(lane.laneTitle, 'Radarr 2');
    });

    test('a lane that stopped is named too', () {
      // "Radarr did not answer" is a worse sentence than "Radarr · 4K did not
      // answer" when the other connection did.
      final lane = _lane(_hd, named: true, state: SearchLaneState.unreachable);
      expect(lane.hasFault, isTrue);
      expect(lane.instanceLabel, 'HD');
      expect(lane.faultSentence, contains('Radarr · HD'));
    });
  });

  group('the lane tone grammar', () {
    // The rule the whole screen is drawn against, and the one the code it
    // replaced got wrong: every failure painted `colorScheme.error` with the
    // word "offline", so a Bazarr taking nine seconds and a Bazarr that was
    // unplugged were the same red sentence.
    test('a lane that ran out of time is AMBER, and says so', () {
      final lane = GlobalSearchServiceResults.fault((
        instance: _fourK,
        name: '',
      ), TimeoutException('too slow'));
      expect(lane.state, SearchLaneState.timedOut);
      expect(lane.state.tone, StatusTone.warning);
      expect(lane.stateWord, 'Did not answer in time');
      expect(lane.faultSentence, contains('timed out'));
    });

    test('red is a connection nothing answered at, and nothing else', () {
      final lane = GlobalSearchServiceResults.fault((
        instance: _fourK,
        name: '',
      ), const SocketException('no route to host'));
      expect(lane.state, SearchLaneState.unreachable);
      expect(lane.state.tone, StatusTone.error);
      expect(lane.stateWord, 'Did not answer');
    });

    test('a refusal is a fault, not an outage', () {
      // The server answered — it just said no. Red here would send the user
      // auditing an address that is correct.
      final lane = GlobalSearchServiceResults.fault(
        (instance: _fourK, name: ''),
        DioException(
          requestOptions: RequestOptions(path: '/api/v3/movie/lookup'),
          response: Response<void>(
            requestOptions: RequestOptions(path: '/api/v3/movie/lookup'),
            statusCode: 401,
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      expect(lane.state, SearchLaneState.failed);
      expect(lane.state.tone, StatusTone.warning);
      expect(lane.reason, ServiceFailureReason.unauthorized);
      expect(lane.stateWord, 'Refused the key');
    });

    test('an answered lane counts, wears no pip and offers no Retry', () {
      final empty = _lane(_sonarr);
      expect(empty.state.tone, StatusTone.neutral);
      expect(empty.state.showsPip, isFalse);
      expect(empty.state.canRetry, isFalse);
      expect(empty.hasFault, isFalse);
      expect(empty.stateWord, '0 results');
    });

    test('a lane still in flight is informational, not a fault', () {
      final lane = _lane(_sonarr, state: SearchLaneState.searching);
      expect(lane.state.tone, StatusTone.info);
      expect(lane.state.showsPip, isTrue);
      // Retrying a lane still in flight would cancel the request the user is
      // waiting on and start it again a keystroke behind.
      expect(lane.state.canRetry, isFalse);
      expect(lane.hasFault, isFalse);
      expect(lane.stateWord, 'Searching…');
    });

    test('every stopped lane offers the Retry that concerns only it', () {
      for (final state in [
        SearchLaneState.timedOut,
        SearchLaneState.unreachable,
        SearchLaneState.failed,
      ]) {
        expect(_lane(_sonarr, state: state).state.canRetry, isTrue);
        expect(_lane(_sonarr, state: state).state.showsPip, isTrue);
      }
    });
  });

  group('the census beside the heading', () {
    // A fold over the lane states and nothing else, so the line can never
    // disagree with the sections under it.
    test('nothing to census before a query', () {
      expect(searchLaneCensus(const []), isNull);
    });

    test('names every state that is actually happening', () {
      expect(
        searchLaneCensus([
          _lane(_fourK, named: true),
          _lane(_hd, named: true),
          _lane(_sonarr, state: SearchLaneState.searching),
          _lane(_sonarr, state: SearchLaneState.timedOut),
        ]),
        '4 connections asked · 2 answered · 1 still searching · 1 timed out',
      );
    });

    test('a count of zero is a word about nothing, except "answered"', () {
      // "0 timed out" is noise; "0 answered" is the entire story while a stack
      // is down.
      expect(
        searchLaneCensus([_lane(_fourK, state: SearchLaneState.unreachable)]),
        '1 connection asked · 0 answered · 1 did not answer',
      );
    });
  });

  group('search follows the lens', () {
    ProviderContainer container({Map<ServiceKey, String> lenses = const {}}) {
      final c = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => const SettingsModel(instances: [_fourK, _hd, _sonarr]),
          ),
          initialActiveInstancesProvider.overrideWithValue(lenses),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a service with one connection reports no label to show', () {
      expect(
        container().read(hasMultipleInstancesProvider(ServiceKey.sonarr)),
        isFalse,
      );
    });

    test('the label follows the lens, not the first connection', () {
      // The bug this guards: the search legs read lens-aware providers while
      // the key that decides whether to refetch described the first connection.
      // Moving the lens showed the previous server's answers and never
      // refetched, because nothing the provider watched had changed.
      final c = container(lenses: {ServiceKey.radarr: 'radarr-hd11111'});

      expect(c.read(hasMultipleInstancesProvider(ServiceKey.radarr)), isTrue);
      expect(c.read(activeInstanceProvider(ServiceKey.radarr))?.label, 'HD');
      expect(
        c.read(activeInstanceProvider(ServiceKey.radarr))?.url,
        'https://hd.lan:7879',
      );
    });
  });
}
