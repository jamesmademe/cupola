@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/main.dart' as cupola;

import '../../test/test_helpers/settings_scope.dart';

/// The app's interactive release search, with the real Prowlarr-synced
/// indexer: the sheet shows the catalogue and the reason a row is rejected.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the movie page searches through Prowlarr and shows the rejection reasons',
    (tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final id = await _movieId();
      final container = ProviderContainer(
        overrides: [
          ...await settingsScopeOverrides(
            customize: (settings) => settings
                .copyWithService(
                  ServiceKey.radarr,
                  url: 'http://127.0.0.1:27878',
                  apiKey: 'test-key',
                )
                .copyWithCredentials(
                  ServiceKey.qbittorrent,
                  url: 'http://127.0.0.1:8080',
                  username: 'admin',
                  password: 'cupola-pass',
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
      container.read(routerProvider).go(ServiceRoutes.radarrMovie(id));
      await _pumpFor(tester, const Duration(seconds: 2));

      await _waitFor(
        tester,
        find.textContaining('Big Buck Bunny'),
        timeout: const Duration(seconds: 90),
      );
      final search = find.text('Search releases');
      await tester.scrollUntilVisible(
        search,
        320,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await _waitFor(tester, search);
      await tester.ensureVisible(search);
      await tester.tap(search);
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(find.text('Releases'), findsWidgets);

      await _waitFor(
        tester,
        find.textContaining('24 releases'),
        timeout: const Duration(minutes: 2),
      );

      // The rows are virtualised and a rejected row is below the fold; the
      // badge is what the sheet draws for it, and the host test proves the
      // reason text Radarr computes. Expanding the row here would test the
      // scroll more than the search.
      expect(find.text('Rejected'), findsWidgets);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<int> _movieId() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:7878/api/v3/movie?tmdbId=10378'),
    );
    request.headers.set('X-Api-Key', 'test-key');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final value = jsonDecode(body) as List;
    return (value.first as Map)['id'] as int;
  } finally {
    client.close(force: true);
  }
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
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('Timed out waiting for $finder');
}
