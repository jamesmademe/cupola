import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/import/presentation/manual_import_review_rows.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'testlab_journey_harness.dart';

/// The manual import, the way a person drives it, for the journeys of
/// catalogue M-01..M-15.
///
/// Only the verbs those rows use, each one a step a person takes: open the
/// wizard from Activity, find a folder, scan it, fix a match, choose how the
/// files go in, confirm, watch the import. Every control is found by the words
/// or the accessible name the app gives it, so a journey breaks when the app
/// says something else, which is the point.
class ManualImportDriver {
  ManualImportDriver(this.tester, this.app);

  final WidgetTester tester;
  final LabApp app;

  LabSurface get surface => app.surface;

  /// Waits for [finder], and fails with what the surface drew instead.
  Future<void> need(
    Finder finder,
    String what, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (finder.evaluate().isNotEmpty) return;
      await settle(tester, const Duration(milliseconds: 300));
    }
    fail('$what. The surface drew: ${surface.texts().join(' | ')}');
  }

  /// Activity, `More`, `Manual import…`, then the connection for [service].
  Future<void> openWizard(ServiceKey service) async {
    await app.go(tester, ServiceRoutes.activity);
    await tester.tap(find.byTooltip('More'));
    await settle(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Manual import…'));
    await settle(tester, const Duration(milliseconds: 800));
    await surface.see('Pick the connection that should take the files');
    await tester.tap(find.text(service.title).last);
    await settle(tester, const Duration(seconds: 1));
  }

  /// Types [path] in `Folder path` and goes there.
  Future<void> goTo(String path) async {
    final field = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Folder path',
    );
    await need(field, 'Locate drew no folder field');
    await tester.enterText(field.first, path);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await settle(tester, const Duration(seconds: 2));
  }

  /// Taps the subfolder [name] in the list Locate drew.
  Future<void> openFolder(String name) async {
    await surface.see(name);
    await app.tapIn(tester, find.text(name).first);
    await settle(tester, const Duration(seconds: 2));
  }

  /// `Scan "<folder>"`, then waits for the Review to have read the folder.
  Future<void> scan(String folder) async {
    final button = find.text('Scan "$folder"');
    await need(button, 'Locate never offered to scan');
    await tester.tap(button);
    await settle(tester, const Duration(seconds: 2));
    await need(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            const [
              'Matched files',
              'Needs attention',
              'Other files',
            ].contains(widget.data),
      ),
      'the Review never showed what the scan found',
      timeout: const Duration(minutes: 2),
    );
  }

  /// Locate, the folder by its path, the scan: the shortest way to Review.
  Future<void> reviewFolder(String path) async {
    await goTo(path);
    final name = path.split('/').last;
    await surface.see('Scan "$name"');
    await scan(name);
  }

  /// Opens the fix sheet of the [index]th file that needs a match.
  Future<void> openFix([int index = 0]) async {
    final row = find.byType(AttentionFileRow);
    await need(row, 'no file needs a match');
    await app.tapIn(tester, row.at(index));
    await settle(tester, const Duration(milliseconds: 800));
  }

  /// Types [query] in the fix sheet's search field.
  Future<void> search(
    String query, {
    String hint = 'Search your movies',
  }) async {
    final field = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == hint,
    );
    await need(field, 'the fix sheet drew no "$hint"');
    await tester.enterText(field, query);
    await settle(tester, const Duration(seconds: 2));
  }

  /// Picks [title] among the results and matches the file to it.
  Future<void> matchTo(String title) async {
    await surface.see(title);
    await tester.tap(find.text(title).last);
    await settle(tester, const Duration(milliseconds: 500));
    final match = find.text('Match to $title');
    await need(match, 'the sheet never offered the match');
    await tester.tap(match);
    await settle(tester, const Duration(seconds: 1));
  }

  /// The import mode menu, then [label] (`Auto`, `Move`, `Copy`).
  Future<void> mode(String label) async {
    // The menu's button reads the current mode; its accessible name,
    // `Import mode`, is not in the tree while the test runs without
    // semantics.
    final button = find.ancestor(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            const ['Auto', 'Move', 'Copy'].contains(widget.data),
      ),
      matching: find.byType(OutlinedButton),
    );
    await need(button, 'the Review drew no import mode');
    await tester.tap(button.first);
    await settle(tester, const Duration(milliseconds: 500));
    await tester.tap(
      find.descendant(
        of: find.byType(MenuItemButton),
        matching: find.text(label),
      ),
    );
    await settle(tester, const Duration(milliseconds: 500));
  }

  /// The footer's `Import N files`, the confirmation, the Track screen.
  Future<void> confirmImport(int files, {String service = 'Radarr'}) async {
    final words = files == 1 ? 'Import 1 file' : 'Import $files files';
    await surface.see(words);
    await tester.tap(find.text(words).last);
    await settle(tester, const Duration(milliseconds: 800));
    final dialog = find.byType(Dialog);
    await surface.see('$words into $service?');
    await tester.tap(
      find.descendant(of: dialog, matching: find.text(words)).last,
    );
    await settle(tester, const Duration(seconds: 2));
  }

  /// Waits for the Track screen to say [state] (`Completed`, `Failed`, …).
  Future<void> waitTrack(String state) =>
      surface.see(state, timeout: const Duration(minutes: 3));
}

