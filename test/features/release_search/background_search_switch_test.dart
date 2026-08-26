import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/release_search/data/background_task_hygiene.dart';
import 'package:cupola/features/release_search/data/release_search_bootstrap.dart';
import 'package:cupola/features/release_search/data/release_search_transport.dart';
import 'package:cupola/features/release_search/domain/release_search_job.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/background_search_switch.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_settings_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// Records the prune instead of reaching for a platform channel.
class _RecordingHygiene extends BackgroundTaskHygiene {
  const _RecordingHygiene(this.calls);

  final List<int> calls;

  @override
  Future<bool> pruneFinishedWork() async {
    calls.add(calls.length);
    return true;
  }
}

final _season = ReleaseSearchTarget.season(
  seriesId: 1,
  seasonNumber: 2,
  label: 'Severance · Season 2',
);

final _movie = ReleaseSearchTarget.movie(movieId: 9, label: 'Dune: Part Two');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the bootstrap', () {
    test('configures and purges even with the feature switched off', () async {
      // **The most important test in this feature.** What clears the records a
      // previous session left on disk — the plugin's own pop at start(), and
      // the WorkManager prune — runs from here. If "off" meant "skip the
      // bootstrap", the user who switches background search off would keep the
      // last copy of their API key on disk for as long as the OS felt like it,
      // and the privacy setting would be a privacy regression. The flag is not
      // even an input to this function, and that is deliberate: there is
      // nothing here to gate.
      var configured = 0;
      var started = 0;
      var pruned = 0;
      bool? rescheduleKilled;

      await configureBackgroundSearch(
        supported: () => true,
        configure: (globalConfig) async {
          configured++;
        },
        start: ({required bool doRescheduleKilledTasks}) async {
          started++;
          rescheduleKilled = doRescheduleKilledTasks;
        },
        prune: () async {
          pruned++;
          return true;
        },
      );
      // The prune is unawaited by design; let the microtask land.
      await pumpEventQueue();

      expect(configured, 1);
      expect(started, 1);
      expect(pruned, 1);
      expect(
        rescheduleKilled,
        isFalse,
        reason:
            'rescheduling a killed task would re-run a full search against the '
            "user's indexers with nobody watching",
      );
    });

    test('passes the two library ceilings that are wrong by default', () async {
      List<(String, Object)>? passed;
      await configureBackgroundSearch(
        supported: () => true,
        configure: (globalConfig) async => passed = globalConfig,
        start: ({required bool doRescheduleKilledTasks}) async {},
        prune: () async => true,
      );

      final byKey = {for (final entry in passed!) entry.$1: entry.$2};
      expect(
        byKey['requestTimeout'],
        const Duration(minutes: 15),
        reason:
            'the default 60s measures the gap between received bytes, and this '
            'server sends nothing while it queries indexers',
      );
      expect(
        byKey['resourceTimeout'],
        kBackgroundSearchResourceTimeout,
        reason:
            'the only ceiling that still applies while suspended, so it is '
            "what bounds a credential-bearing task's life",
      );
    });

    test('does nothing at all where there is no background path', () async {
      var touched = 0;
      await configureBackgroundSearch(
        supported: () => false,
        configure: (globalConfig) async => touched++,
        start: ({required bool doRescheduleKilledTasks}) async => touched++,
        prune: () async {
          touched++;
          return true;
        },
      );
      await pumpEventQueue();

      expect(
        touched,
        0,
        reason: 'desktop never enqueues a task, so there is nothing to purge',
      );
    });

    test('a failing plugin does not take the launch down with it', () async {
      // A platform without the plugin still runs the foreground path — which is
      // the whole reason the transport sits behind an interface.
      await expectLater(
        configureBackgroundSearch(
          supported: () => true,
          configure: (globalConfig) async => throw StateError('no plugin'),
          start: ({required bool doRescheduleKilledTasks}) async {},
          prune: () async => true,
        ),
        completes,
      );
    });
  });

  group('cancelAll', () {
    Future<ProviderContainer> container() async {
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('stops every search in flight and says why', () async {
      final c = await container();
      final notifier = c.read(releaseSearchJobsProvider.notifier);
      notifier.configure(
        concurrency: 1,
        runner: (_, __) => Completer<List<dynamic>>().future,
      );

      final running = notifier.start(_season);
      final queued = notifier.start(_movie);
      expect(
        c.read(releaseSearchJobsProvider).map((j) => j.status),
        containsAll([
          ReleaseSearchJobStatus.running,
          ReleaseSearchJobStatus.queued,
        ]),
      );

      notifier.cancelAll(headline: 'Stopped.', diagnosis: 'Because reasons.');

      for (final id in [running.id, queued.id]) {
        final job = notifier.jobById(id)!;
        expect(job.status, ReleaseSearchJobStatus.failed);
        expect(job.failure!.kind, ReleaseSearchFailureKind.cancelled);
        expect(job.failure!.headline, 'Stopped.');
      }
    });

    test('leaves a finished job alone', () async {
      final c = await container();
      final notifier = c.read(releaseSearchJobsProvider.notifier);
      final answer = Completer<List<dynamic>>();
      notifier.configure(runner: (_, __) => answer.future);

      final job = notifier.start(_season);
      answer.complete([
        {'guid': 'g0'},
      ]);
      await pumpEventQueue();
      expect(
        notifier.jobById(job.id)!.status,
        ReleaseSearchJobStatus.completed,
      );

      notifier.cancelAll(headline: 'Stopped.', diagnosis: 'Because reasons.');

      expect(
        notifier.jobById(job.id)!.status,
        ReleaseSearchJobStatus.completed,
        reason:
            'its releases are still grabbable; cancelling it would discard '
            'work the user can still use',
      );
    });
  });

  group('switching it off', () {
    test('cancels first, then persists, then prunes', () async {
      // The order is the promise. A search left to drain keeps the plugin's
      // record of it — headers, so the API key — until it ends on its own, so
      // cancelling has to come first: a cancelled task reaches a final state,
      // which is the condition under which the plugin deletes that record.
      // Persisting before cancelling would also let a queued job start on the
      // transport the user just switched off.
      final prefs = await SharedPreferences.getInstance();
      final pruneCalls = <int>[];
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          backgroundTaskHygieneProvider.overrideWithValue(
            _RecordingHygiene(pruneCalls),
          ),
        ],
      );
      addTearDown(c.dispose);

      final notifier = c.read(releaseSearchJobsProvider.notifier);
      notifier.configure(runner: (_, __) => Completer<List<dynamic>>().future);
      c.read(releaseSearchSettingsProvider.notifier).setBackgroundEnabled(true);
      final job = notifier.start(_season);

      await c.read(backgroundSearchSwitchProvider).set(false);

      final cancelled = notifier.jobById(job.id)!;
      expect(cancelled.status, ReleaseSearchJobStatus.failed);
      expect(
        cancelled.failure!.headline,
        BackgroundSearchSwitch.cancelHeadline,
        reason: 'the card has to say why it stopped, not just that it did',
      );
      expect(c.read(releaseSearchSettingsProvider).backgroundEnabled, isFalse);
      expect(
        pruneCalls,
        hasLength(1),
        reason:
            'the records just cancelled have become prunable, so they go now '
            'rather than at the next launch',
      );
    });

    test('turning it on cancels nothing and prunes nothing', () async {
      // There is no cleanup on the way in, and no permission to ask: the OS
      // wants none for a background task. The next search simply gets the
      // native transport.
      final prefs = await SharedPreferences.getInstance();
      final pruneCalls = <int>[];
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          backgroundTaskHygieneProvider.overrideWithValue(
            _RecordingHygiene(pruneCalls),
          ),
        ],
      );
      addTearDown(c.dispose);

      final notifier = c.read(releaseSearchJobsProvider.notifier);
      notifier.configure(runner: (_, __) => Completer<List<dynamic>>().future);
      final job = notifier.start(_season);

      await c.read(backgroundSearchSwitchProvider).set(true);

      expect(notifier.jobById(job.id)!.status, ReleaseSearchJobStatus.running);
      expect(c.read(releaseSearchSettingsProvider).backgroundEnabled, isTrue);
      expect(pruneCalls, isEmpty);
    });
  });
}
