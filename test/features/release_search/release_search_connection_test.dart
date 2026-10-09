/// A release search names the connection it runs on, once there are two.
///
/// A search is bound to one connection from the moment it starts, and with
/// two Radarr a job card reading "Sintel · 3 releases" and a notification
/// reading "3 releases for Sintel" did not say which library would take the
/// release.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/release_search/data/release_search_notifications.dart';
import 'package:cupola/features/release_search/domain/release_search_job.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_searches_body.dart';

import '../../test_helpers/profiles/profiles.dart';

final _sintel4k = const ReleaseSearchTarget.movie(
  movieId: 2,
  label: 'Sintel',
).stampedWith(WorldIds.radarr4k);

final _sintelHd = const ReleaseSearchTarget.movie(
  movieId: 4,
  label: 'Sintel',
).stampedWith(WorldIds.radarr);

ReleaseSearchJob _finished(ReleaseSearchTarget target, int releases) =>
    ReleaseSearchJob(
      id: 'rs-${target.instanceId}',
      target: target,
      status: ReleaseSearchJobStatus.completed,
      startedAt: DateTime.utc(2026, 8, 5, 9),
      finishedAt: DateTime.utc(2026, 8, 5, 9, 1),
      releases: List.generate(releases, (i) => {'guid': 'g$i'}),
    );

void main() {
  group('P1: two Radarr, the first one unnamed', () {
    final settings = Profiles.p1.settings;

    test('each search is called by its connection', () {
      expect(_sintel4k.connectionIn(settings), 'Radarr 4K');
      expect(_sintelHd.connectionIn(settings), 'Radarr 1');
    });

    test('the notification says which Radarr the releases are for', () {
      final notice = noticeFor(
        _finished(_sintel4k, 3),
        appInForeground: false,
        notificationsEnabled: true,
        connection: _sintel4k.connectionIn(settings),
      );
      expect(notice!.title, '3 releases for Sintel on Radarr 4K');

      final stopped = noticeFor(
        ReleaseSearchJob(
          id: 'rs-1',
          target: _sintelHd,
          status: ReleaseSearchJobStatus.failed,
          startedAt: DateTime.utc(2026, 8, 5, 9),
          failure: const ReleaseSearchFailure(
            kind: ReleaseSearchFailureKind.clientTimeout,
            headline: 'The search ran out of time',
            diagnosis: 'Try again later.',
          ),
        ),
        appInForeground: false,
        notificationsEnabled: true,
        connection: _sintelHd.connectionIn(settings),
      );
      expect(stopped!.title, 'Search stopped, Sintel on Radarr 1');
    });

    testWidgets('the job list says which Radarr each search runs on, to '
        'the eye and the ear', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await ProfileHarness.start(Profiles.p1);
      final container = ProviderContainer(overrides: harness.overrides);
      final notifier = container.read(releaseSearchJobsProvider.notifier);
      notifier.configure(runner: (_, _) => Completer<List<dynamic>>().future);
      notifier.start(_sintel4k);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(child: ReleaseSearchesGroup()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Radarr 4K · Searching your indexers'), findsOne);
      expect(
        find.bySemanticsLabel('Sintel. Searching on Radarr 4K.'),
        findsOne,
      );

      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  });

  test('one Radarr: no connection named anywhere', () {
    final settings = Profiles.p4.settings;
    final target = const ReleaseSearchTarget.movie(
      movieId: 2,
      label: 'Sintel',
    ).stampedWith(WorldIds.radarr);
    expect(target.connectionIn(settings), isNull);
    expect(
      noticeFor(
        _finished(target, 3),
        appInForeground: false,
        notificationsEnabled: true,
        connection: target.connectionIn(settings),
      )!.title,
      '3 releases for Sintel',
    );
  });
}