/// Radarr's own answers, straight to the service, for the server half of a
/// manual import journey.
class ImportReadings {
  ImportReadings(this.apiKey);

  final String apiKey;

  static const _radarr = 'http://127.0.0.1:7878/api/v3';

  Future<Object?> _get(String path) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$_radarr$path'));
      request.headers.set('X-Api-Key', apiKey);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        fail('Radarr $path answered ${response.statusCode}: $body');
      }
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  /// The movie Radarr holds as [title] ([year]).
  Future<Map<String, dynamic>> movie(String title, int year) async {
    final movies = await _get('/movie');
    for (final movie in (movies as List).cast<Map<String, dynamic>>()) {
      if (movie['title'] == title && movie['year'] == year) return movie;
    }
    fail('Radarr holds no $title ($year)');
  }

  /// The movie once Radarr says it has a file, or a failure after [timeout].
  Future<Map<String, dynamic>> movieWithFile(
    WidgetTester tester,
    String title,
    int year, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final found = await movie(title, year);
      if (found['hasFile'] == true) return found;
      await settle(tester, const Duration(seconds: 1));
    }
    fail('Radarr never gave $title a file');
  }

  /// The titles of the downloads in Radarr's queue.
  Future<List<String>> queueTitles() async {
    final page = await _get('/queue?page=1&pageSize=100');
    return [
      for (final record in ((page as Map)['records'] as List))
        (record as Map)['title'] as String,
    ];
  }

  /// The quality and the languages of the file Radarr holds for the movie.
  static ({String quality, List<String> languages, String path}) fileOf(
    Map<String, dynamic> movie,
  ) {
    final file = movie['movieFile'] as Map<String, dynamic>;
    final quality = (file['quality'] as Map)['quality'] as Map;
    return (
      quality: quality['name'] as String,
      languages: [
        for (final language in (file['languages'] as List? ?? const []))
          (language as Map)['name'] as String,
      ],
      path: file['relativePath'] as String,
    );
  }
}

/// Any arr's own answers, straight to its API, for the server half of a manual
/// import journey: Sonarr and Lidarr, where [ImportReadings] reads Radarr.
class ArrApi {
  ArrApi(this.base, this.apiKey);

  /// `http://127.0.0.1:<port>/api/v<n>`.
  final String base;
  final String apiKey;

  Future<Object?> get(String path) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$base$path'));
      request.headers.set('X-Api-Key', apiKey);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        fail('$path answered ${response.statusCode}: $body');
      }
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  /// Sonarr's episode [season]x[number] of the series named [title].
  Future<Map<String, dynamic>> episode(
    String title,
    int season,
    int number,
  ) async {
    final series = (await get('/series') as List).cast<Map<String, dynamic>>();
    final id = series.firstWhere((item) => item['title'] == title)['id'];
    final episodes = (await get('/episode?seriesId=$id') as List)
        .cast<Map<String, dynamic>>();
    return episodes.firstWhere(
      (item) =>
          item['seasonNumber'] == season && item['episodeNumber'] == number,
    );
  }

  /// The path of the file Sonarr holds for [episode], or null.
  Future<String?> episodeFilePath(Map<String, dynamic> episode) async {
    final id = episode['episodeFileId'] as int? ?? 0;
    if (id == 0) return null;
    final file = await get('/episodefile/$id') as Map<String, dynamic>;
    return file['relativePath'] as String?;
  }

  /// The tracks of [album] by [artist], each with the file it holds
  /// (`trackFileId` 0 when none).
  Future<List<Map<String, dynamic>>> albumTracks(
    String artist,
    String album,
  ) async {
    final artists = (await get('/artist') as List).cast<Map<String, dynamic>>();
    final artistId = artists.firstWhere(
      (item) => item['artistName'] == artist,
    )['id'];
    final albums = (await get('/album?artistId=$artistId') as List)
        .cast<Map<String, dynamic>>();
    final albumId = albums.firstWhere((item) => item['title'] == album)['id'];
    return (await get('/track?albumId=$albumId') as List)
        .cast<Map<String, dynamic>>();
  }

  /// The tracks numbered [numbers] (Lidarr's `a1`, `b2`…) of [album] once
  /// Lidarr holds a file for each: the server's state, not a fixed wait. A
  /// command can say `Completed` a moment before the file is on the record.
  Future<List<Map<String, dynamic>>> albumTracksWithFiles(
    String artist,
    String album,
    List<String> numbers, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final end = DateTime.now().add(timeout);
    while (true) {
      final chosen = (await albumTracks(
        artist,
        album,
      )).where((track) => numbers.contains(track['trackNumber'])).toList();
      final filed =
          chosen.length == numbers.length &&
          chosen.every((track) => (track['trackFileId'] as int? ?? 0) > 0);
      if (filed) return chosen;
      if (DateTime.now().isAfter(end)) {
        fail('Lidarr never gave ${numbers.join(', ')} a file');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
}
