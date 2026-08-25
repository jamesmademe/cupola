import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_settings_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> container() async {
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('defaults match the constants the feature ships with', () async {
    final c = await container();
    final settings = c.read(releaseSearchSettingsProvider);

    expect(settings.concurrency, kDefaultSearchConcurrency);
    expect(settings.timeout, kReleaseSearchReceiveTimeout);
  });

  test('the timeout can never reach the transport ceiling', () {
    // The background library's iOS request timeout is fixed at startup, and a
    // user-facing value that met it would give two different failures the same
    // elapsed — which is the ambiguity the verdicts exist to remove.
    expect(
      ReleaseSearchSettings.maxTimeout,
      lessThan(const Duration(minutes: 15)),
    );
    // Still above every common gateway ceiling, which is what keeps a timeout
    // attributable.
    expect(
      ReleaseSearchSettings.maxTimeout,
      greaterThan(const Duration(seconds: 100)),
    );
  });

  test('concurrency clamps to the courteous range', () async {
    final c = await container();
    final notifier = c.read(releaseSearchSettingsProvider.notifier);

    notifier.setConcurrency(99);
    expect(
      c.read(releaseSearchSettingsProvider).concurrency,
      ReleaseSearchSettings.maxConcurrency,
    );

    notifier.setConcurrency(0);
    expect(
      c.read(releaseSearchSettingsProvider).concurrency,
      ReleaseSearchSettings.minConcurrency,
    );
  });

  test('the timeout clamps at both ends', () async {
    final c = await container();
    final notifier = c.read(releaseSearchSettingsProvider.notifier);

    notifier.setTimeoutMinutes(600);
    expect(
      c.read(releaseSearchSettingsProvider).timeout,
      ReleaseSearchSettings.maxTimeout,
    );

    notifier.setTimeoutMinutes(0);
    expect(
      c.read(releaseSearchSettingsProvider).timeout,
      ReleaseSearchSettings.minTimeout,
    );
  });

  test('both values survive a restart', () async {
    final first = await container();
    first.read(releaseSearchSettingsProvider.notifier).setConcurrency(4);
    first.read(releaseSearchSettingsProvider.notifier).setTimeoutMinutes(8);

    // A fresh container over the same prefs is what a cold start looks like.
    final prefs = await SharedPreferences.getInstance();
    final second = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(second.dispose);

    final settings = second.read(releaseSearchSettingsProvider);
    expect(settings.concurrency, 4);
    expect(settings.timeout, const Duration(minutes: 8));
  });

  test('it still resolves where SharedPreferences was never provided', () {
    // Widget tests routinely omit it; the screen must render rather than throw.
    final bare = ProviderContainer();
    addTearDown(bare.dispose);

    expect(
      bare.read(releaseSearchSettingsProvider).concurrency,
      kDefaultSearchConcurrency,
    );
  });

  group('the background search switch', () {
    test('ships off, on every path that can produce a value', () async {
      // Not a preference with a convenient default: on means the OS gets the
      // request, API key and all, in writing. So every route to a value — fresh
      // prefs, absent prefs — has to answer off, including the fallback that
      // exists for widget tests.
      final c = await container();
      expect(c.read(releaseSearchSettingsProvider).backgroundEnabled, isFalse);

      final bare = ProviderContainer();
      addTearDown(bare.dispose);
      expect(
        bare.read(releaseSearchSettingsProvider).backgroundEnabled,
        isFalse,
      );
    });

    test('survives a restart once turned on', () async {
      final first = await container();
      first
          .read(releaseSearchSettingsProvider.notifier)
          .setBackgroundEnabled(true);

      final prefs = await SharedPreferences.getInstance();
      final second = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(second.dispose);

      expect(
        second.read(releaseSearchSettingsProvider).backgroundEnabled,
        isTrue,
      );
    });

    test('reads a stored opt-in from a previous launch', () async {
      SharedPreferences.setMockInitialValues({
        'release_search_background_enabled': true,
      });
      final c = await container();
      expect(c.read(releaseSearchSettingsProvider).backgroundEnabled, isTrue);
    });

    test('turning it off does not disturb the other settings', () async {
      // The flip goes through copyWith rather than rebuilding the record field
      // by field, which is what used to make every new setting a chance to
      // silently reset an old one.
      final c = await container();
      final notifier = c.read(releaseSearchSettingsProvider.notifier);
      notifier.setConcurrency(4);
      notifier.setTimeoutMinutes(7);
      notifier.setNotifyOnFinish(true);

      notifier.setBackgroundEnabled(true);
      notifier.setBackgroundEnabled(false);

      final settings = c.read(releaseSearchSettingsProvider);
      expect(settings.concurrency, 4);
      expect(settings.timeout, const Duration(minutes: 7));
      expect(
        settings.notifyOnFinish,
        isTrue,
        reason:
            'the notification preference is disabled by the master, not reset '
            'by it — it has to come back when the master does',
      );
    });
  });
}
