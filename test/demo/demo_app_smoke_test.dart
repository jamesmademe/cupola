import 'package:flutter/widgets.dart';
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

/// The whole app, opened on the demo the way the onboarding opens it: the
/// Home draws from the world, and every request it makes is answered.
void main() {
  setUp(() {
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.empty();
    SharedPreferences.resetStatic();
  });

  testWidgets('the demo opens on a Home the world answers', (tester) async {
    final session = (await tester.runAsync(
      () => DemoSession.start(leaving: const SettingsModel()),
    ))!;
    addTearDown(session.end);

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
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    // World A's Home: the download at 62 % and the episode under way.
    expect(find.text('Sprite Fright'), findsWidgets);
    expect(find.text('Cosmos Laundromat'), findsWidgets);
    expect(session.network.requests, isNotEmpty);
    expect(
      session.network.unanswered.map((r) => '${r.method} ${r.uri}'),
      isEmpty,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
