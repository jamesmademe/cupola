/// A Stack band says a service is clean only when Needs you holds no fault
/// on it. Seen live: `6 of 6 clean` over Radarr, Sonarr and Lidarr while
/// Needs you said none of them had an indexer watching for new releases.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/services/presentation/stack_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  testWidgets('P1: a health check failing on three arrs keeps them out of '
      'the Media band\'s clean count, each named', (tester) async {
    final harness = await ProfileHarness.start(Profiles.p1);
    for (final (id, path) in [
      (WorldIds.radarr, '/api/v3/health'),
      (WorldIds.sonarr, '/api/v3/health'),
      (WorldIds.lidarr, '/api/v1/health'),
    ]) {
      harness.network.on(
        id,
        'GET',
        path,
        (_) => NetworkReply.json([
          {
            'source': 'IndexerRssCheck',
            'type': 'error',
            'message': 'No indexers available with RSS sync enabled',
          },
        ]),
      );
    }
    harness.network.followFakeTime(tester.binding);
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const StackScreen(),
        ),
      ),
    );
    await harness.settle(tester);

    // Drawn a part at a time, each with its dot, so a phone breaks the line
    // only between them. The third, Lidarr, is counted, not named: a band
    // header is not a list. What is not set up is said apart, never as one
    // of the others.
    for (final part in [
      '2 of 5 clean\u00A0·',
      'Radarr needs a look\u00A0·',
      'Sonarr needs a look\u00A0·',
      '1 other\u00A0·',
    ]) {
      expect(find.text(part), findsOneWidget, reason: part);
    }
    // Another band is short of a service too.
    expect(find.text('1 not set up'), findsWidgets);

    await harness.unmount(tester);
  });
}
