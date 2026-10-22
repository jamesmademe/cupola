/// The media servers and Now playing: S-01, S-02, S-06, S-03 and S-09.
///
/// The world: the Jellyfin and Plex of L8, with Films, Series and Music on the
/// same folders, a non-admin `cupola-viewer`, a watched film and an episode in
/// Continue watching, and Plex's own on deck. Sessions are opened by the lab's
/// own player (`jellyfin_play.py --listen`), which is the only client that
/// obeys the app's remote pause and stop.
///
/// What each journey proves, in the app's own words:
///
/// - **S-01**: the libraries the server holds are the ones the app draws, and a
///   title opens on its own page.
/// - **S-02**: the household users, the devices and the scheduled tasks the
///   server holds are the rows the tabs draw; the fourth tab (`Activity`) is
///   Now playing, not a log, and it draws the section.
/// - **S-06**: Plex's libraries, on deck, devices and playlists are drawn.
/// - **S-03**: a playback the server knows is a card with the app's controls;
///   pause, resume, message and stop are the app's own commands, and the
///   server's session changes with them.
/// - **S-09**: Now playing draws one and then two playbacks on the Home and on
///   the Jellyfin overview, and goes back to its idle line when they stop.
///
/// S-04 (`Resume in Jellyfin`, a hand-off to the platform's player), S-05 (the
/// client has no watch/task write), S-07 (Plex's stop needs Plex Pass) and S-08
/// (the Plex client has no playlist write) stay agent steps or impossibilities,
/// as the catalogue says.
///
/// **S-03 and S-09 need their playbacks opened on the host.** The app runs on
/// the iOS simulator, where starting a process is forbidden, so the lab's own
/// player is started outside the journey and this file only reads it and
/// commands it: `test/e2e/testlab/journey_sessions.py S-03` (or `S-09`) starts
/// the right devices, runs this file, and ends them on the way out.
@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'testlab_journey_harness.dart';

/// The title the lab's library holds first, by the kind the server names.
Future<String> _movieTitle(LabApp app) async {
  final items = await _jellyfinMap(
    app,
    '/Items?IncludeItemTypes=Movie&Recursive=true&Limit=1',
  );
  return _firstName(items, 'movie');
}

/// The series the lab's first episode belongs to.
///
/// An episode's row draws the show and its place in it ("Breaking Bad · S1 E1"),
/// never the episode's own file name, so this is what a journey can look for.
Future<String> _episodeTitle(LabApp app) async {
  final items = await _jellyfinMap(
    app,
    '/Items?IncludeItemTypes=Episode&Recursive=true&Limit=1',
  );
  final rows = items['Items'] as List? ?? const [];
  if (rows.isEmpty) fail('the Jellyfin library holds no episode');
  final episode = rows.first as Map;
  final series = episode['SeriesName'] as String?;
  return (series == null || series.isEmpty)
      ? episode['Name'] as String
      : series;
}

