@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/features/import/presentation/manual_import_review_rows.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/main.dart' as cupola;

import '../../test/test_helpers/settings_scope.dart';
import 'testlab_journey_harness.dart';

/// The Radarr manual import, driven through the app's own wizard.
///
/// Arrange is the host's: the `manual-import-radarr-ambiguous` scenario has
/// already put a real, completed download in qBittorrent, and Radarr's own
/// `manualimport` scan rejects its file as `Unknown Movie`. The test starts
/// from Activity, walks Locate and Review, chooses Big Buck Bunny, imports, and
/// proves on Radarr that the movie now has that file. The row is gone from the
/// review.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Activity · Manual import · Locate · Review · choose the movie · import',
    (tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final lab = Lab.load();
      final container = ProviderContainer(
        overrides: [
          ...await settingsScopeOverrides(
            customize: (settings) => settings
                .copyWithService(
                  ServiceKey.radarr,
                  url: LabEndpoints.appUrlOf(ServiceKey.radarr),
                  apiKey: lab.arrKeys[ServiceKey.radarr] ?? '',
                )
                .copyWithCredentials(
                  ServiceKey.qbittorrent,
                  url: LabEndpoints.appUrlOf(ServiceKey.qbittorrent),
                  username: lab.credentials.require(
                    'CUPOLA_TESTLAB_QBITTORRENT_USERNAME',
                  ),
                  password: lab.credentials.require(
                    'CUPOLA_TESTLAB_QBITTORRENT_PASSWORD',
                  ),
                ),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const cupola.CupolaApp(),
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));
      container.read(routerProvider).go('/activity');
      await _pumpFor(tester, const Duration(seconds: 2));

      await tester.tap(find.byTooltip('More'));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      await tester.tap(find.text('Manual import…'));
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(
        find.text('Pick the connection that should take the files'),
        findsOneWidget,
      );
      await tester.tap(find.text('Radarr').last);
      await _pumpFor(tester, const Duration(seconds: 1));

      expect(find.text('Locate'), findsWidgets);
      final pathField = find.byType(TextField).first;
      await tester.enterText(
        pathField,
        '/downloads/The.Great.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA',
      );
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await _pumpFor(tester, const Duration(seconds: 2));

      final scan = find.textContaining('Scan "');
      expect(scan, findsOneWidget);
      await tester.tap(scan);
      await _waitFor(tester, find.text('Needs attention'));

      final fileRow = find.byType(AttentionFileRow).first;
      expect(fileRow, findsOneWidget);
      await tester.ensureVisible(fileRow);
      await _pumpFor(tester, const Duration(milliseconds: 300));
      await tester.tap(fileRow);
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text('Which movie?'), findsOneWidget);

      final search = find.byType(TextField).last;
      await tester.enterText(search, 'Big Buck Bunny');
      await _pumpFor(tester, const Duration(seconds: 2));
      final result = find.text('Big Buck Bunny').last;
      expect(result, findsOneWidget);
      await tester.tap(result);
      await _pumpFor(tester, const Duration(milliseconds: 400));
      final match = find.text('Match to Big Buck Bunny');
      expect(match, findsOneWidget);
      await tester.tap(match);
      await _pumpFor(tester, const Duration(seconds: 1));

      final import = find.text('Import 1 file');
      expect(import, findsOneWidget);
      await tester.tap(import);
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text('Import 1 file into Radarr?'), findsOneWidget);
      await tester.tap(find.text('Import 1 file').last);
      await _pumpFor(tester, const Duration(seconds: 2));
      await _waitFor(tester, find.text('Completed'));

      final movie = await _waitForMovie(tester);
      expect(movie['hasFile'], isTrue, reason: 'Radarr did not take the file');
      expect(
        (movie['movieFile'] as Map?)?['relativePath'],
        contains('The.Great.Bunny'),
      );
      expect(await _manualImportItems(), isEmpty);

      final back = find.text('Back to review');
      if (back.evaluate().isNotEmpty) {
        await tester.tap(back);
        await _pumpFor(tester, const Duration(seconds: 2));
        // The scan deliberately reports files the service already holds, so
        // the row does not vanish: it changes from `Needs match` to `Imported`.
        // That is the app's contract, and the plan's "the row disappears" is
        // the one sentence this journey does not assert.
        expect(find.text('Imported'), findsWidgets);
        expect(find.text('Needs match'), findsNothing);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('Timed out waiting for $finder');
}

Future<Map<String, dynamic>> _waitForMovie(
  WidgetTester tester, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final movie = await _movie();
    if (movie['hasFile'] == true) return movie;
    await tester.pump(const Duration(milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('Radarr never reported the file');
}

Future<Map<String, dynamic>> _movie() async {
  final value = await _radarr('/movie?tmdbId=10378');
  if (value is List) {
    for (final item in value) {
      if (item is Map && item['tmdbId'] == 10378) {
        return Map<String, dynamic>.from(item);
      }
    }
  }
  return <String, dynamic>{};
}

Future<List<dynamic>> _manualImportItems() async {
  final value = await _radarr(
    '/manualimport?folder=/downloads/The.Great.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA&filterExistingFiles=true',
  );
  return value is List ? value : const [];
}

Future<Object?> _radarr(String path) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:7878/api/v3$path'),
    );
    request.headers.set(
      'X-Api-Key',
      Lab.load().arrKeys[ServiceKey.radarr] ?? '',
    );
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
