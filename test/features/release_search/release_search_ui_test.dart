import 'dart:async';

import 'package:dio/dio.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/release_search/data/release_search_notifications.dart';
import 'package:cupola/features/release_search/domain/release_search_job.dart';
import 'package:cupola/features/release_search/domain/release_search_reach.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_lifecycle.dart';
import 'package:cupola/features/release_search/presentation/release_search_settings_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_sheet.dart';
import 'package:cupola/features/release_search/presentation/release_searches_body.dart';
import 'package:cupola/features/release_search/presentation/widgets/release_search_job_card.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../test_helpers/settings_scope.dart';

final _season = ReleaseSearchTarget.season(
  seriesId: 1,
  seasonNumber: 2,
  label: 'Severance · Season 2',
);

ReleaseSearchJob _job({
  required ReleaseSearchJobStatus status,
  int releaseCount = 0,
  Duration elapsed = Duration.zero,
  DateTime? finishedAt,
  ReleaseSearchFailure? failure,
  ReleaseSearchTarget? target,
}) {
  return ReleaseSearchJob(
    id: 'rs-1',
    target: target ?? _season,
    status: status,
    startedAt: DateTime.utc(2026, 8, 5, 9),
    finishedAt: finishedAt,
    releases: List.generate(releaseCount, (i) => {'guid': 'g$i'}),
    elapsed: elapsed,
    failure: failure,
  );
}

/// A clock the test moves by hand, so the 30-minute grab window can be crossed
/// without waiting for it. Same shape as the one in release_search_jobs_test.
class _FakeClock {
  DateTime value = DateTime.utc(2026, 8, 5, 9);
  DateTime call() => value;
  void advance(Duration d) => value = value.add(d);
}

