/// Stack's media server rows say what is playing, and they read the same
/// app-wide sessions cache as the Home. Seen live: `0 streaming` on Plex's
/// row while a playback had been running for a minute, because the Home had
/// read the cache before it started and Stack only reads everything again
/// after two minutes away.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/services/presentation/stack_screen.dart';

import '../../../test_helpers/fixtures.dart';
import '../../../test_helpers/profiles/profiles.dart';

void main() {
  testWidgets('P1: opened over sessions another page read, Stack reads '
      "them again and the media server's row says what plays now", (
    tester,
  ) async {
    final harness = await ProfileHarness.start(Profiles.p1);
    var playing = false;
    var reads = 0;
    harness.network.on(WorldIds.jellyfin, 'GET', '/Sessions', (_) {
      reads++;
      return NetworkReply.json(
        jsonFixtureList(
          playing
              ? 'jellyfin/sessions_active.json'
              : 'jellyfin/sessions_idle.json',
        ),
      );
    });
    harness.network.followFakeTime(tester.binding);
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Widget app(Widget home) => ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: home),
    );

    // The Home reads the sessions while nobody is watching, then goes off
    // screen; the answer stays in the cache.
    await tester.pumpWidget(
      app(
        Consumer(
          builder: (context, ref, _) {
            ref.watch(jellyfinSessionsProvider);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await harness.settle(tester);
    expect(reads, 1);

    // Two playbacks start; then Stack is opened.
    playing = true;
    await tester.pumpWidget(app(const StackScreen()));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Two seconds, not a poll interval: the row did not just read what it
    // shows, so it reads again as Stack opens.
    expect(reads, 2);
    expect(find.textContaining('2 streaming'), findsOneWidget);

    await harness.unmount(tester);
  });
}
