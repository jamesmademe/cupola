import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/widgets/status_badge.dart';

void main() {
  group('MediaStatusInfo.label', () {
    test('the pipeline wins over availability', () {
      // The regression this whole layer exists to prevent: nothing on disk plus
      // an active download must never read "Missing".
      const info = MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.downloading,
      );

      expect(info.label, 'Downloading');
      expect(info.tone, StatusTone.info);
    });

    test('labelOverride wins over everything', () {
      const info = MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.paused,
        labelOverride: 'Client unavailable',
      );

      expect(info.label, 'Client unavailable');
    });

    test('unmonitored surfaces only when nothing is on disk', () {
      const unmonitoredMissing = MediaStatusInfo(
        availability: MediaAvailability.missing,
        unmonitored: true,
      );
      const unmonitoredAvailable = MediaStatusInfo(
        availability: MediaAvailability.available,
        unmonitored: true,
      );

      expect(unmonitoredMissing.label, 'Unmonitored');
      expect(unmonitoredMissing.tone, StatusTone.neutral);
      expect(unmonitoredAvailable.label, 'Available');
      expect(unmonitoredAvailable.tone, StatusTone.success);
    });

    test('an in-flight item outranks the unmonitored flag', () {
      const info = MediaStatusInfo(
        availability: MediaAvailability.missing,
        unmonitored: true,
        pipeline: MediaPipeline.downloading,
      );

      expect(info.label, 'Downloading');
    });

    final availabilityLabels = <MediaAvailability, String>{
      MediaAvailability.notTracked: 'Not requested',
      MediaAvailability.unavailable: 'Not released',
      MediaAvailability.missing: 'Missing',
      MediaAvailability.partial: 'Partial',
      MediaAvailability.available: 'Available',
      MediaAvailability.upgradable: 'Upgrade available',
      MediaAvailability.deleted: 'Deleted',
      MediaAvailability.unknown: 'Unknown',
    };

    availabilityLabels.forEach((availability, label) {
      test('${availability.name} reads "$label"', () {
        expect(MediaStatusInfo(availability: availability).label, label);
      });
    });
  });

  group('MediaStatusInfo.tone', () {
    test('a warning lifts a calm tone but never masks an error', () {
      const queuedWarning = MediaStatusInfo(
        pipeline: MediaPipeline.downloading,
        hasWarning: true,
      );
      // The only pipeline that still reaches red: the client did not answer.
      const unreachableWarning = MediaStatusInfo(
        pipeline: MediaPipeline.clientUnavailable,
        hasWarning: true,
      );

      expect(queuedWarning.tone, StatusTone.warning);
      expect(unreachableWarning.tone, StatusTone.error);
    });

    test('notTracked rests in neutral: nobody asked, nothing is wrong', () {
      expect(
        const MediaStatusInfo(availability: MediaAvailability.notTracked).tone,
        StatusTone.neutral,
      );
    });

    test('an unreleased title is neutral, not an error', () {
      expect(
        const MediaStatusInfo(availability: MediaAvailability.unavailable).tone,
        StatusTone.neutral,
      );
    });

    // The rule, in one test, so that drifting any arm of it back costs a red
    // build rather than a screenshot somebody happens to look at. Backlog is
    // the arm this codebase got wrong for a year: `missing` was `error`, which
    // meant the resting state of every \*arr was painted in the alarm colour.
    test('backlog is neutral — missing is not an emergency', () {
      for (final availability in [
        MediaAvailability.missing,
        MediaAvailability.upgradable,
        MediaAvailability.deleted,
      ]) {
        expect(
          MediaStatusInfo(availability: availability).tone,
          StatusTone.neutral,
          reason: '$availability is backlog, not damage',
        );
      }
    });

    test('a fault is amber and red belongs to reachability alone', () {
      for (final pipeline in [
        MediaPipeline.failed,
        MediaPipeline.stalled,
        MediaPipeline.importBlocked,
      ]) {
        expect(
          MediaStatusInfo(pipeline: pipeline).tone,
          StatusTone.warning,
          reason: '$pipeline is a fault the service reported, not silence',
        );
      }

      expect(
        const MediaStatusInfo(pipeline: MediaPipeline.clientUnavailable).tone,
        StatusTone.error,
      );
    });

    test('waiting is informational and a deliberate pause is neutral', () {
      for (final pipeline in [
        MediaPipeline.queued,
        MediaPipeline.importPending,
        MediaPipeline.downloading,
      ]) {
        expect(MediaStatusInfo(pipeline: pipeline).tone, StatusTone.info);
      }

      expect(
        const MediaStatusInfo(pipeline: MediaPipeline.paused).tone,
        StatusTone.neutral,
      );
    });
  });

  group('MediaPipeline.salience', () {
    test('failed outranks downloading, which outranks the waiting states', () {
      expect(
        MediaPipeline.failed.salience,
        greaterThan(MediaPipeline.downloading.salience),
      );
      expect(
        MediaPipeline.downloading.salience,
        greaterThan(MediaPipeline.queued.salience),
      );
      expect(
        MediaPipeline.queued.salience,
        greaterThan(MediaPipeline.paused.salience),
      );
    });
  });

  group('availabilityFromCounts', () {
    test('all files present is available', () {
      expect(
        availabilityFromCounts(fileCount: 10, totalCount: 10),
        MediaAvailability.available,
      );
    });

    test('more files than expected is still available', () {
      expect(
        availabilityFromCounts(fileCount: 15, totalCount: 10),
        MediaAvailability.available,
      );
    });

    test('some files present is partial', () {
      expect(
        availabilityFromCounts(fileCount: 4, totalCount: 10),
        MediaAvailability.partial,
      );
    });

    test('no files present falls back to whenEmpty', () {
      expect(
        availabilityFromCounts(fileCount: 0, totalCount: 10),
        MediaAvailability.missing,
      );
      expect(
        availabilityFromCounts(
          fileCount: 0,
          totalCount: 10,
          whenEmpty: MediaAvailability.unavailable,
        ),
        MediaAvailability.unavailable,
      );
    });

    test('a zero total falls back to file presence', () {
      expect(
        availabilityFromCounts(fileCount: 2, totalCount: 0),
        MediaAvailability.available,
      );
      expect(
        availabilityFromCounts(fileCount: 0, totalCount: 0),
        MediaAvailability.missing,
      );
    });

    test('an absent count is unknown rather than missing', () {
      expect(
        availabilityFromCounts(fileCount: null, totalCount: null),
        MediaAvailability.unknown,
      );
    });
  });

  group('statusIconFor', () {
    test('the pipeline icon wins over the availability icon', () {
      expect(
        statusIconFor(
          const MediaStatusInfo(
            availability: MediaAvailability.missing,
            pipeline: MediaPipeline.downloading,
          ),
        ),
        Icons.downloading_rounded,
      );
    });

    test('unmonitored without files gets the bookmark icon', () {
      expect(
        statusIconFor(
          const MediaStatusInfo(
            availability: MediaAvailability.missing,
            unmonitored: true,
          ),
        ),
        Icons.bookmark_border_rounded,
      );
    });
  });

  group('StatusBadge rendering', () {
    testWidgets('full mode renders the label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              info: MediaStatusInfo(availability: MediaAvailability.available),
            ),
          ),
        ),
      );

      expect(find.text('Available'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('compact mode renders no label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              info: MediaStatusInfo(availability: MediaAvailability.available),
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('Available'), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('an active download renders a progress ring and percentage', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              info: MediaStatusInfo(
                availability: MediaAvailability.missing,
                pipeline: MediaPipeline.downloading,
                progress: 0.42,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Downloading'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.downloading_rounded), findsNothing);
    });

    testWidgets('a waiting state shows its icon, not a ring', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              info: MediaStatusInfo(
                availability: MediaAvailability.missing,
                pipeline: MediaPipeline.queued,
                progress: 0.42,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Queued'), findsOneWidget);
      expect(find.text('42%'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    });

    testWidgets('iconOnly renders a bare dot', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              info: MediaStatusInfo(availability: MediaAvailability.missing),
              iconOnly: true,
            ),
          ),
        ),
      );

      expect(find.text('Missing'), findsNothing);
      expect(find.byType(Icon), findsNothing);
    });
  });

  group('MediaStatusInfo.semanticLabel', () {
    test('spells out the percentage the badge only draws as a ring', () {
      const info = MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.downloading,
        progress: 0.42,
      );

      expect(info.semanticLabel, 'Downloading, 42 percent');
    });

    test('never calls a transfer that is still copying 100 percent', () {
      const nearlyThere = MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.downloading,
        progress: 0.996,
      );
      const done = MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.downloading,
        progress: 1,
      );

      expect(nearlyThere.progressPercent, 99);
      expect(nearlyThere.semanticLabel, 'Downloading, 99 percent');
      expect(done.progressPercent, 100);
    });

    test('spells out a warning carried only by the tone colour', () {
      // hasWarning replaced a "… (Warning)" text suffix, so since then nothing
      // writes it down — the amber tone is the whole signal.
      const info = MediaStatusInfo(
        availability: MediaAvailability.available,
        hasWarning: true,
      );

      expect(info.tone, StatusTone.warning);
      expect(info.semanticLabel, 'Available, warning');
    });

    test('stays silent about progress that is not being drawn', () {
      // A queued item carries a progress value the badge deliberately hides.
      const info = MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.queued,
        progress: 0.42,
      );

      expect(info.progressPercent, isNull);
      expect(info.semanticLabel, 'Queued');
    });
  });

  group('StatusBadge semantics', () {
    testWidgets('all three variants announce the same status', (tester) async {
      const info = MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.downloading,
        progress: 0.42,
      );

      for (final variant in [
        const StatusBadge(info: info),
        const StatusBadge(info: info, compact: true),
        const StatusBadge(info: info, iconOnly: true),
      ]) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: variant)));

        expect(
          find.semantics.byLabel('Downloading, 42 percent'),
          findsOneWidget,
          reason: 'compact=${variant.compact} iconOnly=${variant.iconOnly}',
        );
      }
    });

    testWidgets('excludeFromSemantics leaves the badge silent', (tester) async {
      // Set by tiles that speak the status themselves, so the badge is not a
      // second stop for the same information.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              info: MediaStatusInfo(availability: MediaAvailability.available),
              iconOnly: true,
              excludeFromSemantics: true,
            ),
          ),
        ),
      );

      expect(find.semantics.byLabel('Available'), findsNothing);
    });

    testWidgets('animated variant settles cleanly across a status change', (
      tester,
    ) async {
      Widget wrap(MediaStatusInfo info) => MaterialApp(
        home: Scaffold(body: StatusBadge.animated(info: info)),
      );

      await tester.pumpWidget(
        wrap(
          const MediaStatusInfo(
            pipeline: MediaPipeline.downloading,
            progress: 0.3,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AnimatedSwitcher), findsOneWidget);

      await tester.pumpWidget(
        wrap(const MediaStatusInfo(availability: MediaAvailability.available)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Available'), findsOneWidget);
    });

    testWidgets('animated variant renders statically under Reduce Motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const Scaffold(
            body: StatusBadge.animated(
              info: MediaStatusInfo(availability: MediaAvailability.available),
            ),
          ),
        ),
      );

      expect(find.byType(AnimatedSwitcher), findsNothing);
      expect(find.text('Available'), findsOneWidget);
    });
  });

  group('StatusBadge.poster', () {
    // The test font draws every letter a square em wide: "Available" is nine
    // ems, wider at twice the size than the corner of a 160 poster, and
    // narrower at the reading size.
    Future<RenderParagraph> pump(WidgetTester tester, double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 160,
                child: Align(
                  alignment: Alignment.topRight,
                  child: StatusBadge.poster(
                    info: MediaStatusInfo(
                      availability: MediaAvailability.available,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return tester.renderObject<RenderParagraph>(find.text('Available'));
    }

    testWidgets('at twice the reading size its word is never broken inside', (
      tester,
    ) async {
      final word = await pump(tester, 2);
      final size = word.text.style!.fontSize!;
      final scale = word.textScaler.scale(size) / size;

      expect(scale, greaterThan(1));
      expect(word.size.width, greaterThanOrEqualTo(9 * size * scale - 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('at the reading size it is left as it is', (tester) async {
      // The control: nothing to step down.
      final word = await pump(tester, 1);
      final size = word.text.style!.fontSize!;

      expect(word.textScaler.scale(size), size);
    });
  });
}