Widget _host(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.darkTheme(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('a search that stopped with no verdict says so in one shape '
      'everywhere, the classifier\'s', (tester) async {
    final job = _job(status: ReleaseSearchJobStatus.failed);
    expect(job.stoppedHeadline, 'The search stopped.');
    expect(kSearchStoppedHeadline, endsWith('.'));

    await tester.pumpWidget(
      _host(ReleaseSearchJobCard(job: job, now: DateTime.utc(2026, 8, 5, 9))),
    );
    expect(find.text('The search stopped.'), findsOneWidget);
    expect(find.text('The search stopped'), findsNothing);

    final judged = _job(
      status: ReleaseSearchJobStatus.failed,
      failure: const ReleaseSearchFailure(
        kind: ReleaseSearchFailureKind.unknown,
        headline: 'The search stopped unexpectedly.',
        diagnosis: 'Searching again is safe, nothing was grabbed.',
      ),
    );
    expect(judged.stoppedHeadline, 'The search stopped unexpectedly.');
  });

  group('ReleaseSearchJobCard', () {
    testWidgets('a queued job says it has not started', (tester) async {
      await tester.pumpWidget(
        _host(
          ReleaseSearchJobCard(
            job: _job(status: ReleaseSearchJobStatus.queued),
            now: DateTime.utc(2026, 8, 5, 9),
            queuePosition: 1,
          ),
        ),
      );

      expect(find.text('Queued'), findsOneWidget);
      expect(find.textContaining('1 ahead'), findsOneWidget);
    });

    testWidgets('a running job shows no elapsed clock in the list', (
      tester,
    ) async {
      // Deliberate: once the search is off screen the ticking figure answers
      // nothing actionable, and sharing the trailing slot with the countdown
      // made one position mean two opposite things.
      await tester.pumpWidget(
        _host(
          ReleaseSearchJobCard(
            job: _job(
              status: ReleaseSearchJobStatus.running,
              elapsed: const Duration(minutes: 1, seconds: 12),
            ),
            now: DateTime.utc(2026, 8, 5, 9),
          ),
        ),
      );

      expect(find.text('Searching'), findsOneWidget);
      expect(find.text('1:12'), findsNothing);
    });

    testWidgets('a fresh window reads in minutes with a unit', (tester) async {
      final finished = DateTime.utc(2026, 8, 5, 9);
      await tester.pumpWidget(
        _host(
          ReleaseSearchJobCard(
            job: _job(
              status: ReleaseSearchJobStatus.completed,
              releaseCount: 14,
              finishedAt: finished,
            ),
            now: finished.add(const Duration(minutes: 3)),
          ),
        ),
      );

      expect(find.text('14 releases'), findsOneWidget);
      // Never a bare `27:00`, which would be indistinguishable from elapsed.
      expect(find.text('27\u00A0min'), findsOneWidget);
    });

    testWidgets('zero releases states the answer without a count', (
      tester,
    ) async {
      final finished = DateTime.utc(2026, 8, 5, 9);
      await tester.pumpWidget(
        _host(
          ReleaseSearchJobCard(
            job: _job(
              status: ReleaseSearchJobStatus.completed,
              finishedAt: finished,
            ),
            now: finished,
          ),
        ),
      );

      expect(find.text('No releases found'), findsOneWidget);
    });

    testWidgets('an expired job drains rather than alarming', (tester) async {
      final finished = DateTime.utc(2026, 8, 5, 9);
      await tester.pumpWidget(
        _host(
          ReleaseSearchJobCard(
            job: _job(
              status: ReleaseSearchJobStatus.expired,
              releaseCount: 14,
              finishedAt: finished,
            ),
            now: finished.add(const Duration(minutes: 31)),
          ),
        ),
      );

      expect(find.text('Expired'), findsOneWidget);
      expect(find.textContaining('expired'), findsWidgets);
    });

    testWidgets(
      'a failed job shows the diagnosis, and the exception under it',
      (tester) async {
        await tester.pumpWidget(
          _host(
            ReleaseSearchJobCard(
              job: _job(
                status: ReleaseSearchJobStatus.failed,
                failure: const ReleaseSearchFailure(
                  kind: ReleaseSearchFailureKind.gatewayTimeout,
                  headline:
                      'Your reverse proxy closed the connection after 1:02.',
                  diagnosis: 'Sonarr is probably still searching.',
                  detail: 'HTTP 502 · nginx',
                ),
              ),
              now: DateTime.utc(2026, 8, 5, 9),
              expandVerdict: true,
            ),
          ),
        );

        expect(find.textContaining('reverse proxy closed'), findsOneWidget);
        expect(
          find.text('Sonarr is probably still searching.'),
          findsOneWidget,
        );
        // Present, because a self-hoster can act on it — but demoted, never the
        // message.
        expect(find.text('HTTP 502 · nginx'), findsOneWidget);
      },
    );

    testWidgets(
      'the verdict rail follows the tone rule: red only for silence',
      (tester) async {
        Future<Color?> rail(ReleaseSearchFailureKind kind) async {
          await tester.pumpWidget(
            _host(
              ReleaseSearchJobCard(
                job: _job(
                  status: ReleaseSearchJobStatus.failed,
                  failure: ReleaseSearchFailure(
                    kind: kind,
                    headline: 'Headline.',
                    diagnosis: 'Diagnosis.',
                  ),
                ),
                now: DateTime.utc(2026, 8, 5, 9),
              ),
            ),
          );
          final box = tester
              .widgetList<Container>(find.byType(Container))
              .map((c) => c.decoration)
              .whereType<BoxDecoration>()
              .map((d) => d.border)
              .whereType<Border>()
              .firstWhere((b) => b.left.width == 2);
          return box.left.color;
        }

        final colors = AppTheme.darkTheme().colorScheme;
        Color tone(StatusTone t) =>
            statusToneColor(colors, t, surface: colors.surfaceContainer);

        expect(
          await rail(ReleaseSearchFailureKind.connectionLost),
          tone(StatusTone.error),
        );
        // A fault that answered, or ran out of time, is amber, never red.
        for (final kind in [
          ReleaseSearchFailureKind.serverError,
          ReleaseSearchFailureKind.refused,
          ReleaseSearchFailureKind.gatewayTimeout,
          ReleaseSearchFailureKind.clientTimeout,
          ReleaseSearchFailureKind.cloudflareCap,
        ]) {
          expect(await rail(kind), tone(StatusTone.warning), reason: kind.name);
        }
        expect(
          await rail(ReleaseSearchFailureKind.cancelled),
          colors.onSurfaceVariant,
        );
      },
    );

    testWidgets('the card speaks one sentence, and controls keep their own', (
      tester,
    ) async {
      final finished = DateTime.utc(2026, 8, 5, 9);
      await tester.pumpWidget(
        _host(
          ReleaseSearchJobCard(
            job: _job(
              status: ReleaseSearchJobStatus.completed,
              releaseCount: 3,
              finishedAt: finished,
            ),
            now: finished,
            onSearchAgain: () {},
          ),
        ),
      );

      final semantics = tester.getSemantics(
        find.bySemanticsLabel(RegExp('3 releases found on Sonarr')),
      );
      expect(semantics, isNotNull);
      // The in-card control is still reachable rather than swallowed.
      expect(find.widgetWithText(TextButton, 'Search again'), findsOneWidget);
    });
  });

  group('Activity › Searching', () {
    testWidgets('the empty state teaches the affordance by name', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const ReleaseSearchesBody(bottomPadding: 0)),
      );
      await tester.pump();

      expect(find.text('No searches running'), findsOneWidget);
      expect(
        find.textContaining(ReleaseSearchHandoffCopy.action),
        findsOneWidget,
        reason: 'the empty state must name the button it is pointing at',
      );
    });

    testWidgets('lists every job, newest first', (tester) async {
      // Settings, because a card names its connection once a service has
      // two, and that is the settings' to say.
      final container = ProviderContainer(
        overrides: await settingsScopeOverrides(),
      );
      final notifier = container.read(releaseSearchJobsProvider.notifier);
      notifier.configure(runner: (_, _) => Completer<List<dynamic>>().future);
      notifier.start(_season);
      notifier.start(
        ReleaseSearchTarget.movie(movieId: 9, label: 'Dune: Part Two'),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(body: ReleaseSearchesBody(bottomPadding: 0)),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Dune: Part Two'), findsOneWidget);
      expect(find.text('Severance · Season 2'), findsOneWidget);
      expect(find.byType(ReleaseSearchJobCard), findsAtLeastNWidgets(2));

      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  });

  group('ReleaseSearchSheet grabbing an expired list', () {
    /// Drives a job to `expired` with releases on it, then mounts the sheet
    /// watching that job.
    Future<({ProviderContainer container, String jobId})> pumpExpiredSheet(
      WidgetTester tester,
    ) async {
      final clock = _FakeClock();
      // The sheet watches `releaseSearchReachProvider`, whose settings chain
      // reaches SharedPreferences — overridden here so the test stays offline.
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(releaseSearchJobsProvider.notifier);

      final completer = Completer<List<dynamic>>();
      notifier.configure(now: clock.call, runner: (_, _) => completer.future);

      final job = notifier.start(_season);
      completer.complete([
        {'guid': 'g0', 'indexerId': 3, 'title': 'Severance.S02.2160p'},
      ]);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      clock.advance(const Duration(minutes: 31));
      notifier.refreshWindows();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: Scaffold(
              body: ReleaseSearchSheet(
                jobId: job.id,
                target: _season,
                scrollController: ScrollController(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (container: container, jobId: job.id);
    }

    /// Taps the row's grab button and confirms the shared sheet's own
    /// "Download this?" dialog, which is what hands control to `_grab`.
    ///
    /// Deliberately not `pumpAndSettle` past that confirmation: from there the
    /// grabbing row spins on an indeterminate indicator, so nothing ever
    /// settles while the grab is in flight.
    Future<void> tapGrab(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Grab release').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download release'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('cancelling the search-again prompt claims no download', (
      tester,
    ) async {
      // The whole point of the ReleaseGrabAbandoned signal. `_grab` returns
      // without grabbing on both non-grab outcomes of this prompt, and
      // InteractiveSearchSheet reads a normal return as "grabbed" — so this
      // used to pop the sheet under a green "Download started" for a user who
      // had just pressed Cancel.
      await pumpExpiredSheet(tester);

      await tapGrab(tester);
      expect(find.text('Search again for this release?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Download started'), findsNothing);
      expect(find.byType(ReleaseSearchSheet), findsOneWidget);
      // Not reported as a failure either — the prompt already said why.
      expect(find.byType(SnackBar), findsNothing);
      // Re-armed rather than dead: the row can be grabbed again.
      expect(find.byTooltip('Grab release'), findsOneWidget);
    });

    testWidgets('the prompt promises a search and only a search', (
      tester,
    ) async {
      // The copy is the contract here: accepting re-runs the search and grabs
      // nothing, so nothing in the dialog may say otherwise. It used to be
      // titled "Search again to grab this?" over a "Search & grab" button,
      // which described a re-grab the code has no hook for.
      await pumpExpiredSheet(tester);

      await tapGrab(tester);

      expect(
        find.textContaining('grab the release from the new list'),
        findsOneWidget,
      );
      expect(find.text('Run the search'), findsOneWidget);
      expect(find.textContaining('Search & grab'), findsNothing);
    });

    testWidgets('accepting it starts a fresh search, not a download', (
      tester,
    ) async {
      // The other non-grab outcome: the sheet re-points at a brand new job and
      // the user watches it run. Nothing was grabbed, so nothing may be
      // claimed.
      final (:container, :jobId) = await pumpExpiredSheet(tester);

      await tapGrab(tester);
      await tester.tap(find.text('Run the search'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Download started'), findsNothing);
      expect(find.byType(ReleaseSearchSheet), findsOneWidget);

      // The expired job was replaced by a brand new search rather than grabbed
      // from. (The stub runner answers instantly, so the replacement is already
      // finished here — the id is what says a second pass actually happened.)
      final jobs = container.read(releaseSearchJobsProvider);
      expect(jobs, hasLength(1));
      expect(jobs.single.id, isNot(jobId));
    });
  });

  group('the handoff promise', () {
    test('the label names the mechanism, not a location', () {
      // The defect this guards: a permanent button reading "Continue in
      // background" while Phase 1 only keeps the search alive in-app.
      expect(ReleaseSearchHandoffCopy.action, 'Keep searching');
      expect(
        ReleaseSearchHandoffCopy.action.toLowerCase(),
        isNot(contains('background')),
      );
    });

    test(
      'explainerBody and confirmation agree about what survives, for every reach',
      () {
        // Two functions, not two constants — because under ADR-5 they were two
        // hard-coded strings that quietly drifted apart (one saying "runs while
        // Cupola is open", the other "running in the background", for the same
        // build), and that drift was the most dangerous defect in the design.
        // ADR-6 makes the split three-way (a certificate trusted only inside
        // Cupola also cannot survive leaving the app), so the guard now checks
        // every value of ReleaseSearchReach rather than one hard-coded pair.
        for (final reach in ReleaseSearchReach.values) {
          final body = ReleaseSearchHandoffCopy.explainerBody(reach);
          final confirmation = ReleaseSearchHandoffCopy.confirmation(reach);
          final survivesLeavingTheApp =
              reach == ReleaseSearchReach.beyondTheApp;

          expect(
            body.toLowerCase().contains('while cupola is open'),
            !survivesLeavingTheApp,
            reason:
                '$reach: explainerBody claims "while Cupola is open" iff the '
                'search does NOT survive leaving the app.',
          );
          // Asserted on the *claim* rather than on the word "background",
          // which the opt-in made ambiguous: `whileOpenSwitchedOff` names the
          // setting ("Background search is off") in the same breath as it says
          // the search will not survive, so a bare keyword check read that as a
          // promise. What must never drift is the promise itself — "running in
          // the background" against "keep Cupola open" — so that is what is
          // checked, in both directions. Do not weaken this to a one-way test:
          // the original defect was a confirmation that claimed the background
          // on a build that did not have it.
          expect(
            confirmation.toLowerCase().contains('running in the background'),
            survivesLeavingTheApp,
            reason:
                '$reach: confirmation may claim to be running in the '
                'background iff the search actually survives leaving the app — '
                'the exact pairing whose absence let the two strings drift '
                'apart before ADR-6.',
          );
          expect(
            confirmation.toLowerCase().contains('keep cupola open'),
            !survivesLeavingTheApp,
            reason:
                '$reach: confirmation tells the user to keep the app open iff '
                'the search does NOT survive leaving it.',
          );
        }
      },
    );

    test('the empty-state hint never promises an OS background', () {
      expect(
        ReleaseSearchHandoffCopy.emptyStateHint,
        contains(ReleaseSearchHandoffCopy.action),
      );
      expect(
        ReleaseSearchHandoffCopy.emptyStateHint.toLowerCase(),
        isNot(contains('while you do something else')),
        reason: 'that phrasing promises an OS background Phase 1 does not have',
      );
    });
  });

  group('a tapped notification', () {
    testWidgets('opens the sheet for the job it names', (tester) async {
      // The notice says "Tap to pick one", so landing in Activity and asking
      // for a second tap made the copy a small lie. Found on a device.
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      final notifier = container.read(releaseSearchJobsProvider.notifier);
      final answer = Completer<List<dynamic>>();
      notifier.configure(runner: (_, _) => answer.future);
      final job = notifier.start(_season);
      answer.complete([
        {'guid': 'g0', 'indexerId': 3, 'title': 'Severance.S02.2160p'},
      ]);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      container.read(pendingReleaseSearchJobProvider.notifier).request(job.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(body: ReleaseSearchesBody(bottomPadding: 0)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ReleaseSearchSheet), findsOneWidget);
      expect(
        container.read(pendingReleaseSearchJobProvider),
        isNull,
        reason: 'consumed once, or a rebuild would stack a second sheet',
      );

      // The list holds a 10-second window ticker while it is on screen, so the
      // tree has to come down — and the container be disposed on the spot,
      // since autoDispose would otherwise get there after the test has ended.
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });

    testWidgets('leaves a stopped search on its card, with no picker', (
      tester,
    ) async {
      // The notice for a failure promises a verdict, not a choice — and the
      // verdict, with Search again next to it, is already on the card here.
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      final notifier = container.read(releaseSearchJobsProvider.notifier);
      final answer = Completer<List<dynamic>>();
      notifier.configure(runner: (_, _) => answer.future);
      final job = notifier.start(_season);
      answer.completeError(
        DioException(
          requestOptions: RequestOptions(path: '/api/v3/release'),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/v3/release'),
            statusCode: 504,
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      container.read(pendingReleaseSearchJobProvider.notifier).request(job.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(body: ReleaseSearchesBody(bottomPadding: 0)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ReleaseSearchSheet), findsNothing);
      expect(find.textContaining('reverse proxy'), findsOneWidget);
      expect(container.read(pendingReleaseSearchJobProvider), isNull);

      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });

    testWidgets('falls back to the list when the job is gone', (tester) async {
      // What a cold start after a kill looks like: the payload names a job that
      // no longer exists in memory. Landing on the list is honest; a sheet for a
      // missing job is not.
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      container
          .read(releaseSearchJobsProvider.notifier)
          .configure(runner: (_, _) => Completer<List<dynamic>>().future);
      container
          .read(pendingReleaseSearchJobProvider.notifier)
          .request('rs-does-not-exist');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(body: ReleaseSearchesBody(bottomPadding: 0)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ReleaseSearchSheet), findsNothing);
      expect(container.read(pendingReleaseSearchJobProvider), isNull);

      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  });

  group('a job outliving its launching page', () {
    testWidgets(
      'still notifies and restarts the queue after the page is gone',
      (tester) async {
        // The regression this pins: showReleaseSearch used to hand the job
        // manager callbacks built on the launching widget's own ref, and a
        // WidgetRef throws on any use after its widget unmounts. A search
        // finishing after the page was popped — the flow the feature exists
        // for — then lost its notification, and a queued job never started.
        final firstAnswer = Completer<List<dynamic>>();
        final notifications = _RecordingNotifications();
        final second = ReleaseSearchTarget.movie(
          movieId: 9,
          label: 'Dune: Part Two',
        );
        final container = ProviderContainer(
          overrides: [
            currentSettingsProvider.overrideWith(
              (ref) => const SettingsModel(),
            ),
            releaseSearchRunnerProvider.overrideWithValue(
              (target, token) => target == _season
                  ? firstAnswer.future
                  : Completer<List<dynamic>>().future,
            ),
            releaseSearchNotificationsProvider.overrideWithValue(notifications),
          ],
        );
        addTearDown(container.dispose);

        // One slot, so the queued movie can only run if the queue pumps on
        // after the season finishes; told when done, so a notice composes.
        container
            .read(releaseSearchSettingsProvider.notifier)
            .setConcurrency(1);
        container
            .read(releaseSearchSettingsProvider.notifier)
            .setNotifyOnFinish(true);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.darkTheme(),
              home: Scaffold(body: _SearchLauncher(target: _season)),
            ),
          ),
        );
        await tester.tap(find.text('search'));
        await tester.pump();
        container.read(releaseSearchJobsProvider.notifier).start(second);

        // The launching page — sheet and all — goes away, then the app goes
        // to the background, and only then does the search answer.
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: SizedBox()),
          ),
        );
        container.read(appInForegroundProvider.notifier).set(false);
        firstAnswer.complete([
          {'guid': 'g0', 'indexerId': 3, 'title': 'Severance.S02.2160p'},
        ]);
        await tester.pump();

        final jobs = container.read(releaseSearchJobsProvider);
        expect(
          jobs.firstWhere((j) => j.target == _season).status,
          ReleaseSearchJobStatus.completed,
        );
        expect(
          notifications.shown,
          hasLength(1),
          reason: 'the finished-search notice must survive the page',
        );
        expect(
          jobs.firstWhere((j) => j.target == second).status,
          ReleaseSearchJobStatus.running,
          reason: 'the queue must pump on after a finished job',
        );
      },
    );
  });
}

/// Records what would have been posted, instead of touching the plugin.
class _RecordingNotifications extends ReleaseSearchNotifications {
  final shown = <String>[];

  @override
  Future<void> initialise() async {}

  @override
  Future<void> show(ReleaseSearchNotice notice, {required String jobId}) async {
    shown.add(notice.title);
  }
}

/// The smallest page that can launch a search the way the app does.
class _SearchLauncher extends ConsumerWidget {
  const _SearchLauncher({required this.target});

  final ReleaseSearchTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton(
      onPressed: () => showReleaseSearch(context, ref, target),
      child: const Text('search'),
    );
  }
}
