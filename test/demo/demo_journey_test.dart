import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/main.dart';

import '../test_helpers/profiles/profiles.dart';
import '../test_helpers/demo_artwork.dart';

/// The demo's journey, the whole app on the demo's world: a request waiting
/// for approval is approved, goes to Radarr, downloads, and arrives, and
/// every request on the way is answered inside the process.
void main() {
  setUp(() {
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.empty();
    SharedPreferences.resetStatic();
  });

  testWidgets('a request is approved, downloads and arrives', (tester) async {
    useDemoArtworkFiles();
    final session = (await tester.runAsync(
      () => DemoSession.start(leaving: const SettingsModel()),
    ))!;
    addTearDown(session.end);
    // The demo's clock is the wall's; here it is the test's.
    session.network.followFakeTime(tester.binding);
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...session.overrides,
          // The polls' timers would outlive the test; each has its own.
          homeLivePollProvider.overrideWith((ref) {}),
          homeRecoveryPollProvider.overrideWith((ref) {}),
          activityLivePollProvider.overrideWith((ref, tab) {}),
          featuredAdvancesProvider.overrideWithValue(false),
        ],
        child: const CupolaApp(),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> pullToRefresh() async {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 500));
      await settle();
    }

    await settle();

    // Activity's requests: Luca's Metropolis waits.
    await tester.tap(find.text('Activity').last);
    await settle();
    await tester.tap(find.text('Requests').first);
    await settle();
    expect(find.text('3 requests wait for your approval'), findsOneWidget);

    // Approved: it goes to Radarr, which grabs it.
    await tester.tap(find.text('Approve').first);
    await settle();
    expect(
      find.text('Metropolis goes to Radarr 1 and starts downloading.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Approve request'));
    await settle();
    expect(find.text('2 requests wait for your approval'), findsOneWidget);
    expect(find.textContaining('sent to Radarr 1'), findsOneWidget);
    expect(find.textContaining('Downloading 0%'), findsOneWidget);
    expect(
      session.network.life!.downloads.where(
        (d) => d.title == WorldTitles.metropolis,
      ),
      hasLength(1),
    );

    // A minute and a half later it is on the server.
    await tester.pump(const Duration(minutes: 2));
    await pullToRefresh();
    expect(find.textContaining('Ready to watch since'), findsWidgets);

    // And the Home says it arrived, under what it features.
    await tester.tap(find.text('Home').last);
    await settle();
    await pullToRefresh();
    await tester.scrollUntilVisible(
      find.textContaining('Just now'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await settle();
    expect(find.text('Metropolis'), findsWidgets);
    expect(find.textContaining('Just now'), findsOneWidget);

    expect(tester.takeException(), isNull);
    expect(
      session.network.unanswered.map((r) => '${r.method} ${r.uri}'),
      isEmpty,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