String _firstName(Map items, String kind) {
  final rows = items['Items'] as List? ?? const [];
  if (rows.isEmpty) fail('the Jellyfin library holds no $kind');
  return (rows.first as Map)['Name'] as String;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'S-01 · the Jellyfin libraries and a title',
    (tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final app = await LabApp.asOperator(
        tester,
        services: const {ServiceKey.jellyfin},
      );

      final folders = await _jellyfinList(app, '/Library/VirtualFolders');
      final names = [
        for (final folder in folders)
          if ((folder as Map)['Name'] case final String name) name,
      ];
      expect(
        names,
        containsAll(['Films', 'Series', 'Music']),
        reason: 'the lab seeded three libraries',
      );

      await app.go(tester, ServiceRoutes.jellyfinLibraries);
      await app.surface.see('Libraries');
      for (final name in names) {
        await app.surface.see(name);
      }

      // The title's own page, opened on its own route: the libraries list
      // opens this page for the same item.
      final items = await _jellyfinMap(
        app,
        '/Items?IncludeItemTypes=Movie&Recursive=true&Limit=1',
      );
      final film = (items['Items'] as List).first as Map;
      await app.go(tester, ServiceRoutes.jellyfinItem(film['Id'] as String));
      await app.surface.see(film['Name'] as String);
      await app.surface.seePart('Jellyfin');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'S-02 · the household users, devices and tasks Jellyfin holds',
    (tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final app = await LabApp.asOperator(
        tester,
        services: const {ServiceKey.jellyfin},
      );

      final users = await _jellyfinList(app, '/Users');
      final viewer = users
          .cast<Map>()
          .map((user) => user['Name'])
          .whereType<String>()
          .where((name) => name == 'cupola-viewer');
      expect(viewer, isNotEmpty, reason: 'the lab seeded the viewer account');

      await app.go(tester, ServiceRoutes.jellyfinUsers);
      await app.surface.see('Users');
      await app.surface.see('${users.length} users');
      await _scrollUntil(tester, 'cupola-viewer');
      await app.surface.see('cupola-viewer');

      final devices = await _jellyfinList(app, '/Devices');
      final deviceNames = [
        for (final device in devices)
          if ((device as Map)['Name'] case final String name)
            if (name.trim().isNotEmpty) name,
      ];
      await app.go(tester, ServiceRoutes.jellyfinDevices);
      await app.surface.see('Devices');
      await app.surface.see('${devices.length} devices');
      expect(
        deviceNames.where(app.surface.draws),
        isNotEmpty,
        reason:
            'the Devices tab draws none of the names the server holds: '
            '${app.surface.texts().join(' | ')}',
      );

      final tasks = await _jellyfinList(app, '/ScheduledTasks');
      final taskNames = [
        for (final task in tasks)
          if ((task as Map)['Name'] case final String name)
            if (name.trim().isNotEmpty) name,
      ];
      await app.go(tester, ServiceRoutes.jellyfinTasks);
      await app.surface.see('Tasks');
      expect(
        taskNames.where(app.surface.draws),
        isNotEmpty,
        reason:
            'the Tasks tab draws none of the names the server holds: '
            '${app.surface.texts().join(' | ')}',
      );

      // The app's fourth tab is the server's live sessions read: its own
      // words, not a log's.
      await app.go(tester, ServiceRoutes.jellyfinActivity);
      await app.surface.see('Activity');
      await app.surface.see('Now playing');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'S-06 · the Plex libraries, on deck, devices and playlists',
    (tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final app = await LabApp.asOperator(
        tester,
        services: const {ServiceKey.plex},
      );

      final sections = await _plexContainer(app, '/library/sections');
      final titles = [
        for (final directory in sections['Directory'] as List? ?? const [])
          if ((directory as Map)['title'] case final String title) title,
      ];
      expect(titles, isNotEmpty, reason: 'the lab seeded Plex libraries');

      await app.go(tester, ServiceRoutes.plexLibraries);
      for (final title in titles) {
        await app.surface.see(title);
      }

      final onDeck = await _plexContainer(app, '/library/onDeck');
      final deck = (onDeck['Metadata'] as List? ?? const []);
      await app.go(tester, ServiceRoutes.plexOnDeck);
      await app.surface.see('On deck');
      if (deck.isNotEmpty) {
        await app.surface.see((deck.first as Map)['title'] as String);
      }

      await app.go(tester, ServiceRoutes.plexDevices);
      await app.surface.see('Devices');
      await app.go(tester, ServiceRoutes.plexPlaylists);
      await app.surface.see('Playlists');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'S-03 · pause, resume, message and stop a Jellyfin playback',
    (tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final app = await LabApp.asOperator(
        tester,
        services: const {ServiceKey.jellyfin},
      );
      final device = 'cupola-s03';
      final film = await _movieTitle(app);
      await _waitForSession(tester, app, device);
      await app.go(tester, ServiceRoutes.jellyfinOverview);
      await app.surface.see('Now playing');
      await app.surface.seePart(film);

      // The controls sit at the card's edge, under the bottom bar at this
      // height: lift the page before touching them.
      await tester.dragFrom(const Offset(200, 400), const Offset(0, -240));
      await settle(tester, const Duration(milliseconds: 800));

      // Pause: the app's command, and the server's own state behind it.
      await tester.tap(find.byTooltip('Pause this playback'));
      await app.surface.waitFor(find.byTooltip('Resume this playback'));
      expect(
        await _isPaused(app, device),
        isTrue,
        reason: 'the server did not pause the session',
      );

      await tester.tap(find.byTooltip('Resume this playback'));
      await app.surface.waitFor(find.byTooltip('Pause this playback'));
      expect(
        await _isPaused(app, device),
        isFalse,
        reason: 'the server did not resume the session',
      );

      // A message is the app's prompt, then the server's own channel.
      await tester.tap(find.byTooltip('Send a message to this player'));
      await app.surface.see('Send');
      await tester.enterText(
        find.byType(TextField).last,
        'Dinner in ten minutes',
      );
      await settle(tester, const Duration(milliseconds: 500));
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await app.surface.seePart('Message sent to');

      // Stop: the question, the answer, and the session gone from the server.
      await tester.tap(find.byTooltip('Stop this playback'));
      await app.surface.see('Stop playback?');
      await tester.tap(find.widgetWithText(FilledButton, 'Stop playback'));
      await _waitForNoSession(tester, app, device);
      await app.go(tester, ServiceRoutes.jellyfinOverview);
      await app.surface.see('Nobody is watching right now');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'S-09 · Now playing draws one and two playbacks, then its idle line',
    (tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final app = await LabApp.asOperator(
        tester,
        services: const {ServiceKey.jellyfin},
      );
      final first = 'cupola-s09a';
      final second = 'cupola-s09b';
      final film = await _movieTitle(app);
      final episode = await _episodeTitle(app);
      await _waitForSession(tester, app, first);

      // One session, on the room's page and on the Home.
      await app.go(tester, ServiceRoutes.jellyfinOverview);
      await app.surface.see('Now playing');
      await app.surface.seePart(film);
      await app.go(tester, ServiceRoutes.home);
      await app.surface.seePart(film);

      // A second one: both are on the room's page and on the Home.
      await _waitForSession(tester, app, second);
      await app.go(tester, ServiceRoutes.jellyfinOverview);
      await app.surface.seePart(film);
      await app.surface.seePart(episode);
      await app.go(tester, ServiceRoutes.home);
      await app.surface.seePart(film);
      await app.surface.seePart(episode);

      // Both stop: the room says nobody is watching.
      await _stopOnServer(app, first);
      await _stopOnServer(app, second);
      await _waitForNoSession(tester, app, first);
      await _waitForNoSession(tester, app, second);
      await app.go(tester, ServiceRoutes.jellyfinOverview);
      await app.surface.see('Nobody is watching right now');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// Ends the session on [device] on the server, the way the app's Stop does.
Future<void> _stopOnServer(LabApp app, String device) async {
  final session = await _sessionOf(app, device);
  final id = session?['Id'] as String?;
  if (id == null) return;
  await _jellyfin(app, '/Sessions/$id/Playing/Stop', method: 'POST');
}

Future<void> _waitForSession(
  WidgetTester tester,
  LabApp app,
  String device,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    if (await _sessionOf(app, device) != null) return;
    await settle(tester, const Duration(milliseconds: 500));
  }
  fail(
    'the server never saw the session on $device. Start it with '
    '"test/e2e/testlab/journey_sessions.py S-03" (or "S-09").',
  );
}

Future<void> _waitForNoSession(
  WidgetTester tester,
  LabApp app,
  String device,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (DateTime.now().isBefore(deadline)) {
    if (await _sessionOf(app, device) == null) return;
    await settle(tester, const Duration(milliseconds: 500));
  }
  fail('the server still holds the session on $device');
}

Future<bool> _isPaused(LabApp app, String device) async {
  final session = await _sessionOf(app, device);
  final state = session?['PlayState'] as Map?;
  return state?['IsPaused'] == true;
}

Future<Map?> _sessionOf(LabApp app, String device) async {
  final sessions = await _jellyfinList(app, '/Sessions');
  final slug = device
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  for (final entry in sessions) {
    final session = entry as Map;
    // `--device` is the DeviceName the helper presents; the DeviceId is its
    // namespaced slug, so both identify the same session.
    final name = session['DeviceName'] as String?;
    final id = session['DeviceId'] as String?;
    if (name == device || id == 'cupola-play-$slug') return session;
  }
  return null;
}

Future<List> _jellyfinList(LabApp app, String path) async {
  final answer = await _jellyfin(app, path);
  if (answer is List) return answer;
  // `/Devices` answers with the server's paged container, not a bare list.
  if (answer is Map && answer['Items'] is List) return answer['Items'] as List;
  return const [];
}

Future<Map> _jellyfinMap(LabApp app, String path) async {
  final answer = await _jellyfin(app, path);
  if (answer is Map) return answer;
  fail('Jellyfin answered $path with ${answer.runtimeType}, not an object');
}

Future<Object?> _jellyfin(
  LabApp app,
  String path, {
  String method = 'GET',
}) async {
  final token = app.credentials.require('CUPOLA_TESTLAB_JELLYFIN_TOKEN');
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('${LabEndpoints.directUrlOf(ServiceKey.jellyfin)}$path'),
    );
    request.headers.set(
      'Authorization',
      'MediaBrowser Client="Cupola", Device="journey", '
          'DeviceId="cupola-journey-reader", Version="test", Token="$token"',
    );
    request.headers.set('Accept', 'application/json');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      fail('Jellyfin $path answered ${response.statusCode}: $body');
    }
    return body.isEmpty ? null : jsonDecode(body);
  } finally {
    client.close(force: true);
  }
}

Future<Map> _plexContainer(LabApp app, String path) async {
  final token = app.credentials.require('CUPOLA_TESTLAB_PLEX_TOKEN');
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('${LabEndpoints.directUrlOf(ServiceKey.plex)}$path'),
    );
    request.headers.set('X-Plex-Token', token);
    request.headers.set('Accept', 'application/json');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      fail('Plex $path answered ${response.statusCode}: $body');
    }
    final json = jsonDecode(body) as Map;
    return (json['MediaContainer'] as Map?) ?? json;
  } finally {
    client.close(force: true);
  }
}

/// Scrolls the page's own list until [text] is on the screen.
Future<void> _scrollUntil(WidgetTester tester, String text) async {
  final target = find.text(text);
  if (target.evaluate().isNotEmpty) return;
  // A card that is still arriving is not a reason to drag: give the page the
  // moment its provider needs, then look again.
  await settle(tester, const Duration(seconds: 2));
  if (target.evaluate().isNotEmpty) return;
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) return;
  try {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: scrollables.last,
      maxScrolls: 40,
    );
  } on StateError {
    fail('The page never drew "$text". It drew: ${_texts(tester)}');
  }
  await settle(tester, const Duration(milliseconds: 600));
}

/// Every line the surface draws, for a failure that has to say what it saw.
String _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? '')
    .where((data) => data.isNotEmpty)
    .join(' | ');
