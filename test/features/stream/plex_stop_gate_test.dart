/// One Stop gate for a Plex playback, read by every surface that draws Stop.
///
/// Plex's Now playing and the Activity list that used to sit beside it each
/// derived their own. Now playing treated a capability sheet that had not
/// answered, or that did not say whether the server has Plex Pass, as
/// available; the list treated both as refused. Stop now comes from
/// `plexStopOfferedProvider`, the one gate, and these pin it on Now playing.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_now_playing_section.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_session_card.dart';

import '../../test_helpers/fixtures.dart';
import '../../test_helpers/profiles/profiles.dart';

/// P1 with its Plex set up, on the owner's token.
final _withPlex = Profiles.p1.withConnection(WorldConnections.plex);

const _stopTooltip = 'Stop this playback';

/// Anna watching Tears of Steel on the Plex, with a session Plex can
/// terminate. Not Sintel, which she is watching on P1's Jellyfin too.
NetworkReply _annaWatching(NetworkRequest _) => NetworkReply.json({
  'MediaContainer': {
    'size': 1,
    'Metadata': [
      {
        'ratingKey': '101',
        'key': '/library/metadata/101',
        'type': 'movie',
        'title': WorldTitles.tearsOfSteel.title,
        'year': WorldTitles.tearsOfSteel.year,
        'duration': 888000,
        'viewOffset': 300000,
        'User': {'id': '2', 'title': WorldPeople.anna},
        'Player': {
          'product': 'Plex for Android TV',
          'device': 'Living room TV',
          'state': 'playing',
        },
        'Session': {
          'id': 'plex-session-anna',
          'bandwidth': 4200,
          'location': 'lan',
        },
      },
    ],
  },
});

/// The capability sheet, with `myPlexSubscription` as [subscription] says:
/// absent when null, as several builds send it.
NetworkRoute _sheet({bool? subscription}) => (_) {
  final container = Map<String, dynamic>.from(
    jsonFixtureMap('plex/capabilities.json')['MediaContainer'] as Map,
  )..remove('myPlexSubscription');
  if (subscription != null) container['myPlexSubscription'] = subscription;
  return NetworkReply.json({'MediaContainer': container});
};

Future<ProfileHarness> _start({
  NetworkRoute? sheet,
  List<Override> overrides = const [],
}) async {
  final harness = await ProfileHarness.start(_withPlex, overrides: overrides);
  harness.network.on(WorldIds.plex, 'GET', '/status/sessions', _annaWatching);
  if (sheet != null) harness.network.on(WorldIds.plex, 'GET', '/', sheet);
  return harness;
}

Future<void> _pumpNowPlaying(
  WidgetTester tester,
  ProfileHarness harness,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Consumer(
              builder: (context, ref, _) => StreamNowPlayingSection(
                service: ServiceKey.plex,
                sessions: ref.watch(plexSessionsProvider),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await harness.settle(tester);
}

Finder get _plexCard => find.ancestor(
  of: find.text(WorldTitles.tearsOfSteel.title),
  matching: find.byType(StreamSessionCard),
);

/// The Stop on the Plex session's own card.
Finder get _plexStop =>
    find.descendant(of: _plexCard, matching: find.byTooltip(_stopTooltip));

/// The Plex card is on screen, so the absence of Stop is about the gate.
void _expectAnnaWatching() => expect(_plexCard, findsOneWidget);

void main() {
  group('a sheet that does not say whether the server has Plex Pass', () {
    testWidgets('Now playing offers Stop', (tester) async {
      final harness = await _start(sheet: _sheet());
      await _pumpNowPlaying(tester, harness);

      _expectAnnaWatching();
      expect(_plexStop, findsOneWidget);
      await harness.unmount(tester);
    });
  });

  group('a sheet that has not answered yet', () {
    // Pinned above the network: the sheet is held open for the whole test,
    // which a canned reply cannot do.
    List<Override> holdSheet(Completer<PlexServerCapabilities> sheet) => [
      plexCapabilitiesProvider.overrideWith((ref) => sheet.future),
    ];

    testWidgets('Now playing offers Stop, and keeps it once the sheet says '
        'the server has Plex Pass', (tester) async {
      final sheet = Completer<PlexServerCapabilities>();
      final harness = await _start(overrides: holdSheet(sheet));
      await _pumpNowPlaying(tester, harness);

      _expectAnnaWatching();
      expect(_plexStop, findsOneWidget);

      sheet.complete(
        PlexServerCapabilities.fromMediaContainer(
          jsonFixtureMap('plex/capabilities.json')['MediaContainer']
              as Map<String, dynamic>,
        ),
      );
      await harness.settle(tester);
      expect(_plexStop, findsOneWidget);
      await harness.unmount(tester);
    });
  });

  group('a server that says it has no Plex Pass', () {
    testWidgets('Now playing draws no Stop', (tester) async {
      final harness = await _start(sheet: _sheet(subscription: false));
      await _pumpNowPlaying(tester, harness);

      _expectAnnaWatching();
      expect(_plexStop, findsNothing);
      await harness.unmount(tester);
    });
  });
}
